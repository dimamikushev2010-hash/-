-- LocalScript: StarterPlayer > StarterPlayerScripts > PoliceDeskClient
-- Меню дежурного в полицейском участке:
--   * живой портрет дежурного, его реплики печатаются в облачке;
--   * «Заявление»: что случилось → где → отправить (по заявлению реально выезжает наряд);
--   * «Вопросы»: спросить дежурного о городе;
--   * «Мои заявления»: статус каждого заявления обновляется в реальном времени.
-- Фон размывается, окно плавно появляется, кнопки откликаются на наведение.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("PoliceRemote")
local player = Players.LocalPlayer

local W, H = 700, 450
local C = {
	bg = Color3.fromRGB(16, 22, 38),
	panel = Color3.fromRGB(24, 32, 54),
	card = Color3.fromRGB(34, 45, 74),
	cardHover = Color3.fromRGB(48, 64, 104),
	accent = Color3.fromRGB(70, 140, 255),
	accent2 = Color3.fromRGB(40, 90, 210),
	text = Color3.fromRGB(235, 240, 250),
	dim = Color3.fromRGB(150, 165, 195),
	gold = Color3.fromRGB(255, 205, 90),
	green = Color3.fromRGB(80, 210, 120),
	orange = Color3.fromRGB(255, 160, 60),
	yellow = Color3.fromRGB(250, 220, 80),
	red = Color3.fromRGB(240, 90, 90),
}
local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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
local function corner(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end
local function pad(parent: Instance, p: number)
	new("UIPadding", { PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p) }, parent)
end
local function label(parent: Instance, text: string, size: number, color: Color3?, font: Enum.Font?, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color or C.text,
		Font = font or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 6),
	}, parent)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end

-- Кнопка с откликом на наведение и нажатие
local function button(parent: Instance, text: string, props, onClick)
	local b = new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = C.card,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
	}, parent)
	for k, v in pairs(props or {}) do
		(b :: any)[k] = v
	end
	corner(b, 10)
	local base = b.BackgroundColor3
	local scale = new("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, FAST, { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) }):Play()
		TweenService:Create(scale, FAST, { Scale = 1.03 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, FAST, { BackgroundColor3 = base }):Play()
		TweenService:Create(scale, FAST, { Scale = 1 }):Play()
	end)
	b.Activated:Connect(function()
		scale.Scale = 0.94
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
		onClick()
	end)
	return b
end

---------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "PoliceDesk", ResetOnSpawn = false, Enabled = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
local shade = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)

-- Обычный Frame (не CanvasGroup): внутри ViewportFrame с портретом
local card = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = C.bg,
	ClipsDescendants = true,
}, gui)
corner(card, 18)
new("UIStroke", { Color = C.accent, Thickness = 2, Transparency = 0.3 }, card)
local cardScale = new("UIScale", {}, card)

-- Шапка с градиентом
local header = new("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.accent2, BorderSizePixel = 0 }, card)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(40, 90, 210), Color3.fromRGB(20, 40, 110)), Rotation = 10 }, header)
local badge = new("TextLabel", { BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.85, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(14, 9), Text = "🚔", TextSize = 26, Font = Enum.Font.GothamBold }, header)
corner(badge, 23)
label(header, "Дежурная часть", 22, C.text, Enum.Font.GothamBold, { Position = UDim2.fromOffset(72, 10), Size = UDim2.new(1, -140, 0, 26) })
local subtitle = label(header, "", 15, Color3.fromRGB(200, 215, 255), Enum.Font.Gotham, { Position = UDim2.fromOffset(72, 36), Size = UDim2.new(1, -140, 0, 20) })

-- Левая колонка: портрет и реплика
local left = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 80), Size = UDim2.fromOffset(220, H - 96) }, card)
local portrait = new("ViewportFrame", {
	Size = UDim2.fromOffset(220, 200),
	BackgroundColor3 = C.panel,
	Ambient = Color3.fromRGB(170, 175, 190),
	LightColor = Color3.fromRGB(255, 245, 230),
	LightDirection = Vector3.new(-1, -1, -1),
}, left)
corner(portrait, 14)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(60, 80, 130), Color3.fromRGB(25, 32, 55)), Rotation = 90 }, portrait)
local world = new("WorldModel", {}, portrait)
local camera = new("Camera", { FieldOfView = 30 }, portrait)
portrait.CurrentCamera = camera

