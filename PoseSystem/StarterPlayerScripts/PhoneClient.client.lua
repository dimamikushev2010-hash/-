-- LocalScript: StarterPlayer > StarterPlayerScripts > PhoneClient
-- Телефон игрока: клавиша P или кнопка 📱.
--   Экран блокировки (время, дата, погода, уведомления) → рабочий стол с приложениями:
--   🗺 Карта (дороги, ты, автобус, такси, полиция), 🚕 Такси (вызвать к себе),
--   🚔 Полиция 102 (заявления), 🚌 Автобус (маршрут), 💬 Сообщения (знакомые жители),
--   ☀️ Погода, 📋 Задания, ⚙️ Настройки (обои, часы, капли дождя).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local CityConfig = require(ReplicatedStorage:WaitForChild("CityConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local remote = ReplicatedStorage:WaitForChild("PhoneRemote")

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local W, H = 300, 620
local SW, SH = W - 20, H - 20 -- экран внутри рамки
local FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local WHITE = Color3.new(1, 1, 1)

local WALLPAPERS = {
	{ Color3.fromRGB(60, 40, 140), Color3.fromRGB(20, 120, 200) },
	{ Color3.fromRGB(240, 110, 80), Color3.fromRGB(120, 40, 140) },
	{ Color3.fromRGB(20, 140, 110), Color3.fromRGB(10, 40, 70) },
	{ Color3.fromRGB(30, 30, 40), Color3.fromRGB(80, 80, 100) },
}

local APPS = {
	{ id = "map", name = "Карта", icon = "🗺️", colors = { Color3.fromRGB(70, 200, 120), Color3.fromRGB(20, 120, 80) } },
	{ id = "taxi", name = "Такси", icon = "🚕", colors = { Color3.fromRGB(255, 210, 60), Color3.fromRGB(230, 150, 20) } },
	{ id = "police", name = "Полиция", icon = "🚔", colors = { Color3.fromRGB(80, 140, 255), Color3.fromRGB(30, 60, 170) } },
	{ id = "bus", name = "Автобус", icon = "🚌", colors = { Color3.fromRGB(255, 140, 60), Color3.fromRGB(210, 70, 40) } },
	{ id = "messages", name = "Сообщения", icon = "💬", colors = { Color3.fromRGB(90, 220, 110), Color3.fromRGB(30, 160, 70) } },
	{ id = "weather", name = "Погода", icon = "☀️", colors = { Color3.fromRGB(110, 190, 255), Color3.fromRGB(40, 110, 220) } },
	{ id = "quests", name = "Задания", icon = "📋", colors = { Color3.fromRGB(250, 120, 160), Color3.fromRGB(190, 60, 120) } },
	{ id = "work", name = "Работа", icon = "📦", colors = { Color3.fromRGB(210, 150, 90), Color3.fromRGB(140, 85, 40) } },
	{ id = "shop", name = "Магазин", icon = "🛍️", colors = { Color3.fromRGB(200, 110, 255), Color3.fromRGB(120, 50, 190) } },
	{ id = "awards", name = "Награды", icon = "🏆", colors = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(210, 140, 20) } },
	{ id = "camera", name = "Камера", icon = "📷", colors = { Color3.fromRGB(90, 95, 110), Color3.fromRGB(30, 32, 40) } },
	{ id = "settings", name = "Настройки", icon = "⚙️", colors = { Color3.fromRGB(160, 165, 180), Color3.fromRGB(90, 95, 110) } },
}

---------------------------------------------------------------------
-- Помощники
---------------------------------------------------------------------

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
local function text(parent: Instance, value: string, size: number, color: Color3?, bold: boolean?, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextSize = size,
		TextColor3 = color or WHITE,
		Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 6),
	}, parent)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end

local function playSound(def)
	if not def or def.Id == "" then
		return
	end
	local s = new("Sound", { SoundId = def.Id, Volume = def.Volume or 0.4 }, workspace)
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local soundsOn = true
local function tap()
	if soundsOn then
		playSound(Sounds.Phone and Sounds.Phone.Tap)
	end
end

local function button(parent: Instance, label: string, props, onClick)
	local b = new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.85,
		Text = label,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
	}, parent)
	for k, v in pairs(props or {}) do
		(b :: any)[k] = v
	end
	corner(b, 12)
	local scale = new("UIScale", {}, b)
	local baseT = b.BackgroundTransparency
	b.MouseEnter:Connect(function()
		TweenService:Create(b, FAST, { BackgroundTransparency = math.max(0, baseT - 0.1) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, FAST, { BackgroundTransparency = baseT }):Play()
	end)
	b.Activated:Connect(function()
		scale.Scale = 0.92
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
		tap()
		onClick()
	end)
	return b
end

local function list(parent: Instance, gap: number)
	return new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, parent)
end

local function card(parent: Instance, height: number?, order: number?)
	local c = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.88,
		Size = UDim2.new(1, 0, 0, height or 0),
		AutomaticSize = height and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
		LayoutOrder = order or 0,
	}, parent)
	corner(c, 14)
	pad(c, 12)
	return c
end

local function clockText(): (string, string)
	local hour = workspace:GetAttribute("Hour") or Lighting.ClockTime
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60)
	local weekDay = workspace:GetAttribute("WeekDay") or 1
	local names = { "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье" }
	local period = workspace:GetAttribute("Period") or ""
	return string.format("%02d:%02d", h, m), string.format("%s · %s", names[weekDay] or "", period)
end

---------------------------------------------------------------------
-- Каркас телефона
---------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "Phone", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

-- Кнопка 📱 с красным значком непрочитанного
local toggle = new("TextButton", {
	AnchorPoint = isTouch and Vector2.new(0, 0.5) or Vector2.new(0, 1),
	Position = isTouch and UDim2.new(0, 12, 0.42, 0) or UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(56, 56),
	BackgroundColor3 = Color3.fromRGB(25, 28, 40),
	BackgroundTransparency = 0.1,
	Text = "📱",
	TextSize = 28,
	Font = Enum.Font.GothamBold,
	AutoButtonColor = true,
}, gui)
corner(toggle, 16)
new("UIStroke", { Color = Color3.fromRGB(110, 130, 190), Thickness = 1.5, Transparency = 0.3 }, toggle)
local toggleScale = new("UIScale", {}, toggle)
local badge = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -4, 0, 4),
	Size = UDim2.fromOffset(22, 22),
	BackgroundColor3 = Color3.fromRGB(240, 60, 60),
	TextColor3 = WHITE,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	Text = "",
	Visible = false,
	ZIndex = 3,
}, toggle)
corner(badge, 11)
if not isTouch then
	text(toggle, "P", 11, Color3.fromRGB(180, 190, 220), true, { Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(12, 12), TextXAlignment = Enum.TextXAlignment.Center })
