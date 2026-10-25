-- LocalScript: StarterPlayer > StarterPlayerScripts > WeaponClient
-- Оружие на экране игрока (настройки — ReplicatedStorage > WeaponConfig):
--   * камера из-за плеча, ПКМ — прицел (у винтовки — оптика с сеткой), ЛКМ — огонь;
--   * V — режим огня (одиночные / очередь / авто), R — перезарядка, H — поднять руки (сдаться);
--   * отдача, разброс, вспышка, трассеры, следы от пуль, кровь (17+), хитмаркер;
--   * позы: руки с оружием (видят все), руки вверх, наручники.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
if not Config.Enabled then
	return
end
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))
local remote = ReplicatedStorage:WaitForChild("WeaponRemote")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local gameSettings = UserSettings():GetService("UserGameSettings")
local WHITE = Color3.new(1, 1, 1)
local rng = Random.new()

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local effects = new("Folder", { Name = "WeaponEffects" }, workspace.Terrain)

local function playAt(position: Vector3, def, pitch: number?)
	if not def or def.Id == "" then
		return
	end
	local holder = new("Attachment", { WorldPosition = position }, workspace.Terrain)
	local s = new("Sound", { SoundId = def.Id, Volume = def.Volume or 0.5, PlaybackSpeed = pitch or 1, RollOffMaxDistance = 300, RollOffMinDistance = 8 }, holder)
	s:Play()
	Debris:AddItem(holder, 4)
end

---------------------------------------------------------------------
-- Позы рук (для всех персонажей и полиции)
---------------------------------------------------------------------

local function aimPose(pitch: number, rifle: boolean)
	local p = math.deg(pitch)
	if rifle then
		return {
			RightShoulder = Vector3.new(78 + p, 0, -12),
			LeftShoulder = Vector3.new(88 + p, 0, 38),
			RightElbow = Vector3.new(25, 0, 0),
			LeftElbow = Vector3.new(12, 0, 0),
			Neck = Vector3.new(-p * 0.4, 0, 0),
			R6 = { RightShoulder = Vector3.new(0, 0, 80 + p), LeftShoulder = Vector3.new(0, 0, -80 - p) },
		}
	end
	return {
		RightShoulder = Vector3.new(90 + p, 0, -6),
		LeftShoulder = Vector3.new(88 + p, 0, 34),
		LeftElbow = Vector3.new(22, 0, 0),
		Neck = Vector3.new(-p * 0.4, 0, 0),
		R6 = { RightShoulder = Vector3.new(0, 0, 90 + p), LeftShoulder = Vector3.new(0, 0, -80 - p) },
	}
end

local HANDS_UP = {
	RightShoulder = Vector3.new(165, 0, -12),
	LeftShoulder = Vector3.new(165, 0, 12),
	RightElbow = Vector3.new(25, 0, 0),
	LeftElbow = Vector3.new(25, 0, 0),
	R6 = { RightShoulder = Vector3.new(0, 0, 170), LeftShoulder = Vector3.new(0, 0, -170) },
}
local CUFFED = {
	LeftShoulder = Vector3.new(-32, 0, 26),
	RightShoulder = Vector3.new(-32, 0, -26),
	LeftElbow = Vector3.new(38, 0, 0),
	RightElbow = Vector3.new(38, 0, 0),
}

local function attrLayer(model: Model, attribute: string, priority: number, poseFn)
	local weight = 0
	return {
		Priority = priority,
		Update = function(rig, dt)
			local on = model:GetAttribute(attribute) == true
			weight = math.clamp(weight + (on and dt or -dt) * 6, 0, 1)
			if not on and weight <= 0 then
				return nil, 0, true
			end
			return RigAnimator.Frames(rig, poseFn()), weight
		end,
	}
end

