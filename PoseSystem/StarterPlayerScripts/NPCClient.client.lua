-- LocalScript: StarterPlayer > StarterPlayerScripts > NPCClient
-- Клиент жителей:
--   * облачка с репликами над головой: «выпрыгивают», текст печатается по буквам, потом тают;
--   * значок настроения над головой (💤 💬 🎵 😊 😱 ...), покачивается;
--   * окно разговора с жителем: имя, уровень дружбы, ответ и кнопки тем;
--   * задания: вещь видна только тебе, отмечена значком сквозь стены, трекер сверху экрана;
--   * всплывающие уведомления (+монеты, новый друг);
--   * собаки на поводке у жителей: бегают рядом, виляют хвостом, садятся, гавкают;
--   * звуки жителей: шаги, «бормотание» голосом при репликах (у каждого своя высота),
--     смех, крик, храп, лай, скрип дверей (ID звуков — в SoundConfig).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))

-- Руки за спиной (задержанный в наручниках): только руки, ноги шагают как обычно
local CUFFED_POSE = {
	LeftShoulder = Vector3.new(-32, 0, 26),
	RightShoulder = Vector3.new(-32, 0, -26),
	LeftElbow = Vector3.new(38, 0, 0),
	RightElbow = Vector3.new(38, 0, 0),
}

local function cuffedLayer(model: Model)
	local weight = 0
	return {
		Priority = 40,
		Update = function(rig, dt)
			local on = model:GetAttribute("Cuffed") == true
			weight = math.clamp(weight + (on and dt or -dt) * 4, 0, 1)
			if not on and weight <= 0 then
				return nil, 0, true
			end
			return RigAnimator.Frames(rig, CUFFED_POSE), weight
		end,
	}
end
local dialogRemote = ReplicatedStorage:WaitForChild("NPCDialog")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BUBBLE_FONT = Enum.Font.GothamMedium
local BUBBLE_TEXT_SIZE = 18
local BUBBLE_MAX_WIDTH = 240
local TYPE_SPEED = 45 -- букв в секунду

-- Звук в детали (3D: громче рядом, тише вдали)
local function playAt(parent: Instance?, def, pitch: number?)
	if not parent or not def or def.Id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = 70
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local bubbleGui = Instance.new("ScreenGui")
bubbleGui.Name = "NPCBubbles"
bubbleGui.ResetOnSpawn = false
bubbleGui.Parent = playerGui

---------------------------------------------------------------------
-- Облачка
---------------------------------------------------------------------

local bubbles = {} -- [npc model] = { billboard, token }

-- target — житель (облачко над головой) или любая деталь (например, голова собаки)
local function showBubble(model: Instance, text: string, duration: number)
	local head = model:IsA("BasePart") and model or model:FindFirstChild("Head")
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
		-- Голос: живое «бормотание» с высотой этого жителя; длинная реплика — пара слогов
		local pitch = (not model:IsA("BasePart")) and model:GetAttribute("VoicePitch") or nil
		local syllables = pitch and math.clamp(math.ceil(length / 12), 1, 3) or 0
		local nextBlip = 0
		while billboard.Parent do
			local shown = math.floor((os.clock() - start) * TYPE_SPEED)
			label.MaxVisibleGraphemes = math.min(shown, length)
			if syllables > 0 and os.clock() >= nextBlip then
				syllables -= 1
				nextBlip = os.clock() + 1 / Sounds.VoiceSpeed
				playAt(head, Sounds.NPC.Voice, pitch * (0.95 + math.random() * 0.1))
			end
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
	-- Наручники
	local function onCuffed()
		if model:GetAttribute("Cuffed") == true and not RigAnimator.HasLayer(model, "Cuffed") then
			RigAnimator.SetLayer(model, "Cuffed", cuffedLayer(model))
		end
	end
	model:GetAttributeChangedSignal("Cuffed"):Connect(onCuffed)
	onCuffed()

	-- Звуковые события с сервера: смех, крик, храп...
	model:GetAttributeChangedSignal("SoundEventId"):Connect(function()
		local name = model:GetAttribute("SoundEvent")
		local def = type(name) == "string" and Sounds.NPC[name] or nil
		local pitch = model:GetAttribute("VoicePitch") or 1
		playAt(model:FindFirstChild("Head"), def, name == "Hurt" and pitch * 0.9 + 0.1 or pitch)
	end)
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