end

-- Подсказка рядом с кнопкой, когда телефон закрыт
local peek = new("TextLabel", {
	AnchorPoint = toggle.AnchorPoint,
	Position = toggle.Position + UDim2.fromOffset(66, 0),
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(25, 28, 40),
	BackgroundTransparency = 0.1,
	TextColor3 = WHITE,
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	Text = "",
	Visible = false,
}, gui)
corner(peek, 12)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, peek)

local phone = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, W + 60, 0.5, 0),
	Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = Color3.fromRGB(12, 12, 16),
	Visible = false,
}, gui)
corner(phone, 44)
new("UIStroke", { Color = Color3.fromRGB(70, 72, 85), Thickness = 3 }, phone)
local phoneScale = new("UIScale", {}, phone)

local screen = new("Frame", {
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.fromOffset(SW, SH),
	BackgroundColor3 = WHITE,
	ClipsDescendants = true,
}, phone)
corner(screen, 36)
local wallpaper = new("UIGradient", { Rotation = 120 }, screen)

-- Статус-бар и «островок»
local statusBar = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), ZIndex = 20 }, screen)
local statusTime = text(statusBar, "", 14, WHITE, true, { Position = UDim2.fromOffset(26, 8), Size = UDim2.fromOffset(60, 20), ZIndex = 20 })
local statusIcons = text(statusBar, "", 12, WHITE, true, { Position = UDim2.new(1, -110, 0, 9), Size = UDim2.fromOffset(90, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 20 })
local island = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(84, 24), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 21 }, screen)
corner(island, 12)

-- Полоска «домой»
local homeBar = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(110, 5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, Text = "", ZIndex = 30 }, screen)
corner(homeBar, 3)

-- Уведомление сверху экрана
local banner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -80), Size = UDim2.new(1, -20, 0, 62), BackgroundColor3 = Color3.fromRGB(30, 32, 44), BackgroundTransparency = 0.05, ZIndex = 40 }, screen)
corner(banner, 18)
pad(banner, 10)
local bannerIcon = text(banner, "", 26, WHITE, true, { Size = UDim2.fromOffset(34, 40), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
local bannerTitle = text(banner, "", 13, Color3.fromRGB(180, 190, 215), true, { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -42, 0, 16), ZIndex = 41 })
local bannerText = text(banner, "", 14, WHITE, false, { Position = UDim2.fromOffset(42, 17), Size = UDim2.new(1, -42, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 41 })

-- Слои: блокировка, рабочий стол, приложение
local lockLayer = new("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 5, AutoButtonColor = false }, screen)
local homeLayer = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Visible = false }, screen)
local appLayer = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 20, 30), ZIndex = 10, Visible = false }, screen)
corner(appLayer, 36)
local appScale = new("UIScale", {}, appLayer)

---------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------

local isOpen, locked = false, true
local currentApp = nil
local data = { places = {}, policeTypes = {}, tickets = {}, busStops = {}, friends = {}, taxiPrice = VehicleConfig.TaxiPrice }
local city = { stats = {}, done = {}, owned = {}, equipped = {} } -- работа, магазин, достижения
local weaponState = { owned = {}, ammo = {}, blocked = false } -- оружие (WeaponServer)
local chats = {} -- [имя] = { messages = { {mine, text} }, unread = 0, typingUntil = 0 }
local openChat = nil
local notifications = {}
local taxiStatus = nil
local policeStep, policeType = 1, nil
local policeAnswer = nil
local wallpaperIndex = 1
local renderApp, renderLock, renderHomeBadges, closePhone -- объявлены ниже

local function applyWallpaper()
	local w = WALLPAPERS[wallpaperIndex]
	wallpaper.Color = ColorSequence.new(w[1], w[2])
end
applyWallpaper()

local function unreadTotal(): number
	local n = 0
	for _, chat in pairs(chats) do
		n += chat.unread
	end
	return n
end

local function updateBadges()
	local n = unreadTotal()
	badge.Visible = n > 0
	badge.Text = tostring(math.min(n, 99))
	renderHomeBadges()
end

---------------------------------------------------------------------
-- Уведомления
---------------------------------------------------------------------

local bannerToken = 0
local function notify(icon: string, title: string, body: string)
	table.insert(notifications, 1, { icon = icon, title = title, body = body })
	if #notifications > 5 then
		table.remove(notifications)
	end
	if soundsOn then
		playSound(Sounds.Phone and Sounds.Phone.Notify)
	end
	if isOpen then
		bannerToken += 1
		local token = bannerToken
		bannerIcon.Text, bannerTitle.Text, bannerText.Text = icon, title, body
		TweenService:Create(banner, POP, { Position = UDim2.new(0.5, 0, 0, 40) }):Play()
		task.delay(2.8, function()
			if token == bannerToken then
				TweenService:Create(banner, FAST, { Position = UDim2.new(0.5, 0, 0, -80) }):Play()
			end
		end)
	else
		peek.Text = icon .. "  " .. title .. ": " .. body
		peek.Visible = true
		toggleScale.Scale = 1.2
		TweenService:Create(toggleScale, POP, { Scale = 1 }):Play()
		bannerToken += 1
		local token = bannerToken
		task.delay(3.5, function()
			if token == bannerToken then
				peek.Visible = false
			end
		end)
	end
	if locked then
		renderLock()
	end
end

---------------------------------------------------------------------
-- Экран блокировки
---------------------------------------------------------------------

