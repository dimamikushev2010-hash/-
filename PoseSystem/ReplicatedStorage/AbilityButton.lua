-- ModuleScript: ReplicatedStorage > AbilityButton
-- Общая кнопка способности: иконка, клавиша, затемнение и секунды кулдауна,
-- полоска оставшегося действия. Кнопки выстраиваются в ряд справа внизу по Slot.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки
local ContextActionService = game:GetService("ContextActionService")

local AbilityButton = {}
AbilityButton.__index = AbilityButton

local SIZE = 78
local GAP = 14
local BAR_HEIGHT = 6
local WHITE = Color3.new(1, 1, 1)
local IDLE_STROKE = Color3.fromRGB(150, 165, 190)
local COOLDOWN_STROKE = Color3.fromRGB(90, 100, 120)

local function getGui(): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("AbilitiesGui")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "AbilitiesGui"
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
	end
	return gui
end

--[[
	opts = {
		Name = "Невидимость",
		Icon = "👻",
		KeyName = "Q",
		Slot = 1,            -- 1 = крайняя справа, 2 = левее и т.д.
		Duration = 8,        -- для полоски действия
		Cooldown = 20,       -- для затемнения
		ActiveColor = Color3,
		OnActivate = function() end,
	}
]]
function AbilityButton.new(opts)
	local self = setmetatable({}, AbilityButton)
	self.duration = opts.Duration
	self.cooldown = opts.Cooldown
	self.activeColor = opts.ActiveColor

	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local slotOffset = (opts.Slot - 1) * (SIZE + GAP)

	-- Контейнер: кнопка сверху, полоска под ней
	local holder = Instance.new("Frame")
	holder.Name = opts.Name
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Size = UDim2.fromOffset(SIZE, SIZE + BAR_HEIGHT + 6)
	holder.Position = isTouch and UDim2.new(1, -20 - slotOffset, 1, -165)
		or UDim2.new(1, -24 - slotOffset, 1, -24)
	holder.Parent = getGui()

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(SIZE, SIZE)
	button.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	button.BackgroundTransparency = 0.2
	button.Text = ""
	button.ClipsDescendants = true
	button.Parent = holder
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 14)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = IDLE_STROKE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 1, -18)
	icon.Text = opts.Icon
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
	nameLabel.Text = opts.Name
	nameLabel.TextColor3 = Color3.fromRGB(210, 220, 235)
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 11
	nameLabel.ZIndex = 2
	nameLabel.Parent = button

	if not isTouch and opts.KeyName then
		local keyLabel = Instance.new("TextLabel")
		keyLabel.BackgroundColor3 = Color3.new(0, 0, 0)
		keyLabel.BackgroundTransparency = 0.4
		keyLabel.Position = UDim2.fromOffset(5, 5)
		keyLabel.Size = UDim2.fromOffset(18, 18)
		keyLabel.Text = opts.KeyName
		keyLabel.TextColor3 = WHITE
		keyLabel.Font = Enum.Font.GothamBold
		keyLabel.TextSize = 12
		keyLabel.ZIndex = 4
		keyLabel.Parent = button
		Instance.new("UICorner", keyLabel).CornerRadius = UDim.new(0, 4)
	end

	-- Затемнение кулдауна: уменьшается снизу вверх по мере отката
	local shade = Instance.new("Frame")
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.ZIndex = 3
	shade.Parent = button

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

	-- Полоска оставшегося действия
	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0, 1)
	barBack.Position = UDim2.fromScale(0, 1)
	barBack.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	barBack.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	barBack.BackgroundTransparency = 0.2
	barBack.BorderSizePixel = 0
	barBack.Visible = false
	barBack.Parent = holder
	Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = opts.ActiveColor
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = holder

	-- Нажатие: кнопка «проседает» и пружинит обратно
	button.Activated:Connect(function()
		self:Pulse(0.86)
		opts.OnActivate()
	end)

	self.uiScale = uiScale
	self.wasCooling = false
	self.stroke = stroke
	self.icon = icon
	self.shade = shade
	self.cooldownText = cooldownText
	self.barBack = barBack
	self.barFill = barFill
	return self
end

function AbilityButton:Pulse(from: number)
	self.uiScale.Scale = from
	TweenService:Create(self.uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Вспышка «способность готова»
function AbilityButton:ReadyFlash()
	self:Pulse(1.18)
	self.stroke.Thickness = 5
	TweenService:Create(self.stroke, TweenInfo.new(0.5), { Thickness = 2 }):Play()
end

-- activeLeft: сколько секунд ещё действует способность (nil — не активна)
-- cooldownLeft: сколько секунд осталось до готовности
function AbilityButton:Update(activeLeft: number?, cooldownLeft: number)
	local cooling = activeLeft == nil and cooldownLeft > 0
	if self.wasCooling and not cooling and activeLeft == nil then
		self:ReadyFlash()
	end
	self.wasCooling = cooling
	if self.wasActive and not activeLeft then
		self.stroke.Thickness = 2
	end
	self.wasActive = activeLeft ~= nil

	if activeLeft then
		-- Пока способность действует, обводка «дышит»
		self.stroke.Thickness = 2.5 + math.sin(os.clock() * 8) * 1.2
		self.barBack.Visible = true
		self.barFill.Size = UDim2.fromScale(math.clamp(activeLeft / self.duration, 0, 1), 1)
		self.stroke.Color = self.activeColor
		self.shade.Size = UDim2.fromScale(1, 0)
		self.cooldownText.Text = ""
		self.icon.TextTransparency = 0.4
	elseif cooldownLeft > 0 then
		self.barBack.Visible = false
		self.shade.Size = UDim2.fromScale(1, math.clamp(cooldownLeft / self.cooldown, 0, 1))
		self.cooldownText.Text = tostring(math.ceil(cooldownLeft))
		self.stroke.Color = COOLDOWN_STROKE
		self.icon.TextTransparency = 0.5
	else
		self.barBack.Visible = false
		self.shade.Size = UDim2.fromScale(1, 0)
		self.cooldownText.Text = ""
		self.stroke.Color = IDLE_STROKE
		self.icon.TextTransparency = 0
	end
end

-- Всё сразу: кнопка, клавиши, запрос на сервер и таймеры по атрибутам.
-- opts — как у new(), плюс Remote, Keys, ActionName,
-- ActiveAttribute, UntilAttribute, CooldownAttribute.
function AbilityButton.Create(opts)
	local player = Players.LocalPlayer
	local lastRequest = 0
	local button

	local function request()
		local t = os.clock()
		if t - lastRequest < 0.25 then
			return
		end
		lastRequest = t
		opts.Remote:FireServer()
	end

	opts.OnActivate = request
	opts.KeyName = opts.KeyName or opts.Keys[1].Name
	button = AbilityButton.new(opts)

	ContextActionService:BindAction(opts.ActionName, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			button:Pulse(0.86)
			request()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(opts.Keys))

	DebugTimer.connect(RunService.Heartbeat, "AbilityButton", function()
		local now = workspace:GetServerTimeNow()
		local character = player.Character
		local active = character ~= nil and character:GetAttribute(opts.ActiveAttribute) == true
		local activeLeft = active and math.max(0, (character:GetAttribute(opts.UntilAttribute) or 0) - now) or nil
		local cooldownLeft = math.max(0, (player:GetAttribute(opts.CooldownAttribute) or 0) - now)
		button:Update(activeLeft, cooldownLeft)
	end)

	return button
end

return AbilityButton
