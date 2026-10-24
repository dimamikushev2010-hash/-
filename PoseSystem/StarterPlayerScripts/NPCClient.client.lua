-- LocalScript: StarterPlayer > StarterPlayerScripts > NPCClient
-- Клиент жителей:
--   * облачка с репликами над головой: «выпрыгивают», текст печатается по буквам, потом тают;
--   * значок настроения над головой (💤 💬 🎵 😊 😱 ...), покачивается;
--   * окно разговора с жителем: имя, его ответ и кнопки тем.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local dialogRemote = ReplicatedStorage:WaitForChild("NPCDialog")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BUBBLE_FONT = Enum.Font.GothamMedium
local BUBBLE_TEXT_SIZE = 18
local BUBBLE_MAX_WIDTH = 240
local TYPE_SPEED = 45 -- букв в секунду

local bubbleGui = Instance.new("ScreenGui")
bubbleGui.Name = "NPCBubbles"
bubbleGui.ResetOnSpawn = false
bubbleGui.Parent = playerGui

---------------------------------------------------------------------
-- Облачка
---------------------------------------------------------------------

local bubbles = {} -- [npc model] = { billboard, token }

local function showBubble(model: Model, text: string, duration: number)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local old = bubbles[model]
	if old then
		old.billboard:Destroy()
	end

	local bounds = TextService:GetTextSize(text, BUBBLE_TEXT_SIZE, BUBBLE_FONT, Vector2.new(BUBBLE_MAX_WIDTH, 1000))
	local width, height = bounds.X + 28, bounds.Y + 20

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Bubble"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(width, height + 12)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Parent = bubbleGui

	local group = Instance.new("CanvasGroup")
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.GroupTransparency = 0
	group.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = group

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, -12)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BorderSizePixel = 0
	frame.Parent = group
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

	-- «Хвостик» облачка
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, -12)
	tail.Size = UDim2.fromOffset(14, 14)
	tail.Rotation = 45
	tail.BackgroundColor3 = frame.BackgroundColor3
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = group

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = BUBBLE_FONT
	label.TextSize = BUBBLE_TEXT_SIZE
	label.TextColor3 = Color3.fromRGB(30, 30, 40)
	label.TextWrapped = true
	label.Text = text
	label.MaxVisibleGraphemes = 0
	label.Parent = frame

	local entry = { billboard = billboard }
	bubbles[model] = entry

	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.spawn(function()
		-- Печатаем по буквам
		local length = utf8.len(text) or #text
		local start = os.clock()
		while billboard.Parent do
			local shown = math.floor((os.clock() - start) * TYPE_SPEED)
			label.MaxVisibleGraphemes = math.min(shown, length)
			if shown >= length then
				break
			end
			task.wait()
		end
		label.MaxVisibleGraphemes = -1

		task.wait(duration)
		if bubbles[model] ~= entry then
			return
		end
		local fade = TweenService:Create(group, TweenInfo.new(0.4), { GroupTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if bubbles[model] == entry then
			bubbles[model] = nil
		end
		billboard:Destroy()
	end)
end

---------------------------------------------------------------------
-- Значок настроения
---------------------------------------------------------------------

local moods = {} -- [npc model] = billboard

local function showMood(model: Model)
	local emoji = model:GetAttribute("Mood")
	local old = moods[model]
	if old then
		moods[model] = nil
		local label = old:FindFirstChildOfClass("TextLabel")
		if label then
			local fade = TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 1 })
			fade:Play()
			fade.Completed:Once(function()
				old:Destroy()
			end)
		else
			old:Destroy()
		end
	end
	local head = model:FindFirstChild("Head")
	if type(emoji) ~= "string" or emoji == "" or not head then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Mood"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(38, 38)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.MaxDistance = 60
	billboard.LightInfluence = 0
	billboard.Parent = bubbleGui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = emoji
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- Плавно покачивается вверх-вниз
	TweenService:Create(billboard, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		StudsOffset = Vector3.new(0, 4.35, 0),
	}):Play()
	moods[model] = billboard
end

local function watchNpc(model: Instance)
	if not model:IsA("Model") then
		return
	end
	model:GetAttributeChangedSignal("Mood"):Connect(function()
		showMood(model)
	end)
	if model:GetAttribute("Mood") then
		showMood(model)
	end
	model:GetAttributeChangedSignal("SayId"):Connect(function()
		local text = model:GetAttribute("SayText")
		if type(text) == "string" and text ~= "" then
			showBubble(model, text, model:GetAttribute("SayDuration") or Config.BubbleTime)
		end
	end)
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			if bubbles[model] then
				bubbles[model].billboard:Destroy()
				bubbles[model] = nil
			end
			if moods[model] then
				moods[model]:Destroy()
				moods[model] = nil
			end
		end
	end)