local lockTime = text(lockLayer, "", 64, WHITE, true, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 72), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
local lockDate = text(lockLayer, "", 15, Color3.fromRGB(230, 235, 255), false, { Position = UDim2.fromOffset(0, 148), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
local lockWeather = text(lockLayer, "", 15, Color3.fromRGB(230, 235, 255), false, { Position = UDim2.fromOffset(0, 170), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
local lockList = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 210), Size = UDim2.new(1, -24, 0, 280), ZIndex = 6 }, lockLayer)
list(lockList, 8)
local lockHint = text(lockLayer, "Нажмите, чтобы открыть", 14, WHITE, true, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
TweenService:Create(lockHint, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.6 }):Play()

function renderLock()
	for _, c in lockList:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, n in notifications do
		if i > 3 then
			break
		end
		local c = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = i, ZIndex = 6 }, lockList)
		corner(c, 16)
		pad(c, 10)
		text(c, n.icon, 22, WHITE, true, { Size = UDim2.fromOffset(30, 36), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		text(c, n.title, 13, Color3.fromRGB(240, 240, 255), true, { Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -38, 0, 16), ZIndex = 7 })
		text(c, n.body, 13, WHITE, false, { Position = UDim2.fromOffset(38, 17), Size = UDim2.new(1, -38, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 })
	end
end

local function updateClock()
	local t, d = clockText()
	statusTime.Text = t
	lockTime.Text = t
	lockDate.Text = d
	local icon = workspace:GetAttribute("WeatherIcon") or ""
	local name = workspace:GetAttribute("WeatherName") or ""
	lockWeather.Text = icon .. " " .. name
	statusIcons.Text = icon .. "  📶 🔋"
end

---------------------------------------------------------------------
-- Рабочий стол
---------------------------------------------------------------------

local grid = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 1, -120), ZIndex = 4 }, homeLayer)
new("UIGridLayout", { CellSize = UDim2.fromOffset(72, 92), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, grid)
local homeBadges = {}
local openApp -- объявлена ниже

for i, app in APPS do
	local cell = new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 4 }, grid)
	local icon = new("TextButton", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(4, 0), BackgroundColor3 = WHITE, Text = app.icon, TextSize = 32, Font = Enum.Font.GothamBold, AutoButtonColor = false, ZIndex = 4 }, cell)
	corner(icon, 18)
	new("UIGradient", { Color = ColorSequence.new(app.colors[1], app.colors[2]), Rotation = 90 }, icon)
	local scale = new("UIScale", {}, icon)
	icon.MouseEnter:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 1.08 }):Play()
	end)
	icon.MouseLeave:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 1 }):Play()
	end)
	icon.Activated:Connect(function()
		scale.Scale = 0.85
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
		tap()
		openApp(app.id)
	end)
	text(cell, app.name, 12, WHITE, true, { Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.7, ZIndex = 4 })
	local b = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(64, 4), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromRGB(240, 60, 60), TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 12, Visible = false, ZIndex = 6 }, cell)
	corner(b, 11)
	homeBadges[app.id] = b
end

function renderHomeBadges()
	local unread = unreadTotal()
	homeBadges.messages.Visible = unread > 0
	homeBadges.messages.Text = tostring(unread)
	local active = 0
	for _, t in data.tickets do
		if not t.done then
			active += 1
		end
	end
	homeBadges.police.Visible = active > 0
	homeBadges.police.Text = tostring(active)
	homeBadges.taxi.Visible = taxiStatus ~= nil and not taxiStatus.done
	homeBadges.taxi.Text = "!"
	homeBadges.work.Visible = player:GetAttribute("JobStage") ~= nil
	homeBadges.work.Text = "!"
end

---------------------------------------------------------------------
-- Приложение: шапка и содержимое
---------------------------------------------------------------------

local appHeader = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 44), ZIndex = 11 }, appLayer)
local backButton = new("TextButton", { Position = UDim2.fromOffset(10, 4), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, Text = "‹", TextSize = 34, TextColor3 = Color3.fromRGB(110, 170, 255), Font = Enum.Font.GothamBold, ZIndex = 11 }, appHeader)
local appTitle = text(appHeader, "", 20, WHITE, true, { Position = UDim2.fromOffset(50, 8), Size = UDim2.new(1, -60, 0, 28), ZIndex = 11 })
local content = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 84),
	Size = UDim2.new(1, 0, 1, -100),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 11,
}, appLayer)
pad(content, 12)

local function clearContent()
	for _, c in content:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function goHome()
	if not currentApp then
		return
	end
	currentApp = nil
	openChat = nil
	TweenService:Create(appScale, FAST, { Scale = 0.4 }):Play()
	task.delay(0.15, function()
		if not currentApp then
			appLayer.Visible = false
		end
	end)
end
backButton.Activated:Connect(function()
	tap()
	if currentApp == "messages" and openChat then
		openChat = nil
		renderApp()
	else
		goHome()
	end
end)
homeBar.Activated:Connect(goHome)

function openApp(id: string)
	if id == "camera" then
		-- Камера — это фоторежим на весь экран (CityLifeClient)
		closePhone()
		task.delay(0.25, function()
			player:SetAttribute("PhotoMode", true)
		end)
		return
	end
	currentApp = id
	openChat = nil
	for _, app in APPS do
		if app.id == id then
			appTitle.Text = app.icon .. "  " .. app.name
		end
	end
	if id == "messages" then
		remote:FireServer("Friends")
	elseif id == "shop" or id == "awards" or id == "work" then
		remote:FireServer("City")
		if id == "shop" then
			remote:FireServer("Weapons")
		end
	end
	appLayer.Visible = true
	appScale.Scale = 0.4
	TweenService:Create(appScale, POP, { Scale = 1 }):Play()
	renderApp()
end

---------------------------------------------------------------------
-- 🗺 Карта
---------------------------------------------------------------------

local map = { frame = nil, markers = {}, bounds = nil }
local MAP_W, MAP_H = SW - 24, 360

local function trafficFolder(name: string): Instance?
	local root = workspace:FindFirstChild(VehicleConfig.MapFolder)
	return root and root:FindFirstChild(name)
end

local function toMap(pos: Vector3): UDim2
	local b = map.bounds
	local x = (pos.X - b.minX) / math.max(1, b.maxX - b.minX)
	local y = (pos.Z - b.minZ) / math.max(1, b.maxZ - b.minZ)
	return UDim2.fromOffset(10 + x * (MAP_W - 20), 10 + y * (MAP_H - 20))
end