local function setTopics(model: Model, topics: { string })
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
end

local function openDialog(model: Model, name: string, greeting: string, topics: { string })
	currentNpc = model
	nameLabel.Text = name
	typeText(greeting)
	setTopics(model, topics)

	dialogGui.Enabled = true
	panelScale.Scale = 0.85
	TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------------
-- Всплывающие уведомления
---------------------------------------------------------------------

local toastGui = Instance.new("ScreenGui")
toastGui.Name = "NPCToasts"
toastGui.ResetOnSpawn = false
toastGui.Parent = playerGui

local toastList = Instance.new("Frame")
toastList.AnchorPoint = Vector2.new(0.5, 0)
toastList.Position = UDim2.new(0.5, 0, 0, 110)
toastList.Size = UDim2.fromOffset(360, 200)
toastList.BackgroundTransparency = 1
toastList.Parent = toastGui
local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.Parent = toastList

local function showToast(text: string)
	local holder = Instance.new("CanvasGroup")
	holder.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	holder.BackgroundTransparency = 0.1
	holder.Size = UDim2.fromOffset(0, 36)
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.Parent = toastList
	Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 18)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = holder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 225, 120)
	label.Text = text
	label.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = holder
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.8, function()
		local fade = TweenService:Create(holder, TweenInfo.new(0.4), { GroupTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		holder:Destroy()
	end)
end

---------------------------------------------------------------------
-- Трекер задания (сверху экрана)
---------------------------------------------------------------------

local tracker = Instance.new("Frame")
tracker.AnchorPoint = Vector2.new(0.5, 0)
tracker.Position = UDim2.new(0.5, 0, 0, 62)
tracker.Size = UDim2.fromOffset(0, 38)
tracker.AutomaticSize = Enum.AutomaticSize.X
tracker.BackgroundColor3 = Color3.fromRGB(40, 32, 20)
tracker.BackgroundTransparency = 0.15
tracker.Visible = false
tracker.Parent = toastGui
Instance.new("UICorner", tracker).CornerRadius = UDim.new(0, 12)
local trackerStroke = Instance.new("UIStroke")
trackerStroke.Color = Color3.fromRGB(255, 200, 80)
trackerStroke.Thickness = 1.5
trackerStroke.Parent = tracker
local trackerPad = Instance.new("UIPadding")
trackerPad.PaddingLeft = UDim.new(0, 14)
trackerPad.PaddingRight = UDim.new(0, 14)
trackerPad.Parent = tracker
local trackerLabel = Instance.new("TextLabel")
trackerLabel.BackgroundTransparency = 1
trackerLabel.Size = UDim2.fromScale(0, 1)
trackerLabel.AutomaticSize = Enum.AutomaticSize.X
trackerLabel.Font = Enum.Font.GothamBold
trackerLabel.TextSize = 16
trackerLabel.TextColor3 = Color3.fromRGB(255, 235, 190)
trackerLabel.Parent = tracker
local trackerScale = Instance.new("UIScale")
trackerScale.Parent = tracker

local function updateTracker()
	local text = player:GetAttribute("QuestText")
	if type(text) == "string" and text ~= "" then
		trackerLabel.Text = "❗ " .. text
		if not tracker.Visible then
			tracker.Visible = true
			trackerScale.Scale = 0.6
			TweenService:Create(trackerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	else
		tracker.Visible = false
	end
end
player:GetAttributeChangedSignal("QuestText"):Connect(updateTracker)
updateTracker()

---------------------------------------------------------------------
-- Вещи для заданий: видны только тому, кто ищет
---------------------------------------------------------------------

local questItems = {} -- [part] = { marker, distanceLabel }

local function watchQuestItem(item: Instance)
	if not item:IsA("BasePart") then
		return
	end
	local mine = item:GetAttribute("QuestOwner") == player.UserId
	if not mine then
		item.LocalTransparencyModifier = 1
		for _, d in item:GetDescendants() do
			if d:IsA("ProximityPrompt") or d:IsA("Sparkles") then
				d.Enabled = false
			end
		end
		return
	end
	local marker = Instance.new("BillboardGui")
	marker.Adornee = item
	marker.AlwaysOnTop = true
	marker.Size = UDim2.fromOffset(70, 60)
	marker.StudsOffset = Vector3.new(0, 2, 0)
	marker.LightInfluence = 0
	marker.Parent = bubbleGui
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 0, 36)
	icon.Text = item:GetAttribute("QuestIcon") or "❗"
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBold
	icon.Parent = marker
	local distance = Instance.new("TextLabel")
	distance.BackgroundTransparency = 1
	distance.Position = UDim2.fromOffset(0, 38)
	distance.Size = UDim2.new(1, 0, 0, 20)
	distance.Font = Enum.Font.GothamBold
	distance.TextSize = 15
	distance.TextColor3 = Color3.fromRGB(255, 230, 120)
	distance.TextStrokeTransparency = 0.4
	distance.Parent = marker
	TweenService:Create(marker, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		StudsOffset = Vector3.new(0, 2.6, 0),
	}):Play()
	questItems[item] = { marker = marker, distance = distance, base = item.CFrame }
	item.AncestryChanged:Connect(function()
		if not item.Parent and questItems[item] then
			questItems[item].marker:Destroy()
			questItems[item] = nil
		end
	end)