end

for _, model in CollectionService:GetTagged(Config.Tag) do
	watchNpc(model)
end
CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(watchNpc)

---------------------------------------------------------------------
-- Окно разговора
---------------------------------------------------------------------

local dialogGui = Instance.new("ScreenGui")
dialogGui.Name = "NPCDialog"
dialogGui.ResetOnSpawn = false
dialogGui.Enabled = false
dialogGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -110)
panel.Size = UDim2.new(1, -32, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = dialogGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(520, math.huge)
sizeLimit.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(90, 110, 150)
panelStroke.Thickness = 1.5
panelStroke.Parent = panel
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 14)
padding.PaddingBottom = UDim.new(0, 14)
padding.PaddingLeft = UDim.new(0, 16)
padding.PaddingRight = UDim.new(0, 16)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.Parent = panel

local nameLabel = Instance.new("TextLabel")
nameLabel.LayoutOrder = 1
nameLabel.BackgroundTransparency = 1
nameLabel.Size = UDim2.new(1, 0, 0, 22)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextSize = 18
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextColor3 = Color3.fromRGB(255, 205, 110)
nameLabel.Parent = panel

local speechLabel = Instance.new("TextLabel")
speechLabel.LayoutOrder = 2
speechLabel.BackgroundTransparency = 1
speechLabel.Size = UDim2.new(1, 0, 0, 0)
speechLabel.AutomaticSize = Enum.AutomaticSize.Y
speechLabel.Font = Enum.Font.GothamMedium
speechLabel.TextSize = 17
speechLabel.TextWrapped = true
speechLabel.TextXAlignment = Enum.TextXAlignment.Left
speechLabel.TextColor3 = Color3.fromRGB(235, 238, 245)
speechLabel.Parent = panel

local buttons = Instance.new("Frame")
buttons.LayoutOrder = 3
buttons.BackgroundTransparency = 1
buttons.Size = UDim2.new(1, 0, 0, 0)
buttons.AutomaticSize = Enum.AutomaticSize.Y
buttons.Parent = panel
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -5, 0, 38)
grid.CellPadding = UDim2.fromOffset(10, 8)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = buttons

local currentNpc: Model? = nil
local typingToken = 0
local busyUntil = 0

local function typeText(text: string)
	typingToken += 1
	local token = typingToken
	speechLabel.Text = text
	speechLabel.MaxVisibleGraphemes = 0
	local length = utf8.len(text) or #text
	task.spawn(function()
		local start = os.clock()
		while token == typingToken do
			local shown = math.floor((os.clock() - start) * TYPE_SPEED)
			speechLabel.MaxVisibleGraphemes = math.min(shown, length)
			if shown >= length then
				speechLabel.MaxVisibleGraphemes = -1
				break
			end
			task.wait()
		end
	end)
end

local function makeButton(text: string, order: number, accent: boolean, onClick)
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.BackgroundColor3 = accent and Color3.fromRGB(70, 50, 55) or Color3.fromRGB(45, 55, 75)
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(240, 242, 250)
	button.Text = text
	button.TextWrapped = true
	button.Parent = buttons
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
	button.Activated:Connect(function()
		if os.clock() < busyUntil then
			return
		end
		onClick()
	end)
	return button
end

local function closeDialog()
	currentNpc = nil
	typingToken += 1
	dialogGui.Enabled = false
end

local function openDialog(model: Model, name: string, greeting: string, topics: { string })
	currentNpc = model
	nameLabel.Text = name
	typeText(greeting)
	for _, child in buttons:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for i, text in topics do
		makeButton(text, i, false, function()
			busyUntil = os.clock() + 0.7
			dialogRemote:FireServer("Ask", model, i)
		end)
	end
	makeButton("Пока 👋", #topics + 1, true, function()
		dialogRemote:FireServer("Bye", model)
		closeDialog()
	end)

	dialogGui.Enabled = true
	panelScale.Scale = 0.85
	TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

dialogRemote.OnClientEvent:Connect(function(action, model, a, b, c)
	if action == "Open" then
		openDialog(model, a, b, c)
	elseif action == "Answer" and model == currentNpc then
		typeText(a)
	elseif action == "Close" and model == currentNpc then
		closeDialog()
	end
end)
