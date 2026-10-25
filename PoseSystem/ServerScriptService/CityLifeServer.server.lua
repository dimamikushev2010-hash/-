-- Script: ServerScriptService > CityLifeServer
-- Новые механики города (настройки — ReplicatedStorage > CityConfig):
--   📦 Курьер      — забрать посылку на «Почте» и отнести случайному жителю
--   🛍 Магазин     — аксессуары за монеты (собираются из деталей прямо на персонаже)
--   🏆 Достижения  — счётчики полёта, такси, друзей, доставок... с наградой
--   📷 Фоторежим   — жители рядом позируют, когда игрок фотографирует
--   💾 Сохранение  — монеты, покупки, достижения (DataStore)
-- Работает через телефон (PhoneRemote) и на уже расставленных метках. Новых меток не нужно.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CityConfig"))
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local rng = Random.new()
local remote = ReplicatedStorage:WaitForChild("PhoneRemote")

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function toast(player: Player, text: string)
	if Registry.toast then
		Registry.toast(player, text)
	end
end

local function wallet(player: Player): IntValue?
	if Registry.getCoins then
		return Registry.getCoins(player)
	end
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild(NPCConfig.CurrencyName) or nil
end

local function giveCoins(player: Player, amount: number)
	if Registry.addCoins then
		Registry.addCoins(player, amount)
	else
		local w = wallet(player)
		if w then
			w.Value += amount
		end
	end
end

local SHOP = {}
for _, item in Config.Shop do
	SHOP[item.Id] = item
end

---------------------------------------------------------------------
-- Данные игрока и сохранение
---------------------------------------------------------------------

local profiles = {} -- [player] = { stats, done, owned, equipped, loaded }
local store = nil
if Config.SaveEnabled then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	store = ok and result or nil
end

local function profileOf(player: Player)
	local p = profiles[player]
	if not p then
		p = { stats = {}, done = {}, owned = {}, equipped = {}, loaded = false }
		profiles[player] = p
	end
	return p
end

local function save(player: Player)
	local p = profiles[player]
	if not store or not p or not p.loaded then
		return
	end
	local w = wallet(player)
	local data = { coins = w and w.Value or 0, stats = p.stats, done = p.done, owned = p.owned, equipped = p.equipped }
	local ok, err = pcall(function()
		store:SetAsync("p_" .. player.UserId, data)
	end)
	if not ok then
		warn("[CityLife] Не удалось сохранить", player.Name, err)
	end
end

local function load(player: Player)
	local p = profileOf(player)
	if not store then
		local w = wallet(player)
		if w and (Config.StartCoins or 0) > 0 then
			w.Value = Config.StartCoins
		end
	end
	if store then
		local ok, data = pcall(function()
			return store:GetAsync("p_" .. player.UserId)
		end)
		if ok and data == nil then
			-- Новый игрок: стартовые монеты
			local w = wallet(player)
			if w and (Config.StartCoins or 0) > 0 then
				w.Value = Config.StartCoins
			end
		end
		if ok and type(data) == "table" then
			p.stats = data.stats or {}
			p.done = data.done or {}
			p.owned = data.owned or {}
			p.equipped = data.equipped or {}
			local w = wallet(player)
			if w and type(data.coins) == "number" then
				w.Value = data.coins
			end
		elseif not ok then
			warn("[CityLife] Сохранения недоступны (в Studio включи API Services):", data)
		end
	end
	p.loaded = true
end

---------------------------------------------------------------------
-- Данные для телефона
---------------------------------------------------------------------

local function cityData(player: Player)
	local p = profileOf(player)
	local done = {}
	for id in pairs(p.done) do
		table.insert(done, id)
	end
	local owned = {}
	for id in pairs(p.owned) do
		table.insert(owned, id)
	end
	local equipped = {}
	for _, id in pairs(p.equipped) do
		table.insert(equipped, id)
	end
	return { stats = p.stats, done = done, owned = owned, equipped = equipped }
end