end

for _, item in CollectionService:GetTagged("QuestItem") do
	watchQuestItem(item)
end
CollectionService:GetInstanceAddedSignal("QuestItem"):Connect(watchQuestItem)

---------------------------------------------------------------------
-- Собаки на поводке
---------------------------------------------------------------------

local dogs = {} -- [npc model] = собака
local dogParams = RaycastParams.new()
dogParams.FilterType = Enum.RaycastFilterType.Exclude

local function dogPart(folder: Instance, size: Vector3, color: Color3, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Parent = folder
	return p
end

local function createDog(model: Model)
	local color = model:GetAttribute("DogColor")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hand = model:FindFirstChild("LeftHand")
	if typeof(color) ~= "Color3" or not hrp then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "Dog_" .. model.Name
	folder.Parent = workspace
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local dog = {
		folder = folder,
		body = dogPart(folder, Vector3.new(1.1, 0.9, 2), color),
		head = dogPart(folder, Vector3.new(0.9, 0.85, 0.9), color),
		snout = dogPart(folder, Vector3.new(0.5, 0.35, 0.45), dark),
		nose = dogPart(folder, Vector3.new(0.2, 0.15, 0.1), Color3.fromRGB(20, 20, 20)),
		earL = dogPart(folder, Vector3.new(0.22, 0.5, 0.12), dark),
		earR = dogPart(folder, Vector3.new(0.22, 0.5, 0.12), dark),
		tail = dogPart(folder, Vector3.new(0.18, 0.18, 0.9), color),
		legs = {},
		pos = hrp.Position - hrp.CFrame.LookVector * 3,
		look = hrp.CFrame.LookVector,
		phase = 0,
		still = 0,
		nextBark = os.clock() + math.random(8, 25),
	}
	for i = 1, 4 do
		dog.legs[i] = dogPart(folder, Vector3.new(0.28, 0.7, 0.28), color)
	end
	for _, eyeX in { -0.22, 0.22 } do
		dog["eye" .. (eyeX < 0 and "L" or "R")] = dogPart(folder, Vector3.new(0.14, 0.14, 0.05), Color3.fromRGB(15, 15, 15))
	end

	-- Поводок
	if hand then
		local a0 = Instance.new("Attachment")
		a0.Name = "LeashHand"
		a0.Position = Vector3.new(0, -0.3, 0)
		a0.Parent = hand
		local a1 = Instance.new("Attachment")
		a1.Name = "LeashCollar"
		a1.Parent = dog.head
		local leash = Instance.new("Beam")
		leash.Attachment0 = a0
		leash.Attachment1 = a1
		leash.Color = ColorSequence.new(Color3.fromRGB(170, 40, 40))
		leash.Width0 = 0.08
		leash.Width1 = 0.08
		leash.FaceCamera = true
		leash.Segments = 12
		leash.CurveSize0 = -1
		leash.CurveSize1 = 1
		leash.Parent = dog.head
		dog.handAttachment = a0
	end
	dogs[model] = dog
end

local function destroyDog(model: Model)
	local dog = dogs[model]
	if dog then
		dogs[model] = nil
		dog.folder:Destroy()
		if dog.handAttachment then
			dog.handAttachment:Destroy()
		end
	end
end

local function updateDog(model: Model, dog, dt: number, now: number)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	-- Место рядом с хозяином: сбоку и чуть сзади
	local goal = hrp.Position + hrp.CFrame.RightVector * 2.2 - hrp.CFrame.LookVector * 1.2
	local toGoal = Vector3.new(goal.X - dog.pos.X, 0, goal.Z - dog.pos.Z)
	local dist = toGoal.Magnitude
	local speed = 0
	if dist > 0.4 then
		local maxStep = math.max(10, dist * 3) * dt
		local step = math.min(dist, maxStep)
		dog.pos += toGoal.Unit * step
		speed = step / dt
		dog.look = dog.look:Lerp(toGoal.Unit, math.min(1, dt * 8))
	else
		local ownerLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		dog.look = dog.look:Lerp(ownerLook.Unit, math.min(1, dt * 3))
	end
	-- Пол под собакой
	dogParams.FilterDescendantsInstances = { model, dog.folder }
	local hit = workspace:Raycast(Vector3.new(dog.pos.X, hrp.Position.Y + 2, dog.pos.Z), Vector3.new(0, -12, 0), dogParams)
	local ground = hit and hit.Position.Y or (hrp.Position.Y - 3)
	dog.pos = Vector3.new(dog.pos.X, ground, dog.pos.Z)

	local moving = speed > 1
	dog.still = moving and 0 or dog.still + dt
	local sitting = dog.still > 2.5
	dog.phase += dt * (moving and math.clamp(speed, 4, 20) * 1.1 or 0)

	local look = Vector3.new(dog.look.X, 0, dog.look.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local bob = moving and math.abs(math.sin(dog.phase)) * 0.15 or 0
	local root = CFrame.lookAt(dog.pos, dog.pos + look.Unit) * CFrame.new(0, 1.15 + bob, 0)
	-- Сидит: корпус наклонён назад
	local bodyCF = sitting and (root * CFrame.new(0, -0.25, 0.2) * CFrame.Angles(math.rad(25), 0, 0)) or root
	dog.body.CFrame = bodyCF
	local headCF = bodyCF * CFrame.new(0, 0.55, -1.15) * CFrame.Angles(math.rad(sitting and -20 or 0) + math.sin(now * 2) * 0.05, math.sin(now * 0.7) * 0.25, 0)
	dog.head.CFrame = headCF
	dog.snout.CFrame = headCF * CFrame.new(0, -0.15, -0.6)
	dog.nose.CFrame = headCF * CFrame.new(0, -0.05, -0.85)
	dog.eyeL.CFrame = headCF * CFrame.new(-0.22, 0.15, -0.46)
	dog.eyeR.CFrame = headCF * CFrame.new(0.22, 0.15, -0.46)
	local earFlap = math.sin(dog.phase * 2) * (moving and 0.25 or 0.05)
	dog.earL.CFrame = headCF * CFrame.new(-0.4, 0.2, 0.05) * CFrame.Angles(0, 0, math.rad(20) + earFlap)
	dog.earR.CFrame = headCF * CFrame.new(0.4, 0.2, 0.05) * CFrame.Angles(0, 0, -math.rad(20) - earFlap)
	-- Хвост виляет, на ходу быстрее
	local wag = math.sin(now * (moving and 18 or 10)) * 0.6
	dog.tail.CFrame = bodyCF * CFrame.new(0, 0.35, 1.05) * CFrame.Angles(math.rad(35), wag, 0) * CFrame.new(0, 0, 0.4)
	-- Лапы шагают
	local legOffsets = { Vector3.new(-0.35, -0.55, -0.7), Vector3.new(0.35, -0.55, -0.7), Vector3.new(-0.35, -0.55, 0.7), Vector3.new(0.35, -0.55, 0.7) }
	for i = 1, 4 do
		local swing = moving and math.sin(dog.phase + (i % 2 == 0 and math.pi or 0) + (i > 2 and math.pi or 0)) * 0.6 or 0
		local legRoot = (sitting and i > 2) and root or bodyCF
		dog.legs[i].CFrame = legRoot * CFrame.new(legOffsets[i] + Vector3.new(0, 0.2, 0)) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.35, 0)
	end
	-- Гав!
	if now > dog.nextBark then
		dog.nextBark = now + math.random(12, 35)
		showBubble(dog.head, "Гав!", 1.2)
		playAt(dog.head, Sounds.NPC.DogBark, 0.9 + math.random() * 0.3)
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, model in CollectionService:GetTagged(Config.Tag) do
		if model:GetAttribute("DogColor") and not dogs[model] and model:FindFirstChild("HumanoidRootPart") then
			createDog(model)
		end
	end
	for model, dog in pairs(dogs) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not model.Parent or not humanoid or humanoid.Health <= 0 then
			destroyDog(model)
		else
			updateDog(model, dog, dt, now)
		end
	end
	-- Вещи для заданий вращаются, показываем расстояние
	local character = player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	for item, entry in pairs(questItems) do
		item.CFrame = entry.base * CFrame.new(0, math.sin(now * 3) * 0.2, 0) * CFrame.Angles(0, now * 2, 0)
		if myRoot then
			entry.distance.Text = string.format("%d м", math.floor((item.Position - myRoot.Position).Magnitude))
		end
	end
end)

