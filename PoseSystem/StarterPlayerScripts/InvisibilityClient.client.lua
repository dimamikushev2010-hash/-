-- LocalScript: StarterPlayer > StarterPlayerScripts > InvisibilityClient
-- Клиент способности «Невидимость»:
--   * себя видишь полупрозрачным «стеклом» с голубым оттенком и лёгкой синевой на экране;
--   * другие невидимые игроки скрыты полностью (тело, ник, полоска здоровья, звуки);
--   * при выходе из невидимости персонажа на 1,5 сек обводит красный контур;
--   * анимации: исчезновение (руки крест-накрест и резкий взмах) и появление (силовая стойка),
--     вспышки частиц;
--   * кнопка с таймером кулдауна и полоской оставшейся невидимости.
-- Этот же скрипт прячет тело персонажа, когда он превращается в куб (CubeConfig).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("InvisibilityConfig"))
local CubeConfig = require(ReplicatedStorage:WaitForChild("CubeConfig"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))
local AbilityFx = require(ReplicatedStorage:WaitForChild("AbilityFx"))
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName)

local CUBE_FADE_TIME = 0.15

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------
-- Эффекты на персонажах
---------------------------------------------------------------------

local visuals = {} -- [character] = состояние эффекта

local screenTint = Instance.new("ColorCorrectionEffect")
screenTint.Name = "InvisibilityTint"
screenTint.Enabled = false
screenTint.Parent = Lighting

local function isFadeable(inst: Instance): boolean
	-- Сам куб и его лицо не трогаем
	if inst.Name == CubeConfig.PartName or (inst.Parent and inst.Parent.Name == CubeConfig.PartName) then
		return false
	end
	if inst:IsA("BasePart") then
		return inst.Name ~= "HumanoidRootPart"
	end
	return inst:IsA("Decal") -- Texture тоже наследуется от Decal
end

local function capture(v, inst: Instance)
	if v.saved[inst] or v.sounds[inst] then
		return
	end
	if isFadeable(inst) then
		local orig = { Transparency = (inst :: any).Transparency }
		if inst:IsA("BasePart") then
			orig.Material = inst.Material
			orig.Color = inst.Color
		end
		v.saved[inst] = orig
	elseif inst:IsA("Sound") and not v.isLocal and Config.HideSounds then
		v.sounds[inst] = inst.Volume
	end
end

local function restoreOne(v, inst: Instance)
	local orig = v.saved[inst]
	if orig then
		v.saved[inst] = nil
		local any = inst :: any
		any.Transparency = orig.Transparency
		if orig.Material then
			any.Material = orig.Material
			any.Color = orig.Color
		end
	end
	local volume = v.sounds[inst]
	if volume then
		v.sounds[inst] = nil
		local sound = inst :: Sound
		sound.Volume = volume
	end
end

-- a: 0 = обычный вид, 1 = полностью применён эффект.
-- Куб: тело скрыто у всех. Невидимость: себе — стекло, другим — пусто.
local function applyAlpha(v, a: number)
	local glass = v.isLocal and v.invisible and not v.cube
	for inst, orig in pairs(v.saved) do
		local any = inst :: any
		local goal = glass and math.max(orig.Transparency, Config.SelfTransparency) or 1
		any.Transparency = orig.Transparency + (goal - orig.Transparency) * a
		if orig.Material then
			if glass and a > 0 then
				any.Material = Config.SelfMaterial
				any.Color = orig.Color:Lerp(Config.SelfTint, Config.SelfTintStrength * a)
			else
				any.Material = orig.Material
				any.Color = orig.Color
			end
		end
	end
	local muted = v.invisible and not v.isLocal
	for sound, volume in pairs(v.sounds) do
		sound.Volume = muted and volume * (1 - a) or volume
	end
	if not v.isLocal and Config.HideName then
		if v.invisible and a > 0 and v.savedDisplay == nil then
			v.savedDisplay = v.humanoid.DisplayDistanceType
			v.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		elseif not v.invisible and v.savedDisplay ~= nil then
			v.humanoid.DisplayDistanceType = v.savedDisplay
			v.savedDisplay = nil
		end
	end
	if v.isLocal then
		local tint = glass and a or 0
		screenTint.Enabled = tint > 0
		screenTint.TintColor = WHITE:Lerp(Config.ScreenTint, tint)
		screenTint.Saturation = Config.ScreenSaturation * tint
	end
end

local function begin(v)
	if v.begun then
		return
	end
	v.begun = true
	for _, d in v.character:GetDescendants() do
		capture(v, d)
	end