local pushQueued = {}
local function push(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.delay(0.3, function()
		pushQueued[player] = nil
		if player.Parent then
			remote:FireClient(player, "City", cityData(player))
		end
	end)
end

---------------------------------------------------------------------
-- 🏆 Достижения
---------------------------------------------------------------------

local function addStat(player: Player, stat: string, amount: number?)
	local p = profileOf(player)
	if Registry.debugCount then
		Registry.debugCount(stat, amount or 1)
	end
	local before = p.stats[stat] or 0
	local after = before + (amount or 1)
	p.stats[stat] = after
	local changed = math.floor(before) ~= math.floor(after)
	for _, a in Config.Achievements do
		if a.Stat == stat and not p.done[a.Id] and after >= a.Goal then
			p.done[a.Id] = true
			changed = true
			giveCoins(player, a.Reward)
			remote:FireClient(player, "Achievement", { icon = a.Icon, name = a.Name, reward = a.Reward })
			if Registry.debugEvent then
				Registry.debugEvent(string.format("🏆 %s: достижение «%s»", player.Name, a.Name))
			end
		end
	end
	if changed then
		push(player)
	end
end

-- События от жителей и транспорта: Taxi, Bus, Report, Arrest, Friend, Quest
Registry.playerEvent = function(player: Player, name: string)
	if player and player.Parent then
		addStat(player, name, 1)
	end
end

-- Способности, прогулки и ночь — проверяем по атрибутам персонажа
local ABILITY_FLAGS = { Invisible = "Invisible", LaserActive = "Laser", CubeForm = "Cube" }
local tracking = {} -- [player] = { flags = {}, lastPos }

task.spawn(function()
	local STEP = 0.5
	while true do
		task.wait(STEP)
		local night = workspace:GetAttribute("Period") == "Ночь"
		for _, player in Players:GetPlayers() do
			local t = tracking[player]
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if t and humanoid and root and humanoid.Health > 0 then
				if character:GetAttribute("Flying") == true then
					addStat(player, "Fly", STEP)
				end
				for attribute, stat in pairs(ABILITY_FLAGS) do
					local on = character:GetAttribute(attribute) == true
					if on and not t.flags[attribute] then
						addStat(player, stat, 1)
					end
					t.flags[attribute] = on
				end
				local pos = root.Position
				if t.lastPos then
					local moved = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(t.lastPos.X, 0, t.lastPos.Z)).Magnitude
					local walking = humanoid.SeatPart == nil and humanoid.FloorMaterial ~= Enum.Material.Air
						and character:GetAttribute("Flying") ~= true and character:GetAttribute("CubeForm") ~= true
					if walking and moved > 0.5 and moved < 25 then
						addStat(player, "Walk", moved)
					end
				end
				t.lastPos = pos
				if night then
					addStat(player, "Night", STEP / 60)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- 🛍 Аксессуары
---------------------------------------------------------------------

local function decor(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	p:SetAttribute("BaseTransparency", p.Transparency)
	p.Parent = parent
	return p
end

local function weldTo(part: BasePart, to: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- цилиндр стоя

-- Видимая ширина головы: у R6 деталь 2×1×1, но выглядит как ~1.25
local function headSize(head: BasePart): Vector3
	local w = math.min(head.Size.X, head.Size.Z * 1.25)
	return Vector3.new(w, head.Size.Y, w)
end

local BUILDERS = {}

function BUILDERS.Hat(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local top = head.CFrame * CFrame.new(0, hs.Y / 2, 0)
	weldTo(decor(folder, Vector3.new(hs.X * 1.08, 0.42, hs.Z * 1.08), top * CFrame.new(0, 0.08, 0), item.Color), head)
	weldTo(decor(folder, Vector3.new(hs.X * 0.95, 0.08, 0.75), top * CFrame.new(0, -0.08, -hs.Z / 2 - 0.3), item.Color:Lerp(Color3.new(1, 1, 1), 0.1)), head)
	weldTo(decor(folder, Vector3.new(0.22, 0.22, 0.22), top * CFrame.new(0, 0.32, 0), Color3.new(1, 1, 1), nil, Enum.PartType.Ball), head)
end

function BUILDERS.TopHat(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local top = head.CFrame * CFrame.new(0, hs.Y / 2, 0)
	local w = hs.X
	weldTo(decor(folder, Vector3.new(0.08, w * 1.6, w * 1.6), top * UPRIGHT, item.Color, nil, Enum.PartType.Cylinder), head)
	weldTo(decor(folder, Vector3.new(1.1, w * 0.95, w * 0.95), top * CFrame.new(0, 0.58, 0) * UPRIGHT, item.Color, nil, Enum.PartType.Cylinder), head)
	weldTo(decor(folder, Vector3.new(0.2, w * 0.97, w * 0.97), top * CFrame.new(0, 0.18, 0) * UPRIGHT, Color3.fromRGB(170, 30, 40), nil, Enum.PartType.Cylinder), head)
end

function BUILDERS.Crown(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local top = head.CFrame * CFrame.new(0, hs.Y / 2 + 0.12, 0)
	local r = hs.X * 0.5
	weldTo(decor(folder, Vector3.new(0.28, r * 2.1, r * 2.1), top * UPRIGHT, item.Color, Enum.Material.Metal, Enum.PartType.Cylinder), head)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local spike = top * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, -r * 0.92)
		weldTo(decor(folder, Vector3.new(0.18, 0.36, 0.08), spike, item.Color, Enum.Material.Metal), head)
		local gem = decor(folder, Vector3.new(0.13, 0.13, 0.13), spike * CFrame.new(0, -0.18, -0.06), i % 2 == 0 and Color3.fromRGB(220, 30, 60) or Color3.fromRGB(40, 120, 255), Enum.Material.Neon, Enum.PartType.Ball)
		weldTo(gem, head)
	end
end

function BUILDERS.Face(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local front = head.CFrame * CFrame.new(0, hs.Y * 0.08, -hs.Z / 2 - 0.04)
	local lensW = hs.X * 0.32
	for _, side in { -1, 1 } do
		local lens = decor(folder, Vector3.new(lensW, 0.26, 0.05), front * CFrame.new(side * lensW * 0.62, 0, 0), item.Color, Enum.Material.Glass)
		lens.Reflectance = 0.3
		weldTo(lens, head)
	end
	weldTo(decor(folder, Vector3.new(lensW * 0.4, 0.06, 0.05), front * CFrame.new(0, 0.06, 0), item.Color), head)
end

function BUILDERS.Halo(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local center = head.CFrame * CFrame.new(0, hs.Y / 2 + 0.7, 0)
	local r = hs.X * 0.55
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		local seg = decor(folder, Vector3.new(0.12, 0.08, r * 0.5), center * CFrame.Angles(0, a, 0) * CFrame.new(r, 0, 0), item.Color, Enum.Material.Neon)
		weldTo(seg, head)
	end
	local glow = Instance.new("PointLight")
	glow.Color = item.Color
	glow.Brightness = 1.5
	glow.Range = 8
	glow.Parent = folder:FindFirstChildWhichIsA("BasePart")
end

function BUILDERS.Balloon(folder, character, item)
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart
	if not hand then
		return
	end
	local ball = decor(folder, Vector3.new(1.7, 1.9, 1.7), hand.CFrame * CFrame.new(0, 6, 0), item.Color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	ball.Massless = false
	ball.Reflectance = 0.15
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.05, 0, 0, 1, 1)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = ball
	folder:SetAttribute("HandAttachment", true)
	a0.Name = "BalloonAttachment"
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = a0
	rope.Attachment1 = a1
	rope.Length = 5
	rope.Visible = true
	rope.Thickness = 0.04
	rope.Color = BrickColor.new("Institutional white")
	rope.Parent = ball
	-- Подъёмная сила чуть больше веса
	local lift = Instance.new("VectorForce")
	lift.Attachment0 = a1
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.Force = Vector3.new(0, ball:GetMass() * workspace.Gravity * 1.6, 0)
	lift.Parent = ball
	-- Немного сопротивления воздуха, чтобы шарик не болтался
	local drag = Instance.new("LinearVelocity")
	drag.Attachment0 = a1
	drag.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drag.VectorVelocity = Vector3.zero
	drag.MaxForce = ball:GetMass() * workspace.Gravity * 0.6
	drag.Parent = ball
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		pcall(function()
			ball:SetNetworkOwner(player)
		end)
	end
end

function BUILDERS.Trail(folder, character)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local a0 = Instance.new("Attachment")
	a0.Name = "CosmeticTrailTop"
	a0.Position = Vector3.new(0, 0.9, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "CosmeticTrailBottom"
	a1.Position = Vector3.new(0, -1.6, 0.4)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.7
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 60)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 220, 90)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(60, 140, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 80, 255)),
	})
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = folder
end

function BUILDERS.Aura(folder, character, item)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local a = Instance.new("Attachment")
	a.Name = "CosmeticAura"
	a.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(item.Color)
	e.LightEmission = 0.7
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate = 14
	e.Speed = NumberRange.new(1, 2.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 2, 0)
	e.Parent = a
	-- Эмиттер живёт в папке, чтобы его можно было найти и выключить
	local ref = Instance.new("ObjectValue")
	ref.Name = "AuraRef"
	ref.Value = e
	ref.Parent = folder
end

-- Спрятать аксессуары, пока персонаж невидим или в форме куба
local function hiddenNow(character: Model): boolean
	return character:GetAttribute("Invisible") == true or character:GetAttribute("CubeForm") == true
end

local function refreshVisibility(character: Model)
	local folder = character:FindFirstChild("Cosmetics")
	if not folder then
		return
	end
	local hide = hiddenNow(character)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = hide and 1 or (d:GetAttribute("BaseTransparency") or 0)
		elseif d:IsA("Trail") or d:IsA("RopeConstraint") or d:IsA("PointLight") then
			if d:IsA("RopeConstraint") then
				d.Visible = not hide
			else
				d.Enabled = not hide
			end
		elseif d:IsA("ObjectValue") and d.Value and d.Value:IsA("ParticleEmitter") then
			(d.Value :: ParticleEmitter).Enabled = not hide
		end
	end
end

local function clearCosmetics(character: Model)
	local old = character:FindFirstChild("Cosmetics")
	if old then
		for _, d in old:GetDescendants() do
			if d:IsA("ObjectValue") and d.Value then
				local att = d.Value.Parent
				d.Value:Destroy()
				if att and att:IsA("Attachment") then
					att:Destroy()
				end
			end
		end
		old:Destroy()
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, name in { "CosmeticTrailTop", "CosmeticTrailBottom", "CosmeticAura" } do
			local a = root:FindFirstChild(name)
			if a then
				a:Destroy()
			end
		end
	end
	for _, d in character:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "BalloonAttachment" then
			d:Destroy()
		end
	end
end

local function applyCosmetics(player: Player)
	local character = player.Character
	if not character or not character:FindFirstChild("Head") or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	clearCosmetics(character)
	local folder = Instance.new("Folder")
	folder.Name = "Cosmetics"
	folder.Parent = character
	for _, id in pairs(profileOf(player).equipped) do
		local item = SHOP[id]
		local build = item and BUILDERS[item.Kind]
		if build then
			local ok, err = pcall(build, folder, character, item)
			if not ok then
				warn("[CityLife] Не удалось надеть", id, err)
			end
		end
	end
	refreshVisibility(character)
end

local function equip(player: Player, id: string)
	local p = profileOf(player)
	local item = SHOP[id]
	if not item or not p.owned[id] then
		return
	end
	if p.equipped[item.Slot] == id then
		p.equipped[item.Slot] = nil
	else
		p.equipped[item.Slot] = id
	end
	applyCosmetics(player)
	push(player)
end

local function buy(player: Player, id: string)
	local p = profileOf(player)
	local item = SHOP[id]
	if not item then
		return
	end
	if p.owned[id] then
		equip(player, id)
		return
	end
	local w = wallet(player)
	if not w or w.Value < item.Price then
		toast(player, "Не хватает монет 🪙")
		remote:FireClient(player, "ShopResult", { ok = false })
		return
	end
	w.Value -= item.Price
	p.owned[id] = true
	p.equipped[item.Slot] = id
	toast(player, string.format("%s %s куплено! -%d 🪙", item.Icon, item.Name, item.Price))
	remote:FireClient(player, "ShopResult", { ok = true, id = id })
	applyCosmetics(player)
	addStat(player, "Buy", 1)
	push(player)
end

---------------------------------------------------------------------
-- 📦 Курьер
---------------------------------------------------------------------

local jobs = {} -- [player] = { stage, crate, target, item, started }

local function jobTargetValue(player: Player): ObjectValue
	local v = player:FindFirstChild("JobTarget")
	if not v then
		v = Instance.new("ObjectValue")
		v.Name = "JobTarget"
		v.Parent = player
	end
	return v :: ObjectValue
end

local function setJobInfo(player: Player, stage: string?, text: string?, target: Instance?)
	player:SetAttribute("JobStage", stage)
	player:SetAttribute("JobText", text)
	jobTargetValue(player).Value = target
	local job = jobs[player]
	player:SetAttribute("JobEnds", job and stage and (workspace:GetServerTimeNow() + Config.Job.TimeLimit - (os.clock() - job.started)) or nil)
end

local function removeBox(player: Player)
	local character = player.Character
	if character then
		character:SetAttribute("CarryBox", nil)
		local box = character:FindFirstChild("CourierBox")
		if box then
			box:Destroy()
		end
	end
end

local function giveBox(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or character:FindFirstChild("CourierBox") then
		return
	end
	local box = decor(character, Vector3.new(1.7, 1.2, 1.3), root.CFrame * CFrame.new(0, 0.1, -1.25), Color3.fromRGB(190, 140, 85), Enum.Material.Cardboard)
	box.Name = "CourierBox"
	local tape = decor(box, Vector3.new(0.3, 1.22, 1.32), box.CFrame, Color3.fromRGB(150, 105, 60), Enum.Material.SmoothPlastic)
	weldTo(tape, box)
	weldTo(box, root)
	character:SetAttribute("CarryBox", true)
	refreshVisibility(character)
end

local function endJob(player: Player, message: string?)
	local job = jobs[player]
	if job and job.crate then
		job.crate:Destroy()
	end
	jobs[player] = nil
	removeBox(player)
	setJobInfo(player, nil, nil, nil)
	if message then
		toast(player, message)
	end
	remote:FireClient(player, "Job", { active = false, text = message })
end

local function residentOk(npc): boolean
	return npc.alive and not npc.officer and not npc.controlled and npc.model and npc.model.Parent ~= nil
end

local function chooseRecipient(player: Player, except)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local options = {}
	for _, npc in pairs(Registry.npcs) do
		if residentOk(npc) and npc ~= except then
			local far = root and (npc.hrp.Position - root.Position).Magnitude or 100
			table.insert(options, { npc = npc, weight = far > 40 and 3 or 1 })
		end
	end
	if #options == 0 then
		return nil
	end
	local total = 0
	for _, o in options do
		total += o.weight
	end
	local roll = rng:NextNumber() * total
	for _, o in options do
		roll -= o.weight
		if roll <= 0 then
			return o.npc
		end
	end
	return options[1].npc
end

local function startDelivery(player: Player)
	local job = jobs[player]
	if not job then
		return
	end
	local target = chooseRecipient(player, nil)
	if not target then
		endJob(player, "В городе пока никого нет — заказ отменён")
		return
	end
	job.stage = "deliver"
	job.target = target
	giveBox(player)
	setJobInfo(player, "deliver", string.format("Отнеси %s → %s", job.item, target.name), target.model)
	toast(player, string.format("📦 Посылка для: %s", target.name))
	remote:FireClient(player, "Job", { active = true, stage = "deliver", text = player:GetAttribute("JobText") })
end

local function placesList()
	local root = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local folder = root and root:FindFirstChild("Places")
	local list = {}
	if folder then
		for _, p in folder:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(list, p)
			end
		end
	end
	return list
end

local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	return hit and hit.Position or position
end

local function startJob(player: Player)
	if jobs[player] then
		endJob(player, "Заказ отменён")
		return
	end
	local job = { stage = "pickup", item = pick(Config.Job.Items), started = os.clock() }
	jobs[player] = job
	-- Где забрать
	local list = placesList()
	local depot = nil
	for _, p in list do
		if (p:GetAttribute("PlaceName") or p.Name) == Config.Job.DepotName then
			depot = p
		end
	end
	depot = depot or (#list > 0 and list[rng:NextInteger(1, #list)] or nil)
	if not depot then
		startDelivery(player)
		return
	end
	local floor = groundAt(depot.Position)
	local crate = Instance.new("Part")
	crate.Name = "CourierPickup"
	crate.Size = Vector3.new(2, 1.4, 1.6)
	crate.CFrame = CFrame.new(floor + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
	crate.Anchored = true
	crate.CanCollide = false
	crate.Color = Color3.fromRGB(190, 140, 85)
	crate.Material = Enum.Material.Cardboard
	crate.Parent = workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Взять посылку"
	prompt.ObjectText = job.item
	prompt.HoldDuration = 0.4
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = crate
	prompt.Triggered:Connect(function(who)
		if who == player and jobs[player] == job and job.stage == "pickup" then
			crate:Destroy()
			job.crate = nil
			startDelivery(player)
		end
	end)
	job.crate = crate
	local placeName = depot:GetAttribute("PlaceName") or depot.Name
	setJobInfo(player, "pickup", string.format("Забери посылку: %s", placeName), crate)
	toast(player, "📦 Новый заказ! Забери посылку: " .. placeName)
	remote:FireClient(player, "Job", { active = true, stage = "pickup", text = player:GetAttribute("JobText") })
end

local function deliver(player: Player, job)
	local npc = job.target
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and Registry.face then
		task.spawn(Registry.face, npc, root.Position - npc.hrp.Position, 2)
	end
	if Registry.say then
		Registry.say(npc, pick(Config.Job.Thanks))
	end
	if Registry.emote then
		Registry.emote(npc, "Cheer")
	end
	if Registry.sfx then
		Registry.sfx(npc, "Cheer")
	end
	if Registry.setMood then
		Registry.setMood(npc, "Happy", 4)
	end
	local took = os.clock() - job.started
	local reward = rng:NextInteger(Config.Job.Reward.Min, Config.Job.Reward.Max)
	local fast = took <= Config.Job.FastTime
	if fast then
		reward += Config.Job.FastBonus
	end
	giveCoins(player, reward)
	if Registry.addFriendship then
		Registry.addFriendship(npc, player, Config.Job.FriendPoints)
	end
	endJob(player, string.format("✅ Доставлено за %d с%s", math.floor(took), fast and " — быстро! ⚡" or ""))
	addStat(player, "Delivery", 1)
	task.delay(Config.Job.Cooldown, function()
		if player.Parent then
			remote:FireClient(player, "Job", { active = false, ready = true })
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(0.3)
		for player, job in pairs(jobs) do
			if not player.Parent then
				jobs[player] = nil
				continue
			end
			if os.clock() - job.started > Config.Job.TimeLimit then
				endJob(player, "⌛ Время вышло — заказ отменён")
				continue
			end
			if job.stage == "deliver" then
				local npc = job.target
				if not npc or not residentOk(npc) then
					-- Получатель пропал — посылку ждёт другой
					local nextOne = chooseRecipient(player, npc)
					if nextOne then
						job.target = nextOne
						setJobInfo(player, "deliver", string.format("Отнеси %s → %s", job.item, nextOne.name), nextOne.model)
						toast(player, "📦 Новый получатель: " .. nextOne.name)
					else
						endJob(player, "Получатель пропал — заказ отменён")
					end
					continue
				end
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then
					if not character:FindFirstChild("CourierBox") then
						giveBox(player) -- после возрождения
					end
					if (root.Position - npc.hrp.Position).Magnitude <= Config.Job.DeliverDistance and not npc.inVehicle then
						deliver(player, job)
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- 📷 Фото: жители позируют
---------------------------------------------------------------------

local lastPhoto = {}
local POSES = { "Wave", "Cheer", "Point", "Laugh" }

local function photo(player: Player)
	local now = os.clock()
	if now - (lastPhoto[player] or 0) < 1 then
		return
	end
	lastPhoto[player] = now
	addStat(player, "Photo", 1)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local posed = 0
	for _, npc in pairs(Registry.npcs) do
		if posed >= 4 then
			break
		end
		if residentOk(npc) and not npc.inVehicle and not npc.talkingTo and npc.lock == nil
			and (npc.hrp.Position - root.Position).Magnitude <= Config.Photo.PoseRadius and rng:NextNumber() < Config.Photo.PoseChance then
			posed += 1
			task.spawn(function()
				task.wait(rng:NextNumber(0, 0.4))
				if Registry.face then
					Registry.face(npc, root.Position - npc.hrp.Position, 1.5)
				end
				if Registry.emote then
					Registry.emote(npc, pick(POSES))
				end
				if Registry.say and rng:NextNumber() < 0.6 then
					Registry.say(npc, pick(Config.Photo.Lines), 2.5)
				end
			end)
		end
	end
end

---------------------------------------------------------------------
-- Запросы телефона
---------------------------------------------------------------------

Registry.cityData = cityData

-- Меню отладки: сбросить прогресс игрока (вещи, достижения, счётчики)
Registry.cityReset = function(player: Player)
	local p = profileOf(player)
	p.stats, p.done, p.owned, p.equipped = {}, {}, {}, {}
	applyCosmetics(player)
	push(player)
end
-- Меню отладки: добавить к счётчику (проверка достижений)
Registry.cityAddStat = addStat
Registry.cityAction = function(player: Player, action: string, a: any)
	if action == "Job" then
		startJob(player)
	elseif action == "Buy" and type(a) == "string" then
		buy(player, a)
	elseif action == "Equip" and type(a) == "string" then
		equip(player, a)
	elseif action == "Photo" then
		photo(player)
	elseif action == "City" then
		push(player)
	end
end

---------------------------------------------------------------------
-- Игроки
---------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Head", 10)
	task.wait(0.5)
	if player.Character ~= character then
		return
	end
	applyCosmetics(player)
	for _, attribute in { "Invisible", "CubeForm" } do
		character:GetAttributeChangedSignal(attribute):Connect(function()
			task.defer(refreshVisibility, character)
		end)
	end
	local tracker = tracking[player]
	if tracker then
		tracker.lastPos = nil
	end
end

local function onPlayer(player: Player)
	tracking[player] = { flags = {}, lastPos = nil }
	task.spawn(function()
		-- Ждём, пока жители создадут кошелёк, иначе загруженные монеты перезапишутся
		local t = os.clock()
		while not Registry.getCoins and os.clock() - t < 10 do
			task.wait(0.2)
		end
		load(player)
		if player.Character then
			onCharacter(player, player.Character)
		end
		push(player)
	end)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
Players.PlayerAdded:Connect(onPlayer)

Players.PlayerRemoving:Connect(function(player)
	local job = jobs[player]
	if job and job.crate then
		job.crate:Destroy()
	end
	jobs[player] = nil
	save(player)
	profiles[player] = nil
	tracking[player] = nil
	lastPhoto[player] = nil
	pushQueued[player] = nil
end)

-- Автосохранение и сохранение при выключении сервера
task.spawn(function()
	while true do
		task.wait(120)
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
	end
end)
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(save, player)
	end
	task.wait(2)
end)