local function watchModel(model: Model)
	local function aimFn()
		local dir = model:GetAttribute("AimDir")
		local pitch = typeof(dir) == "Vector3" and math.asin(math.clamp(dir.Y, -1, 1)) or 0
		local rifle = model:FindFirstChild("Rifle") ~= nil
		return aimPose(pitch, rifle)
	end
	local function check()
		if model:GetAttribute("AimGun") == true and not RigAnimator.HasLayer(model, "AimGun") then
			RigAnimator.SetLayer(model, "AimGun", attrLayer(model, "AimGun", 34, aimFn))
		end
		if model:GetAttribute("HandsUp") == true and not RigAnimator.HasLayer(model, "HandsUp") then
			RigAnimator.SetLayer(model, "HandsUp", attrLayer(model, "HandsUp", 45, function()
				return HANDS_UP
			end))
		end
		-- Наручники у игроков (у жителей — в NPCClient)
		if model:GetAttribute("Cuffed") == true and Players:GetPlayerFromCharacter(model) and not RigAnimator.HasLayer(model, "PlayerCuffed") then
			RigAnimator.SetLayer(model, "PlayerCuffed", attrLayer(model, "Cuffed", 46, function()
				return CUFFED
			end))
		end
	end
	for _, a in { "AimGun", "HandsUp", "Cuffed" } do
		model:GetAttributeChangedSignal(a):Connect(check)
	end
	check()
end

local function watchPlayer(p: Player)
	if p.Character then
		watchModel(p.Character)
	end
	p.CharacterAdded:Connect(watchModel)
end
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, m in CollectionService:GetTagged(NPCConfig.Tag) do
	if m:IsA("Model") then
		watchModel(m)
	end
end
CollectionService:GetInstanceAddedSignal(NPCConfig.Tag):Connect(function(m)
	if m:IsA("Model") then
		watchModel(m)
	end
end)

---------------------------------------------------------------------
-- Эффекты выстрела (у всех)
---------------------------------------------------------------------

local holes = {}

local function tracer(from: Vector3, to: Vector3)
	local len = (to - from).Magnitude
	if len < 1 then
		return
	end
	local p = new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 220, 140),
		Size = Vector3.new(0.07, 0.07, math.min(len, 14)),
		CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -math.min(len, 14) / 2),
		Transparency = 0.2,
	}, effects)
	-- Летит к цели
	TweenService:Create(p, TweenInfo.new(math.clamp(len / 900, 0.03, 0.25), Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -len + math.min(len, 14) / 2),
		Transparency = 0.7,
	}):Play()
	Debris:AddItem(p, 0.3)
end

local function muzzleFlash(position: Vector3, look: Vector3?)
	local p = new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 200, 90),
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.5, 0.5, 0.5) * rng:NextNumber(0.8, 1.3),
		CFrame = CFrame.new(position + (look or Vector3.zero) * 0.25),
		Transparency = 0.1,
	}, effects)
	new("PointLight", { Color = Color3.fromRGB(255, 190, 90), Brightness = 4, Range = 12 }, p)
	Debris:AddItem(p, 0.05)
end

local function burst(position: Vector3, normal: Vector3?, color: Color3, count: number, speed: number, size: number)
	local a = new("Attachment", { WorldPosition = position }, workspace.Terrain)
	if normal then
		a.WorldCFrame = CFrame.lookAt(position, position + normal) * CFrame.Angles(math.rad(-90), 0, 0)
	end
	local e = new("ParticleEmitter", {
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.25, 0.6),
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -workspace.Gravity * 0.4, 0),
		EmissionDirection = Enum.NormalId.Top,
		Rate = 0,
		LightInfluence = 1,
	}, a)
	e:Emit(count)
	Debris:AddItem(a, 1)
end

local function bulletHole(position: Vector3, normal: Vector3)
	local p = new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(25, 22, 20),
		Material = Enum.Material.SmoothPlastic,
		Size = Vector3.new(0.02, 0.22, 0.22),
		CFrame = CFrame.lookAt(position + normal * 0.012, position + normal * 2) * CFrame.Angles(0, math.rad(90), 0),
	}, effects)
	table.insert(holes, p)
	if #holes > 60 then
		table.remove(holes, 1):Destroy()
	end
	task.delay(20, function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(2), { Transparency = 1 }):Play()
			Debris:AddItem(p, 2)
		end
	end)
