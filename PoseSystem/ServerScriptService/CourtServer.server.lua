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
local CourtAI = require(script.Parent:WaitForChild("CourtAI"))
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

Registry.courtAIStatus = function(): string
	return CourtAI.status()
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
local buildCtx -- объявлена ниже (дело для нейросети)

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
	c.judge = pick(Config.Judges) -- кто будет судить (адвокат может это обсуждать)
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
		c.history = c.history or {}
		local freeText = (not topicId or not (type(a) == "string" and a == topicId)) and type(b) == "string" and b ~= "" and string.sub(b, 1, 300) or nil
		if freeText then
			table.insert(c.history, "Подзащитный: " .. freeText)
		end
		task.spawn(function()
			local reply = nil
			-- Свой текст — через нейросеть (если есть ключ); кнопки и запасной вариант — готовые ответы
			if freeText and CourtAI.available() then
				reply = CourtAI.lawyerReply(buildCtx(player, c), c.history, freeText, player.UserId)
			end
			if not reply then
				task.wait(rng:NextNumber(0.8, 1.8))
				reply = answerFor(player, c, topicId or "Fallback")
			end
			c.typing = false
			if cases[player] == c and c.phase == "holding" then
				table.insert(c.history, "Адвокат: " .. reply)
				lawyerSays(player, c, reply)
			end
		end)
	elseif action == "Protest" then
		-- Шепнуть адвокату: «протест!»
		local c = cases[player]
		if c and c.phase == "trial" and not c.protest and (c.protests or 0) > 0 then
			c.protests -= 1
			c.protest = true
			remote:FireClient(player, "Protests", { left = c.protests })
		end
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
-- ⚖️ Суд (от WantedServer): живой спор — через нейросеть или без неё — и исход.
-- Возвращает { kind = acquit / fine / probation / community / prison, acquitted, sentence, fine, bags, sub }
---------------------------------------------------------------------

-- Дело для спора: улики с кодами (W1, CALL1, C1, P, LOST1), судья, весы
function buildCtx(player: Player, c)
	local case = c.case
	local evidence, codes = {}, {}
	local function add(e)
		table.insert(evidence, e)
		codes[e.code] = e
	end
	if case.policeSaw then
		add({ code = "P", kind = "police" })
	end
	for i, w in case.witnesses do
		local alive = w.npc ~= nil and w.npc.alive == true
		add({ code = (alive and "W" or "CALL") .. i, kind = alive and "witness" or "call", name = w.name, why = w.why, Why = capital(w.why) })
	end
	for i, r in camRecords(player) do
		add({ code = "C" .. i, kind = "camera", cam = r.name, why = r.why, time = r.time })
	end
	for i, name in lostList(player) do
		add({ code = "LOST" .. i, kind = "lost", cam = name })
	end
	local serious = (case.kills or 0) > 0
	local allowed = (serious and Config.Verdict.SeriousOnlyPrison) and { "acquit", "prison" } or { "acquit", "fine", "probation", "community", "prison" }
	c.judge = c.judge or pick(Config.Judges)
	local score = expectedScore(player, case)
	return {
		number = case.number,
		defendant = player.DisplayName,
		stars = case.stars or 0,
		kills = case.kills or 0,
		injuries = case.injuries or 0,
		policeKills = case.policeKills or 0,
		crimes = case.crimes or {},
		evidence = evidence,
		codes = codes,
		confessed = case.confessed or 0,
		lied = case.lied or 0,
		surrendered = case.surrendered == true,
		resisted = case.resisted == true,
		probationBreach = (player:GetAttribute("ProbationUntil") or 0) > workspace:GetServerTimeNow(),
		judge = c.judge,
		lawyer = LAWYERS[c.lawyer] or PUBLIC,
		friend = nil,
		scale = math.clamp(-0.6 + score * 0.25 + c.judge.Bias, -0.85, 0.85),
		allowed = allowed,
		serious = serious,
		transcript = {},
	}
end