local function renderMap()
	local roads = trafficFolder("Roads")
	local frame = new("Frame", { BackgroundColor3 = Color3.fromRGB(28, 40, 34), Size = UDim2.fromOffset(MAP_W, MAP_H), ClipsDescendants = true, LayoutOrder = 1, ZIndex = 11 }, content)
	corner(frame, 16)
	map.frame = frame
	map.markers = {}
	if not roads then
		text(frame, "Карта недоступна: нет дорог", 14, WHITE, false, { Position = UDim2.fromOffset(12, 12), ZIndex = 12 })
		return
	end
	local nodes = {}
	local b = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
	for _, p in roads:GetDescendants() do
		if p:IsA("BasePart") then
			nodes[p.Name] = p
			b.minX, b.maxX = math.min(b.minX, p.Position.X), math.max(b.maxX, p.Position.X)
			b.minZ, b.maxZ = math.min(b.minZ, p.Position.Z), math.max(b.maxZ, p.Position.Z)
		end
	end
	-- Сохраняем пропорции
	local spanX, spanZ = b.maxX - b.minX, b.maxZ - b.minZ
	local aspect = (MAP_W - 20) / (MAP_H - 20)
	if spanX / math.max(1, spanZ) > aspect then
		local extra = spanX / aspect - spanZ
		b.minZ -= extra / 2
		b.maxZ += extra / 2
	else
		local extra = spanZ * aspect - spanX
		b.minX -= extra / 2
		b.maxX += extra / 2
	end
	b.minX -= 15
	b.maxX += 15
	b.minZ -= 15
	b.maxZ += 15
	map.bounds = b

	-- Дороги
	local drawn = {}
	for name, p in pairs(nodes) do
		local links = p:GetAttribute("Links")
		if type(links) == "string" then
			for item in string.gmatch(links, "[^,;]+") do
				local other = string.match(item, "^%s*(.-)%s*$")
				local q = nodes[other]
				local key = name < other and name .. "|" .. other or other .. "|" .. name
				if q and not drawn[key] then
					drawn[key] = true
					local a, c = toMap(p.Position), toMap(q.Position)
					local ax, ay, cx, cy = a.X.Offset, a.Y.Offset, c.X.Offset, c.Y.Offset
					local len = math.sqrt((cx - ax) ^ 2 + (cy - ay) ^ 2)
					local road = new("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset((ax + cx) / 2, (ay + cy) / 2),
						Size = UDim2.fromOffset(len + 6, 6),
						Rotation = math.deg(math.atan2(cy - ay, cx - ax)),
						BackgroundColor3 = Color3.fromRGB(120, 125, 135),
						BorderSizePixel = 0,
						ZIndex = 12,
					}, frame)
					corner(road, 3)
				end
			end
		end
	end

	local function marker(icon: string, pos: Vector3, size: number, z: number)
		return new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(pos), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Text = icon, TextSize = size - 4, Font = Enum.Font.GothamBold, ZIndex = z }, frame)
	end
	-- Места, остановки, участок
	local places = trafficFolder("Places")
	if places then
		for _, p in places:GetDescendants() do
			if p:IsA("BasePart") then
				marker("📍", p.Position, 18, 13)
				text(frame, p:GetAttribute("PlaceName") or p.Name, 10, Color3.fromRGB(230, 235, 245), true, {
					AnchorPoint = Vector2.new(0.5, 0), Position = toMap(p.Position) + UDim2.fromOffset(0, 8),
					Size = UDim2.fromOffset(90, 14), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, ZIndex = 13,
				})
			end
		end
	end
	local stops = trafficFolder("BusStops")
	if stops then
		for _, p in stops:GetDescendants() do
			if p:IsA("BasePart") then
				marker("🚏", p.Position, 16, 13)
			end
		end
	end
	local station = trafficFolder("PoliceStation")
	local desk = station and station:FindFirstChild("Desk", true)
	if desk then
		marker("🏢", desk.Position, 20, 13)
	end

	-- Живые метки: машины и ты
	map.vehicleIcons = {}
	map.me = marker("🔵", Vector3.zero, 18, 16)
	map.arrow = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Text = "▲", TextSize = 16, TextColor3 = Color3.fromRGB(120, 190, 255), Font = Enum.Font.GothamBold, ZIndex = 15 }, frame)

	local legend = card(content, nil, 2)
	text(legend, "🔵 Ты   🚌 Автобус   🚕 Такси   🚓 Полиция   🚗 Машины   🚏 Остановка   🏢 Участок", 12, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 34) })
end

local VEHICLE_ICONS = { Bus = "🚌", Taxi = "🚕", Police = "🚓", Civilian = "🚗" }

local function updateMap(now: number)
	if not map.frame or not map.bounds or not map.frame.Parent then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		map.me.Position = toMap(root.Position)
		map.me.TextSize = 14 + math.sin(now * 5) * 2
		local look = root.CFrame.LookVector
		map.arrow.Position = toMap(root.Position + look * 9)
		map.arrow.Rotation = math.deg(math.atan2(look.Z, look.X)) + 90
	end
	local vehicles = trafficFolder(VehicleConfig.VehiclesFolder)
	local seen = {}
	if vehicles then
		for _, m in vehicles:GetChildren() do
			local body = m:IsA("Model") and m.PrimaryPart
			if body then
				seen[m] = true
				local icon = map.vehicleIcons[m]
				if not icon then
					icon = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, TextSize = 16, Font = Enum.Font.GothamBold, ZIndex = 14 }, map.frame)
					map.vehicleIcons[m] = icon
				end
				icon.Text = VEHICLE_ICONS[m:GetAttribute("VehicleType")] or "🚗"
				icon.Position = toMap(body.Position)
				-- Мигалки полиции на карте
				icon.TextTransparency = (m:GetAttribute("Siren") and (now * 4) % 1 < 0.5) and 0.5 or 0
			end
		end
	end
	for m, icon in pairs(map.vehicleIcons) do
		if not seen[m] then
			icon:Destroy()
			map.vehicleIcons[m] = nil
		end
	end
end

---------------------------------------------------------------------
-- Остальные приложения
---------------------------------------------------------------------

local function statusChip(parent: Instance, value: string, color: Color3, order: number?)
	local chip = new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.7,
		TextColor3 = color:Lerp(WHITE, 0.4),
		Text = "  " .. value .. "  ",
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		LayoutOrder = order or 0,
	}, parent)
	corner(chip, 10)
	return chip
end

local function renderTaxi()
	list(content, 8)
	local top = card(content, nil, 0)
	list(top, 4)
	text(top, "🚕 Такси к вашему месту", 16, WHITE, true)
	text(top, string.format("Цена поездки: %d 🪙", data.taxiPrice or 5), 14, Color3.fromRGB(255, 220, 120), false)
	if taxiStatus then
		local s = card(content, nil, 1)
		list(s, 6)
		text(s, taxiStatus.text, 15, WHITE, true, { Size = UDim2.new(1, 0, 0, 40) })
		if not taxiStatus.done then
			statusChip(s, "В процессе", Color3.fromRGB(255, 190, 60))
		end
	end
	local busy = taxiStatus and not taxiStatus.done
	text(content, busy and "Дождитесь окончания поездки" or "Куда едем?", 14, Color3.fromRGB(180, 190, 215), true, { LayoutOrder = 2 })
	if not busy then
		for i, name in data.places do
			button(content, "📍  " .. name, { LayoutOrder = 2 + i, TextXAlignment = Enum.TextXAlignment.Left }, function()
				taxiStatus = { text = "Ищем свободное такси...", done = false }
				remote:FireServer("Taxi", i)
				renderApp()
			end)
		end
	end
end

local function ticketColor(t): Color3
	if t.done then
		return Color3.fromRGB(80, 210, 120)
	elseif string.find(t.status, "пути") or string.find(t.status, "выезжает") then
		return Color3.fromRGB(255, 160, 60)
	elseif string.find(t.status, "месте") or string.find(t.status, "доставлен") then
		return Color3.fromRGB(250, 220, 80)
	end
	return Color3.fromRGB(90, 150, 255)
end

