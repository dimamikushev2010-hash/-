-- Script: ServerScriptService > CourtServer
-- Адвокат, залог, настоящий суд и камеры наблюдения (настройки — ReplicatedStorage > CourtConfig).
--   🔒 КПЗ: дело (свидетели, камеры, полиция, арест), один звонок — адвокату или другу, залог — сразу в суд.
--   💬 С адвокатом можно говорить: кнопки тем или свой текст (тема узнаётся по словам).
--   ⚖️ Суд: обвинение → полиция → свидетели (кто звонил в 911) → записи камер → защита → последнее слово
--      → приговор (или оправдание, если улик мало) → апелляция.
--   📹 Камеры записывают преступления. Сломал (выстрел или E) — её записи пропали; через 3 минуты чинят.
-- WantedServer вызывает Registry.courtHolding / courtTrial и сообщает о преступлениях через Registry.cameraCrime.
--
-- Метки (все необязательные):
--   Workspace > JusticeSystem > Cameras: любые Part — камеры (передняя грань — куда смотрит; атрибуты CameraName, Range, Fov).
--      Нет папки — камеры ставятся сами у PoliceCalls и Places.
--   Workspace > JusticeSystem > Court: Prosecutor, Defense, Witness, Defender
--   TrafficSystem > PoliceStation: Visit — где стоит адвокат у КПЗ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("CourtConfig"))
local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
if not Config.Enabled or not WeaponConfig.Enabled then
	return
end
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local DebugTimer = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))
local J = WeaponConfig.Justice
local L = Config.Lines
local C = Config.Cameras
local E = Config.Evidence

local rng = Random.new()
local remote = Instance.new("RemoteEvent")
remote.Name = "CourtRemote"
remote.Parent = ReplicatedStorage

local LAWYERS = {}
for _, l in Config.Lawyers do
	LAWYERS[l.Id] = l
end
local PUBLIC = Config.Lawyers[1]

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
local function now(): number
	return os.clock()
end
local function event(text: string)
	if Registry.debugEvent then
		Registry.debugEvent(text)
	end
end
local function toast(player: Player, text: string)
	if Registry.toast then
		Registry.toast(player, text)
	end
end
local function say(npc, text: string, seconds: number?)
	if npc and npc.alive and Registry.say then
		Registry.say(npc, text, seconds)
	end
end
local function wallet(player: Player): IntValue?
	return Registry.getCoins and Registry.getCoins(player) or nil
end
local function coins(player: Player): number
	local w = wallet(player)
	return w and w.Value or 0
end
local function pay(player: Player, amount: number): boolean
	local w = wallet(player)
	if amount <= 0 then
		return true
	end
	if not w or w.Value < amount then
		return false
	end
	w.Value -= amount
	return true
end

-- Подстановки {player} {sentence} ...
local function fill(text: string, vars): string
	return (string.gsub(text, "{(%w+)}", function(key)
		local v = vars[key]
		return v ~= nil and tostring(v) or "{" .. key .. "}"
	end))
end

-- Первая буква большая (для {Why})
local function capital(text: string): string
	local first = utf8.offset(text, 2)
	if not first then
		return text
	end
	local head = string.sub(text, 1, first - 1)
	local code = utf8.codepoint(head)
	if code >= 0x430 and code <= 0x44F then
		head = utf8.char(code - 0x20)
	elseif code == 0x451 then
		head = utf8.char(0x401)
	else
		head = string.upper(head)
	end
	return head .. string.sub(text, first)
end

-- Маленькие буквы и для русского (string.lower понимает только латиницу)
local function lower(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if code >= 0x410 and code <= 0x42F then
			code += 0x20
		elseif code == 0x401 then
			code = 0x451
		elseif code >= 65 and code <= 90 then
			code += 32
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local function secondsText(n: number): string
	n = math.max(0, math.floor(n))
	if n < 60 then
		return n .. " с"
	end
	local m, sec = math.floor(n / 60), n % 60
	return sec > 0 and string.format("%d мин %d с", m, sec) or (m .. " мин")
end

local function courtPart(name: string): BasePart?
	return Registry.justicePart and Registry.justicePart("Court", name) or nil
end

-- Временный человек в суде (прокурор, свидетель, адвокат)
local function spawnPerson(spot: BasePart?, name: string, shirt: Color3, pants: Color3?, role: string)
	if not spot or not Registry.spawnCustom then
		return nil
	end
	local look = flat(spot.CFrame.LookVector)
	local p = spot.Position + Vector3.new(0, 3, 0)
	local npc = Registry.spawnCustom(CFrame.lookAt(p, p + (look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1))), {
		shirt = shirt,
		pants = pants or shirt,
		role = role,
	})
	if not npc then
		return nil
	end
	npc.officer = true -- не участвует в жизни города и не пугается
	npc.noSocial = true
	npc.name = name
	npc.title = name
	npc.model.Name = name
	npc.humanoid.DisplayName = name
	npc.humanoid.WalkSpeed = 0
	if npc.prompt then
		npc.prompt.Enabled = false
	end
	return npc
end
-- Перенести игрока (сначала встать с сиденья, иначе потянет машину)
local function movePlayer(p: Player, cf: CFrame)
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if humanoid.SeatPart then
		local weld = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
		task.wait(0.15)
	end
	character:PivotTo(cf)
end