local function lineSeconds(text: string): number
	return math.clamp(2 + (utf8.len(text) or #text) * 0.045, 2.6, 7)
end

Registry.courtTrial = function(player: Player, case, info)
	local c = cases[player]
	if not c then
		c = { case = case, lawyer = PUBLIC.Id, bail = nil }
		cases[player] = c
	end
	c.phase = "trial"
	c.protests = Config.Protests
	c.protest = false
	local lawyer = LAWYERS[c.lawyer] or PUBLIC
	local ctx = buildCtx(player, c)
	local judge = info and info.judge
	if judge and judge.alive then
		-- Сегодня в зале — этот судья
		judge.name = ctx.judge.Name
		judge.model.Name = ctx.judge.Name
		judge.humanoid.DisplayName = ctx.judge.Name
	end

	-- Друг-защитник приходит в зал
	local defender = c.defender
	if defender and (not defender.Parent or (defender:GetAttribute("WantedMode") or "free") ~= "free" or not defender.Character) then
		defender = nil
	end
	local audience = { player }
	if defender then
		ctx.friend = defender.DisplayName
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
		Registry.justiceStage(player, "Trial", {}, 600)
	end
	local prosecutor = spawnPerson(courtPart("Prosecutor"), Config.ProsecutorName, Config.ProsecutorShirt, nil, "Суд")
	local advocate = spawnPerson(courtPart("Defense"), lawyer.Name, lawyer.Shirt, lawyer.Pants, "Адвокат")
	local witnessNpc = nil
	local useAI = CourtAI.available()
	send("TrialStart", {
		number = case.number,
		defendant = player.DisplayName,
		defendantId = player.UserId,
		lawyer = { Name = lawyer.Name, Title = lawyer.Title, Icon = lawyer.Icon, Rating = lawyer.Rating },
		defender = defender and defender.DisplayName or nil,
		judge = ctx.judge.Name,
		mood = ctx.judge.Mood,
		ai = useAI,
		protests = c.protests,
	})
	send("Scale", { value = ctx.scale })
	event(string.format("⚖️ Суд над %s: %s, %s", player.Name, ctx.judge.Name, useAI and "нейросеть" or "без нейросети"))

	local NAMES = { judge = ctx.judge.Name, prosecutor = Config.ProsecutorName, lawyer = lawyer.Name, police = "Офицер полиции" }
	-- Реплика: субтитры у всех в зале, облачко над говорящим, улика на экране
	local function play(l)
		if not player.Parent then
			return
		end
		local role = l.role
		local e = l.evidence and ctx.codes[l.evidence]
		local name = NAMES[role] or l.name or ""
		local npc = nil
		if role == "judge" then
			npc = judge
		elseif role == "prosecutor" then
			npc = prosecutor
		elseif role == "lawyer" then
			npc = advocate
		elseif role == "witness" then
			name = (e and e.name) or (name ~= "" and name) or "Свидетель"
			-- Свидетель выходит на трибуну
			if not witnessNpc or witnessNpc.name ~= name then
				removePerson(witnessNpc)
				witnessNpc = spawnPerson(courtPart("Witness"), name, Config.WitnessShirt, nil, "Суд")
			end
			npc = witnessNpc
		end
		local card = e and { kind = e.kind, name = e.name, why = e.why, cam = e.cam, time = e.time } or nil
		send("Line", { role = role, name = role == "witness" and ("Свидетель " .. name) or name, text = l.text, evidence = card })
		table.insert(ctx.transcript, { role = role, name = name, text = l.text })
		local seconds = lineSeconds(l.text)
		say(npc, l.text, seconds)
		task.wait(seconds)
	end
	local function speak(role: string, name: string, text: string)
		send("Line", { role = role, name = name, text = text })
		table.insert(ctx.transcript, { role = role == "friend" and "friend" or "defendant", name = name, text = text })
		task.wait(lineSeconds(text))
	end
	local function shiftScale(d: number)
		ctx.scale = math.clamp(ctx.scale + d, -1, 1)
		send("Scale", { value = ctx.scale })
	end
	local function choose(who: Player, kind: string, title: string, options, seconds: number): number?
		if not who.Parent or not player.Parent then
			return nil
		end
		local pending = { who = who, kind = kind, options = options, value = nil }
		c.choice = pending
		remote:FireClient(who, "Choice", { kind = kind, title = title, options = options, seconds = seconds })
		local deadline = now() + seconds
		while who.Parent and player.Parent and now() < deadline and not pending.value do
			task.wait(0.1)
		end
		c.choice = nil
		remote:FireClient(who, "ChoiceEnd", {})
		return pending.value
	end
	-- Протест без нейросети — сразу после текущей реплики
	local function offlineProtest()
		if c.protest and not useAI then
			c.protest = false
			local seg = CourtAI.offline(ctx, 0, true)
			for _, l in seg.lines do
				play(l)
			end
			shiftScale(seg.shift)
		end
	end
	-- Одна часть заседания
	local function runPart(part: number, promptIndex: number)
		local protest = c.protest
		c.protest = false
		local seg = nil
		if useAI then
			send("Wait", { text = pick(Config.Debate.Waiting) })
			seg = CourtAI.segment(ctx, promptIndex, protest, player.UserId)
			send("WaitEnd", {})
			if not seg then
				useAI = false
				event("🤖 Нейросеть суда: " .. CourtAI.status() .. " — дальше без неё")
				send("Mode", { ai = false })
			end
		end
		if not seg then
			seg = CourtAI.offline(ctx, part, protest)
			seg.offline = true
		end
		for _, l in seg.lines do
			play(l)
			offlineProtest()
		end
		shiftScale(seg.shift)
		return seg
	end
	-- Вопрос: от нейросети или запасной; ответ без нейросети сдвигает весы сразу
	local function question(seg, part: number, who: Player, kind: string, role: string): string?
		if not seg.question then
			local backup = CourtAI.offline(ctx, part, false)
			seg.question = backup.question
			seg.offline = true
		end
		if not seg.question then
			return nil
		end
		local i = choose(who, kind, seg.question.text, seg.question.options, 16)
		local text = i and seg.question.options[i] or "…(молчит)"
		speak(role, who.DisplayName, text)
		if seg.offline then
			shiftScale((i and ctx.optionShifts and ctx.optionShifts[i]) or 0.03)
			ctx.answerShift = (i and ctx.optionShifts and ctx.optionShifts[i]) or 0.03
		end
		return text
	end

	-- 1. Открытие, обвинение, улики
	runPart(1, 1)
	-- 2. Защита и вопрос подсудимому
	local seg = runPart(2, 2)
	question(seg, 2, player, "Question", "defendant")
	-- 3. Реакция, повороты, слово другу
	seg = runPart(3, defender and 4 or 3)
	if defender and defender.Parent then
		question(seg, 3, defender, "Speech", "friend")
	end
	-- 4. Заключительные речи и последнее слово
	seg = runPart(4, 5)
	question(seg, 4, player, "LastWord", "defendant")
	-- 5. Приговор
	seg = runPart(5, 6)
	local verdict = seg.verdict or CourtAI.offline(ctx, 5, false).verdict
	local kind = verdict.kind
	if not table.find(ctx.allowed, kind) then
		kind = "prison"
	end
	if ctx.probationBreach and kind ~= "acquit" then
		kind = "prison"
		play({ role = "judge", text = "Подсудимый нарушил условный срок. Наказание — вдвое строже." })
	end
	if verdict.reason and verdict.reason ~= "" then
		play({ role = "judge", text = verdict.reason })
	end

	-- Числа исхода
	local sev = verdict.severity
	local base = case.baseSentence * (case.modifier or 1) * (1 - lawyer.Discount)
	if case.surrendered then
		base *= 1 - Config.Surrender
	elseif case.resisted then
		base *= 1 + Config.Resist
	end
	local sentence = math.floor(math.clamp(base * (0.5 + sev), Config.MinSentence, J.Sentence.Max))
	if ctx.probationBreach then
		sentence = math.min(J.Sentence.Max, sentence * Config.Probation.Multiplier)
	end
	local fineBase = info and info.fine or 0
	local fine = kind == "acquit" and 0 or math.floor(fineBase * (kind == "fine" and (1 + sev) or (0.5 + sev * 0.8)))
	local CM = Config.Community
	local bags = math.floor(CM.MinBags + sev * (CM.MaxBags - CM.MinBags) + 0.5)
	local function verdictText(): string
		return fill(pick(Config.Verdict.Lines[kind]), {
			fine = fine,
			sentence = secondsText(sentence),
			bags = bags,
			probation = secondsText(Config.Probation.Time),
		})
	end
	send("Verdict", { kind = kind, sentence = secondsText(sentence), fine = fine, bags = bags })
	play({ role = "judge", text = verdictText() })
	if kind ~= "acquit" and J.ConfiscateWeapons then
		play({ role = "judge", text = L.Confiscate })
	end

	-- Апелляция
	local price = Config.Appeal.Price
	if kind ~= "acquit" and player.Parent and coins(player) >= price then
		play({ role = "judge", text = L.JudgeAppealAsk })
		local yes = string.format("📄 Обжаловать (%d монет, шанс %d%%)", price, math.floor(lawyer.Appeal * 100))
		local ai = choose(player, "Appeal", "Обжаловать приговор?", { yes, "Принять приговор" }, Config.Appeal.Time)
		if ai == 1 and pay(player, price) then
			play({ role = "court", text = "Апелляционный суд рассматривает жалобу…" })
			if rng:NextNumber() < lawyer.Appeal then
				local cut = Config.Appeal.Cut
				sentence = math.max(Config.MinSentence, math.floor(sentence * (1 - cut)))
				bags = math.max(1, math.floor(bags * (1 - cut) + 0.5))
				fine = math.floor(fine / 2)
				if kind == "prison" and sentence <= Config.MinSentence and rng:NextNumber() < 0.5 then
					kind = "community" -- апелляция заменила тюрьму работами
				end
				send("Verdict", { kind = kind, sentence = secondsText(sentence), fine = fine, bags = bags, appeal = "win" })
				play({ role = "judge", text = "Жалоба удовлетворена! " .. verdictText() })
			else
				send("Verdict", { kind = kind, sentence = secondsText(sentence), fine = fine, bags = bags, appeal = "lose" })
				play({ role = "judge", text = pick(L.AppealLose) })
			end
		end
	end

	-- Конец заседания
	send("TrialEnd", {})
	removePerson(prosecutor)
	removePerson(advocate)
	removePerson(witnessNpc)
	if defender and defender.Parent then
		if Registry.addCoins and Config.FriendReward > 0 then
			Registry.addCoins(defender, Config.FriendReward)
		end
		local door = courtPart("CourtDoor")
		if door then
			movePlayer(defender, CFrame.new(door.Position + Vector3.new(0, 3.2, 0)))
		end
	end
	if kind == "probation" then
		player:SetAttribute("ProbationUntil", workspace:GetServerTimeNow() + Config.Probation.Time)
	end
	cases[player] = nil
	event(string.format("⚖️ %s: %s (весы %.2f) — срок %d, штраф %d, мусор %d", player.Name, kind, ctx.scale, sentence, fine, bags))
	local SUB = {
		acquit = "Оправдан судом — оружие и монеты остаются у тебя",
		fine = string.format("Штраф %d монет оплачен — ты свободен", fine),
		probation = string.format("Условный срок %s: попадёшься — сядешь вдвое дольше", secondsText(Config.Probation.Time)),
		community = "Общественные работы выполнены — ты свободен",
	}
	return { kind = kind, acquitted = kind == "acquit", sentence = sentence, fine = fine, bags = bags, sub = SUB[kind] }
end

---------------------------------------------------------------------
-- 🧹 Общественные работы (от WantedServer): убрать мусор по городу. true — справился
---------------------------------------------------------------------

local function groundAt(pos: Vector3, ignore): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), params)
	return hit and hit.Position or nil