local function renderPolice()
	list(content, 8)
	if policeAnswer then
		local a = card(content, nil, 0)
		text(a, "👮 " .. policeAnswer, 14, WHITE, false, { Size = UDim2.new(1, 0, 0, 40) })
	end
	if policeStep == 1 then
		text(content, "Что случилось?", 15, WHITE, true, { LayoutOrder = 1 })
		local g = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, content)
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 58), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, g)
		for i, t in data.policeTypes do
			button(g, t.icon .. "\n" .. t.name, { LayoutOrder = i, TextSize = 13 }, function()
				policeType = i
				policeStep = 2
				renderApp()
			end)
		end
	else
		local t = data.policeTypes[policeType]
		text(content, (t and t.icon .. " " .. t.name or "") .. " — где?", 15, WHITE, true, { LayoutOrder = 1 })
		for i, name in data.places do
			button(content, "📍  " .. name, { LayoutOrder = 1 + i, TextXAlignment = Enum.TextXAlignment.Left }, function()
				remote:FireServer("Report", policeType, i)
				policeStep, policeType = 1, nil
				policeAnswer = "Отправляем заявление..."
				renderApp()
			end)
		end
		button(content, "← Назад", { LayoutOrder = 99, Size = UDim2.new(0, 110, 0, 32), BackgroundTransparency = 0.92 }, function()
			policeStep = 1
			renderApp()
		end)
	end
	if #data.tickets > 0 then
		text(content, "Мои заявления", 15, WHITE, true, { LayoutOrder = 100 })
		for i, t in data.tickets do
			local row = card(content, nil, 100 + i)
			list(row, 4)
			text(row, string.format("%s №%d · %s", t.icon, t.id, t.kind), 14, WHITE, true)
			text(row, "📍 " .. t.place, 12, Color3.fromRGB(180, 190, 215), false)
			statusChip(row, t.status, ticketColor(t))
		end
	end
end

local function findBus(): Model?
	local vehicles = trafficFolder(VehicleConfig.VehiclesFolder)
	if vehicles then
		for _, m in vehicles:GetChildren() do
			if m:GetAttribute("VehicleType") == "Bus" then
				return m
			end
		end
	end
	return nil
end

local function renderBus()
	list(content, 8)
	local bus = findBus()
	local top = card(content, nil, 0)
	list(top, 4)
	if not bus then
		text(top, "Автобус сейчас не ходит", 15, WHITE, true)
		return
	end
	local at = bus:GetAttribute("AtStop") or ""
	local nextStop = bus:GetAttribute("NextStop") or ""
	text(top, at ~= "" and ("🚌 Стоит: " .. at) or ("🚌 Едет к: " .. nextStop), 16, WHITE, true)
	local speed = math.floor((bus:GetAttribute("Speed") or 0) * 10) / 10
	text(top, at ~= "" and "Двери открыты — успейте сесть!" or string.format("Скорость: %s", tostring(speed)), 13, Color3.fromRGB(180, 190, 215), false)
	text(content, "Маршрут", 15, WHITE, true, { LayoutOrder = 1 })
	for i, name in data.busStops do
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1 + i }, content)
		local here = name == at
		local nextOne = at == "" and name == nextStop
		local dotColor = here and Color3.fromRGB(80, 210, 120) or nextOne and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(110, 115, 135)
		local dot = new("Frame", { Position = UDim2.fromOffset(10, 12), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = dotColor }, row)
		corner(dot, 9)
		if i < #data.busStops then
			new("Frame", { Position = UDim2.fromOffset(17, 30), Size = UDim2.fromOffset(4, 16), BackgroundColor3 = Color3.fromRGB(80, 85, 100), BorderSizePixel = 0 }, row)
		end
		text(row, name .. (here and "  🚌" or nextOne and "  ← едет сюда" or ""), 15, WHITE, here or nextOne, { Position = UDim2.fromOffset(40, 10), Size = UDim2.new(1, -40, 0, 22) })
	end
end

local function chatOf(name: string)
	chats[name] = chats[name] or { messages = {}, unread = 0, typingUntil = 0 }
	return chats[name]
end

local function renderMessages()
	list(content, 8)
	if not openChat then
		local names, seen = {}, {}
		for _, f in data.friends do
			table.insert(names, f)
			seen[f.name] = true
		end
		for name in pairs(chats) do
			if not seen[name] then
				table.insert(names, { name = name, level = "", icon = "" })
			end
		end
		if #names == 0 then
			local c = card(content, nil, 0)
			text(c, "Пока никто не пишет. Поговори с жителями — знакомые будут писать сюда!", 14, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 56) })
			return
		end
		for i, f in names do
			local chat = chatOf(f.name)
			local last = chat.messages[#chat.messages]
			local row = button(content, "", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 0.9 }, function()
				openChat = f.name
				chat.unread = 0
				updateBadges()
				renderApp()
			end)
			local hue = (string.byte(f.name, 1) or 0) % 6
			local avatar = new("TextLabel", { Position = UDim2.fromOffset(8, 9), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = Color3.fromHSV(hue / 6, 0.55, 0.85), Text = string.sub(f.name, 1, utf8.offset(f.name, 2) and utf8.offset(f.name, 2) - 1 or 1), TextSize = 20, Font = Enum.Font.GothamBold, TextColor3 = WHITE }, row)
			corner(avatar, 22)
			text(row, f.name .. (f.icon ~= "" and " " .. f.icon or ""), 15, WHITE, true, { Position = UDim2.fromOffset(62, 10), Size = UDim2.new(1, -100, 0, 20) })
			local preview = os.clock() < chat.typingUntil and "печатает…" or (last and ((last.mine and "Вы: " or "") .. last.text) or f.level)
			text(row, preview, 13, Color3.fromRGB(180, 190, 215), false, { Position = UDim2.fromOffset(62, 32), Size = UDim2.new(1, -100, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
			if chat.unread > 0 then
				local b = new("TextLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromRGB(60, 200, 100), Text = tostring(chat.unread), TextColor3 = WHITE, TextSize = 12, Font = Enum.Font.GothamBold }, row)
				corner(b, 11)
			end
		end
		return
	end

	-- Переписка
	appTitle.Text = "💬  " .. openChat
	local chat = chatOf(openChat)
	for i, m in chat.messages do
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i }, content)
		local bubble = new("TextLabel", {
			AnchorPoint = Vector2.new(m.mine and 1 or 0, 0),
			Position = m.mine and UDim2.fromScale(1, 0) or UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = m.mine and Color3.fromRGB(60, 130, 255) or Color3.fromRGB(55, 58, 75),
			Text = m.text,
			TextColor3 = WHITE,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		new("UISizeConstraint", { MaxSize = Vector2.new(190, math.huge) }, bubble)
		corner(bubble, 14)
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, bubble)
	end
	if os.clock() < chat.typingUntil then
		text(content, "  " .. openChat .. " печатает…", 13, Color3.fromRGB(160, 170, 195), false, { LayoutOrder = #chat.messages + 1 })
	end
	text(content, "Ответить:", 13, Color3.fromRGB(160, 170, 195), true, { LayoutOrder = 1000 })
	local replies = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1001 }, content)
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 34), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }, replies)
	for i, r in NPCConfig.Phone.Replies do
		button(replies, r.Text, { LayoutOrder = i, TextSize = 13, BackgroundColor3 = Color3.fromRGB(60, 130, 255), BackgroundTransparency = 0.3 }, function()
			table.insert(chat.messages, { mine = true, text = r.Text })
			if soundsOn then
				playSound(Sounds.Phone and Sounds.Phone.Send)
			end
			remote:FireServer("Reply", openChat, i)
			renderApp()
		end)
	end
	task.defer(function()
		content.CanvasPosition = Vector2.new(0, math.max(0, content.AbsoluteCanvasSize.Y - content.AbsoluteSize.Y))
	end)