end

local function impact(kind: string, to: Vector3, normal: Vector3?)
	if kind == "flesh" then
		if Config.Blood then
			burst(to, normal, Color3.fromRGB(120, 8, 12), 14, 9, 0.22)
		else
			burst(to, normal, Color3.fromRGB(230, 230, 230), 6, 6, 0.15)
		end
	elseif kind == "wall" and normal then
		burst(to, normal, Color3.fromRGB(200, 180, 140), 8, 12, 0.12)
		burst(to, normal, Color3.fromRGB(255, 220, 120), 3, 18, 0.06)
		bulletHole(to, normal)
		playAt(to, Sounds.Weapons and Sounds.Weapons.Impact, rng:NextNumber(0.9, 1.15))
	end
end

local showHit -- объявлена ниже

local function weaponSound(id: string?)
	local def = id and Config.Weapons[id]
	return Sounds.Weapons and Sounds.Weapons[def and def.Sound or "PistolShot"]
end

remote.OnClientEvent:Connect(function(action, data)
	if action == "Shot" then
		if data.shooter and data.shooter == player.Character then
			return -- свои выстрелы рисуем сами, без задержки
		end
		muzzleFlash(data.from, (data.to - data.from).Unit)
		tracer(data.from, data.to)
		impact(data.kind, data.to, data.normal)
		playAt(data.from, weaponSound(data.weapon), rng:NextNumber(0.94, 1.06))
		-- Пуля просвистела рядом
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head then
			local ab = data.to - data.from
			local t = math.clamp((head.Position - data.from):Dot(ab) / math.max(ab:Dot(ab), 0.01), 0, 1)
			if (data.from + ab * t - head.Position).Magnitude < 5 then
				playAt(head.Position, Sounds.Weapons and Sounds.Weapons.Whiz, rng:NextNumber(0.9, 1.2))
			end
		end
	elseif action == "Hit" then
		showHit(data.head, data.kill)
	end
end)

---------------------------------------------------------------------
-- Интерфейс: прицел, оптика, хитмаркер, патроны
---------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "WeaponHud", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6, Enabled = false }, player:WaitForChild("PlayerGui"))

local cross = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(80, 80), BackgroundTransparency = 1 }, gui)
local dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, cross)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
new("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.5 }, dot)
local lines = {}
for i, d in { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) } do
	local l = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = d.X == 0 and UDim2.fromOffset(2, 9) or UDim2.fromOffset(9, 2), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, cross)
	new("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.5 }, l)
	lines[i] = { frame = l, dir = d }
end

-- Оптика: круг с сеткой, вокруг — чёрное (обводка круга шире экрана)
local scope = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), BackgroundTransparency = 1, Visible = false }, gui)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, scope)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, scope)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2500, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, scope)
new("UIStroke", { Color = Color3.fromRGB(20, 20, 20), Thickness = 6 }, scope)
local vignette = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, scope)
new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.8, 1), NumberSequenceKeypoint.new(1, 0.4) }) }, vignette)
new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)
new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)
for i = 1, 4 do
	for _, sign in { -1, 1 } do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5 + sign * i * 0.06, 0), Size = UDim2.fromOffset(i == 4 and 18 or 10, 2), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5 + sign * i * 0.06, 0, 0.5, 0), Size = UDim2.fromOffset(2, i == 4 and 18 or 10), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)
	end
end
local redDot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(255, 40, 40), BorderSizePixel = 0 }, scope)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, redDot)

-- Хитмаркер
local hit = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, Visible = false, ZIndex = 5 }, gui)
local hitLines = {}
for i, r in { 45, 135, 225, 315 } do
	local a = math.rad(r)
	hitLines[i] = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * 11, 0.5, math.sin(a) * 11), Size = UDim2.fromOffset(10, 2), Rotation = r, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 5 }, hit)