local bubble = new("Frame", { Position = UDim2.fromOffset(0, 212), Size = UDim2.fromOffset(220, H - 96 - 212), BackgroundColor3 = Color3.fromRGB(245, 247, 252) }, left)
corner(bubble, 14)
pad(bubble, 12)
local speech = label(bubble, "", 15, Color3.fromRGB(30, 35, 50), Enum.Font.GothamMedium, { Size = UDim2.fromScale(1, 1), TextYAlignment = Enum.TextYAlignment.Top })
new("Frame", { BackgroundColor3 = bubble.BackgroundColor3, Size = UDim2.fromOffset(16, 16), Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 212), ZIndex = 0 }, left)

-- Правая колонка: вкладки и содержимое
local right = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(252, 80), Size = UDim2.new(1, -268, 1, -96) }, card)
local tabsRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38) }, right)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabsRow)
local content = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 48),
	Size = UDim2.new(1, 0, 1, -48),
	BackgroundColor3 = C.panel,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = C.accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, right)
corner(content, 14)
pad(content, 12)

local closeButton = button(header, "✕", { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -52, 0, 12), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.85, TextSize = 20, Font = Enum.Font.GothamBold }, function() end)

---------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------

local data = nil
local officerModel: Model? = nil
local currentTab = "report"
local step, chosenType, chosenPlace = 1, nil, nil
local typingToken = 0
local blur: BlurEffect? = nil
local tabButtons = {}
local render -- объявлена ниже

local function typeText(text: string)
	typingToken += 1
	local token = typingToken
	speech.Text = text
	speech.MaxVisibleGraphemes = 0
	local length = utf8.len(text) or #text
	task.spawn(function()
		local start = os.clock()
		while token == typingToken do
			local shown = math.floor((os.clock() - start) * 50)
			speech.MaxVisibleGraphemes = math.min(shown, length)
			if shown >= length then
				speech.MaxVisibleGraphemes = -1
				break
			end
			task.wait()
		end
	end)
end

local function clearContent()
	for _, c in content:GetChildren() do
		if not c:IsA("UICorner") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function list(parent: Instance, gap: number)
	return new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end

local function statusColor(status: string, done: boolean): Color3
	if done then
		return C.green
	elseif string.find(status, "пути") or string.find(status, "выезжает") then
		return C.orange
	elseif string.find(status, "месте") or string.find(status, "доставлен") then
		return C.yellow
	end
	return C.accent
end

-- Шаги заявления: 1 Что → 2 Где → 3 Отправить
local function stepper(parent: Instance)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0 }, parent)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center }, row)
	for i, name in { "Что случилось", "Где", "Отправить" } do
		local active, passed = i == step, i < step
		local dot = new("TextLabel", {
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = (active or passed) and C.accent or C.card,
			Text = passed and "✓" or tostring(i),
			TextColor3 = C.text,
			TextSize = 13,
			Font = Enum.Font.GothamBold,
		}, row)
		corner(dot, 12)
		new("TextLabel", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24),
			Text = name,
			TextSize = 13,
			Font = active and Enum.Font.GothamBold or Enum.Font.Gotham,
			TextColor3 = active and C.text or C.dim,
		}, row)
		if i < 3 then
			new("Frame", { Size = UDim2.fromOffset(14, 2), BackgroundColor3 = passed and C.accent or C.card, BorderSizePixel = 0 }, row)
		end
	end
end