end

local function bar(parent: Instance, label: string, value: number, color: Color3, order: number)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order }, parent)
	text(row, label, 13, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 16) })
	local back = new("Frame", { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Color3.fromRGB(60, 65, 80) }, row)
	corner(back, 4)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color }, back)
	corner(fill, 4)
	TweenService:Create(fill, SLIDE, { Size = UDim2.fromScale(math.clamp(value, 0, 1), 1) }):Play()
end

local function renderWeather()
	list(content, 10)
	local key = workspace:GetAttribute("Weather") or "Clear"
	local top = card(content, 150, 0)
	text(top, workspace:GetAttribute("WeatherIcon") or "☀️", 64, WHITE, true, { Size = UDim2.new(1, 0, 0, 76), TextXAlignment = Enum.TextXAlignment.Center })
	text(top, workspace:GetAttribute("WeatherName") or "", 22, WHITE, true, { Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	local t, d = clockText()
	text(top, t .. " · " .. d, 13, Color3.fromRGB(200, 210, 230), false, { Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	local details = card(content, nil, 1)
	list(details, 6)
	bar(details, "🌧 Дождь", workspace:GetAttribute("Rain") or 0, Color3.fromRGB(90, 160, 255), 1)
	bar(details, "☁️ Облачность", workspace:GetAttribute("Clouds") or 0, Color3.fromRGB(190, 195, 210), 2)
	bar(details, "🌫 Туман", workspace:GetAttribute("Fog") or 0, Color3.fromRGB(170, 175, 190), 3)
	local tips = {
		Clear = "Отличный день для прогулки! 😎",
		Cloudy = "Пасмурно, но без дождя.",
		Rain = "Возьми зонт ☂️ — жители прячутся по домам.",
		Storm = "Гроза! Лучше переждать под крышей ⚡",
		Fog = "Туман: на дорогах осторожнее 🚗",
	}
	local tip = card(content, nil, 2)
	text(tip, "💡 " .. (tips[key] or ""), 14, WHITE, false, { Size = UDim2.new(1, 0, 0, 40) })
end

local function renderQuests()
	list(content, 10)
	local quest = player:GetAttribute("QuestText")
	local q = card(content, nil, 0)
	list(q, 6)
	text(q, "Текущее задание", 15, WHITE, true)
	text(q, (type(quest) == "string" and quest ~= "") and ("❗ " .. quest) or "Нет активных заданий. Ищи жителей с ❗ над головой!", 14, Color3.fromRGB(220, 225, 240), false, { Size = UDim2.new(1, 0, 0, 40) })
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild(NPCConfig.CurrencyName)
	local c = card(content, nil, 1)
	list(c, 4)
	text(c, "🪙 " .. (coins and tostring(coins.Value) or "0") .. " " .. NPCConfig.CurrencyName, 20, Color3.fromRGB(255, 215, 90), true)
	text(c, "👥 Знакомых жителей: " .. #data.friends, 14, Color3.fromRGB(200, 210, 230), false)
	if #data.friends > 0 then
		local f = card(content, nil, 2)
		list(f, 4)
		text(f, "Друзья", 15, WHITE, true)
		for i, friend in data.friends do
			if i > 8 then
				break
			end
			text(f, string.format("%s — %s %s", friend.name, friend.level, friend.icon), 13, Color3.fromRGB(210, 215, 235), false)
		end
	end
end

local function toggleRow(parent: Instance, label: string, value: boolean, order: number, onChange)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order }, parent)
	text(row, label, 15, WHITE, false, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, -60, 0, 20) })
	local sw = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(48, 28), BackgroundColor3 = value and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(80, 85, 100), Text = "", AutoButtonColor = false }, row)
	corner(sw, 14)
	local knob = new("Frame", { Position = value and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = WHITE }, sw)
	corner(knob, 12)
	local state = value
	sw.Activated:Connect(function()
		state = not state
		tap()
		TweenService:Create(knob, FAST, { Position = state and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2) }):Play()
		TweenService:Create(sw, FAST, { BackgroundColor3 = state and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(80, 85, 100) }):Play()
		onChange(state)
	end)
end

local function renderSettings()
	list(content, 10)
	local c = card(content, nil, 0)
	list(c, 4)
	local clock = player.PlayerGui:FindFirstChild("ClockHud")
	toggleRow(c, "🕗 Часы на экране", clock == nil or clock.Enabled, 1, function(v)
		local hud = player.PlayerGui:FindFirstChild("ClockHud")
		if hud then
			hud.Enabled = v
		end
	end)
	toggleRow(c, "🌧 Капли дождя", player:GetAttribute("RainEffects") ~= false, 2, function(v)
		player:SetAttribute("RainEffects", v)
	end)
	toggleRow(c, "🔔 Звуки телефона", soundsOn, 3, function(v)
		soundsOn = v
	end)
	local w = card(content, nil, 1)
	list(w, 8)
	text(w, "🖼 Обои", 15, WHITE, true)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70) }, w)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }, row)
	for i, colors in WALLPAPERS do
		local sw = new("TextButton", { Size = UDim2.fromOffset(48, 70), BackgroundColor3 = WHITE, Text = i == wallpaperIndex and "✓" or "", TextColor3 = WHITE, TextSize = 20, Font = Enum.Font.GothamBold, AutoButtonColor = false }, row)
		corner(sw, 10)
		new("UIGradient", { Color = ColorSequence.new(colors[1], colors[2]), Rotation = 120 }, sw)
		if i == wallpaperIndex then
			new("UIStroke", { Color = WHITE, Thickness = 2 }, sw)
		end
		sw.Activated:Connect(function()
			wallpaperIndex = i
			tap()
			applyWallpaper()
			renderApp()
		end)
	end
end

---------------------------------------------------------------------
-- 📦 Работа, 🛍 Магазин, 🏆 Награды
---------------------------------------------------------------------

local function coinsText(): string
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild(NPCConfig.CurrencyName)
	return coins and tostring(coins.Value) or "0"
end