end
local hitToken = 0
function showHit(head: boolean, kill: boolean)
	hitToken += 1
	local token = hitToken
	local color = kill and Color3.fromRGB(255, 50, 50) or head and Color3.fromRGB(255, 200, 60) or WHITE
	for _, l in hitLines do
		l.BackgroundColor3 = color
	end
	hit.Visible = true
	hit.Size = UDim2.fromOffset(kill and 46 or 34, kill and 46 or 34)
	playAt(camera.CFrame.Position, Sounds.Weapons and Sounds.Weapons.Hit, kill and 0.8 or 1.1)
	task.delay(0.18, function()
		if token == hitToken then
			hit.Visible = false
		end
	end)
end

-- Патроны
local ammoCard = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -110), Size = UDim2.fromOffset(210, 74), BackgroundColor3 = Color3.fromRGB(16, 18, 26), BackgroundTransparency = 0.25 }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, ammoCard)
local weaponLabel = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 18), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.fromRGB(190, 200, 225), TextXAlignment = Enum.TextXAlignment.Left }, ammoCard)
local ammoLabel = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -24, 0, 32), Font = Enum.Font.GothamBlack, TextSize = 28, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, RichText = true }, ammoCard)
local modeLabel = new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 30), Size = UDim2.fromOffset(80, 20), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.fromRGB(255, 205, 90), TextXAlignment = Enum.TextXAlignment.Right }, ammoCard)
local reloadBack = new("Frame", { Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 4), BackgroundColor3 = Color3.fromRGB(50, 55, 70), BorderSizePixel = 0, Visible = false }, ammoCard)
local reloadFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 205, 90), BorderSizePixel = 0 }, reloadBack)
local hint = new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -188), Size = UDim2.fromOffset(300, 18), Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(200, 205, 225), TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.6, Text = "ЛКМ — огонь · ПКМ — прицел · R — перезарядка · V — режим · H — руки вверх" }, gui)

local MODE_NAMES = { Semi = "ОДИНОЧНЫЕ", Burst = "ОЧЕРЕДЬ", Auto = "АВТО" }

---------------------------------------------------------------------
-- Управление оружием
---------------------------------------------------------------------

local tool: Tool? = nil
local def = nil
local ads = false
local triggerDown = false
local fired = false -- одиночный: один выстрел на нажатие
local burstLeft = 0
local lastFire = 0
local localAmmo = 0
local bloom = 0
local kick, recover = 0, 0
local baseFov = 70
local reloadStart = 0
local aimSendTimer = 0
local savedRotation = nil

local function muzzlePos(): Vector3
	local m = tool and tool:FindFirstChild("Muzzle", true)
	if m and m:IsA("Attachment") then
		return m.WorldPosition
	end
	local handle = tool and tool:FindFirstChild("Handle")
	return handle and handle.Position or camera.CFrame.Position
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function aimPoint(range: number): Vector3
	local cf = camera.CFrame
	aimParams.FilterDescendantsInstances = { player.Character, effects }
	local result = workspace:Raycast(cf.Position, cf.LookVector * range, aimParams)
	return result and result.Position or cf.Position + cf.LookVector * range
end

local function spread(dir: Vector3, degrees: number): Vector3
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local a = rng:NextNumber() * math.pi * 2
	local r = math.rad(degrees) * math.sqrt(rng:NextNumber())
	return (cf * CFrame.Angles(math.cos(a) * r, math.sin(a) * r, 0)).LookVector
end

local function canShoot(): boolean
	local character = player.Character
	return tool ~= nil and def ~= nil and character ~= nil and not character:GetAttribute("Cuffed") and not character:GetAttribute("HandsUp")
		and not tool:GetAttribute("Reloading")
end