local function removePerson(npc)
	if npc and npc.model and npc.model.Parent then
		npc.alive = false
		npc.model:Destroy()
	end
end

---------------------------------------------------------------------
-- 📹 Камеры наблюдения
---------------------------------------------------------------------

local cameras = {} -- { id, name, model, parts, pos, look, cosFov, range, broken, hits }
local records = {} -- [player] = { { cam, name, why, time } }
local lostCams = {} -- [player] = { [имя камеры] = true } — записи пропали, камеру сломали
local lastRecord = {} -- ["камера:игрок:что"] = время
local lastNotify = {} -- [player] = время

local camFolder = Instance.new("Folder")
camFolder.Name = "SecurityCameras"
camFolder.Parent = workspace

local camRay = RaycastParams.new()
camRay.FilterType = Enum.RaycastFilterType.Exclude

local function camPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true -- пули попадают
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- Камера: крепление, корпус, объектив, красный огонёк. dome — купольная (видит во все стороны)
local function buildCamera(pos: Vector3, look: Vector3, name: string, range: number, fov: number, dome: boolean, pole: number?)
	local id = #cameras + 1
	local model = Instance.new("Model")
	model.Name = "SecurityCamera" .. id
	model:SetAttribute("SecurityCamera", id)
	look = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	local base = CFrame.lookAt(pos, pos + look)
	local dark = Color3.fromRGB(45, 47, 52)
	local light = Color3.fromRGB(215, 218, 222)
	local parts = {}
	if pole then
		local stick = camPart(model, "Pole", Vector3.new(pole, 0.35, 0.35), CFrame.new(pos - Vector3.new(0, pole / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), dark, Enum.Material.Metal, Enum.PartType.Cylinder)
		stick.CanQuery = false
	end
	local body, lens
	if dome then
		camPart(model, "Mount", Vector3.new(1.4, 0.25, 1.4), base * CFrame.new(0, 0.15, 0), dark)
		body = camPart(model, "Body", Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(0, -0.25, 0), Color3.fromRGB(25, 25, 30), Enum.Material.Glass, Enum.PartType.Ball)
		body.Transparency = 0.15
		lens = body
	else
		camPart(model, "Mount", Vector3.new(0.6, 0.6, 0.3), base * CFrame.new(0, 0, 0.6), dark)
		camPart(model, "Arm", Vector3.new(0.2, 0.2, 0.8), base * CFrame.new(0, -0.2, 0.2), dark)
		body = camPart(model, "Body", Vector3.new(0.9, 0.8, 1.7), base * CFrame.new(0, -0.45, -0.6) * CFrame.Angles(math.rad(-18), 0, 0), light)
		lens = camPart(model, "Lens", Vector3.new(0.25, 0.65, 0.65), body.CFrame * CFrame.new(0, 0, -0.95) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(10, 10, 14), Enum.Material.Glass, Enum.PartType.Cylinder)
	end
	local led = camPart(model, "Led", Vector3.new(0.16, 0.16, 0.16), (dome and body.CFrame * CFrame.new(0, 0.62, 0) or body.CFrame * CFrame.new(0.3, 0.42, -0.7)), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
	led.CanQuery = false
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 40, 40)
	glow.Brightness = 0.8
	glow.Range = 4
	glow.Parent = led
	for _, d in model:GetChildren() do
		parts[d] = d.CFrame
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BreakPrompt"
	prompt.ActionText = "Сломать камеру"
	prompt.ObjectText = "📹 " .. name
	prompt.HoldDuration = C.BreakHold
	prompt.MaxActivationDistance = C.BreakDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	model.PrimaryPart = body
	model.Parent = camFolder
	local cam = {
		id = id,
		name = name,
		model = model,
		parts = parts,
		body = body,
		lens = lens,
		led = led,
		glow = glow,
		prompt = prompt,
		pos = lens.Position,
		look = look,
		cosFov = math.cos(math.rad(math.clamp(fov, 1, 360) / 2)),
		range = range,
		broken = false,
		hits = 0,
	}
	cameras[id] = cam
	return cam
end

local breakCamera -- объявлена ниже

local function placeCameras()
	if not C.Enabled then
		return
	end
	local root = workspace:FindFirstChild("JusticeSystem")
	local folder = root and root:FindFirstChild("Cameras")
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				local fov = d:GetAttribute("Fov") or C.Fov
				buildCamera(d.Position, d.CFrame.LookVector, d:GetAttribute("CameraName") or d.Name, d:GetAttribute("Range") or C.Range, fov, fov >= 300, nil)
			end
		end
		return
	end
	if not C.AutoPlace then
		return
	end
	-- Сами: у мест вызова полиции и мест города — под навесом (если есть) или на столбе
	local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local spots = {}
	for _, group in { "Places", "PoliceCalls" } do
		local f = map and map:FindFirstChild(group)
		for _, d in f and f:GetDescendants() or {} do
			if d:IsA("BasePart") then
				table.insert(spots, d)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { camFolder, map }
	local npcRoot = workspace:FindFirstChild("NPCSystem")
	local live = npcRoot and npcRoot:FindFirstChild("Live")
	if live then
		table.insert(ignore, live) -- жители
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	for _, spot in spots do
		if #cameras >= C.AutoMax then
			break
		end
		local near = false
		for _, cam in cameras do
			near = near or (flat(cam.pos - spot.Position)).Magnitude < 25
		end
		if near then
			continue
		end
		local name = spot:GetAttribute("PlaceName") or spot:GetAttribute("Zone") or spot.Name
		local up = workspace:Raycast(spot.Position + Vector3.new(0, 2, 0), Vector3.new(0, 16, 0), params)
		if up and up.Position.Y - spot.Position.Y > 6 then
			buildCamera(up.Position - Vector3.new(0, 0.5, 0), spot.CFrame.LookVector, name, C.AutoRange, 360, true, nil)
		else
			local side = spot.Position + spot.CFrame.RightVector * 3.5
			local down = workspace:Raycast(side + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
			local ground = down and down.Position.Y or (spot.Position.Y - spot.Size.Y / 2)
			buildCamera(Vector3.new(side.X, ground + 11, side.Z), spot.CFrame.LookVector, name, C.AutoRange, 360, true, 11)
		end
	end
	if #cameras > 0 then
		print(string.format("[Court] Камер наблюдения поставлено сами: %d (свои — Workspace > JusticeSystem > Cameras)", #cameras))
	end
end

-- Видит ли камера персонажа
local function camSees(cam, character: Model): boolean
	if cam.broken then
		return false
	end
	local head = character:FindFirstChild("Head")
	if not head or character:GetAttribute("Invisible") == true then
		return false
	end
	local d = head.Position - cam.pos
	if d.Magnitude > cam.range then
		return false
	end
	if cam.cosFov > -0.99 and flat(d).Magnitude > 1 and flat(d).Unit:Dot(cam.look) < cam.cosFov then
		return false
	end
	camRay.FilterDescendantsInstances = { cam.model, character }
	return workspace:Raycast(cam.pos, d, camRay) == nil
end

local function clockText(): string
	local t = Lighting.ClockTime
	return string.format("%02d:%02d", math.floor(t), math.floor((t % 1) * 60))
end

local function blink(cam)
	task.spawn(function()
		for _ = 1, 3 do
			if cam.broken then
				return
			end
			cam.led.Color = Color3.fromRGB(255, 255, 255)
			task.wait(0.12)
			cam.led.Color = Color3.fromRGB(255, 30, 30)
			task.wait(0.12)
		end
	end)
end

-- Преступление (от WantedServer): каждая камера, которая видит, записывает
Registry.cameraCrime = function(player: Player, why: string, pos: Vector3)
	local character = player.Character
	if not C.Enabled or not character then
		return
	end
	for _, cam in cameras do
		if cam.broken or (cam.pos - pos).Magnitude > cam.range + 5 then
			continue
		end
		local key = cam.id .. ":" .. player.UserId .. ":" .. why
		if now() - (lastRecord[key] or -999) < C.Throttle or not camSees(cam, character) then
			continue
		end
		lastRecord[key] = now()
		local list = records[player] or {}
		records[player] = list
		table.insert(list, { cam = cam.id, name = cam.name, why = why, time = clockText(), at = now() })
		if #list > 40 then
			table.remove(list, 1)
		end
		blink(cam)
		event(string.format("📹 Камера «%s» сняла %s: %s", cam.name, player.Name, why))
		if C.NotifyPlayer and now() - (lastNotify[player] or -999) > 20 then
			lastNotify[player] = now()
			remote:FireClient(player, "Recorded", { name = cam.name, why = why })
		end
	end
end

Registry.cameraClear = function(player: Player)
	records[player] = nil
	lostCams[player] = nil
end

Registry.courtCameras = function()
	return cameras
end

local function repairCamera(cam)
	cam.broken = false
	cam.hits = 0
	for part, cf in cam.parts do
		part.CFrame = cf
	end
	cam.led.Color = Color3.fromRGB(255, 30, 30)
	cam.led.Material = Enum.Material.Neon
	cam.glow.Enabled = true
	cam.prompt.Enabled = true
	local smoke = cam.body:FindFirstChild("BrokenSmoke")
	if smoke then
		smoke:Destroy()
	end
end

function breakCamera(cam, player: Player?)
	if cam.broken then
		return
	end
	cam.broken = true
	-- Висит на проводе, огонёк погас, искры и дым
	for part, cf in cam.parts do
		if part.Name ~= "Mount" and part.Name ~= "Pole" then
			part.CFrame = cf * CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(35), 0, math.rad(18))
		end
	end
	cam.led.Color = Color3.fromRGB(40, 20, 20)
	cam.led.Material = Enum.Material.SmoothPlastic
	cam.glow.Enabled = false
	cam.prompt.Enabled = false
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Lifetime = NumberRange.new(0.2, 0.5)
	sparks.Rate = 0
	sparks.Parent = cam.body
	sparks:Emit(30)
	game:GetService("Debris"):AddItem(sparks, 1.5)
	local smoke = Instance.new("Smoke")
	smoke.Name = "BrokenSmoke"
	smoke.Size = 0.6
	smoke.RiseVelocity = 2
	smoke.Opacity = 0.15
	smoke.Color = Color3.fromRGB(60, 60, 60)
	smoke.Parent = cam.body
	game:GetService("Debris"):AddItem(smoke, 8)
	local sound = Sounds.Weapons and Sounds.Weapons.CameraBreak
	if sound and sound.Id ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = sound.Id
		s.Volume = sound.Volume or 0.6
		s.RollOffMaxDistance = 80
		s.Parent = cam.body
		s:Play()
		game:GetService("Debris"):AddItem(s, 4)
	end
	-- Записи этой камеры пропадают у всех
	local lost = 0
	for p, list in records do
		for i = #list, 1, -1 do
			if list[i].cam == cam.id then
				table.remove(list, i)
				lostCams[p] = lostCams[p] or {}
				lostCams[p][cam.name] = true
				if p == player then
					lost += 1
				end
			end
		end
	end
	event(string.format("💥 Камера «%s» сломана%s", cam.name, player and (" — " .. player.Name) or ""))
	if player then
		remote:FireClient(player, "CameraBroken", { name = cam.name, lost = lost })
		-- Порча на глазах у людей и других камер
		local pos = cam.body.Position
		task.defer(function()
			if Registry.crimeSeen then
				Registry.crimeSeen(player, "Vandalism", pos, "сломал камеру наблюдения")
			end
			Registry.cameraCrime(player, "порча камеры наблюдения", pos)
		end)
	end
	task.delay(C.RepairTime, repairCamera, cam)
end

-- Пуля попала (от WeaponServer)
Registry.cameraHit = function(part: Instance, player: Player)
	local model = part:FindFirstAncestorOfClass("Model")
	local id = model and model:GetAttribute("SecurityCamera")
	local cam = id and cameras[id]
	if cam and not cam.broken then
		cam.hits += 1
		if cam.hits >= C.BulletsToBreak then
			breakCamera(cam, player)
		end
	end
end

task.spawn(function()
	task.wait(4) -- ждём карту и демо-городок
	placeCameras()
	for _, cam in cameras do
		cam.prompt.Triggered:Connect(function(player: Player)
			local character = player.Character
			if not character or character:GetAttribute("Cuffed") then
				return
			end
			local mode = player:GetAttribute("WantedMode") or "free"
			if mode == "free" or mode == "wanted" then
				breakCamera(cam, player)
			end
		end)
	end
end)

-- Огонёк камеры мигает раз в 2 секунды (идёт запись)
local blinkTime = 0
DebugTimer.connect(RunService.Heartbeat, "CourtServer", function(dt)
	blinkTime += dt
	if blinkTime < 1 then
		return
	end
	blinkTime = 0
	local on = math.floor(os.clock()) % 2 == 0
	for _, cam in cameras do
		if not cam.broken then
			cam.glow.Enabled = on
		end
	end
end)

---------------------------------------------------------------------
-- ⚖️ Дело: улики, сила обвинения, ожидаемый срок
---------------------------------------------------------------------

local cases = {} -- [player] = { case, lawyer, called, bail, bailPaid, defender, ... }

-- Записи камер по делу: одна строка на камеру
local function camRecords(player: Player)
	local byCam, list = {}, {}
	for _, r in records[player] or {} do
		if now() - r.at > C.RecordLife then
			continue -- старые записи уже не в деле
		end
		if not byCam[r.cam] then
			byCam[r.cam] = r
			table.insert(list, r)
		end
	end
	return list
end

local function lostList(player: Player)
	local list = {}
	for name in lostCams[player] or {} do
		table.insert(list, name)
	end
	return list
end

-- Очки улик (без адвокатских сомнений)
local function expectedScore(player: Player, case): number
	local score = 0
	for _, w in case.witnesses do
		score += (w.npc and w.npc.alive) and E.Witness or E.CallRecord
	end
	score += #camRecords(player) * E.Camera
	if case.policeSaw then
		score += E.Police
	end
	score += (case.confessed or 0) * E.Confession
	return score
end

local function strengthOf(score: number): string
	if score < E.AcquitBelow then
		return "Weak"
	elseif score < 3.5 then
		return "Medium"
	end
	return "Strong"
end

local function strengthMult(score: number): number
	local s = Config.Strength
	return math.clamp(s.Base + s.PerPoint * score, s.Min, s.Max)
end

local function sentenceFor(case, score: number, lawyer, extra: number): number
	local mult = strengthMult(score) * (case.modifier or 1) * (1 - lawyer.Discount)
	if case.surrendered then
		mult *= 1 - Config.Surrender
	end
	if case.resisted then
		mult *= 1 + Config.Resist
	end
	mult *= 1 + extra
	return math.floor(math.clamp(case.baseSentence * mult, Config.MinSentence, J.Sentence.Max))
end

local function bailOf(case): number?
	local b = Config.Bail
	if b.NoBailForPoliceKill and (case.policeKills or 0) > 0 then
		return nil
	end
	return math.floor(math.min(b.Max, b.Base + b.PerStar * case.stars + b.PerKill * case.kills))
end

local function crimesText(case): string
	if #case.crimes == 0 then
		return "нарушение общественного порядка"
	end
	return table.concat(case.crimes, ", ")
end

local function varsOf(player: Player, c)
	local lawyer = LAWYERS[c.lawyer] or PUBLIC
	local score = expectedScore(player, c.case)
	local strength = strengthOf(score)
	return {
		player = player.DisplayName,
		lawyer = lawyer.Name,
		sentence = strength == "Weak" and "почти ничего — улик мало" or secondsText(sentenceFor(c.case, score, lawyer, 0)),
		witnesses = #c.case.witnesses,
		cameras = #camRecords(player),
		bail = c.bail or "—",
		price = lawyer.Price,
		strength = ({ Weak = "слабые", Medium = "средние", Strong = "серьёзные" })[strength],
		crimes = crimesText(c.case),
		number = c.case.number,
	}, strength
end

-- Данные для окна КПЗ
local function pushHolding(player: Player)
	local c = cases[player]
	if not c then
		return
	end
	local case = c.case
	local vars, strength = varsOf(player, c)
	local lawyers = {}
	for _, l in Config.Lawyers do
		table.insert(lawyers, { Id = l.Id, Name = l.Name, Title = l.Title, Icon = l.Icon, Price = l.Price, Rating = l.Rating, Perks = l.Perks })
	end
	local friends = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and (p:GetAttribute("WantedMode") or "free") == "free" then
			table.insert(friends, { userId = p.UserId, name = p.DisplayName })
		end
	end
	local alive, dead = 0, 0
	for _, w in case.witnesses do
		if w.npc and w.npc.alive then
			alive += 1
		else
			dead += 1
		end
	end
	remote:FireClient(player, "Holding", {
		number = case.number,
		stars = case.stars,
		witnesses = alive,
		calls = dead,
		cameras = #camRecords(player),
		lost = #lostList(player),
		policeSaw = case.policeSaw,
		surrendered = case.surrendered,
		resisted = case.resisted,
		confessed = case.confessed or 0,
		strength = strength,
		estimate = vars.sentence,
		bail = c.bail,
		bailPaid = c.bailPaid,
		coins = coins(player),
		lawyer = c.lawyer,
		called = c.called,
		calledFriend = c.friendName,
		defender = c.defender and c.defender.DisplayName or nil,
		lawyers = lawyers,
		friends = friends,
		topics = Config.Topics,
		holdEnd = workspace:GetServerTimeNow() + math.max(0, c.holdEnd - now()),
	})
end

---------------------------------------------------------------------
-- 💬 Разговор с адвокатом
---------------------------------------------------------------------

local function answerFor(player: Player, c, topicId: string): string
	local lawyer = LAWYERS[c.lawyer] or PUBLIC
	local book = Config.Answers[lawyer.Id] or Config.Answers.Public
	local set = book[topicId] or book.Fallback
	local vars, strength = varsOf(player, c)
	local topic = nil
	for _, t in Config.Topics do
		if t.Id == topicId then
			topic = t
		end
	end
	if topic and topic.Case and set[1] == nil then
		local key
		if topic.Case == "witnesses" then
			key = #c.case.witnesses > 0 and "Some" or "None"
		elseif topic.Case == "cameras" then
			key = #camRecords(player) > 0 and "Some" or "None"
		elseif topic.Case == "bail" then
			key = c.bailPaid and "Paid" or (c.bail and "Yes" or "No")
		else
			key = strength
		end
		set = set[key] or set.Some or set.Weak or book.Fallback
	end
	if type(set) ~= "table" or #set == 0 then
		set = book.Fallback
	end
	return fill(pick(set), vars)
end

-- Тема по словам игрока
-- Приветствие и «спасибо» — в последнюю очередь: «привет, что мне грозит?» — это про срок
local SMALL_TALK = { hello = true, thanks = true, bye = true }
local function topicOfText(text: string): string?
	local t = lower(text)
	for pass = 1, 2 do
		for _, topic in Config.Topics do
			if (SMALL_TALK[topic.Id] == true) == (pass == 2) then
				for _, word in topic.Keywords or {} do
					if string.find(t, lower(word), 1, true) then
						return topic.Id
					end
				end
			end
		end
	end
	return nil
end

local function lawyerSays(player: Player, c, text: string)
	remote:FireClient(player, "Lawyer", { text = text, lawyer = c.lawyer })
	if c.visit then
		say(c.visit, text, 4)
	end
end

local function spawnVisit(player: Player, c)
	removePerson(c.visit)
	c.visit = nil
	local lawyer = LAWYERS[c.lawyer] or PUBLIC
	local spot = Registry.justiceStationPart and Registry.justiceStationPart("Visit")
	c.visit = spawnPerson(spot, lawyer.Name, lawyer.Shirt, lawyer.Pants, "Адвокат")
end

---------------------------------------------------------------------
-- 🔒 КПЗ (от WantedServer): блокирует, пока не кончится время или не внесён залог
---------------------------------------------------------------------

local friendCalls = {} -- [друг] = { from = игрок, untilTime }

Registry.courtHolding = function(player: Player, case)
	local c = {
		case = case,
		lawyer = PUBLIC.Id,
		called = false,
		bail = bailOf(case),
		bailPaid = false,
		defender = nil,
		holdEnd = now() + Config.HoldingTime,
		phase = "holding",
		lastAsk = 0,
	}
	cases[player] = c
	if Registry.justiceStage then
		Registry.justiceStage(player, "Holding", { court = true }, Config.HoldingTime)
	end
	pushHolding(player)
	task.delay(1.5, function()
		if cases[player] == c and c.phase == "holding" then
			lawyerSays(player, c, fill(pick(Config.Answers.Public.Greeting), varsOf(player, c)))
		end
	end)
	event(string.format("🔒 %s в КПЗ: свидетелей %d, записей камер %d", player.Name, #case.witnesses, #camRecords(player)))
	local lastPush = now()
	while player.Parent and now() < c.holdEnd and not c.bailPaid do
		task.wait(0.25)
		if now() - lastPush > 5 then
			lastPush = now()
			pushHolding(player) -- свидетель мог погибнуть, друг — выйти из игры
		end
	end
	c.phase = "trial"
	removePerson(c.visit)
	c.visit = nil
	if player.Parent then
		remote:FireClient(player, "HoldingEnd", { bail = c.bailPaid })
	end
end

local function holdingOf(player: Player)
	local c = cases[player]
	return (c and c.phase == "holding") and c or nil
end

remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	if action == "Hire" then
		local c = holdingOf(player)
		local lawyer = type(a) == "string" and LAWYERS[a]
		if not c or not lawyer or c.called or lawyer == PUBLIC then
			return
		end
		if not pay(player, lawyer.Price) then
			toast(player, "Не хватает монет на адвоката")
			return
		end
		c.called = true
		c.lawyer = lawyer.Id
		toast(player, string.format("📞 Ты позвонил адвокату: %s", lawyer.Name))
		event(string.format("💼 %s нанял адвоката: %s (%d)", player.Name, lawyer.Name, lawyer.Price))
		spawnVisit(player, c)
		pushHolding(player)
		task.delay(1.2, function()
			if cases[player] == c then
				lawyerSays(player, c, fill(pick(Config.Answers[lawyer.Id].Greeting), varsOf(player, c)))
			end
		end)
	elseif action == "CallFriend" then
		local c = holdingOf(player)
		local friend = type(a) == "number" and Players:GetPlayerByUserId(a)
		if not c or c.called or not friend or friend == player then
			return
		end
		if (friend:GetAttribute("WantedMode") or "free") ~= "free" then
			toast(player, "Друг сейчас не может ответить")
			return
		end
		c.called = true
		c.friendName = friend.DisplayName
		friendCalls[friend] = { from = player, untilTime = now() + Config.CallTimeout }
		remote:FireClient(friend, "FriendCall", {
			from = player.UserId,
			name = player.DisplayName,
			stars = c.case.stars,
			bail = c.bail,
			canBail = c.bail ~= nil and not c.bailPaid and coins(friend) >= c.bail,
			seconds = Config.CallTimeout,
		})
		toast(player, "📞 Звонишь другу: " .. friend.DisplayName)
		pushHolding(player)
	elseif action == "FriendAnswer" then
		local call = friendCalls[player]
		if not call or now() > call.untilTime or not call.from.Parent or call.from.UserId ~= a then
			return
		end
		friendCalls[player] = nil
		local target = call.from
		local c = cases[target]
		if not c then
			return
		end
		if b == "bail" then
			if c.phase == "holding" and c.bail and not c.bailPaid and pay(player, c.bail) then
				c.bailPaid = true
				toast(target, string.format("💰 %s внёс за тебя залог! Едем в суд", player.DisplayName))
				toast(player, "💰 Залог внесён")
				event(string.format("💰 %s внёс залог за %s", player.Name, target.Name))
			else
				toast(player, "Не получилось внести залог")
			end
		elseif b == "defend" then
			c.defender = player
			toast(target, string.format("⚖️ %s придёт в суд тебя защищать", player.DisplayName))
			toast(player, "⚖️ Тебя позовут в суд, когда начнётся заседание")
		else
			toast(target, string.format("📞 %s знает, что ты в КПЗ", player.DisplayName))
		end
		pushHolding(target)
	elseif action == "Bail" then
		local c = holdingOf(player)
		if not c or not c.bail or c.bailPaid then
			return
		end
		if pay(player, c.bail) then
			c.bailPaid = true
			toast(player, "💰 Залог внесён — сразу в суд")
			event(string.format("💰 %s внёс залог %d", player.Name, c.bail))
		else
			toast(player, "Не хватает монет на залог")
		end
	elseif action == "Ask" then
		local c = holdingOf(player)
		if not c or now() - c.lastAsk < 0.6 or c.typing then
			return
		end
		c.lastAsk = now()
		local topicId = nil
		if type(a) == "string" and #a <= 40 then
			for _, t in Config.Topics do
				if t.Id == a then
					topicId = t.Id
				end
			end
		end
		if not topicId and type(b) == "string" and #b > 0 and #b <= 300 then
			topicId = topicOfText(b)
		end
		c.typing = true
		remote:FireClient(player, "Typing", {})
		task.delay(rng:NextNumber(0.8, 1.8), function()
			c.typing = false
			if cases[player] == c and c.phase == "holding" then
				lawyerSays(player, c, answerFor(player, c, topicId or "Fallback"))
			end
		end)
	elseif action == "Choice" then
		local c = cases[player]
		local pending = c and c.choice
		-- Выбор подсудимого или друга-защитника
		if not pending then
			for _, other in cases do
				if other.choice and other.choice.who == player then
					pending = other.choice
				end
			end
		end
		if pending and pending.who == player and pending.kind == a and type(b) == "number" and pending.options[b] then
			pending.value = b
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local c = cases[player]
	if c then
		removePerson(c.visit)
	end
	cases[player] = nil
	records[player] = nil
	lostCams[player] = nil
	lastNotify[player] = nil
	friendCalls[player] = nil
	for _, other in cases do
		if other.defender == player then
			other.defender = nil
		end
	end
end)

---------------------------------------------------------------------
-- ⚖️ Суд (от WantedServer): возвращает { sentence, fine } или { acquitted = true }
---------------------------------------------------------------------

Registry.courtTrial = function(player: Player, case, info)
	local c = cases[player]
	if not c then
		c = { case = case, lawyer = PUBLIC.Id, bail = nil, phase = "trial" }
		cases[player] = c
	end
	c.phase = "trial"
	local lawyer = LAWYERS[c.lawyer] or PUBLIC
	local judge = info and info.judge
	local judgeName = judge and judge.name or J.JudgeName
	local vars = varsOf(player, c)

	-- Друг-защитник приходит в зал
	local defender = c.defender
	if defender and (not defender.Parent or (defender:GetAttribute("WantedMode") or "free") ~= "free" or not defender.Character) then
		defender = nil
	end
	local audience = { player }
	if defender then
		table.insert(audience, defender)
		local spot = courtPart("Defender") or courtPart("Defense") or courtPart("Dock")
		if spot then
			local p = spot.Position + Vector3.new(0, 3.2, 0) + (courtPart("Defender") and Vector3.zero or spot.CFrame.RightVector * 4)
			local look = flat(spot.CFrame.LookVector)
			movePlayer(defender, CFrame.lookAt(p, p + (look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1))))
		end
		toast(defender, "⚖️ Ты в суде как защитник " .. player.DisplayName)
	end
	local function send(action: string, data)
		for _, p in audience do
			if p.Parent then
				remote:FireClient(p, action, data)
			end
		end
	end

	if Registry.justiceStage then
		Registry.justiceStage(player, "Trial", {}, 300)
	end
	local prosecutor = spawnPerson(courtPart("Prosecutor"), Config.ProsecutorName, Config.ProsecutorShirt, nil, "Суд")
	local advocate = spawnPerson(courtPart("Defense"), lawyer.Name, lawyer.Shirt, lawyer.Pants, "Адвокат")
	send("TrialStart", {
		number = case.number,
		defendant = player.DisplayName,
		lawyer = { Name = lawyer.Name, Title = lawyer.Title, Icon = lawyer.Icon, Rating = lawyer.Rating },
		defender = defender and defender.DisplayName or nil,
	})

	-- Реплика: субтитры у всех в зале + облачко над говорящим
	local function line(role: string, name: string, text: string, npc, evidence)
		if not player.Parent then
			return
		end
		send("Line", { role = role, name = name, text = text, evidence = evidence })
		local seconds = math.clamp(2 + (utf8.len(text) or #text) * 0.045, 2.6, 7)
		say(npc, text, seconds)
		task.wait(seconds)
	end
	local function choose(who: Player, kind: string, options, seconds: number): number?
		if not who.Parent then
			return nil
		end
		local pending = { who = who, kind = kind, options = options, value = nil }
		c.choice = pending
		local texts = {}
		for i, o in options do
			texts[i] = type(o) == "table" and o.Text or o
		end
		remote:FireClient(who, "Choice", { kind = kind, options = texts, seconds = seconds })
		local deadline = now() + seconds
		while who.Parent and player.Parent and now() < deadline and not pending.value do
			task.wait(0.1)
		end
		c.choice = nil
		remote:FireClient(who, "ChoiceEnd", {})
		return pending.value
	end

	local score = 0
	local extra = 0 -- последнее слово и речь друга

	-- 1. Открытие и обвинение
	line("judge", judgeName, fill(pick(L.JudgeOpen), vars), judge)
	line("prosecutor", Config.ProsecutorName, fill(pick(L.ProsecutorCharge), vars), prosecutor)

	-- 2. Полиция видела сама
	if case.policeSaw then
		score += E.Police
		line("police", "Офицер полиции", pick(L.PoliceSay), nil, { kind = "police" })
	end

	-- 3. Свидетели — те, кто дозвонился в 911
	for i, w in case.witnesses do
		local doubted = rng:NextNumber() < lawyer.DoubtWitness
		if i > E.MaxWitnesses then
			score += doubted and E.DoubtedWitness or E.Witness
			continue
		end
		local wv = { name = w.name, why = w.why, Why = capital(w.why) }
		line("prosecutor", Config.ProsecutorName, fill(pick(L.ProsecutorWitness), wv), prosecutor)
		if w.npc and w.npc.alive then
			local person = spawnPerson(courtPart("Witness"), w.name, Config.WitnessShirt, nil, "Суд")
			line("witness", "Свидетель " .. w.name, fill(pick(L.WitnessSay), wv), person, { kind = "witness", name = w.name, why = w.why })
			if doubted then
				line("lawyer", lawyer.Name, pick(L.LawyerDoubtWitness), advocate)
				line("witness", "Свидетель " .. w.name, pick(L.WitnessUnsure), person, { kind = "witness", name = w.name, why = w.why, doubted = true })
				score += E.DoubtedWitness
			else
				score += E.Witness
			end
			removePerson(person)
		else
			line("prosecutor", Config.ProsecutorName, fill(pick(L.WitnessDead), wv), prosecutor, { kind = "call", name = w.name, why = w.why })
			score += E.CallRecord
		end
	end
	if #case.witnesses > E.MaxWitnesses then
		line("prosecutor", Config.ProsecutorName, string.format("Ещё свидетелей: %d. Они говорят то же самое.", #case.witnesses - E.MaxWitnesses), prosecutor)
	end
	if #case.witnesses == 0 then
		line("judge", judgeName, pick(L.NoWitnesses), judge)
	end

	-- 4. Камеры
	for _, name in lostList(player) do
		line("prosecutor", Config.ProsecutorName, fill(pick(L.CameraLost), { cam = name }), prosecutor, { kind = "lost", cam = name })
	end
	for i, r in camRecords(player) do
		local doubted = rng:NextNumber() < lawyer.DoubtCamera
		if i > E.MaxCameras then
			score += doubted and 0 or E.Camera
			continue
		end
		local cv = { cam = r.name, why = r.why }
		line("prosecutor", Config.ProsecutorName, fill(pick(L.ProsecutorCamera), cv), prosecutor)
		line("court", "Запись камеры", fill(L.CameraShow, cv), nil, { kind = "camera", cam = r.name, why = r.why, time = r.time })
		if doubted then
			line("lawyer", lawyer.Name, pick(L.LawyerDoubtCamera), advocate)
			line("judge", judgeName, pick(L.JudgeRejectCamera), judge, { kind = "camera", cam = r.name, why = r.why, time = r.time, doubted = true })
		else
			score += E.Camera
		end
	end

	-- 5. Допрос и арест
	if (case.confessed or 0) > 0 then
		score += case.confessed * E.Confession
		line("prosecutor", Config.ProsecutorName, fill(L.ConfessionSay, { n = case.confessed }), prosecutor)
	end
	if case.surrendered then
		line("lawyer", lawyer.Name, L.Surrendered, advocate)
	elseif case.resisted then
		line("prosecutor", Config.ProsecutorName, L.Resisted, prosecutor)
	end

	-- 6. Защита
	local speeches = Config.DefenseSpeech[lawyer.Id] or Config.DefenseSpeech.Public
	local strength = strengthOf(score)
	line("lawyer", lawyer.Name, fill(pick(speeches[strength] or speeches.Medium), vars), advocate)
	if defender and defender.Parent then
		line("judge", judgeName, fill(L.JudgeFriend, { name = defender.DisplayName }), judge)
		local options = {}
		for i, s in Config.FriendSpeeches do
			options[i] = { Text = fill(s.Text, vars), Effect = s.Effect }
		end
		local i = choose(defender, "Speech", options, Config.FriendSpeechTime) or #options
		extra += options[i].Effect
		line("friend", defender.DisplayName, options[i].Text, nil)
	end

	-- 7. Последнее слово
	line("judge", judgeName, L.JudgeLastWord, judge)
	local wi = choose(player, "LastWord", Config.LastWord, Config.LastWordTime) or 2
	local word = Config.LastWord[wi]
	extra += word.Effect
	line("defendant", player.DisplayName, word.Text, nil)
	if word.Reply and word.Reply ~= "" then
		line("judge", judgeName, word.Reply, judge)
	end

	-- 8. Приговор
	local result
	if score < E.AcquitBelow then
		line("judge", judgeName, pick(L.JudgeAcquit), judge)
		send("Verdict", { acquitted = true })
		result = { acquitted = true }
		event(string.format("⚖️ %s: оправдан (улик %.1f)", player.Name, score))
	else
		local sentence = sentenceFor(case, score, lawyer, extra)
		local base = math.max(case.baseSentence, 1)
		local fine = math.floor((info and info.fine or 0) * math.clamp(sentence / base, 0.5, 1.3))
		line("judge", judgeName, pick(L.JudgeGuilty), judge)
		send("Verdict", { sentence = secondsText(sentence), fine = fine })
		line("judge", judgeName, fill(L.JudgeSentence, { sentence = secondsText(sentence), fine = fine }), judge)
		if J.ConfiscateWeapons then
			line("judge", judgeName, L.Confiscate, judge)
		end
		-- 9. Апелляция
		local price = Config.Appeal.Price
		if coins(player) >= price then
			line("judge", judgeName, L.JudgeAppealAsk, judge)
			local yes = string.format("📄 Обжаловать (%d монет, шанс %d%%)", price, math.floor(lawyer.Appeal * 100))
			local ai = choose(player, "Appeal", { yes, "Принять приговор" }, Config.Appeal.Time)
			if ai == 1 and pay(player, price) then
				line("court", "Апелляционный суд", "Апелляционный суд рассматривает жалобу…", nil)
				if rng:NextNumber() < lawyer.Appeal then
					sentence = math.max(Config.MinSentence, math.floor(sentence * (1 - Config.Appeal.Cut)))
					fine = math.floor(fine / 2)
					send("Verdict", { sentence = secondsText(sentence), fine = fine, appeal = "win" })
					line("judge", "Апелляционный суд", fill(pick(L.AppealWin), { sentence = secondsText(sentence), fine = fine }), judge)
				else
					send("Verdict", { sentence = secondsText(sentence), fine = fine, appeal = "lose" })
					line("judge", "Апелляционный суд", pick(L.AppealLose), judge)
				end
			end
		end
		result = { sentence = sentence, fine = fine }
		event(string.format("⚖️ %s: виновен (улик %.1f) — %d с, штраф %d", player.Name, score, sentence, fine))
	end

	-- Конец заседания
	send("TrialEnd", {})
	removePerson(prosecutor)
	removePerson(advocate)
	if defender and defender.Parent then
		if Registry.addCoins and Config.FriendReward > 0 then
			Registry.addCoins(defender, Config.FriendReward)
		end
		local door = courtPart("CourtDoor")
		if door then
			movePlayer(defender, CFrame.new(door.Position + Vector3.new(0, 3.2, 0)))
		end
	end
	cases[player] = nil
	return result
end