end

local function communitySpots(center: Vector3, count: number, ignore): { Vector3 }
	local CM = Config.Community
	local candidates = {}
	local root = workspace:FindFirstChild("JusticeSystem")
	local own = root and root:FindFirstChild("Community")
	local folders = {}
	if own then
		table.insert(folders, own)
	else
		local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
		for _, name in { "Places", "BusStops", "PoliceCalls" } do
			local f = map and map:FindFirstChild(name)
			if f then
				table.insert(folders, f)
			end
		end
	end
	for _, f in folders do
		for _, d in f:GetDescendants() do
			if d:IsA("BasePart") and (d.Position - center).Magnitude < CM.Radius then
				local offset = own and Vector3.zero or Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
				table.insert(candidates, d.Position + offset)
			end
		end
	end
	for i = #candidates, 2, -1 do
		local j = rng:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local spots = {}
	local function far(p: Vector3): boolean
		for _, q in spots do
			if (p - q).Magnitude < 14 then
				return false
			end
		end
		return true
	end
	for _, p in candidates do
		if #spots >= count then
			break
		end
		local g = groundAt(p, ignore)
		if g and far(g) then
			table.insert(spots, g)
		end
	end
	-- Мест не хватило — вокруг
	local tries = 0
	while #spots < count and tries < 60 do
		tries += 1
		local a = rng:NextNumber() * math.pi * 2
		local r = rng:NextNumber(20, 70)
		local g = groundAt(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), ignore)
		if g and far(g) then
			table.insert(spots, g)
		end
	end
	return spots