end

local function restoreAll(v)
	for inst in pairs(v.saved) do
		restoreOne(v, inst)
	end
	for sound in pairs(v.sounds) do
		restoreOne(v, sound)
	end
	if v.savedDisplay then
		v.humanoid.DisplayDistanceType = v.savedDisplay
		v.savedDisplay = nil
	end
	if v.isLocal then
		screenTint.Enabled = false
	end
	v.begun = false
end

---------------------------------------------------------------------
-- Анимации исчезновения и появления
---------------------------------------------------------------------

-- Исчезновение, фаза 1: руки крест-накрест, лёгкое приседание
local VANISH_CROSS = {
	Waist = Vector3.new(-12, 0, 0),
	Neck = Vector3.new(-12, 0, 0),
	LeftShoulder = Vector3.new(75, 0, 38),
	RightShoulder = Vector3.new(75, 0, -38),
	LeftElbow = Vector3.new(95, 0, 0),
	RightElbow = Vector3.new(95, 0, 0),
	LeftHip = Vector3.new(15, 0, -4),
	RightHip = Vector3.new(15, 0, 4),
	LeftKnee = Vector3.new(-25, 0, 0),
	RightKnee = Vector3.new(-25, 0, 0),
}
-- Фаза 2: резкий взмах руками в стороны
local VANISH_FLING = {
	Waist = Vector3.new(10, 0, 0),
	Neck = Vector3.new(12, 0, 0),
	LeftShoulder = Vector3.new(25, 0, -75),
	RightShoulder = Vector3.new(25, 0, 75),
	LeftElbow = Vector3.new(10, 0, 0),
	RightElbow = Vector3.new(10, 0, 0),
}
-- Появление: силовая стойка, грудь вперёд, кулаки сжаты
local APPEAR = {
	Waist = Vector3.new(12, 0, 0),
	Neck = Vector3.new(10, 0, 0),
	LeftShoulder = Vector3.new(-10, 0, -30),
	RightShoulder = Vector3.new(-10, 0, 30),
	LeftElbow = Vector3.new(35, 0, 0),
	RightElbow = Vector3.new(35, 0, 0),
	LeftHip = Vector3.new(0, 0, -7),
	RightHip = Vector3.new(0, 0, 7),
}

local VANISH_TIME = 0.65
local APPEAR_TIME = 0.75

local function vanishLayer()
	local start = os.clock()
	return {
		Priority = 30,
		Update = function(rig, _, now)
			local elapsed = now - start
			if elapsed >= VANISH_TIME then
				return nil, 0, true
			end
			local p = elapsed / VANISH_TIME
			local pose = RigAnimator.Blend(VANISH_CROSS, VANISH_FLING, RigAnimator.Smooth((p - 0.35) / 0.2))
			local frames = RigAnimator.Frames(rig, pose)
			local crouch = 1 - 0.08 * (1 - RigAnimator.Smooth((p - 0.35) / 0.2))
			frames.Root = RigAnimator.RootFrame(rig, crouch)
			return frames, RigAnimator.Envelope(elapsed, VANISH_TIME, 0.1, 0.2)
		end,
	}
end

local function appearLayer()
	local start = os.clock()
	return {
		Priority = 30,
		Update = function(rig, _, now)
			local elapsed = now - start
			if elapsed >= APPEAR_TIME then
				return nil, 0, true
			end
			return RigAnimator.Frames(rig, APPEAR), RigAnimator.Envelope(elapsed, APPEAR_TIME, 0.12, 0.3)
		end,
	}
end

local function burstAt(character: Model, color: Color3)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		AbilityFx.Burst(hrp.Position, {
			Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
			Count = 35,
			Speed = NumberRange.new(6, 14),
			Size = 0.6,
			Lifetime = NumberRange.new(0.4, 0.9),
			Drag = 4,
			Acceleration = Vector3.new(0, 6, 0),
			Light = 12,
		})
	end
end