local function shoot()
	if not canShoot() then
		return
	end
	local t = os.clock()
	if t - lastFire < 60 / def.RPM then
		return
	end
	if localAmmo <= 0 then
		lastFire = t
		playAt(muzzlePos(), Sounds.Weapons and Sounds.Weapons.Empty)
		fired = true
		return
	end
	lastFire = t
	localAmmo -= 1
	local from = muzzlePos()
	local target = aimPoint(def.Range)
	local dir = (target - from)
	if dir.Magnitude < 0.5 then
		dir = camera.CFrame.LookVector
	end
	remote:FireServer("Fire", tool:GetAttribute("WeaponId"), from, dir.Unit)
	-- Свои эффекты сразу
	local shown = spread(dir.Unit, (ads and def.AimSpread or def.Spread) * 0.5 + bloom * 0.3)
	aimParams.FilterDescendantsInstances = { player.Character, effects }
	local result = workspace:Raycast(from, shown * def.Range, aimParams)
	local to = result and result.Position or from + shown * def.Range
	muzzleFlash(from, shown)
	tracer(from, to)
	if result then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local isBody = model and model:FindFirstChildOfClass("Humanoid") ~= nil
		impact(isBody and "flesh" or "wall", to, result.Normal)
	end
	playAt(from, weaponSound(tool:GetAttribute("WeaponId")), rng:NextNumber(0.96, 1.04))
	-- Отдача
	kick += def.Recoil * (ads and 0.6 or 1)
	bloom = math.min(bloom + def.Recoil * 0.8, 8)
end

local function equip(newTool: Tool)
	tool = newTool
	def = Config.Weapons[newTool:GetAttribute("WeaponId")]
	localAmmo = newTool:GetAttribute("Ammo") or 0
	newTool:GetAttributeChangedSignal("Ammo"):Connect(function()
		if tool == newTool then
			localAmmo = newTool:GetAttribute("Ammo") or 0
		end
	end)
	newTool:GetAttributeChangedSignal("Reloading"):Connect(function()
		if newTool:GetAttribute("Reloading") then
			reloadStart = os.clock()
			playAt(muzzlePos(), Sounds.Weapons and Sounds.Weapons.Reload)
		end
	end)
	gui.Enabled = true
	baseFov = camera.FieldOfView
	savedRotation = gameSettings.RotationType
	gameSettings.RotationType = Enum.RotationType.CameraRelative
	ContextActionService:BindActionAtPriority("WeaponReload", function(_, state)
		if state == Enum.UserInputState.Begin then
			remote:FireServer("Reload")
		end
		return Enum.ContextActionResult.Sink
	end, true, 3000, Config.Keys.Reload)
	ContextActionService:SetTitle("WeaponReload", "R")
	ContextActionService:BindActionAtPriority("WeaponMode", function(_, state)
		if state == Enum.UserInputState.Begin then
			remote:FireServer("Mode")
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Config.Keys.Mode)
	-- Прицел на телефоне — кнопка
	ContextActionService:BindActionAtPriority("WeaponAim", function(_, state)
		if state == Enum.UserInputState.Begin then
			ads = not ads
		end
		return Enum.ContextActionResult.Sink
	end, true, 3000, Enum.KeyCode.ButtonL2)
	ContextActionService:SetTitle("WeaponAim", "🎯")
end

local function unequip()
	if not tool then
		return
	end
	tool = nil
	def = nil
	ads = false
	triggerDown = false
	gui.Enabled = false
	scope.Visible = false
	ContextActionService:UnbindAction("WeaponReload")
	ContextActionService:UnbindAction("WeaponMode")
	ContextActionService:UnbindAction("WeaponAim")
	if savedRotation then
		gameSettings.RotationType = savedRotation
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end
	camera.FieldOfView = baseFov
	remote:FireServer("Aim", camera.CFrame.LookVector, false)
end

local function watchCharacter(character: Model)
	unequip()
	character.ChildAdded:Connect(function(c)
		if c:IsA("Tool") and c:GetAttribute("WeaponId") then
			equip(c)
			c.Activated:Connect(function()
				-- Касание на телефоне — выстрел
				if UserInputService.TouchEnabled then
					shoot()
				end
			end)
		end
	end)
	character.ChildRemoved:Connect(function(c)
		if c == tool then
			unequip()
		end
	end)