end

Registry.courtCommunity = function(player: Player, bagsCount: number, sentence: number): boolean
	local CM = Config.Community
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	-- Не досидел (вышел из игры) — при следующем заходе сядет
	local profile = Registry.weaponProfile and Registry.weaponProfile(player)
	if profile then
		profile.jail = sentence
		if Registry.weaponSave then
			Registry.weaponSave(player)
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "Community_" .. player.UserId
	folder.Parent = workspace
	local npcRoot = workspace:FindFirstChild("NPCSystem")
	local ignore = { folder, camFolder, character }
	if npcRoot and npcRoot:FindFirstChild("Live") then
		table.insert(ignore, npcRoot.Live)
	end
	local spots = communitySpots(root.Position, bagsCount, ignore)

	-- Оранжевый жилет
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local vest = nil
	if torso and torso:IsA("BasePart") then
		vest = Instance.new("Part")
		vest.Name = "CommunityVest"
		vest.Size = torso.Size * Vector3.new(1.08, 0.9, 1.15)
		vest.Color = CM.Color
		vest.Material = Enum.Material.SmoothPlastic
		vest.CanCollide = false
		vest.CanQuery = false
		vest.CanTouch = false
		vest.Massless = true
		vest.CFrame = torso.CFrame
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = vest
		w.Parent = vest
		vest.Parent = character
	end
	local from = Instance.new("Attachment")
	from.Name = "CommunityFrom"
	from.Parent = root
	local beam = Instance.new("Beam")
	beam.Color = ColorSequence.new(CM.Color)
	beam.Width0, beam.Width1 = 0.25, 0.25
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.Transparency = NumberSequence.new(0.3)
	beam.Attachment0 = from
	beam.Parent = root

	local bags = {}
	local done = 0
	for _, pos in spots do
		local bag = Instance.new("Part")
		bag.Name = "TrashBag"
		bag.Shape = Enum.PartType.Ball
		bag.Size = Vector3.new(2.2, 2.2, 2.2)
		bag.Color = Color3.fromRGB(25, 25, 28)
		bag.Material = Enum.Material.Plastic
		bag.Anchored = true
		bag.CanCollide = false
		bag.Position = pos + Vector3.new(0, 1, 0)
		bag.Parent = folder
		local knot = Instance.new("Part")
		knot.Size = Vector3.new(0.5, 0.6, 0.5)
		knot.Color = bag.Color
		knot.Anchored = true
		knot.CanCollide = false
		knot.Position = bag.Position + Vector3.new(0, 1.2, 0)
		knot.Parent = folder
		local att = Instance.new("Attachment")
		att.Parent = bag
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Убрать мусор"
		prompt.ObjectText = "🧹 Общественные работы"
		prompt.HoldDuration = CM.HoldTime
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = bag
		local entry = { bag = bag, knot = knot, att = att, taken = false }
		table.insert(bags, entry)
		prompt.Triggered:Connect(function(who: Player)
			if who ~= player then
				toast(who, "Это чужие общественные работы")
				return
			end
			if entry.taken then
				return
			end
			entry.taken = true
			done += 1
			local burst = Instance.new("ParticleEmitter")
			burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			burst.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
			burst.Rate = 0
			burst.Speed = NumberRange.new(4, 8)
			burst.Parent = bag
			burst:Emit(20)
			bag.Transparency = 1
			knot:Destroy()
			prompt:Destroy()
			game:GetService("Debris"):AddItem(bag, 1)
		end)
	end
	local total = #bags
	local endAt = now() + math.max(total, 1) * CM.TimePerBag
	toast(player, string.format("🧹 Общественные работы: убери %d куч мусора", total))
	while player.Parent and done < total and now() < endAt do
		-- Луч — к ближайшей неубранной куче
		local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local best, bestD = nil, math.huge
		for _, b in bags do
			if not b.taken and r then
				local d = (b.bag.Position - r.Position).Magnitude
				if d < bestD then
					best, bestD = b, d
				end
			end
		end
		beam.Attachment1 = best and best.att or nil
		remote:FireClient(player, "Community", { done = done, total = total, endAt = workspace:GetServerTimeNow() + (endAt - now()) })
		task.wait(0.5)
	end
	local ok = player.Parent ~= nil and done >= total
	folder:Destroy()
	beam:Destroy()
	from:Destroy()
	if vest then
		vest:Destroy()
	end
	if player.Parent then
		remote:FireClient(player, "CommunityEnd", { ok = ok })
		if ok and profile then
			profile.jail = nil
			if Registry.weaponSave then
				Registry.weaponSave(player)
			end
		end
	end
	event(string.format("🧹 %s: общественные работы %s (%d/%d)", player.Name, ok and "выполнены" or "провалены", done, total))
	return ok
end