local function renderWork()
	list(content, 10)
	local stage = player:GetAttribute("JobStage")
	local top = card(content, nil, 0)
	list(top, 6)
	text(top, "📦 Курьер города", 17, WHITE, true)
	if not stage then
		text(top, "Забери посылку и отнеси её жителю. Получатель подсвечен, к нему ведёт золотой луч.", 13, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 52) })
		text(top, string.format("Награда: %d–%d 🪙, за %d с — ещё +%d ⚡", CityConfig.Job.Reward.Min, CityConfig.Job.Reward.Max, CityConfig.Job.FastTime, CityConfig.Job.FastBonus), 13, Color3.fromRGB(255, 220, 120), false, { Size = UDim2.new(1, 0, 0, 36) })
		button(content, "Взять заказ", { LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(60, 200, 100), BackgroundTransparency = 0.2, Font = Enum.Font.GothamBold }, function()
			remote:FireServer("Job")
		end)
	else
		text(top, player:GetAttribute("JobText") or "", 15, WHITE, true, { Size = UDim2.new(1, 0, 0, 40) })
		local ends = player:GetAttribute("JobEnds")
		local left = ends and math.max(0, ends - workspace:GetServerTimeNow()) or 0
		statusChip(top, string.format("⏱ %d:%02d", math.floor(left / 60), math.floor(left % 60)), left < 30 and Color3.fromRGB(255, 100, 90) or Color3.fromRGB(255, 190, 60))
		text(top, stage == "pickup" and "Шаг 1 из 2: забери посылку (кнопка у коробки)" or "Шаг 2 из 2: подойди к получателю", 13, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 34) })
		button(content, "Отменить заказ", { LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(240, 80, 80), BackgroundTransparency = 0.4 }, function()
			remote:FireServer("Job")
		end)
	end
	local stats = card(content, nil, 2)
	list(stats, 4)
	text(stats, "📊 Статистика", 15, WHITE, true)
	text(stats, "Доставлено посылок: " .. math.floor(city.stats.Delivery or 0), 14, Color3.fromRGB(210, 215, 235), false)
	text(stats, "🪙 " .. coinsText() .. " " .. NPCConfig.CurrencyName, 14, Color3.fromRGB(255, 215, 90), true)
end

local function contains(list: { string }, value: string): boolean
	for _, v in list do
		if v == value then
			return true
		end
	end
	return false
end

local function renderShop()
	list(content, 10)
	local top = card(content, nil, 0)
	text(top, "🪙 " .. coinsText() .. " " .. NPCConfig.CurrencyName, 20, Color3.fromRGB(255, 215, 90), true)
	local g = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 }, content)
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 132), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, g)
	for i, item in CityConfig.Shop do
		local owned = contains(city.owned, item.Id)
		local worn = contains(city.equipped, item.Id)
		local cell = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = worn and 0.75 or 0.88, LayoutOrder = i }, g)
		corner(cell, 14)
		if worn then
			new("UIStroke", { Color = Color3.fromRGB(120, 230, 140), Thickness = 2 }, cell)
		end
		text(cell, item.Icon, 34, WHITE, true, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
		text(cell, item.Name, 13, WHITE, true, { Position = UDim2.fromOffset(4, 52), Size = UDim2.new(1, -8, 0, 32), TextXAlignment = Enum.TextXAlignment.Center })
		local label = worn and "Снять" or owned and "Надеть" or (item.Price .. " 🪙")
		local color = worn and Color3.fromRGB(240, 90, 90) or owned and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(255, 190, 50)
		button(cell, label, { Position = UDim2.new(0, 8, 1, -40), Size = UDim2.new(1, -16, 0, 32), BackgroundColor3 = color, BackgroundTransparency = 0.25, TextSize = 13, Font = Enum.Font.GothamBold }, function()
			remote:FireServer(owned and "Equip" or "Buy", item.Id)
		end)
	end
	text(content, "Вещи остаются у тебя навсегда. В одном месте (голова, лицо...) — одна вещь.", 12, Color3.fromRGB(160, 170, 195), false, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 34) })

	-- 🔫 Оружие (WeaponServer)
	local weaponConfig = ReplicatedStorage:FindFirstChild("WeaponConfig")
	if weaponConfig and require(weaponConfig).Enabled then
		local WC = require(weaponConfig)
		local wcard = card(content, nil, 3)
		list(wcard, 6)
		text(wcard, "🔫 Оружие (18+)", 16, WHITE, true)
		if weaponState.blocked then
			text(wcard, "🚫 Недоступно, пока ты под арестом", 13, Color3.fromRGB(255, 120, 120), false)
		end
		for i, id in { "Pistol", "Rifle" } do
			local def = WC.Weapons[id]
			if def then
				local owned = weaponState.owned[id] == true
				local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 10 + i }, wcard)
				text(row, string.format("%s %s%s", def.Icon, def.Name, owned and ("  · " .. tostring(weaponState.ammo[id] or 0) .. " патр.") or ""), 14, WHITE, true, { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, -110, 0, 20) })
				text(row, string.format("Урон %d · магазин %d · %s", def.Damage, def.Magazine, table.concat(def.Modes, "/")), 11, Color3.fromRGB(170, 180, 205), false, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -110, 0, 16) })
				button(row, owned and ("+" .. def.Magazine .. " · " .. def.AmmoPrice .. " 🪙") or (def.Price .. " 🪙"), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(104, 32), TextSize = 12, BackgroundColor3 = owned and Color3.fromRGB(90, 150, 255) or Color3.fromRGB(255, 190, 50), BackgroundTransparency = 0.25, Font = Enum.Font.GothamBold }, function()
					remote:FireServer(owned and "AmmoBuy" or "WeaponBuy", id)
				end)
			end
		end
	end
end

