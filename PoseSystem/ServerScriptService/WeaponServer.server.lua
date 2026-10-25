-- Script: ServerScriptService > WeaponServer
-- Оружие игрока (настройки — ReplicatedStorage > WeaponConfig):
--   * пистолет и винтовка — 3D-модели из деталей (или свои: ServerStorage > WeaponModels > Pistol / Rifle);
--   * сервер сам проверяет каждый выстрел: темп, патроны, откуда стреляют, куда попали;
--   * урон по жителям, полиции и игрокам; ragdoll и кровь (как в GTA, 17+);
--   * патроны, перезарядка, режимы огня, покупка в телефоне, конфискация при аресте;
--   * о стрельбе узнаёт розыск (WantedServer) — через свидетелей.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
if not Config.Enabled then
	return
end
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local rng = Random.new()
local remote = Instance.new("RemoteEvent")
remote.Name = "WeaponRemote"
remote.Parent = ReplicatedStorage

local function toast(player: Player, text: string)
	if Registry.toast then
		Registry.toast(player, text)
	end
end

local function coins(player: Player): IntValue?
	if Registry.getCoins then
		return Registry.getCoins(player)
	end
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild(NPCConfig.CurrencyName) or nil
end

---------------------------------------------------------------------
-- 3D-модели оружия
---------------------------------------------------------------------

local METAL = Color3.fromRGB(38, 40, 44)
local DARK = Color3.fromRGB(22, 23, 26)
local POLYMER = Color3.fromRGB(30, 31, 34)
local TAN = Color3.fromRGB(150, 128, 92)

local function piece(model: Instance, handle: BasePart?, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Reflectance = 0.02
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	if shape then
		p.Shape = shape
	end
	if handle then
		p.CFrame = handle.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = handle
		w.Part1 = p
		w.Parent = p
	end
	p.Parent = model
	return p
end

local ALONG = CFrame.Angles(0, math.rad(90), 0) -- цилиндр вдоль ствола (ось -Z)

-- Ствол смотрит вдоль -Z детали Handle (передняя грань — к дулу)
local BUILD = {}

function BUILD.Pistol(model: Instance)
	local handle = piece(model, nil, "Handle", Vector3.new(0.32, 0.75, 0.42), CFrame.new(), POLYMER, Enum.Material.SmoothPlastic)
	local tilt = handle.CFrame * CFrame.Angles(math.rad(-12), 0, 0)
	handle.CFrame = tilt
	-- Рамка, затвор, ствол, спуск, мушка, магазин
	piece(model, handle, "Frame", Vector3.new(0.3, 0.28, 1.25), CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.44, -0.42), POLYMER, Enum.Material.SmoothPlastic)
	local slide = piece(model, handle, "Slide", Vector3.new(0.31, 0.3, 1.38), CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.7, -0.46), METAL, Enum.Material.Metal)
	for i = 0, 4 do
		piece(model, handle, "Serration", Vector3.new(0.32, 0.22, 0.03), CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.7, 0.05 - i * 0.07), DARK)
	end
	piece(model, handle, "Barrel", Vector3.new(0.14, 0.14, 0.2), CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.7, -1.2) * ALONG, DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece(model, handle, "FrontSight", Vector3.new(0.05, 0.07, 0.07), CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.88, -1.06), DARK)
	piece(model, handle, "RearSight", Vector3.new(0.2, 0.07, 0.06), CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.88, 0.14), DARK)
	piece(model, handle, "TriggerGuard", Vector3.new(0.06, 0.06, 0.42), CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.15, -0.45), POLYMER, Enum.Material.SmoothPlastic)
	piece(model, handle, "Trigger", Vector3.new(0.04, 0.16, 0.05), CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.26, -0.32), METAL)
	piece(model, handle, "MagBase", Vector3.new(0.34, 0.08, 0.44), CFrame.new(0, -0.4, 0), DARK, Enum.Material.SmoothPlastic)
	for i = 0, 3 do
		piece(model, handle, "Grip", Vector3.new(0.33, 0.04, 0.43), CFrame.new(0, -0.25 + i * 0.15, 0), DARK, Enum.Material.Fabric)
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = slide
	muzzle.Position = Vector3.new(0, 0, -0.75)
	return handle