local function flash(character: Model)
	local h = Instance.new("Highlight")
	h.Name = "InvisibilityFlash"
	h.Adornee = character
	h.FillColor = Config.FlashColor
	h.OutlineColor = Config.FlashColor
	h.FillTransparency = Config.FlashFillTransparency
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = character

	-- Сначала держится, потом плавно гаснет
	local info = TweenInfo.new(
		Config.FlashTime * 0.6,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		0,
		false,
		Config.FlashTime * 0.4
	)
	TweenService:Create(h, info, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(h, Config.FlashTime + 0.1)
end

local function onAttributeChanged(v)
	local invisible = v.character:GetAttribute(Config.ActiveAttribute) == true
	local cube = v.character:GetAttribute(CubeConfig.ActiveAttribute) == true
	local wasInvisible = v.invisible

	v.invisible = invisible
	v.cube = cube
	v.fadeTime = cube and CUBE_FADE_TIME or Config.FadeTime

	if invisible and not wasInvisible then
		RigAnimator.SetLayer(v.character, "InvisibilityVanish", vanishLayer())
		burstAt(v.character, Config.SelfTint)
		if v.isLocal then
			AbilityFx.Shake(0.015, 0.3)
		end
	elseif not invisible and wasInvisible and not cube then
		flash(v.character)
		RigAnimator.SetLayer(v.character, "InvisibilityAppear", appearLayer())
		burstAt(v.character, Config.FlashColor)
	end

	local wanted = (invisible or cube) and 1 or 0
	if wanted == 1 then
		begin(v)
	end
	v.target = wanted
	if v.begun then
		applyAlpha(v, v.alpha)
	end
end

local function removeVisual(character: Model)
	local v = visuals[character]
	if not v then
		return
	end
	visuals[character] = nil
	for _, conn in v.connections do
		conn:Disconnect()
	end
	restoreAll(v)
end

local function addVisual(character: Model)
	if visuals[character] then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local v = {
		character = character,
		humanoid = humanoid,
		isLocal = Players:GetPlayerFromCharacter(character) == player,
		alpha = 0,
		target = 0,
		fadeTime = Config.FadeTime,
		invisible = false,
		cube = false,
		begun = false,
		saved = {},
		sounds = {},
		savedDisplay = nil,
		connections = {},
	}
	visuals[character] = v

	-- Новые части (аксессуары, взятый в руки инструмент) тоже прячем
	table.insert(v.connections, character.DescendantAdded:Connect(function(d)
		if v.begun then
			capture(v, d)
			applyAlpha(v, v.alpha)
		end
	end))
	-- Убранный инструмент возвращаем в нормальный вид
	table.insert(v.connections, character.DescendantRemoving:Connect(function(d)
		restoreOne(v, d)
	end))
	table.insert(v.connections, character:GetAttributeChangedSignal(Config.ActiveAttribute):Connect(function()
		onAttributeChanged(v)
	end))
	table.insert(v.connections, character:GetAttributeChangedSignal(CubeConfig.ActiveAttribute):Connect(function()
		onAttributeChanged(v)
	end))
	table.insert(v.connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			removeVisual(character)
		end
	end))

	onAttributeChanged(v)
end

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(function(character)
		task.spawn(addVisual, character)
	end)
	if p.Character then
		task.spawn(addVisual, p.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end

---------------------------------------------------------------------
-- Кнопка и таймеры
---------------------------------------------------------------------

local AbilityButton = require(ReplicatedStorage:WaitForChild("AbilityButton"))

local lastRequest = 0

local function request()
	local t = os.clock()
	if t - lastRequest < 0.25 then
		return
	end
	lastRequest = t
	remote:FireServer()
end

local button = AbilityButton.new({
	Name = Config.ButtonText,
	Icon = "👻",
	KeyName = Config.Keys[1].Name,
	Slot = Config.ButtonSlot,
	Duration = Config.Duration,
	Cooldown = Config.Cooldown,
	ActiveColor = Config.ActiveColor,
	OnActivate = request,
})

ContextActionService:BindAction("Invisibility", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		request()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, table.unpack(Config.Keys))

---------------------------------------------------------------------
-- Кадровый цикл: плавность эффектов и таймеры
---------------------------------------------------------------------

DebugTimer.connect(RunService.Heartbeat, "InvisibilityClient", function(dt)
	for _, v in pairs(visuals) do
		local step = dt / v.fadeTime
		if v.alpha ~= v.target then
			if v.target > v.alpha then
				v.alpha = math.min(v.target, v.alpha + step)
			else
				v.alpha = math.max(v.target, v.alpha - step)
			end
			applyAlpha(v, v.alpha)
			if v.alpha == 0 and v.target == 0 then
				restoreAll(v)
			end
		end
	end

	local now = serverNow()
	local character = player.Character
	local active = character ~= nil and character:GetAttribute(Config.ActiveAttribute) == true
	local activeLeft = active and math.max(0, (character:GetAttribute(Config.UntilAttribute) or 0) - now) or nil
	local cooldownLeft = math.max(0, (player:GetAttribute(Config.CooldownAttribute) or 0) - now)
	button:Update(activeLeft, cooldownLeft)
end)