local function renderAwards()
	list(content, 8)
	local doneCount = 0
	for _, a in CityConfig.Achievements do
		if contains(city.done, a.Id) then
			doneCount += 1
		end
	end
	local top = card(content, nil, 0)
	list(top, 6)
	text(top, string.format("🏆 Получено: %d из %d", doneCount, #CityConfig.Achievements), 17, WHITE, true)
	bar(top, "", doneCount / math.max(1, #CityConfig.Achievements), Color3.fromRGB(255, 200, 60), 2)
	-- Сначала незавершённые, ближайшие к цели
	local order = {}
	for i, a in CityConfig.Achievements do
		local done = contains(city.done, a.Id)
		local progress = math.clamp((city.stats[a.Stat] or 0) / a.Goal, 0, 1)
		table.insert(order, { a = a, done = done, progress = progress, i = i })
	end
	table.sort(order, function(x, y)
		if x.done ~= y.done then
			return not x.done
		end
		if x.progress ~= y.progress then
			return x.progress > y.progress
		end
		return x.i < y.i
	end)
	for n, o in order do
		local a = o.a
		local row = card(content, 74, n)
		row.BackgroundTransparency = o.done and 0.8 or 0.9
		text(row, a.Icon, 30, WHITE, true, { Size = UDim2.fromOffset(40, 50), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = o.done and 0 or 0.35 })
		text(row, a.Name .. (o.done and "  ✓" or ""), 14, o.done and Color3.fromRGB(255, 215, 90) or WHITE, true, { Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -100, 0, 18) })
		text(row, a.Desc, 12, Color3.fromRGB(180, 190, 215), false, { Position = UDim2.fromOffset(48, 18), Size = UDim2.new(1, -48, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		text(row, "+" .. a.Reward .. " 🪙", 12, Color3.fromRGB(255, 215, 90), true, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(60, 18), TextXAlignment = Enum.TextXAlignment.Right })
		if not o.done then
			local back = new("Frame", { Position = UDim2.fromOffset(48, 40), Size = UDim2.new(1, -48, 0, 6), BackgroundColor3 = Color3.fromRGB(60, 65, 80) }, row)
			corner(back, 3)
			local fill = new("Frame", { Size = UDim2.fromScale(o.progress, 1), BackgroundColor3 = Color3.fromRGB(255, 190, 60) }, back)
			corner(fill, 3)
		end
	end
end

local RENDERERS = {
	map = renderMap,
	taxi = renderTaxi,
	police = renderPolice,
	bus = renderBus,
	messages = renderMessages,
	weather = renderWeather,
	quests = renderQuests,
	settings = renderSettings,
	work = renderWork,
	shop = renderShop,
	awards = renderAwards,
}

function renderApp()
	if not currentApp then
		return
	end
	clearContent()
	map.frame = nil
	local r = RENDERERS[currentApp]
	if r then
		r()
	end
end

---------------------------------------------------------------------
-- Открыть / закрыть
---------------------------------------------------------------------

local function fitScale(): number
	local view = workspace.CurrentCamera.ViewportSize
	return math.min(1, (view.Y - 40) / H)
end

local function setLocked(value: boolean)
	locked = value
	if value then
		lockLayer.Visible = true
		lockLayer.Position = UDim2.fromScale(0, 0)
		homeLayer.Visible = false
		appLayer.Visible = false
		currentApp = nil
		renderLock()
	else
		homeLayer.Visible = true
		if soundsOn then
			playSound(Sounds.Phone and Sounds.Phone.Unlock)
		end
		local slide = TweenService:Create(lockLayer, SLIDE, { Position = UDim2.fromScale(0, -1) })
		slide:Play()
		slide.Completed:Once(function()
			if not locked then
				lockLayer.Visible = false
			end
		end)
		renderHomeBadges()
	end
end
lockLayer.Activated:Connect(function()
	tap()
	setLocked(false)
end)

local function openPhone()
	if isOpen then
		return
	end
	isOpen = true
	peek.Visible = false
	remote:FireServer("Open")
	setLocked(true)
	updateClock()
	phone.Visible = true
	phoneScale.Scale = fitScale()
	phone.Position = UDim2.new(1, W + 60, 0.5, 0)
	TweenService:Create(phone, SLIDE, { Position = UDim2.new(1, -24, 0.5, 0) }):Play()
end

function closePhone()
	if not isOpen then
		return
	end
	isOpen = false
	local slide = TweenService:Create(phone, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.new(1, W + 60, 0.5, 0) })
	slide:Play()
	slide.Completed:Once(function()
		if not isOpen then
			phone.Visible = false
		end
	end)
end

local function togglePhone()
	if isOpen then
		closePhone()
	else
		openPhone()
	end
end
toggle.Activated:Connect(togglePhone)
ContextActionService:BindAction("TogglePhone", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		togglePhone()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.P, Enum.KeyCode.ButtonSelect)

---------------------------------------------------------------------
-- Сообщения от сервера
---------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action, payload)
	if action == "Data" then
		for k, v in pairs(payload) do
			if k == "city" then
				city = v
			else
				data[k] = v
			end
		end
		renderHomeBadges()
		if currentApp and currentApp ~= "map" then
			renderApp()
		end
	elseif action == "Weapons" then
		weaponState = payload
		if currentApp == "shop" then
			renderApp()
		end
	elseif action == "City" then
		city = payload
		if currentApp == "shop" or currentApp == "awards" or currentApp == "work" then
			renderApp()
		end
	elseif action == "Job" then
		if payload.text then
			notify("📦", "Работа", payload.text)
		elseif payload.ready then
			notify("📦", "Работа", "Есть новые заказы!")
		end
		renderHomeBadges()
		if currentApp == "work" then
			renderApp()
		end
	elseif action == "Achievement" then
		notify(payload.icon, "Достижение", payload.name .. "  +" .. payload.reward .. " 🪙")
	elseif action == "Friends" then
		data.friends = payload
		if currentApp == "messages" or currentApp == "quests" then
			renderApp()
		end
	elseif action == "Tickets" then
		data.tickets = payload
		renderHomeBadges()
		if currentApp == "police" then
			renderApp()
		end
	elseif action == "PoliceAnswer" then
		policeAnswer = payload
		notify("🚔", "Полиция", payload)
		if currentApp == "police" then
			renderApp()
		end
	elseif action == "Taxi" then
		taxiStatus = payload
		notify("🚕", "Такси", payload.text)
		renderHomeBadges()
		if currentApp == "taxi" then
			renderApp()
		end
	elseif action == "Typing" then
		local chat = chatOf(payload)
		chat.typingUntil = os.clock() + 4
		if currentApp == "messages" then
			renderApp()
		end
	elseif action == "Message" then
		local chat = chatOf(payload.from)
		chat.typingUntil = 0
		table.insert(chat.messages, { mine = false, text = payload.text })
		if #chat.messages > 40 then
			table.remove(chat.messages, 1)
		end
		local viewing = isOpen and currentApp == "messages" and openChat == payload.from
		if not viewing then
			chat.unread += 1
			notify("💬", payload.from, payload.text)
		end
		updateBadges()
		if currentApp == "messages" then
			renderApp()
		end
	end
end)

---------------------------------------------------------------------
-- Живые обновления
---------------------------------------------------------------------

local clockTimer, slowTimer = 0, 0
DebugTimer.connect(RunService.RenderStepped, "PhoneClient", function(dt)
	if not isOpen then
		return
	end
	local now = os.clock()
	clockTimer -= dt
	if clockTimer <= 0 then
		clockTimer = 1
		updateClock()
	end
	if currentApp == "map" then
		updateMap(now)
	end
	slowTimer -= dt
	if slowTimer <= 0 then
		slowTimer = 1.5
		if currentApp == "bus" or currentApp == "weather" or currentApp == "work" then
			renderApp()
		end
	end
end)

workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	phoneScale.Scale = fitScale()
end)
