-- LocalScript: StarterPlayer > StarterPlayerScripts > InvisibilityClient
-- Клиент способности «Невидимость»:
--   * себя видишь полупрозрачным «стеклом» с голубым оттенком и лёгкой синевой на экране;
--   * другие невидимые игроки скрыты полностью (тело, ник, полоска здоровья, звуки);
--   * при выходе из невидимости персонажа на 1,5 сек обводит красный контур;
--   * кнопка с таймером кулдауна и полоской оставшейся невидимости.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
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

local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local gui = Instance.new("ScreenGui")
gui.Name = "InvisibilityGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Name = "InvisibilityButton"
button.AnchorPoint = Vector2.new(1, 1)
button.Position = isTouch and UDim2.new(1, -20, 1, -175) or UDim2.new(1, -24, 1, -34)
button.Size = UDim2.fromOffset(78, 78)
button.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
button.BackgroundTransparency = 0.2
button.AutoButtonColor = true
button.Text = ""
button.ClipsDescendants = true
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(90, 100, 120)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = button

local icon = Instance.new("TextLabel")
icon.BackgroundTransparency = 1
icon.Size = UDim2.new(1, 0, 1, -18)
icon.Text = "👻"
icon.TextScaled = true
icon.Font = Enum.Font.GothamBold
icon.TextColor3 = WHITE
icon.ZIndex = 2
icon.Parent = button
local iconPad = Instance.new("UIPadding")
iconPad.PaddingTop = UDim.new(0, 8)
iconPad.PaddingLeft = UDim.new(0, 14)
iconPad.PaddingRight = UDim.new(0, 14)
iconPad.Parent = icon

local nameLabel = Instance.new("TextLabel")
nameLabel.BackgroundTransparency = 1
nameLabel.AnchorPoint = Vector2.new(0, 1)
nameLabel.Position = UDim2.new(0, 0, 1, -4)
nameLabel.Size = UDim2.new(1, 0, 0, 14)
nameLabel.Text = Config.ButtonText
nameLabel.TextColor3 = Color3.fromRGB(210, 220, 235)
nameLabel.Font = Enum.Font.GothamMedium
nameLabel.TextSize = 11
nameLabel.ZIndex = 2
nameLabel.Parent = button

if not isTouch then
	local keyLabel = Instance.new("TextLabel")
	keyLabel.BackgroundColor3 = Color3.new(0, 0, 0)
	keyLabel.BackgroundTransparency = 0.4
	keyLabel.Position = UDim2.fromOffset(5, 5)
	keyLabel.Size = UDim2.fromOffset(18, 18)
	keyLabel.Text = Config.Keys[1].Name
	keyLabel.TextColor3 = WHITE
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextSize = 12
	keyLabel.ZIndex = 4
	keyLabel.Parent = button
	Instance.new("UICorner", keyLabel).CornerRadius = UDim.new(0, 4)
end

-- Затемнение кулдауна (опускается сверху вниз по мере отката)
local cooldownShade = Instance.new("Frame")
cooldownShade.AnchorPoint = Vector2.new(0, 1)
cooldownShade.Position = UDim2.fromScale(0, 1)
cooldownShade.Size = UDim2.fromScale(1, 0)
cooldownShade.BackgroundColor3 = Color3.new(0, 0, 0)
cooldownShade.BackgroundTransparency = 0.35
cooldownShade.BorderSizePixel = 0
cooldownShade.ZIndex = 3
cooldownShade.Parent = button

local cooldownText = Instance.new("TextLabel")
cooldownText.BackgroundTransparency = 1
cooldownText.Size = UDim2.fromScale(1, 1)
cooldownText.Text = ""
cooldownText.TextColor3 = WHITE
cooldownText.Font = Enum.Font.GothamBlack
cooldownText.TextSize = 28
cooldownText.TextStrokeTransparency = 0.5
cooldownText.ZIndex = 4
cooldownText.Parent = button

-- Полоска оставшейся невидимости под кнопкой
local barBack = Instance.new("Frame")
barBack.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
barBack.BackgroundTransparency = 0.2
barBack.BorderSizePixel = 0
barBack.Visible = false
barBack.Parent = gui
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = Config.ActiveColor
barFill.BorderSizePixel = 0
barFill.Parent = barBack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

local function placeBar()
	-- Полоска живёт в ScreenGui (у кнопки обрезка), ставим её прямо под кнопкой
	local pos, size = button.AbsolutePosition, button.AbsoluteSize
	barBack.Position = UDim2.fromOffset(pos.X, pos.Y + size.Y + 6)
	barBack.Size = UDim2.fromOffset(size.X, 6)
end
button:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeBar)
button:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeBar)
placeBar()

local lastRequest = 0

local function request()
	local t = os.clock()
	if t - lastRequest < 0.25 then
		return
	end
	lastRequest = t
	remote:FireServer()
end

button.Activated:Connect(request)

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

	if active then
		local left = math.max(0, (character:GetAttribute(Config.UntilAttribute) or 0) - now)
		barBack.Visible = true
		barFill.Size = UDim2.fromScale(math.clamp(left / Config.Duration, 0, 1), 1)
		stroke.Color = Config.ActiveColor
		cooldownShade.Size = UDim2.fromScale(1, 0)
		cooldownText.Text = ""
		icon.TextTransparency = 0.4
	else
		barBack.Visible = false
		local cdLeft = math.max(0, (player:GetAttribute(Config.CooldownAttribute) or 0) - now)
		if cdLeft > 0 then
			cooldownShade.Size = UDim2.fromScale(1, math.clamp(cdLeft / Config.Cooldown, 0, 1))
			cooldownText.Text = tostring(math.ceil(cdLeft))
			stroke.Color = Color3.fromRGB(90, 100, 120)
			icon.TextTransparency = 0.5
		else
			cooldownShade.Size = UDim2.fromScale(1, 0)
			cooldownText.Text = ""
			stroke.Color = Color3.fromRGB(150, 165, 190)
			icon.TextTransparency = 0
		end
	end
end)