end
if player.Character then
	watchCharacter(player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

UserInputService.InputBegan:Connect(function(input, processed)
	if not tool then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
		triggerDown = true
		fired = false
		if def and tool:GetAttribute("Mode") == "Burst" then
			burstLeft = def.BurstCount or 3
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		ads = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerDown = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		ads = false
	end
end)

-- Поднять руки — в любое время
ContextActionService:BindAction("WeaponSurrender", function(_, state)
	if state == Enum.UserInputState.Begin then
		remote:FireServer("Surrender")
	end
	return Enum.ContextActionResult.Pass
end, false, Config.Keys.Surrender)

---------------------------------------------------------------------
-- Каждый кадр
---------------------------------------------------------------------

RunService:BindToRenderStep("WeaponCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not tool or not def then
		return
	end
	-- Отдача камеры: резкий подброс и частичный возврат
	local apply = kick * math.min(1, dt * 30)
	kick -= apply
	recover += apply * 0.55
	local back = recover * math.min(1, dt * 7)
	recover -= back
	local yaw = (rng:NextNumber() - 0.5) * apply * 0.35
	camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(apply - back), math.rad(yaw), 0)
end)

DebugTimer.connect(RunService.RenderStepped, "WeaponClient", function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not tool or not def or not humanoid then
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	-- Камера через плечо, в прицеле — ближе
	local offset = ads and Vector3.new(1.1, 0.4, 0) or Vector3.new(1.8, 0.5, 0)
	humanoid.CameraOffset = humanoid.CameraOffset:Lerp(offset, math.min(1, dt * 10))
	local targetFov = ads and def.AimFov or baseFov
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(1, dt * 12)
	local scoped = ads and def.Scope and camera.FieldOfView < def.AimFov + 6
	scope.Visible = scoped
	cross.Visible = not scoped
	-- Стрельба
	local mode = tool:GetAttribute("Mode") or "Semi"
	if triggerDown then
		if mode == "Auto" then
			shoot()
		elseif mode == "Semi" and not fired then
			fired = true
			shoot()
		elseif mode == "Burst" and burstLeft > 0 and os.clock() - lastFire >= 60 / def.RPM then
			burstLeft -= 1
			shoot()
		end
	elseif mode == "Burst" and burstLeft > 0 and os.clock() - lastFire >= 60 / def.RPM then
		burstLeft -= 1
		shoot()
	end
	-- Прицел: разброс
	bloom = math.max(0, bloom - dt * 10)
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local gap = 6 + ((ads and def.AimSpread or def.Spread) + bloom + (moving and 1.5 or 0)) * 6
	for _, l in lines do
		l.frame.Position = UDim2.new(0.5, l.dir.X * gap, 0.5, l.dir.Y * gap)
	end
	-- Патроны и режим
	local reserve = tool:GetAttribute("Reserve") or 0
	weaponLabel.Text = def.Icon .. "  " .. def.Name
	ammoLabel.Text = string.format("%d <font size=\"18\" color=\"#9aa3c0\">/ %d</font>", localAmmo, reserve)
	ammoLabel.TextColor3 = localAmmo == 0 and Color3.fromRGB(255, 90, 90) or localAmmo <= def.Magazine * 0.25 and Color3.fromRGB(255, 200, 90) or WHITE
	modeLabel.Text = MODE_NAMES[mode] or mode
	local reloading = tool:GetAttribute("Reloading") == true
	reloadBack.Visible = reloading
	if reloading then
		reloadFill.Size = UDim2.fromScale(math.clamp((os.clock() - reloadStart) / def.ReloadTime, 0, 1), 1)
	end
	hint.Visible = localAmmo > 0 or reserve > 0
	if localAmmo == 0 and reserve == 0 then
		hint.Visible = true
		hint.Text = "Нет патронов — купи в 📱 Магазине"
	else
		hint.Text = "ЛКМ — огонь · ПКМ — прицел · R — перезарядка · V — режим · H — руки вверх"
	end
	-- Направление взгляда — серверу (поза рук видна всем, свидетели видят прицел)
	aimSendTimer -= dt
	if aimSendTimer <= 0 then
		aimSendTimer = 0.1
		remote:FireServer("Aim", camera.CFrame.LookVector, ads)
	end
end)