local function renderReport()
	list(content, 10)
	stepper(content)
	if step == 1 then
		label(content, "Что случилось?", 17, C.text, Enum.Font.GothamBold, { LayoutOrder = 1 })
		local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, content)
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 70), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for i, t in data.types do
			local b = button(grid, "", { LayoutOrder = i }, function()
				chosenType = i
				step = 2
				render()
			end)
			label(b, t.icon, 26, nil, Enum.Font.GothamBold, { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(40, 40), TextXAlignment = Enum.TextXAlignment.Center })
			label(b, t.name, 15, nil, Enum.Font.GothamMedium, { Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -64, 1, 0), TextYAlignment = Enum.TextYAlignment.Center })
		end
	elseif step == 2 then
		local t = data.types[chosenType]
		label(content, string.format("%s %s — где это случилось?", t.icon, t.name), 17, C.text, Enum.Font.GothamBold, { LayoutOrder = 1 })
		for i, name in data.places do
			button(content, "📍  " .. name, { LayoutOrder = 1 + i, TextXAlignment = Enum.TextXAlignment.Left }, function()
				chosenPlace = i
				step = 3
				render()
			end)
		end
		button(content, "← Назад", { LayoutOrder = 100, BackgroundColor3 = C.panel, TextColor3 = C.dim, Size = UDim2.new(0, 120, 0, 32) }, function()
			step = 1
			render()
		end)
	else
		local t = data.types[chosenType]
		local summary = new("Frame", { BackgroundColor3 = C.card, Size = UDim2.new(1, 0, 0, 96), LayoutOrder = 1 }, content)
		corner(summary, 12)
		new("UIStroke", { Color = C.accent, Transparency = 0.5 }, summary)
		label(summary, t.icon, 40, nil, Enum.Font.GothamBold, { Position = UDim2.fromOffset(14, 20), Size = UDim2.fromOffset(56, 56), TextXAlignment = Enum.TextXAlignment.Center })
		label(summary, t.name, 19, C.text, Enum.Font.GothamBold, { Position = UDim2.fromOffset(84, 18), Size = UDim2.new(1, -96, 0, 26) })
		label(summary, "📍 " .. data.places[chosenPlace], 16, C.dim, Enum.Font.Gotham, { Position = UDim2.fromOffset(84, 50), Size = UDim2.new(1, -96, 0, 22) })
		local send = button(content, "Подать заявление", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 18 }, function()
			remote:FireServer("Report", chosenType, chosenPlace)
			step, chosenType, chosenPlace = 1, nil, nil
			currentTab = "tickets"
			render()
		end)
		-- Кнопка «дышит», чтобы притягивать взгляд
		local glow = new("UIStroke", { Color = Color3.fromRGB(150, 200, 255), Thickness = 2 }, send)
		TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.9 }):Play()
		button(content, "← Изменить", { LayoutOrder = 3, BackgroundColor3 = C.panel, TextColor3 = C.dim, Size = UDim2.new(0, 140, 0, 32) }, function()
			step = 2
			render()
		end)
	end
end

local function renderQuestions()
	list(content, 8)
	label(content, "Спросить дежурного", 17, C.text, Enum.Font.GothamBold, { LayoutOrder = 0 })
	for i, q in data.questions do
		button(content, "❓  " .. q, { LayoutOrder = i, TextXAlignment = Enum.TextXAlignment.Left }, function()
			remote:FireServer("Ask", i)
		end)
	end
end

local function renderTickets()
	list(content, 8)
	label(content, "Мои заявления", 17, C.text, Enum.Font.GothamBold, { LayoutOrder = 0 })
	if #data.tickets == 0 then
		label(content, "Пока нет заявлений. Если что-то случилось — подайте заявление.", 15, C.dim, Enum.Font.Gotham, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 44) })
	end
	for i, t in data.tickets do
		local row = new("Frame", { BackgroundColor3 = C.card, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = i }, content)
		corner(row, 12)
		label(row, t.icon, 26, nil, Enum.Font.GothamBold, { Position = UDim2.fromOffset(10, 14), Size = UDim2.fromOffset(36, 36), TextXAlignment = Enum.TextXAlignment.Center })
		label(row, string.format("№%d · %s", t.id, t.kind), 15, C.text, Enum.Font.GothamBold, { Position = UDim2.fromOffset(54, 8), Size = UDim2.new(1, -64, 0, 20) })
		label(row, "📍 " .. t.place, 13, C.dim, Enum.Font.Gotham, { Position = UDim2.fromOffset(54, 26), Size = UDim2.new(1, -64, 0, 16) })
		local color = statusColor(t.status, t.done)
		local chip = new("TextLabel", {
			Position = UDim2.fromOffset(54, 43),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.75,
			TextColor3 = color,
			Text = "  " .. t.status .. "  ",
			TextSize = 12,
			Font = Enum.Font.GothamBold,
		}, row)
		corner(chip, 8)
		if not t.done then
			-- Активное заявление мигает статусом
			TweenService:Create(chip, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.55 }):Play()
		end
	end
end

local TABS = {
	{ id = "report", text = "📝 Заявление" },
	{ id = "questions", text = "❓ Вопросы" },
	{ id = "tickets", text = "📋 Мои заявления" },
}

