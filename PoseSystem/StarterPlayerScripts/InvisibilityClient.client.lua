-- LocalScript: StarterPlayer > StarterPlayerScripts > InvisibilityClient
-- Клиент способности «Невидимость»:
--   * себя видишь полупрозрачным «стеклом» с голубым оттенком и лёгкой синевой на экране;
--   * другие невидимые игроки скрыты полностью (тело, ник, полоска здоровья, звуки);
--   * при выходе из невидимости персонажа на 1,5 сек обводит красный контур;
--   * кнопка с таймером кулдауна и полоской оставшейся невидимости.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("InvisibilityConfig"))
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName)

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
	if inst:IsA("BasePart") then
		return inst.Name ~= "HumanoidRootPart"
	end
	return inst:IsA("Decal") -- Texture тоже наследуется от Decal
end

local function capture(v, inst: Instance)
	if v.saved[inst] then
		return
	end
	if isFadeable(inst) then
		local orig = { Transparency = (inst :: any).Transparency }
		if inst:IsA("BasePart") then
			orig.Material = inst.Material
			orig.Color = inst.Color
			if v.isLocal then
				inst.Material = Config.SelfMaterial
			end
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

local function applyAlpha(v, a: number)
	for inst, orig in pairs(v.saved) do
		local any = inst :: any
		local goal = v.isLocal and math.max(orig.Transparency, Config.SelfTransparency) or 1
		any.Transparency = orig.Transparency + (goal - orig.Transparency) * a
		if orig.Color and v.isLocal then
			any.Color = orig.Color:Lerp(Config.SelfTint, Config.SelfTintStrength * a)
		end
	end
	for sound, volume in pairs(v.sounds) do
		sound.Volume = volume * (1 - a)
	end
	if v.isLocal then
		screenTint.Enabled = a > 0
		screenTint.TintColor = WHITE:Lerp(Config.ScreenTint, a)
		screenTint.Saturation = Config.ScreenSaturation * a
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
	if not v.isLocal and Config.HideName then
		v.savedDisplay = v.humanoid.DisplayDistanceType
		v.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
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
	local active = v.character:GetAttribute(Config.ActiveAttribute) == true
	if active and v.target == 0 then
		begin(v)
		v.target = 1
	elseif not active and v.target == 1 then
		v.target = 0
		flash(v.character)
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

RunService.Heartbeat:Connect(function(dt)
	local step = dt / Config.FadeTime
	for _, v in pairs(visuals) do
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