end

function BUILD.Rifle(model: Instance)
	local handle = piece(model, nil, "Handle", Vector3.new(0.3, 0.7, 0.4), CFrame.new(), POLYMER, Enum.Material.SmoothPlastic)
	handle.CFrame = handle.CFrame * CFrame.Angles(math.rad(-15), 0, 0)
	local up = CFrame.Angles(math.rad(15), 0, 0)
	-- Ствольная коробка, цевьё, ствол, приклад, магазин, прицел
	local receiver = piece(model, handle, "Receiver", Vector3.new(0.38, 0.5, 2), up * CFrame.new(0, 0.55, -0.55), METAL, Enum.Material.Metal)
	piece(model, handle, "Handguard", Vector3.new(0.42, 0.44, 1.7), up * CFrame.new(0, 0.58, -2.35), TAN, Enum.Material.SmoothPlastic)
	for i = 0, 5 do
		piece(model, handle, "Vent", Vector3.new(0.43, 0.12, 0.12), up * CFrame.new(0, 0.58, -1.75 - i * 0.24), DARK)
	end
	local barrel = piece(model, handle, "Barrel", Vector3.new(1.4, 0.13, 0.13), up * CFrame.new(0, 0.62, -3.85) * ALONG, DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece(model, handle, "FlashHider", Vector3.new(0.3, 0.2, 0.2), up * CFrame.new(0, 0.62, -4.6) * ALONG, DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece(model, handle, "Stock", Vector3.new(0.34, 0.55, 1.35), up * CFrame.new(0, 0.45, 1.05), TAN, Enum.Material.SmoothPlastic)
	piece(model, handle, "ButtPad", Vector3.new(0.36, 0.6, 0.12), up * CFrame.new(0, 0.42, 1.78), DARK, Enum.Material.Fabric)
	piece(model, handle, "BufferTube", Vector3.new(0.9, 0.18, 0.18), up * CFrame.new(0, 0.72, 0.75) * ALONG, METAL, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece(model, handle, "Magazine", Vector3.new(0.28, 0.95, 0.42), up * CFrame.new(0, -0.05, -0.95) * CFrame.Angles(math.rad(10), 0, 0), DARK, Enum.Material.SmoothPlastic)
	piece(model, handle, "TriggerGuard", Vector3.new(0.06, 0.06, 0.45), up * CFrame.new(0, 0.2, -0.2), POLYMER, Enum.Material.SmoothPlastic)
	piece(model, handle, "Rail", Vector3.new(0.24, 0.08, 1.9), up * CFrame.new(0, 0.84, -0.6), DARK)
	-- Оптический прицел: труба, линзы, кольца
	piece(model, handle, "ScopeTube", Vector3.new(1.3, 0.24, 0.24), up * CFrame.new(0, 1.12, -0.55) * ALONG, DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece(model, handle, "ScopeFront", Vector3.new(0.32, 0.36, 0.36), up * CFrame.new(0, 1.12, -1.3) * ALONG, DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece(model, handle, "ScopeBack", Vector3.new(0.26, 0.3, 0.3), up * CFrame.new(0, 1.12, 0.18) * ALONG, DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece(model, handle, "Lens", Vector3.new(0.02, 0.3, 0.3), up * CFrame.new(0, 1.12, -1.47) * ALONG, Color3.fromRGB(70, 140, 220), Enum.Material.Glass, Enum.PartType.Cylinder).Reflectance = 0.5
	for _, z in { -0.95, -0.2 } do
		piece(model, handle, "ScopeRing", Vector3.new(0.12, 0.34, 0.34), up * CFrame.new(0, 1.12, z) * ALONG, METAL, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = barrel
	muzzle.Position = Vector3.new(0.7, 0, 0) -- конец ствола (цилиндр повёрнут: его ось X смотрит вперёд, вдоль -Z оружия)
	local _ = receiver
	return handle
end

-- Своя модель: ServerStorage > WeaponModels > Pistol / Rifle (Tool с Handle и Attachment «Muzzle»)
local function makeTool(id: string): Tool?
	local def = Config.Weapons[id]
	if not def then
		return nil
	end
	local custom = ServerStorage:FindFirstChild("WeaponModels")
	custom = custom and custom:FindFirstChild(id)
	local tool
	if custom and custom:IsA("Tool") then
		tool = custom:Clone()
	else
		tool = Instance.new("Tool")
		tool.Name = id
		tool.CanBeDropped = false
		tool.RequiresHandle = true
		BUILD[id](tool)
		tool.Grip = CFrame.new(0, -0.15, 0.1)
	end
	tool.ToolTip = def.Name
	tool:SetAttribute("WeaponId", id)
	tool:SetAttribute("Mode", def.Modes[1])
	return tool
end

-- Модель пистолета для полиции (без Tool): приваривается к руке
Registry.buildGun = function(id: string): Model
	local model = Instance.new("Model")
	model.Name = "PoliceGun"
	local handle = BUILD[id or "Pistol"](model)
	model.PrimaryPart = handle
	return model
end

---------------------------------------------------------------------
-- Профили: какое оружие есть, патроны (DataStore)
---------------------------------------------------------------------

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("Weapons_v1")
end)
local profiles = {} -- [player] = { owned = {id=true}, ammo = {id = запас}, mag = {id = в магазине}, jail = секунд }
local blocked = {} -- [player] = true — оружие отобрано на время ареста

local function newProfile()
	local p = { owned = {}, ammo = {}, mag = {} }
	for _, id in Config.StartWeapons do
		p.owned[id] = true
		p.ammo[id] = Config.Weapons[id].StartAmmo
		p.mag[id] = Config.Weapons[id].Magazine
	end
	return p
end

local function profileOf(player: Player)
	profiles[player] = profiles[player] or newProfile()
	return profiles[player]
end

local function save(player: Player)
	local p = profiles[player]
	if store and p and p.loaded then
		pcall(function()
			store:SetAsync("w_" .. player.UserId, { owned = p.owned, ammo = p.ammo, mag = p.mag, jail = p.jail, record = p.record })
		end)
	end
end

local function load(player: Player)
	local p = newProfile()
	if store then
		local ok, data = pcall(function()
			return store:GetAsync("w_" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			p.owned = data.owned or {}
			p.ammo = data.ammo or {}
			p.mag = data.mag or {}
			p.jail = data.jail
			p.record = data.record
		end
	end
	p.loaded = true
	profiles[player] = p
	return p
end

Registry.weaponProfile = profileOf
Registry.weaponSave = save

---------------------------------------------------------------------
-- Выдать / забрать оружие
---------------------------------------------------------------------

local function removeTools(player: Player)
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("WeaponId") then
					local p = profileOf(player)
					local id = t:GetAttribute("WeaponId")
					p.mag[id] = t:GetAttribute("Ammo") or p.mag[id]
					p.ammo[id] = t:GetAttribute("Reserve") or p.ammo[id]
					t:Destroy()
				end
			end
		end
	end
end

local function giveTools(player: Player)
	if blocked[player] then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local p = profileOf(player)
	for _, id in { "Pistol", "Rifle" } do
		local def = Config.Weapons[id]
		if def and p.owned[id] and not backpack:FindFirstChild(id) and not (player.Character and player.Character:FindFirstChild(id)) then
			local tool = makeTool(id)
			if tool then
				tool:SetAttribute("Ammo", math.clamp(p.mag[id] or def.Magazine, 0, def.Magazine))
				tool:SetAttribute("Reserve", p.ammo[id] or def.StartAmmo)
				tool.Parent = backpack
			end
		end
	end
end

local function pushPhone(player: Player)
	local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
	if phone and player.Parent then
		local p = profileOf(player)
		phone:FireClient(player, "Weapons", { owned = p.owned, ammo = p.ammo, blocked = blocked[player] == true })
	end
end

-- Для розыска: отобрать на время ареста / конфисковать / вернуть
Registry.blockWeapons = function(player: Player, on: boolean)
	blocked[player] = on or nil
	if on then
		removeTools(player)
	else
		giveTools(player)
	end
	pushPhone(player)
end
Registry.confiscateWeapons = function(player: Player)
	removeTools(player)
	local p = profileOf(player)
	p.owned, p.ammo, p.mag = {}, {}, {}
	pushPhone(player)
	save(player)
end

---------------------------------------------------------------------
-- Выстрел (общий: игроки и полиция)
---------------------------------------------------------------------

local shotParams = RaycastParams.new()
shotParams.FilterType = Enum.RaycastFilterType.Exclude

local function spreadDir(dir: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return dir.Unit
	end
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local a = rng:NextNumber() * math.pi * 2
	local r = math.rad(degrees) * math.sqrt(rng:NextNumber())
	return (cf * CFrame.Angles(math.cos(a) * r, math.sin(a) * r, 0)).LookVector
end

local function humanoidOf(part: Instance): (Model?, Humanoid?)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local h = model:FindFirstChildOfClass("Humanoid")
		if h then
			return model, h
		end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

-- Луч выстрела + эффекты у всех. Возвращает: результат, модель, humanoid, позицию попадания
Registry.fireShot = function(origin: Vector3, dir: Vector3, range: number, ignore: { Instance }, weaponId: string, shooter: Instance?)
	shotParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(origin, dir.Unit * range, shotParams)
	local hitPos = result and result.Position or origin + dir.Unit * range
	local model, humanoid = nil, nil
	local kind = "none"
	if result then
		model, humanoid = humanoidOf(result.Instance)
		kind = (humanoid and humanoid.Health > 0) and "flesh" or "wall"
	end
	remote:FireAllClients("Shot", {
		shooter = shooter,
		from = origin,
		to = hitPos,
		normal = result and result.Normal or nil,
		kind = kind,
		weapon = weaponId,
	})
	return result, model, humanoid, hitPos
end

local function isHead(part: BasePart): boolean
	if part.Name == "Head" then
		return true
	end
	local acc = part.Parent
	return acc ~= nil and acc:IsA("Accessory")
end

---------------------------------------------------------------------
-- Выстрелы игроков
---------------------------------------------------------------------

local lastShot = {} -- [player] = время
local aiming = {} -- [player] = прицеливается ли

local function equippedTool(player: Player, id: string?): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	for _, t in character:GetChildren() do
		if t:IsA("Tool") and t:GetAttribute("WeaponId") and (id == nil or t:GetAttribute("WeaponId") == id) then
			return t
		end
	end
	return nil
end

local function onFire(player: Player, id: any, origin: any, direction: any)
	local def = type(id) == "string" and Config.Weapons[id]
	if not def or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5 then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tool = equippedTool(player, id)
	if not head or not tool or not humanoid or humanoid.Health <= 0 or blocked[player] or character:GetAttribute("Cuffed") then
		return
	end
	if tool:GetAttribute("Reloading") then
		return
	end
	local now = os.clock()
	if now - (lastShot[player] or 0) < 60 / def.RPM * 0.8 then
		return
	end
	local ammo = tool:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		return
	end
	lastShot[player] = now
	tool:SetAttribute("Ammo", ammo - 1)
	-- Откуда стреляет: дуло рядом с головой, иначе — из головы
	if (origin - head.Position).Magnitude > 7 then
		origin = head.Position
	end
	local dir = spreadDir(direction, (aiming[player] and def.AimSpread or def.Spread) * 0.5)
	local result, model, victim, hitPos = Registry.fireShot(origin, dir, def.Range, { character }, id, character)
	if Registry.gunshot then
		Registry.gunshot(player, origin)
	end
	-- Попал в камеру наблюдения — сломал (CourtServer)
	if result and not victim and Registry.cameraHit then
		Registry.cameraHit(result.Instance, player)
	end
	if not (result and victim and victim.Health > 0 and model) then
		return
	end
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	if victimPlayer and Config.PvP == false then
		return
	end
	local dist = (hitPos - origin).Magnitude
	local falloff = dist > def.Range * 0.6 and math.max(0.5, 1 - (dist - def.Range * 0.6) / (def.Range * 0.4) * 0.5) or 1
	local headshot = isHead(result.Instance)
	local damage = def.Damage * falloff * (headshot and def.HeadMultiplier or 1)
	model:SetAttribute("LastAttacker", player.UserId)
	model:SetAttribute("LastHitDir", dir)
	local wasAlive = victim.Health > 0
	victim:TakeDamage(damage)
	local killed = wasAlive and victim.Health <= 0
	remote:FireClient(player, "Hit", { head = headshot, kill = killed })
	-- Преступление (узнают свидетели или полиция — WantedServer)
	if Registry.wantedCrime then
		local isOfficer = model:GetAttribute("Police") == true
		local kind
		if isOfficer then
			kind = killed and "PoliceKill" or "PoliceAttack"
		else
			kind = killed and "Murder" or "Injury"
		end
		Registry.wantedCrime(player, kind, hitPos, model)
	end
end

remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any, c: any)
	if action == "Fire" then
		onFire(player, a, b, c)
	elseif action == "Aim" then
		local character = player.Character
		if character and typeof(a) == "Vector3" then
			local tool = equippedTool(player, nil)
			aiming[player] = b == true
			character:SetAttribute("AimGun", tool ~= nil)
			character:SetAttribute("AimDir", a.Unit)
			character:SetAttribute("Aiming", b == true and tool ~= nil)
		end
	elseif action == "Reload" then
		local tool = equippedTool(player, nil)
		local id = tool and tool:GetAttribute("WeaponId")
		local def = id and Config.Weapons[id]
		if not def or tool:GetAttribute("Reloading") then
			return
		end
		local ammo, reserve = tool:GetAttribute("Ammo") or 0, tool:GetAttribute("Reserve") or 0
		if ammo >= def.Magazine or reserve <= 0 then
			return
		end
		tool:SetAttribute("Reloading", true)
		task.delay(def.ReloadTime, function()
			if tool.Parent then
				local need = math.min(def.Magazine - (tool:GetAttribute("Ammo") or 0), tool:GetAttribute("Reserve") or 0)
				tool:SetAttribute("Ammo", (tool:GetAttribute("Ammo") or 0) + need)
				tool:SetAttribute("Reserve", (tool:GetAttribute("Reserve") or 0) - need)
				tool:SetAttribute("Reloading", nil)
				local p = profileOf(player)
				p.mag[id] = tool:GetAttribute("Ammo")
				p.ammo[id] = tool:GetAttribute("Reserve")
			end
		end)
	elseif action == "Mode" then
		local tool = equippedTool(player, nil)
		local def = tool and Config.Weapons[tool:GetAttribute("WeaponId")]
		if def and #def.Modes > 1 then
			local i = table.find(def.Modes, tool:GetAttribute("Mode")) or 1
			tool:SetAttribute("Mode", def.Modes[i % #def.Modes + 1])
		end
	elseif action == "Surrender" then
		local character = player.Character
		if character then
			character:SetAttribute("HandsUp", not character:GetAttribute("HandsUp") or nil)
			if character:GetAttribute("HandsUp") then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:UnequipTools()
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Смерть жителя: ragdoll и кровь
---------------------------------------------------------------------

local function ragdoll(model: Model)
	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 and motor.Name ~= "RootJoint" and motor.Name ~= "Root" then
			local a0 = Instance.new("Attachment")
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 50
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -40
			socket.TwistUpperAngle = 40
			socket.Parent = motor.Part1
			motor.Enabled = false
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = p.Name ~= "HumanoidRootPart"
			p.Massless = p.Name == "HumanoidRootPart"
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		local dir = model:GetAttribute("LastHitDir")
		if typeof(dir) == "Vector3" then
			local torso = (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")) :: BasePart?
			if torso then
				torso:ApplyImpulse(dir * torso.AssemblyMass * 18)
			end
		end
	end
end

local function bloodPool(model: Model)
	local torso = (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")) :: BasePart?
	if not torso then
		return
	end
	task.delay(1.2, function()
		if not torso.Parent then
			return
		end
		shotParams.FilterDescendantsInstances = { model }
		local hit = workspace:Raycast(torso.Position, Vector3.new(0, -8, 0), shotParams)
		if not hit then
			return
		end
		local pool = Instance.new("Part")
		pool.Name = "BloodPool"
		pool.Shape = Enum.PartType.Cylinder
		pool.Anchored = true
		pool.CanCollide = false
		pool.CanQuery = false
		pool.CanTouch = false
		pool.Material = Enum.Material.Glass
		pool.Color = Color3.fromRGB(95, 6, 10)
		pool.Transparency = 0.15
		pool.Size = Vector3.new(0.06, 0.4, 0.4)
		pool.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pool.Parent = model
		local size = rng:NextNumber(3.2, 5)
		TweenService:Create(pool, TweenInfo.new(7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.06, size, size * rng:NextNumber(0.8, 1)) }):Play()
	end)
end

Registry.npcDied = function(npc)
	local model = npc.model
	npc.corpseTime = Config.CorpseTime or 40
	ragdoll(model)
	local attacker = model:GetAttribute("LastAttacker")
	if Config.Blood and attacker then
		bloodPool(model)
	end
	-- Тело постепенно исчезает в конце
	task.delay(npc.corpseTime - 2, function()
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "BloodPool" then
				TweenService:Create(p, TweenInfo.new(1.8), { Transparency = 1 }):Play()
			end
		end
	end)
end

---------------------------------------------------------------------
-- Магазин в телефоне
---------------------------------------------------------------------

Registry.weaponAction = function(player: Player, action: string, id: any): boolean
	if action ~= "WeaponBuy" and action ~= "AmmoBuy" and action ~= "Weapons" then
		return false
	end
	if action == "Weapons" then
		pushPhone(player)
		return true
	end
	local def = type(id) == "string" and Config.Weapons[id]
	local wallet = coins(player)
	if not def or not wallet then
		return true
	end
	if blocked[player] then
		toast(player, "🚫 Оружие сейчас недоступно")
		return true
	end
	local p = profileOf(player)
	if action == "WeaponBuy" then
		if p.owned[id] then
			return true
		end
		if wallet.Value < def.Price then
			toast(player, "Не хватает монет 🪙")
			return true
		end
		wallet.Value -= def.Price
		p.owned[id] = true
		p.ammo[id] = def.StartAmmo
		p.mag[id] = def.Magazine
		toast(player, string.format("%s %s куплен! -%d 🪙", def.Icon, def.Name, def.Price))
		giveTools(player)
	else
		if not p.owned[id] then
			return true
		end
		if wallet.Value < def.AmmoPrice then
			toast(player, "Не хватает монет 🪙")
			return true
		end
		wallet.Value -= def.AmmoPrice
		local tool = equippedTool(player, id) or (player:FindFirstChildOfClass("Backpack") and player.Backpack:FindFirstChild(id))
		if tool then
			tool:SetAttribute("Reserve", (tool:GetAttribute("Reserve") or 0) + def.Magazine)
		end
		p.ammo[id] = (p.ammo[id] or 0) + def.Magazine
		toast(player, string.format("+%d патронов %s", def.Magazine, def.Icon))
	end
	pushPhone(player)
	save(player)
	return true
end

---------------------------------------------------------------------
-- Игроки
---------------------------------------------------------------------

local function onPlayer(player: Player)
	task.spawn(function()
		load(player)
		if player.Character then
			giveTools(player)
		end
		pushPhone(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.3)
		local p = profiles[player]
		if p and p.loaded then
			giveTools(player)
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.BreakJointsOnDeath = false
			humanoid.Died:Connect(function()
				-- Сохраняем патроны из инструментов; тело падает (ragdoll)
				removeTools(player)
				ragdoll(character)
			end)
		end
	end)
end
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	removeTools(player)
	save(player)
	profiles[player] = nil
	blocked[player] = nil
	lastShot[player] = nil
	aiming[player] = nil
end)
game:BindToClose(function()
	for _, p in Players:GetPlayers() do
		task.spawn(save, p)
	end
	task.wait(2)
end)
task.spawn(function()
	while true do
		task.wait(90)
		for _, p in Players:GetPlayers() do
			task.spawn(save, p)
		end
	end
end)