function render()
	if not data then
		return
	end
	for _, t in TABS do
		local b = tabButtons[t.id]
		if b then
			local active = currentTab == t.id
			TweenService:Create(b, FAST, { BackgroundColor3 = active and C.accent or C.card, TextColor3 = active and C.text or C.dim }):Play()
		end
	end
	clearContent()
	if currentTab == "report" then
		renderReport()
	elseif currentTab == "questions" then
		renderQuestions()
	else
		renderTickets()
	end
	content.CanvasPosition = Vector2.zero
end

for i, t in TABS do
	local b = button(tabsRow, t.text, { Size = UDim2.new(1 / 3, -6, 1, 0), TextSize = 14, LayoutOrder = i }, function()
		currentTab = t.id
		render()
	end)
	tabButtons[t.id] = b
end

---------------------------------------------------------------------
-- Портрет дежурного
---------------------------------------------------------------------

local function setPortrait(model: Model?)
	world:ClearAllChildren()
	if not model then
		return
	end
	local ok, clone = pcall(function()
		model.Archivable = true
		return model:Clone()
	end)
	if not ok or not clone then
		return
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	clone:PivotTo(CFrame.new())
	clone.Parent = world
	local head = clone:FindFirstChild("Head")
	if head then
		local focus = head.Position - Vector3.new(0, 0.6, 0)
		camera.CFrame = CFrame.lookAt(focus + head.CFrame.LookVector * 7 + Vector3.new(0, 0.3, 0), focus)
	end
end

---------------------------------------------------------------------
-- Открыть / закрыть
---------------------------------------------------------------------

local function fitScale()
	local view = workspace.CurrentCamera.ViewportSize
	return math.min(1, (view.X - 24) / W, (view.Y - 24) / H)
end

local function close()
	if not gui.Enabled then
		return
	end
	TweenService:Create(cardScale, FAST, { Scale = 0.6 * fitScale() }):Play()
	TweenService:Create(shade, FAST, { BackgroundTransparency = 1 }):Play()
	if blur then
		local b = blur
		blur = nil
		local fade = TweenService:Create(b, FAST, { Size = 0 })
		fade:Play()
		fade.Completed:Once(function()
			b:Destroy()
		end)
	end
	task.delay(0.16, function()
		gui.Enabled = false
		world:ClearAllChildren()
	end)
	data = nil
end
closeButton.Activated:Connect(close)

local function open(payload)
	data = payload
	officerModel = payload.officer
	subtitle.Text = (payload.name or "Дежурный") .. " · на связи"
	currentTab, step, chosenType, chosenPlace = "report", 1, nil, nil
	setPortrait(officerModel)
	typeText(payload.greeting or "")
	render()

	gui.Enabled = true
	if not blur then
		blur = new("BlurEffect", { Size = 0, Name = "PoliceDeskBlur" }, Lighting)
		TweenService:Create(blur, TweenInfo.new(0.3), { Size = 14 }):Play()
	end
	shade.BackgroundTransparency = 1
	TweenService:Create(shade, TweenInfo.new(0.3), { BackgroundTransparency = 0.55 }):Play()
	cardScale.Scale = 0.75 * fitScale()
	TweenService:Create(cardScale, POP, { Scale = fitScale() }):Play()
end

remote.OnClientEvent:Connect(function(action, payload)
	if action == "Open" then
		open(payload)
	elseif action == "Say" and data then
		typeText(payload)
	elseif action == "Tickets" and data then
		data.tickets = payload
		if currentTab == "tickets" then
			render()
		end
	end
end)

-- Отошёл от стойки — окно закрывается; портрет чуть «дышит»
RunService.RenderStepped:Connect(function()
	if not gui.Enabled or not data then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local officerRoot = officerModel and officerModel:FindFirstChild("HumanoidRootPart")
	if not root or not officerRoot or (root.Position - officerRoot.Position).Magnitude > 18 then
		close()
		return
	end
	local head = world:FindFirstChildWhichIsA("Model") and world:FindFirstChildWhichIsA("Model"):FindFirstChild("Head")
	if head then
		local t = os.clock()
		local focus = head.Position - Vector3.new(0, 0.6, 0)
		local offset = Vector3.new(math.sin(t * 0.6) * 0.25, 0.3 + math.sin(t * 0.9) * 0.08, 0)
		camera.CFrame = CFrame.lookAt(focus + head.CFrame.LookVector * 7 + offset, focus)
	end
end)