dialogRemote.OnClientEvent:Connect(function(action, model, a, b, c)
	if action == "Toast" then
		showToast(model)
		return
	elseif action == "Title" and model == currentNpc then
		nameLabel.Text = a
		return
	end
	if action == "Open" then
		openDialog(model, a, b, c)
	elseif action == "Answer" and model == currentNpc then
		typeText(a)
		if type(b) == "table" then
			setTopics(model, b)
		end
	elseif action == "Close" and model == currentNpc then
		closeDialog()
	end
end)

---------------------------------------------------------------------
-- Шаги жителей
---------------------------------------------------------------------

local steps = {} -- [npc] = пройденное расстояние
local STEP_LENGTH = 2.6

RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	for _, model in CollectionService:GetTagged(Config.Tag) do
		local hrp = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if hrp and humanoid and humanoid.Health > 0 and (hrp.Position - camera.CFrame.Position).Magnitude < 60 then
			local v = hrp.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local grounded = math.abs(v.Y) < 2
			if speed > 2 and grounded and not humanoid.PlatformStand then
				steps[model] = (steps[model] or 0) + speed * dt
				if steps[model] >= STEP_LENGTH then
					steps[model] = 0
					playAt(hrp, Sounds.NPC.Footstep, 0.9 + math.random() * 0.25 + (speed > 15 and 0.15 or 0))
				end
			end
		else
			steps[model] = nil
		end
	end
end)

---------------------------------------------------------------------
-- Скрип дверей домов
---------------------------------------------------------------------

task.spawn(function()
	local system = workspace:WaitForChild(Config.FolderName, 60)
	local doors = system and system:WaitForChild("Doors", 30)
	if not doors then
		return
	end
	local function watchDoor(door: Instance)
		door:GetAttributeChangedSignal("DoorOpen"):Connect(function()
			local part = door:IsA("BasePart") and door or door:FindFirstChildWhichIsA("BasePart", true)
			playAt(part, door:GetAttribute("DoorOpen") and Sounds.NPC.HouseDoorOpen or Sounds.NPC.HouseDoorClose)
		end)
	end
	for _, d in doors:GetChildren() do
		watchDoor(d)
	end
	doors.ChildAdded:Connect(watchDoor)
end)
