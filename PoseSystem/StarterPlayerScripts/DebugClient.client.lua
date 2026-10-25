-- LocalScript: StarterPlayer > StarterPlayerScripts > DebugClient
-- Меню отладки: F2 или кнопка 🛠 (только у админов, см. DebugConfig).
-- Вкладки:
--   📋 Новое     — что добавлено в каждом обновлении + проверки с кнопкой «▶» и отметками ✓ / 🐞
--   🌍 Мир       — время, ускорение, погода, вызов полиции, монеты, кулдауны, телепорт
--   🧑 Жители    — что делает каждый житель, куда идёт; следить камерой, телепорт
--   🚗 Машины    — тип, состояние, скорость, куда едет; следить, телепорт
--   🗺 Метки     — показать на карте дороги, точки, двери, парковки, пути жителей, маршруты машин
--   🖥 Output    — сообщения сервера и клиента, фильтры, копирование
--   ✅ Проверка  — автопроверка разметки карты и установки скриптов, проверка путей жителей
--   🩺 Диагностика — застревания, ошибки скриптов по группам, счётчики, кто тормозит
--   📜 История   — все обновления с датами и подробностями
-- F3 — свободная камера.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local LogService = game:GetService("LogService")
local ScriptContext = game:GetService("ScriptContext")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DebugConfig"))
if not Config.Enabled then
	return
end
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local WeatherConfig = require(ReplicatedStorage:WaitForChild("WeatherConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- Меню только для админов: сервер ставит атрибут DebugAdmin
if player:GetAttribute("DebugAdmin") ~= true then
	player:GetAttributeChangedSignal("DebugAdmin"):Wait()
end
local remote = ReplicatedStorage:WaitForChild("DebugRemote")

local W, H = 480, 560
local C = {
	bg = Color3.fromRGB(16, 18, 26),
	panel = Color3.fromRGB(26, 29, 40),
	panel2 = Color3.fromRGB(34, 38, 52),
	text = Color3.fromRGB(235, 238, 248),
	dim = Color3.fromRGB(150, 158, 185),
	accent = Color3.fromRGB(90, 150, 255),
	ok = Color3.fromRGB(80, 210, 120),
	warn = Color3.fromRGB(255, 190, 60),
	error = Color3.fromRGB(255, 85, 85),
	event = Color3.fromRGB(190, 140, 255),
	debug = Color3.fromRGB(110, 200, 255),
}

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
local function corner(p: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end
local function label(parent: Instance, text: string, size: number, color: Color3?, bold: boolean?, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color or C.text,
		Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end
local function btn(parent: Instance, text: string, props, onClick)
	local b = new("TextButton", {
		BackgroundColor3 = C.panel2,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
	}, parent)
	for k, v in pairs(props or {}) do
		(b :: any)[k] = v
	end
	corner(b, 8)
	if b.AutomaticSize == Enum.AutomaticSize.X then
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, b)
	end
	b.Activated:Connect(onClick)
	return b
end
local function vlist(parent: Instance, gap: number)
	return new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end
local function hflow(parent: Instance, order: number?)
	local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order or 0 }, parent)
	local layout = new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	pcall(function()
		layout.Wraps = true -- кнопки переносятся на новую строку
	end)
	return f
end
local function section(parent: Instance, title: string, order: number)
	local s = new("Frame", { BackgroundColor3 = C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, parent)
	corner(s, 10)
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, s)
	vlist(s, 6)
	label(s, title, 14, C.text, true, { LayoutOrder = 0 })
	return s
end

---------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "DebugMenu", ResetOnSpawn = false, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)

local toggle = new("TextButton", {
	Position = UDim2.new(0, 16, 0, 110),
	Size = UDim2.fromOffset(44, 44),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.1,
	Text = "🛠",
	TextSize = 22,
	Font = Enum.Font.GothamBold,
}, gui)
corner(toggle, 12)
new("UIStroke", { Color = C.accent, Thickness = 1.5, Transparency = 0.3 }, toggle)
local errBadge = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 0, 2), Size = UDim2.fromOffset(22, 18), BackgroundColor3 = C.error, TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = Enum.Font.GothamBold, Visible = false, ZIndex = 3 }, toggle)
corner(errBadge, 9)

local win = new("Frame", {
	Position = UDim2.new(0, 70, 0, 80),
	Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = C.bg,
	Visible = false,
}, gui)
corner(win, 14)
new("UIStroke", { Color = Color3.fromRGB(60, 70, 100), Thickness = 1.5 }, win)
local winScale = new("UIScale", {}, win)

local titleBar = new("TextButton", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, win)
label(titleBar, "🛠  Меню отладки", 15, C.text, true, { Position = UDim2.fromOffset(14, 9), Size = UDim2.new(1, -60, 0, 18), AutomaticSize = Enum.AutomaticSize.None })
btn(titleBar, "✕", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(28, 28), AutomaticSize = Enum.AutomaticSize.None, BackgroundTransparency = 1 }, function()
	win.Visible = false
end)

-- Перетаскивание за заголовок
do
	local dragging, start, startPos
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, start, startPos = true, input.Position, win.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - start
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local TABS = {
	{ id = "news", text = "📋 Проверки" },
	{ id = "history", text = "📜 История" },
	{ id = "world", text = "🌍 Мир" },
	{ id = "npcs", text = "🧑 Жители" },
	{ id = "cars", text = "🚗 Машины" },
	{ id = "overlay", text = "🗺 Метки" },
	{ id = "output", text = "🖥 Output" },
	{ id = "check", text = "✅ Проверка" },
	{ id = "diag", text = "🩺 Диагностика" },
}
local tabBar = new("ScrollingFrame", { Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, -16, 0, 32), BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X }, win)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)

local body = new("ScrollingFrame", {
	Position = UDim2.fromOffset(8, 76),
	Size = UDim2.new(1, -16, 1, -112),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, win)

local footer = label(win, "", 11, C.dim, false, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -8), Size = UDim2.new(1, -24, 0, 26), AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Center })
local resultToast = label(win, "", 12, C.debug, true, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -34), Size = UDim2.new(1, -24, 0, 0), Visible = false })

---------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------

local currentTab = "news"
local logs = {} -- { t, kind, text, src }
local tested = {}
local placeNames = {}
local snapshot = { npcs = {}, cars = {}, perf = {} }
local checks = nil
local unseenErrors = 0
local outputFilter, outputPaused, outputSearch = "all", false, ""
local followTarget = nil
local overlays = {} -- [слой] = true
local npcSearch = ""
local selectedNPC = nil -- житель, чей журнал открыт
local journal = {}
local historyVersion = nil -- открытая страница истории
local diag = nil -- данные диагностики сервера
local pathState = nil -- проверка путей: { done, total, bad }
local clientErrors, clientErrorOrder = {}, {}
local clientTimings = {}
local diagCopy = false
local freeCam -- объявлена ниже
overlays.Stuck = true -- застрявшие подсвечены всегда
local render -- объявлена ниже

local function addLog(entry)
	table.insert(logs, entry)
	if #logs > Config.LogLimit then
		table.remove(logs, 1)
	end
	if entry.kind == "error" and not (win.Visible and currentTab == "output") then
		unseenErrors += 1
	end
end

local function updateBadge()
	errBadge.Visible = unseenErrors > 0
	errBadge.Text = tostring(math.min(unseenErrors, 99))
end

-- Output клиента
local CLIENT_KIND = {
	[Enum.MessageType.MessageOutput] = "info",
	[Enum.MessageType.MessageInfo] = "info",
	[Enum.MessageType.MessageWarning] = "warn",
	[Enum.MessageType.MessageError] = "error",
}
for _, m in LogService:GetLogHistory() do
	addLog({ t = workspace:GetServerTimeNow(), kind = CLIENT_KIND[m.messageType] or "info", text = m.message, src = "C" })
end
local outputDirty = false
LogService.MessageOut:Connect(function(message, messageType)
	addLog({ t = workspace:GetServerTimeNow(), kind = CLIENT_KIND[messageType] or "info", text = message, src = "C" })
	outputDirty = true
	updateBadge()
end)

ScriptContext.Error:Connect(function(message, stack, source)
	local g = clientErrors[message]
	local now = workspace:GetServerTimeNow()
	if not g then
		g = { message = message, script = source and source:GetFullName() or "?", line = tonumber(string.match(message, ":(%d+):")) or 0, stack = stack, count = 0, first = now, last = now, src = "C" }
		clientErrors[message] = g
		table.insert(clientErrorOrder, message)
		if #clientErrorOrder > 40 then
			clientErrors[table.remove(clientErrorOrder, 1)] = nil
		end
	end
	g.count += 1
	g.last = now
end)

-- Секундомер скриптов клиента: раз в секунду
task.spawn(function()
	while true do
		local start = os.clock()
		task.wait(1)
		clientTimings = Config.takeTimings(os.clock() - start)
	end
end)

local function showResult(text: string)
	resultToast.Text = "→ " .. text
	resultToast.Visible = true
	local token = os.clock()
	resultToast:SetAttribute("Token", token)
	task.delay(3, function()
		if resultToast:GetAttribute("Token") == token then
			resultToast.Visible = false
		end
	end)
end

local function action(name: string, arg: any)
	remote:FireServer("Action", name, arg)
end

---------------------------------------------------------------------
-- 🗺 Слои меток на карте (видны только тебе)
---------------------------------------------------------------------

local overlayRoot = new("Folder", { Name = "DebugOverlay" }, camera)
local layerFolders = {}
local LAYERS = {
	{ id = "Roads", name = "🛣 Дороги: точки, связи, имена", color = Color3.fromRGB(255, 220, 60) },
	{ id = "Points", name = "📍 Точки жителей (Activity / Zone)", color = Color3.fromRGB(80, 210, 255) },
	{ id = "Spawns", name = "🐣 Точки появления", color = Color3.fromRGB(120, 255, 120) },
	{ id = "Doors", name = "🚪 Двери", color = Color3.fromRGB(255, 150, 60) },
	{ id = "Parking", name = "🅿️ Парковки", color = Color3.fromRGB(110, 140, 255) },
	{ id = "BusStops", name = "🚏 Остановки", color = Color3.fromRGB(255, 120, 200) },
	{ id = "Police", name = "🚔 Участок и вызовы", color = Color3.fromRGB(60, 120, 255) },
	{ id = "Places", name = "📌 Места (Places)", color = Color3.fromRGB(255, 255, 255) },
	{ id = "PathZones", name = "🚸 Переходы и проезжая часть (куда жителям нельзя)", color = Color3.fromRGB(255, 120, 60) },
	{ id = "NPCPaths", name = "🧭 Пути жителей (живые)", color = Color3.fromRGB(80, 255, 200) },
	{ id = "CarRoutes", name = "🚗 Маршруты машин (живые)", color = Color3.fromRGB(255, 90, 90) },
	{ id = "NPCLabels", name = "🏷 Ярлыки над жителями (живые)", color = Color3.fromRGB(255, 255, 255) },
	{ id = "Stuck", name = "🚨 Застрявшие жители и машины (живые)", color = Color3.fromRGB(255, 60, 60) },
	{ id = "PathBad", name = "❌ Недоступные точки (проверка путей)", color = Color3.fromRGB(255, 40, 40) },
}
local LAYER_COLOR = {}
for _, l in LAYERS do
	LAYER_COLOR[l.id] = l.color
end

local function layerFolder(id: string): Folder
	local f = layerFolders[id]
	if not f then
		f = new("Folder", { Name = id }, overlayRoot)
		layerFolders[id] = f
	end
	return f
end

local function line(parent: Instance, a: Vector3, b: Vector3, color: Color3, width: number?)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return
	end
	new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.25,
		Size = Vector3.new(width or 0.2, width or 0.2, len),
		CFrame = CFrame.lookAt((a + b) / 2, b),
	}, parent)
end

local function tag(parent: Instance, adornee: Instance?, position: Vector3?, text: string, color: Color3, offset: number?)
	local holder = adornee
	if not holder then
		holder = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1), Position = position }, parent)
	end
	local bb = new("BillboardGui", { Adornee = holder, Size = UDim2.fromOffset(220, 40), StudsOffset = Vector3.new(0, offset or 2, 0), AlwaysOnTop = true, MaxDistance = 180, LightInfluence = 0 }, parent)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextWrapped = true,
	}, bb)
	return bb
end

local function markPart(parent: Instance, part: BasePart, color: Color3, text: string?)
	new("BoxHandleAdornment", { Adornee = part, Size = part.Size + Vector3.new(0.05, 0.05, 0.05), Color3 = color, Transparency = 0.45, AlwaysOnTop = true, ZIndex = 1 }, parent)
	-- Стрелка «передняя грань»
	line(parent, part.Position, part.Position + part.CFrame.LookVector * math.max(2, part.Size.Z / 2 + 1), color, 0.15)
	if text then
		tag(parent, part, nil, text, color, 1.5)
	end
end

local function partsIn(folder: Instance?): { BasePart }
	local out = {}
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	return out
end

local function attrText(p: Instance, keys: { string }): string
	local bits = { p.Name }
	for _, k in keys do
		local v = p:GetAttribute(k)
		if v ~= nil then
			table.insert(bits, k .. "=" .. tostring(v))
		end
	end
	return table.concat(bits, "  ")
end

local function buildStatic(id: string)
	local f = layerFolder(id)
	f:ClearAllChildren()
	local npcRoot = workspace:FindFirstChild(NPCConfig.FolderName)
	local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local color = LAYER_COLOR[id]
	if id == "Roads" then
		remote:FireServer("Nodes")
		return -- рисуем, когда придёт граф
	elseif id == "Points" and npcRoot then
		for _, p in partsIn(npcRoot:FindFirstChild("Points")) do
			markPart(f, p, color, p:IsA("Seat") and ("🪑 " .. tostring(p:GetAttribute("Zone"))) or attrText(p, { "Activity", "Zone", "Role", "Route", "Order" }))
		end
	elseif id == "Spawns" and npcRoot then
		for _, p in partsIn(npcRoot:FindFirstChild("Spawns")) do
			markPart(f, p, color, attrText(p, { "Count", "Zone" }))
		end
	elseif id == "Doors" and npcRoot then
		local doors = npcRoot:FindFirstChild("Doors")
		for _, d in doors and doors:GetChildren() or {} do
			local part = d:IsA("BasePart") and d or (d:IsA("Model") and (d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")))
			if part then
				markPart(f, part, color, attrText(d, { "Hinge", "Locked" }))
			end
		end
	elseif id == "Parking" and map then
		for _, p in partsIn(map:FindFirstChild("Parking")) do
			markPart(f, p, color, attrText(p, { "Type", "Zone" }))
		end
	elseif id == "BusStops" and map then
		for _, p in partsIn(map:FindFirstChild("BusStops")) do
			markPart(f, p, color, attrText(p, { "Order", "StopName", "Node" }))
		end
	elseif id == "Police" and map then
		for _, p in partsIn(map:FindFirstChild("PoliceStation")) do
			markPart(f, p, color, "🚔 " .. p.Name)
		end
		for _, p in partsIn(map:FindFirstChild("PoliceCalls")) do
			markPart(f, p, Color3.fromRGB(150, 180, 255), attrText(p, { "Zone" }))
		end
	elseif id == "PathZones" and map then
		local zones = map:FindFirstChild("NPCPathZones")
		for _, p in zones and zones:GetChildren() or {} do
			if p:IsA("BasePart") and p.Name == "Road" then
				new("BoxHandleAdornment", { Adornee = p, Size = p.Size, Color3 = color, Transparency = 0.8, AlwaysOnTop = false, ZIndex = 0 }, f)
			elseif p:IsA("BasePart") and p.Name == "Crosswalk" then
				new("BoxHandleAdornment", { Adornee = p, Size = p.Size, Color3 = Color3.new(1, 1, 1), Transparency = 0.5, AlwaysOnTop = true, ZIndex = 1 }, f)
				tag(f, p, nil, "🚸 переход", Color3.new(1, 1, 1), 1)
			end
		end
	elseif id == "Places" and map then
		for _, p in partsIn(map:FindFirstChild("Places")) do
			markPart(f, p, color, "📌 " .. tostring(p:GetAttribute("PlaceName") or p.Name))
		end
	end
end

local function drawRoads(nodes)
	local f = layerFolder("Roads")
	f:ClearAllChildren()
	local color = LAYER_COLOR.Roads
	for name, n in pairs(nodes) do
		local holder = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = n.pos + Vector3.new(0, 0.6, 0), Material = Enum.Material.Neon, Color = #n.links == 0 and C.error or color }, f)
		tag(f, holder, nil, name .. (#n.links <= 1 and "  (тупик)" or ""), #n.links == 0 and C.error or color, 1.6)
		for _, other in n.links do
			local o = nodes[other]
			if o then
				local a, b = n.pos + Vector3.new(0, 0.6, 0), o.pos + Vector3.new(0, 0.6, 0)
				line(f, a, b, color, 0.18)
				-- Стрелка направления в середине связи
				local mid = a:Lerp(b, 0.6)
				local dir = (b - a).Unit
				local side = dir:Cross(Vector3.yAxis)
				line(f, mid, mid - dir * 1.2 + side * 0.6, color, 0.14)
				line(f, mid, mid - dir * 1.2 - side * 0.6, color, 0.14)
			end
		end
	end
end

local function drawPathBad()
	local f = layerFolder("PathBad")
	f:ClearAllChildren()
	if not overlays.PathBad or not pathState then
		return
	end
	for _, b in pathState.bad or {} do
		if b.part and b.part.Parent then
			markPart(f, b.part, LAYER_COLOR.PathBad, "❌ не дойти: " .. tostring(b.activity) .. " (" .. tostring(b.zone) .. ")")
		end
		new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = b.pos + Vector3.new(0, 3, 0), Material = Enum.Material.Neon, Color = LAYER_COLOR.PathBad }, f)
	end
end

local function drawDynamic()
	if overlays.Stuck then
		local f = layerFolder("Stuck")
		f:ClearAllChildren()
		for _, n in snapshot.npcs or {} do
			if n.stuck and n.model and n.model:FindFirstChild("Head") then
				new("Highlight", { Adornee = n.model, FillColor = LAYER_COLOR.Stuck, OutlineColor = LAYER_COLOR.Stuck, FillTransparency = 0.6, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }, f)
				tag(f, n.model.Head, nil, "🚨 ЗАСТРЯЛ: " .. n.name, LAYER_COLOR.Stuck, 4.5)
			end
		end
		for _, c in snapshot.cars or {} do
			if c.stuck and c.model and c.model.PrimaryPart then
				new("Highlight", { Adornee = c.model, FillColor = LAYER_COLOR.Stuck, OutlineColor = LAYER_COLOR.Stuck, FillTransparency = 0.6, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }, f)
				tag(f, c.model.PrimaryPart, nil, "🚨 ЗАСТРЯЛА: " .. tostring(c.kind) .. " #" .. c.id, LAYER_COLOR.Stuck, 5)
			end
		end
	end
	if overlays.NPCPaths then
		local f = layerFolder("NPCPaths")
		f:ClearAllChildren()
		for _, n in snapshot.npcs do
			if n.goal then
				line(f, n.pos, n.goal, LAYER_COLOR.NPCPaths, 0.12)
				new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), Position = n.goal, Material = Enum.Material.Neon, Color = LAYER_COLOR.NPCPaths }, f)
			end
		end
	end
	if overlays.CarRoutes then
		local f = layerFolder("CarRoutes")
		f:ClearAllChildren()
		for _, car in snapshot.cars do
			local prev = car.pos
			for _, p in car.route or {} do
				line(f, prev + Vector3.new(0, 1, 0), p + Vector3.new(0, 1, 0), LAYER_COLOR.CarRoutes, 0.16)
				prev = p
			end
		end
	end
	if overlays.NPCLabels then
		local f = layerFolder("NPCLabels")
		f:ClearAllChildren()
		for _, n in snapshot.npcs do
			if n.model and n.model.Parent then
				local head = n.model:FindFirstChild("Head")
				if head then
					tag(f, head, nil, n.name .. "\n" .. n.action, n.officer and Color3.fromRGB(150, 180, 255) or Color3.new(1, 1, 1), 3.4)
				end
			end
		end
		for _, car in snapshot.cars do
			if car.model and car.model.Parent then
				tag(f, car.model.PrimaryPart, nil, string.format("%s · %s · %s → %s", car.kind, car.state, tostring(car.speed), tostring(car.to or "—")), LAYER_COLOR.CarRoutes, 4)
			end
		end
	end
end

local function setOverlay(id: string, on: boolean)
	overlays[id] = on or nil
	if on then
		if id == "PathBad" then
			drawPathBad()
		elseif id == "NPCPaths" or id == "CarRoutes" or id == "NPCLabels" or id == "Stuck" then
			remote:FireServer("Snapshot")
		else
			buildStatic(id)
		end
	elseif layerFolders[id] then
		layerFolders[id]:ClearAllChildren()
	end
end

---------------------------------------------------------------------
-- Слежение камерой
---------------------------------------------------------------------

local followBar = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(320, 36), BackgroundColor3 = C.bg, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 14, Visible = false }, gui)
corner(followBar, 12)
new("UIStroke", { Color = C.accent, Thickness = 1.5 }, followBar)

local function stopFollow()
	followTarget = nil
	followBar.Visible = false
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end
followBar.Activated:Connect(stopFollow)

local function follow(model: Instance?, name: string)
	if not model or not model.Parent then
		return
	end
	local subject = model:FindFirstChildOfClass("Humanoid") or (model:IsA("Model") and model.PrimaryPart) or model
	camera.CameraSubject = subject
	followTarget = model
	followBar.Text = "👁 Слежу за: " .. name .. "   (нажми, чтобы вернуться)"
	followBar.Visible = true
end

---------------------------------------------------------------------
-- Вкладки
---------------------------------------------------------------------

local function clearBody()
	for _, c in body:GetChildren() do
		c:Destroy()
	end
	vlist(body, 8)
end

local function testKey(entry, i: number): string
	return entry.Version .. "#" .. i
end

local function renderNews()
	local total, done, bugs = 0, 0, 0
	for _, e in Config.Changelog do
		for i in e.Tests or {} do
			total += 1
			local s = tested[testKey(e, i)]
			if s == "ok" then
				done += 1
			elseif s == "bug" then
				bugs += 1
			end
		end
	end
	local top = section(body, string.format("Проверено %d из %d   🐞 багов: %d", done, total, bugs), 0)
	label(top, "▶ — подготовить проверку (время, погода, телепорт...). ✓ — работает, 🐞 — баг. Отметки сохраняются.", 12, C.dim, false, { LayoutOrder = 1 })
	for order, e in Config.Changelog do
		local s = section(body, "v" .. e.Version .. " — " .. e.Title, order)
		label(s, (e.Date and (e.Date .. " · ") or "") .. (e.Summary or ""), 12, C.dim, false, { LayoutOrder = 1 })
		for i, t in e.Tests or {} do
			local key = testKey(e, i)
			local state = tested[key]
			local row = new("Frame", { BackgroundColor3 = state == "ok" and Color3.fromRGB(28, 56, 38) or state == "bug" and Color3.fromRGB(64, 28, 30) or C.panel2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 10 + i }, s)
			corner(row, 8)
			new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 104) }, row)
			label(row, t.Text, 12, C.text, false)
			local buttons = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 100, 0.5, 0), Size = UDim2.fromOffset(96, 26), BackgroundTransparency = 1 }, row)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Right }, buttons)
			if t.Action then
				btn(buttons, "▶", { Size = UDim2.fromOffset(28, 26), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = C.accent }, function()
					if t.Action == "Overlay" then
						setOverlay(t.Arg, true)
						showResult("Слой включён: " .. tostring(t.Arg))
					elseif t.Action == "Tab" then
						currentTab = t.Arg
						render()
					elseif t.Action == "PathCheck" then
						remote:FireServer("PathCheck")
						pathState = { done = 0, total = 0, bad = {}, running = true }
						currentTab = "check"
						render()
					elseif t.Action == "FreeCam" then
						freeCam(true)
					else
						action(t.Action, t.Arg)
					end
				end)
			end
			for _, mark in { { "ok", "✓", C.ok }, { "bug", "🐞", C.error } } do
				btn(buttons, mark[2], { Size = UDim2.fromOffset(28, 26), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = state == mark[1] and mark[3] or C.panel }, function()
					local value = tested[key] ~= mark[1] and mark[1] or nil
					tested[key] = value
					remote:FireServer("Tested", key, value)
					render()
				end)
			end
		end
	end
end

local function renderWorld()
	local p = snapshot.perf or {}
	local time = section(body, string.format("🕗 Время: %s  %s  (день %s, ×%s)", tostring(p.hour or "?"), tostring(p.period or ""), tostring(p.day or "?"), tostring(p.timeScale or 1)), 1)
	local hours = hflow(time, 1)
	for _, h in { { 3, "3:00" }, { 7, "7:00" }, { 9.5, "9:30" }, { 13.5, "13:30" }, { 16, "16:00" }, { 19, "19:00" }, { 22, "22:00" } } do
		btn(hours, h[2], {}, function()
			action("SetHour", h[1])
		end)
	end
	local speed = hflow(time, 2)
	for _, x in { 0, 1, 5, 20, 60 } do
		btn(speed, x == 0 and "⏸ Пауза" or ("×" .. x), { BackgroundColor3 = (p.timeScale or 1) == x and C.accent or C.panel2 }, function()
			action("TimeScale", x)
		end)
	end

	local weather = section(body, "🌦 Погода: " .. tostring(p.weather or "?"), 2)
	local wf = hflow(weather, 1)
	for key, t in pairs(WeatherConfig.Types) do
		btn(wf, t.Icon .. " " .. t.Name, {}, function()
			action("Weather", key)
		end)
	end

	local police = section(body, "🚔 Вызов полиции (место — ближайшее к тебе)", 3)
	local pf = hflow(police, 1)
	for i, t in VehicleConfig.PoliceCallTypes do
		btn(pf, t.Icon .. " " .. t.Name, {}, function()
			action("PoliceCall", i)
		end)
	end

	local me = section(body, "🙋 Игрок", 4)
	local mf = hflow(me, 1)
	btn(mf, "+100 🪙", {}, function()
		action("Coins", 100)
	end)
	btn(mf, "⏱ Сбросить кулдауны", {}, function()
		action("ResetCooldowns")
	end)
	btn(mf, "❤️ Вылечить", {}, function()
		action("Heal")
	end)
	btn(mf, "📦 Заказ курьера", {}, function()
		action("StartJob")
	end)
	btn(mf, "🗑 Сбросить прогресс", { BackgroundColor3 = Color3.fromRGB(90, 40, 40) }, function()
		action("ResetCity")
	end)

	local cam = section(body, "🎥 Камера", 6)
	local cf = hflow(cam, 1)
	btn(cf, "🎥 Свободная камера (F3)", { BackgroundColor3 = C.accent }, function()
		freeCam(true)
	end)
	label(cam, "WASD — лететь, Пробел / Ctrl — вверх / вниз, Shift — быстрее, правая кнопка мыши — обзор, колесо — скорость.", 11, C.dim, false, { LayoutOrder = 2 })

	local tp = section(body, "📍 Телепорт", 5)
	local tf = hflow(tp, 1)
	btn(tf, "👮 Дежурный", {}, function()
		action("Teleport", "Desk")
	end)
	btn(tf, "🔒 Камера", {}, function()
		action("Teleport", "Cell")
	end)
	btn(tf, "🚏 Остановка 1", {}, function()
		action("Teleport", "Stop:1")
	end)
	for _, name in placeNames do
		btn(tf, "📌 " .. name, {}, function()
			action("Teleport", "Place:" .. name)
		end)
	end
end

local function renderNPCs()
	local list = snapshot.npcs or {}
	local top = section(body, string.format("🧑 Жителей: %d", #list), 0)
	local box = new("TextBox", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.panel2, TextColor3 = C.text, PlaceholderText = "🔍 Поиск по имени, зоне, действию…", PlaceholderColor3 = C.dim, Text = npcSearch, Font = Enum.Font.GothamMedium, TextSize = 13, ClearTextOnFocus = false, LayoutOrder = 1 }, top)
	corner(box, 8)
	box.FocusLost:Connect(function()
		npcSearch = box.Text
		render()
	end)
	if selectedNPC then
		local sel = nil
		for _, n in list do
			if n.model == selectedNPC then
				sel = n
			end
		end
		local j = section(body, "📖 Журнал: " .. (sel and (sel.title or sel.name) or "житель пропал"), 1)
		local jf = hflow(j, 1)
		btn(jf, "✕ Закрыть", {}, function()
			selectedNPC = nil
			render()
		end)
		if sel then
			btn(jf, "👁 Следить", {}, function()
				follow(sel.model, sel.name)
			end)
			label(j, "Сейчас: " .. sel.action .. (sel.stuck and "   🚨 ЗАСТРЯЛ" or ""), 12, sel.stuck and C.error or C.debug, true, { LayoutOrder = 2 })
			if sel.goal then
				label(j, string.format("Цель: (%.0f, %.0f, %.0f), до неё %.0f стадов, идёт %.0f с", sel.goal.X, sel.goal.Y, sel.goal.Z, (sel.goal - sel.pos).Magnitude, sel.walkingFor or 0), 11, C.dim, false, { LayoutOrder = 3 })
			end
		end
		for k = #journal, 1, -1 do
			local e = journal[k]
			label(j, e.hour .. "  " .. e.action, 12, k == #journal and C.text or C.dim, k == #journal, { LayoutOrder = 10 + (#journal - k), Font = Enum.Font.Code })
		end
		if #journal == 0 then
			label(j, "Пока пусто — журнал пишется, пока сервер работает.", 11, C.dim, false, { LayoutOrder = 10 })
		end
	end
	local q = string.lower(npcSearch)
	for i, n in list do
		local hay = string.lower(n.name .. " " .. (n.title or "") .. " " .. n.action .. " " .. tostring(n.zone) .. " " .. tostring(n.home))
		if q == "" or string.find(hay, q, 1, true) then
			local row = new("Frame", { BackgroundColor3 = n.stuck and Color3.fromRGB(70, 26, 28) or C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i + 2 }, body)
			corner(row, 8)
			new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 110) }, row)
			vlist(row, 2)
			label(row, string.format("%s%s%s  %s%s", n.officer and "👮 " or "", n.title or n.name, n.quest and " ❗" or "", tostring(n.mood or ""), n.stuck and "   🚨 ЗАСТРЯЛ" or ""), 13, n.stuck and C.error or C.text, true)
			label(row, n.action, 12, C.debug, false)
			label(row, string.format("зона: %s · дом: %s · ❤ %s", tostring(n.zone or "Street"), tostring(n.home or "—"), tostring(n.health)), 11, C.dim, false)
			local bf = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 106, 0.5, 0), Size = UDim2.fromOffset(100, 26), BackgroundTransparency = 1 }, row)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, bf)
			btn(bf, "📖", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = selectedNPC == n.model and C.accent or C.panel2 }, function()
				selectedNPC = n.model
				journal = {}
				remote:FireServer("Journal", n.model)
				body.CanvasPosition = Vector2.zero
				render()
			end)
			btn(bf, "👁", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
				follow(n.model, n.name)
			end)
			btn(bf, "📍", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
				remote:FireServer("Action", "TeleportTo", n.model)
			end)
		end
	end
end

local CAR_ICON = { Civilian = "🚗", Taxi = "🚕", Bus = "🚌", Police = "🚓" }
local function renderCars()
	local list = snapshot.cars or {}
	section(body, string.format("🚗 Машин: %d", #list), 0)
	for i, car in list do
		local row = new("Frame", { BackgroundColor3 = car.stuck and Color3.fromRGB(70, 26, 28) or C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i }, body)
		corner(row, 8)
		new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 76) }, row)
		vlist(row, 2)
		local standing = car.driving and car.speed < 0.1 and not car.atStop
		label(row, string.format("%s %s #%d %s%s", CAR_ICON[car.kind] or "🚗", tostring(car.kind), car.id, car.siren and "🚨" or "", car.stuck and "   🚨 ЗАСТРЯЛА" or ""), 13, car.stuck and C.error or C.text, true)
		label(row, string.format("состояние: %s · скорость: %s%s%s", tostring(car.state), tostring(car.speed), car.driving and " · в пути" or "", standing and "  (стоит)" or ""), 12, standing and C.warn or C.debug, false)
		label(row, string.format("едет к: %s · водитель: %s", tostring(car.to or "—"), tostring(car.driver or "—")), 11, C.dim, false)
		local bf = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 72, 0.5, 0), Size = UDim2.fromOffset(66, 26), BackgroundTransparency = 1 }, row)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, bf)
		btn(bf, "👁", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
			follow(car.model, tostring(car.kind) .. " #" .. car.id)
		end)
		btn(bf, "📍", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
			remote:FireServer("Action", "TeleportTo", car.model)
		end)
	end
end

local function renderOverlay()
	local s = section(body, "🗺 Метки на карте — видишь только ты", 0)
	label(s, "Невидимые метки становятся видны: цвет, имя, атрибуты и линия «куда смотрит передняя грань».", 12, C.dim, false, { LayoutOrder = 1 })
	for i, l in LAYERS do
		local on = overlays[l.id] == true
		btn(s, (on and "☑ " or "☐ ") .. l.name, { LayoutOrder = 1 + i, Size = UDim2.new(1, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = on and C.panel2:Lerp(l.color, 0.25) or C.panel2 }, function()
			setOverlay(l.id, not on)
			render()
		end)
	end
	btn(s, "Выключить все", { LayoutOrder = 100 }, function()
		for id in pairs(overlays) do
			setOverlay(id, false)
		end
		render()
	end)
end

local OUTPUT_FILTERS = {
	{ id = "all", text = "Все" },
	{ id = "error", text = "❌ Ошибки" },
	{ id = "warn", text = "⚠️ Предупр." },
	{ id = "event", text = "✨ События" },
	{ id = "C", text = "💻 Клиент" },
	{ id = "S", text = "🖥 Сервер" },
}
for _, t in Config.LogTags do
	table.insert(OUTPUT_FILTERS, { id = t, text = t })
end

local function logMatches(l): boolean
	local f = outputFilter
	local ok
	if f == "all" then
		ok = true
	elseif f == "error" or f == "warn" or f == "event" then
		ok = l.kind == f
	elseif f == "C" or f == "S" then
		ok = l.src == f
	else
		ok = string.find(l.text, f, 1, true) ~= nil
	end
	if ok and outputSearch ~= "" then
		ok = string.find(string.lower(l.text), string.lower(outputSearch), 1, true) ~= nil
	end
	return ok
end

local function filteredLogs(limit: number)
	local out = {}
	for i = #logs, 1, -1 do
		if logMatches(logs[i]) then
			table.insert(out, 1, logs[i])
			if #out >= limit then
				break
			end
		end
	end
	return out
end

local function timeOf(t: number): string
	local d = os.date("!*t", math.floor(t))
	return string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
end

local copyMode = false
local function renderOutput()
	unseenErrors = 0
	updateBadge()
	local top = section(body, "🖥 Output — сервер (S) и клиент (C)", 0)
	local ff = hflow(top, 1)
	for _, f in OUTPUT_FILTERS do
		btn(ff, f.text, { BackgroundColor3 = outputFilter == f.id and C.accent or C.panel2, TextSize = 12 }, function()
			outputFilter = f.id
			render()
		end)
	end
	local tools = hflow(top, 2)
	btn(tools, outputPaused and "▶ Продолжить" or "⏸ Пауза", {}, function()
		outputPaused = not outputPaused
		render()
	end)
	btn(tools, "🗑 Очистить", {}, function()
		table.clear(logs)
		render()
	end)
	btn(tools, copyMode and "📄 Списком" or "📋 Текстом (скопировать)", {}, function()
		copyMode = not copyMode
		render()
	end)
	local box = new("TextBox", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.panel2, TextColor3 = C.text, PlaceholderText = "🔍 Поиск в Output…", PlaceholderColor3 = C.dim, Text = outputSearch, Font = Enum.Font.GothamMedium, TextSize = 13, ClearTextOnFocus = false, LayoutOrder = 3 }, top)
	corner(box, 8)
	box.FocusLost:Connect(function()
		outputSearch = box.Text
		render()
	end)

	local list = filteredLogs(copyMode and 300 or 120)
	if copyMode then
		local lines = {}
		for _, l in list do
			table.insert(lines, string.format("%s [%s] %s %s", timeOf(l.t), l.src or "S", string.upper(l.kind), l.text))
		end
		local area = new("TextBox", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.panel,
			TextColor3 = C.text,
			Font = Enum.Font.Code,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ClearTextOnFocus = false,
			TextEditable = false,
			MultiLine = true,
			Text = #lines > 0 and table.concat(lines, "\n") or "(пусто)",
			LayoutOrder = 1,
		}, body)
		corner(area, 8)
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, area)
		label(body, "Выдели текст (Ctrl+A внутри поля) и скопируй (Ctrl+C) — так удобно прислать ошибки Claude.", 11, C.dim, false, { LayoutOrder = 2 })
		return
	end
	if #list == 0 then
		label(body, "Пусто", 12, C.dim, false, { LayoutOrder = 1 })
	end
	for i, l in list do
		local color = C[l.kind] or C.text
		local row = label(body, string.format("%s  %s  %s", timeOf(l.t), l.src or "S", l.text), 12, l.kind == "info" and C.dim:Lerp(C.text, 0.5) or color, l.kind == "error", { LayoutOrder = i, Font = Enum.Font.Code })
		if l.kind == "error" then
			row.BackgroundTransparency = 0.85
			row.BackgroundColor3 = C.error
		end
	end
	task.defer(function()
		body.CanvasPosition = Vector2.new(0, math.max(0, body.AbsoluteCanvasSize.Y - body.AbsoluteSize.Y))
	end)
end

local LEVEL = { ok = { "✅", C.ok }, warn = { "⚠️", C.warn }, error = { "❌", C.error } }
local function renderCheck()
	local top = section(body, "✅ Проверка карты и установки", 0)
	label(top, "Ищет пропущенные скрипты, ошибки разметки (точки без связей, дом без кровати, нет дежурного...) и ошибки в Output.", 12, C.dim, false, { LayoutOrder = 1 })
	btn(top, checks and "🔄 Проверить ещё раз" or "▶ Запустить проверку", { LayoutOrder = 2, BackgroundColor3 = C.accent }, function()
		remote:FireServer("Check")
	end)

	-- Проверка путей жителей
	local ps = section(body, "🧭 Проверка путей жителей", -1)
	label(ps, "От дома (точки появления зоны) к каждой точке жителей прокладывается путь. По одной проверке раз в 0.15 с — ПК не грузится, можно играть дальше.", 12, C.dim, false, { LayoutOrder = 1 })
	local running = pathState and pathState.running
	btn(ps, running and string.format("⏳ Проверено %d из %d… (недоступных: %d)", pathState.done or 0, pathState.total or 0, pathState.badCount or #(pathState.bad or {})) or "▶ Проверить пути", { LayoutOrder = 2, BackgroundColor3 = running and C.panel2 or C.accent }, function()
		if not running then
			remote:FireServer("PathCheck")
			pathState = { done = 0, total = 0, bad = {}, running = true }
			render()
		end
	end)
	if pathState and not running then
		if pathState.error then
			label(ps, "❌ " .. pathState.error, 12, C.error, true, { LayoutOrder = 3 })
		elseif #(pathState.bad or {}) == 0 then
			label(ps, string.format("✅ Все %d точек доступны", pathState.total or 0), 13, C.ok, true, { LayoutOrder = 3 })
		else
			label(ps, string.format("❌ Недоступно %d из %d точек. Они отмечены красным на карте (слой «Недоступные точки»).", #pathState.bad, pathState.total or 0), 12, C.error, true, { LayoutOrder = 3 })
			for i, b in pathState.bad do
				local row = new("Frame", { BackgroundColor3 = C.panel2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 + i }, ps)
				corner(row, 8)
				new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 44) }, row)
				label(row, string.format("%s · %s · от %s\n%s", tostring(b.activity), tostring(b.zone), tostring(b.from), b.name), 11, C.text, false)
				btn(row, "📍", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 40, 0.5, 0), Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
					remote:FireServer("Action", "TeleportPos", b.pos + Vector3.new(0, 3, 0))
				end)
			end
		end
	end
	if not checks then
		return
	end
	local counts = { ok = 0, warn = 0, error = 0 }
	for _, c in checks do
		counts[c.level] += 1
	end
	label(top, string.format("✅ %d   ⚠️ %d   ❌ %d", counts.ok, counts.warn, counts.error), 15, C.text, true, { LayoutOrder = 3 })
	-- Сначала ошибки, потом предупреждения
	local order = { error = 1, warn = 2, ok = 3 }
	local sorted = table.clone(checks)
	table.sort(sorted, function(a, b)
		if order[a.level] ~= order[b.level] then
			return order[a.level] < order[b.level]
		end
		return a.group < b.group
	end)
	for i, c in sorted do
		local lv = LEVEL[c.level]
		label(body, string.format("%s  %s: %s", lv[1], c.group, c.text), 12, c.level == "ok" and C.dim or lv[2], c.level == "error", { LayoutOrder = i })
	end
end

-- 📜 История обновлений: список и страница каждого обновления
local function renderHistory()
	if historyVersion then
		local e = nil
		for _, entry in Config.Changelog do
			if entry.Version == historyVersion then
				e = entry
			end
		end
		if not e then
			historyVersion = nil
			renderHistory()
			return
		end
		local nav = hflow(body, 0)
		btn(nav, "‹ Все обновления", {}, function()
			historyVersion = nil
			render()
		end)
		local head = section(body, "v" .. e.Version .. " — " .. e.Title, 1)
		label(head, "📅 " .. tostring(e.Date or "—"), 12, C.dim, false, { LayoutOrder = 1 })
		label(head, e.Summary or "", 13, C.text, false, { LayoutOrder = 2 })
		local details = section(body, "Что добавлено", 2)
		for i, d in e.Details or {} do
			label(details, d.Title, 13, C.debug, true, { LayoutOrder = i * 2 })
			label(details, d.Text, 12, C.text, false, { LayoutOrder = i * 2 + 1 })
		end
		if e.Files then
			local files = section(body, "📁 Файлы (скрипты)", 3)
			label(files, table.concat(e.Files, ", "), 12, C.dim, false, { LayoutOrder = 1, Font = Enum.Font.Code })
		end
		local tests = section(body, "✅ Что проверить", 4)
		for i, t in e.Tests or {} do
			local state = tested[testKey(e, i)]
			label(tests, (state == "ok" and "✓ " or state == "bug" and "🐞 " or "○ ") .. t.Text, 12, state == "ok" and C.ok or state == "bug" and C.error or C.text, false, { LayoutOrder = i })
		end
		btn(tests, "Перейти к проверкам ›", { LayoutOrder = 100, BackgroundColor3 = C.accent }, function()
			currentTab = "news"
			render()
		end)
		return
	end
	section(body, string.format("📜 История обновлений — %d", #Config.Changelog), 0)
	for i, e in Config.Changelog do
		local total, done, bugs = 0, 0, 0
		for k in e.Tests or {} do
			total += 1
			local st = tested[testKey(e, k)]
			done += st == "ok" and 1 or 0
			bugs += st == "bug" and 1 or 0
		end
		local card = new("TextButton", { BackgroundColor3 = C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", AutoButtonColor = true, LayoutOrder = i }, body)
		corner(card, 10)
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 26) }, card)
		vlist(card, 3)
		label(card, string.format("v%s — %s", e.Version, e.Title), 14, i == 1 and C.debug or C.text, true, { LayoutOrder = 1 })
		label(card, string.format("📅 %s   ✓ %d/%d%s", tostring(e.Date or "—"), done, total, bugs > 0 and ("   🐞 " .. bugs) or ""), 11, C.dim, false, { LayoutOrder = 2 })
		label(card, e.Summary or "", 12, C.text, false, { LayoutOrder = 3 })
		label(card, "›", 20, C.dim, true, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 20, 0.5, 0), Size = UDim2.fromOffset(16, 24), AutomaticSize = Enum.AutomaticSize.None })
		card.Activated:Connect(function()
			historyVersion = e.Version
			body.CanvasPosition = Vector2.zero
			render()
		end)
	end
end

-- 🩺 Диагностика
local COUNTER_NAMES = {
	{ "PoliceCall", "🚔 Вызовов полиции" }, { "ArrestAny", "🔒 Задержаний" }, { "Report", "📝 Заявлений игроков" }, { "Arrest", "🕵️ Задержаний по заявлениям" },
	{ "Taxi", "🚕 Поездок на такси" }, { "Bus", "🚌 Посадок в автобус" }, { "CarSpawn", "🚗 Машин создано" },
	{ "Quest", "❗ Заданий выполнено" }, { "Friend", "❤️ Новых друзей" }, { "Delivery", "📦 Доставок" }, { "Buy", "🛍 Покупок" }, { "Photo", "📷 Фото" },
	{ "NPCDeath", "💀 Смертей жителей" }, { "NPCPathFail", "🧭 Жители не дошли до цели" }, { "Stuck", "🚨 Застреваний" },
	{ "Errors", "❌ Ошибок (сервер)" }, { "Warnings", "⚠️ Предупреждений (сервер)" }, { "WeatherChange", "🌦 Смен погоды" }, { "Days", "📅 Игровых дней" },
	{ "Fly", "🦅 Секунд полёта" }, { "Invisible", "👻 Невидимостей" }, { "Laser", "🔴 Лазеров" }, { "Cube", "🧊 Кубов" }, { "Walk", "🚶 Стадов пешком" },
}

local function allErrors()
	local list = {}
	for _, g in diag and diag.errors or {} do
		table.insert(list, g)
	end
	for _, key in clientErrorOrder do
		table.insert(list, clientErrors[key])
	end
	table.sort(list, function(a, b)
		return a.last > b.last
	end)
	return list
end

local function diagReport(): string
	local lines = { "=== ОТЧЁТ ОТЛАДКИ ===", "Время игры: " .. tostring(diag and diag.perf and diag.perf.hour), "" }
	local errors = allErrors()
	table.insert(lines, string.format("ОШИБКИ СКРИПТОВ (%d разных):", #errors))
	for _, g in errors do
		table.insert(lines, string.format("[%s] ×%d  %s", g.src, g.count, g.message))
		table.insert(lines, "   скрипт: " .. tostring(g.script) .. "  строка: " .. tostring(g.line))
		for stackLine in string.gmatch(g.stack or "", "[^\n]+") do
			table.insert(lines, "   " .. stackLine)
		end
	end
	table.insert(lines, "")
	table.insert(lines, "ЗАСТРЕВАНИЯ:")
	for _, st in diag and diag.stuck or {} do
		table.insert(lines, string.format("  %s %s%s", timeOf(st.t), st.text, st.now and " (сейчас)" or ""))
	end
	table.insert(lines, "")
	table.insert(lines, "СЧЁТЧИКИ:")
	for _, c in COUNTER_NAMES do
		local v = diag and diag.counters and diag.counters[c[1]]
		if v then
			table.insert(lines, string.format("  %s: %s", c[2], tostring(math.floor(v))))
		end
	end
	return table.concat(lines, "\n")
end

local function timingRows(parent: Instance, timings, order: number)
	local list = {}
	for name, t in pairs(timings or {}) do
		table.insert(list, { name = name, ms = t.ms, peak = t.peak, calls = t.calls })
	end
	table.sort(list, function(a, b)
		return a.ms > b.ms
	end)
	if #list == 0 then
		label(parent, "Нет данных", 11, C.dim, false, { LayoutOrder = order })
	end
	for i, t in list do
		-- 1000 мс в секунду = 100% одного ядра; больше 30 мс/с — заметно
		local color = t.ms > 30 and C.error or t.ms > 10 and C.warn or C.ok
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order + i }, parent)
		label(row, string.format("%s — %.2f мс/с · пик %.2f мс · %d вызовов", t.name, t.ms, t.peak, t.calls), 11, C.text, false, { Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None })
		local back = new("Frame", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C.panel2, BorderSizePixel = 0 }, row)
		corner(back, 3)
		local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(t.ms / 50, 0.01, 1), 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
		corner(fill, 3)
	end
end

local function renderDiag()
	if not diag then
		label(body, "Загрузка…", 12, C.dim, false)
		remote:FireServer("Diag")
		return
	end
	local tools = hflow(body, 0)
	btn(tools, diagCopy and "📄 Обычный вид" or "📋 Скопировать для Claude", { BackgroundColor3 = C.accent }, function()
		diagCopy = not diagCopy
		render()
	end)
	btn(tools, "🔄 Обновить", {}, function()
		remote:FireServer("Diag")
	end)
	if diagCopy then
		local area = new("TextBox", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel, TextColor3 = C.text,
			Font = Enum.Font.Code, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			ClearTextOnFocus = false, TextEditable = false, MultiLine = true, Text = diagReport(), LayoutOrder = 1,
		}, body)
		corner(area, 8)
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, area)
		label(body, "Нажми в поле, Ctrl+A, Ctrl+C — и вставь в сообщение Claude.", 11, C.dim, false, { LayoutOrder = 2 })
		return
	end

	-- Застревания
	local stuck = section(body, string.format("🚨 Застревания (%d)", #(diag.stuck or {})), 1)
	if #(diag.stuck or {}) == 0 then
		label(stuck, "✅ Никто не застревал", 12, C.ok, false, { LayoutOrder = 1 })
	end
	for i, st in diag.stuck or {} do
		local row = new("Frame", { BackgroundColor3 = st.now and Color3.fromRGB(70, 26, 28) or C.panel2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i }, stuck)
		corner(row, 8)
		new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 76) }, row)
		label(row, string.format("%s  %s%s", timeOf(st.t), st.text, st.now and "  (сейчас)" or ""), 11, st.now and C.error or C.dim, st.now)
		local bf = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 72, 0.5, 0), Size = UDim2.fromOffset(66, 26), BackgroundTransparency = 1 }, row)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, bf)
		btn(bf, "👁", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
			follow(st.model, "застрявший")
		end)
		btn(bf, "📍", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
			remote:FireServer("Action", "TeleportPos", st.pos + Vector3.new(0, 4, 0))
		end)
	end

	-- Ошибки скриптов
	local errors = allErrors()
	local es = section(body, string.format("❌ Ошибки скриптов (%d разных)", #errors), 2)
	if #errors == 0 then
		label(es, "✅ Ошибок нет", 12, C.ok, false, { LayoutOrder = 1 })
	end
	for i, g in errors do
		local row = new("Frame", { BackgroundColor3 = C.panel2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i }, es)
		corner(row, 8)
		new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, row)
		vlist(row, 2)
		label(row, string.format("×%d  %s  %s:%s", g.count, g.src == "C" and "💻 клиент" or "🖥 сервер", tostring(g.script), tostring(g.line)), 12, C.error, true)
		label(row, g.message, 12, C.text, false, { Font = Enum.Font.Code })
		label(row, string.format("первая %s · последняя %s", timeOf(g.first), timeOf(g.last)), 11, C.dim, false)
		if g.stack and g.stack ~= "" then
			label(row, g.stack, 10, C.dim, false, { Font = Enum.Font.Code })
		end
	end

	-- Счётчики
	local cs = section(body, "🔢 Счётчики за сессию", 3)
	local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 }, cs)
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 22), CellPadding = UDim2.fromOffset(8, 2), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, c in COUNTER_NAMES do
		local v = diag.counters and diag.counters[c[1]] or 0
		label(grid, string.format("%s: %s", c[2], tostring(math.floor(v))), 11, v > 0 and ((c[1] == "Errors" or c[1] == "Stuck" or c[1] == "NPCPathFail") and C.error or C.text) or C.dim, v > 0, { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 1, 0) })
	end

	-- Кто тормозит
	local ts = section(body, "🐢 Кто тормозит — сервер", 4)
	label(ts, "Сколько миллисекунд в секунду тратит каждый скрипт. До 10 — отлично, 10–30 — заметно, больше 30 — тормозит. Жители (NPCServer) работают по своим таймерам, их нагрузка видна по серверному FPS и HeartbeatTimeMs.", 11, C.dim, false, { LayoutOrder = 1 })
	timingRows(ts, diag.timings, 10)
	local st = diag.stats or {}
	local engine = {}
	for _, k in { "HeartbeatTimeMs", "PhysicsStepTimeMs", "InstanceCount", "PrimitivesCount", "MovingPrimitivesCount", "ContactsCount", "DataSendKbps", "DataReceiveKbps" } do
		if st[k] then
			table.insert(engine, k .. ": " .. tostring(st[k]))
		end
	end
	label(ts, "Движок: " .. table.concat(engine, " · "), 11, C.dim, false, { LayoutOrder = 100 })
	local mem = {}
	for k, v in pairs(st.memory or {}) do
		table.insert(mem, k .. " " .. tostring(v))
	end
	table.sort(mem)
	label(ts, "Память (МБ): " .. table.concat(mem, " · "), 11, C.dim, false, { LayoutOrder = 101 })
	local tc = section(body, "🐢 Кто тормозит — твой клиент", 5)
	timingRows(tc, clientTimings, 10)
end

local RENDER = { news = renderNews, history = renderHistory, world = renderWorld, npcs = renderNPCs, cars = renderCars, overlay = renderOverlay, output = renderOutput, check = renderCheck, diag = renderDiag }
local tabButtons = {}
for i, t in TABS do
	tabButtons[t.id] = btn(tabBar, t.text, { LayoutOrder = i, Size = UDim2.fromOffset(0, 30), TextSize = 12 }, function()
		currentTab = t.id
		render()
	end)
end

function render()
	for id, b in pairs(tabButtons) do
		b.BackgroundColor3 = id == currentTab and C.accent or C.panel2
	end
	local keepScroll = body.CanvasPosition
	clearBody()
	RENDER[currentTab]()
	if currentTab ~= "output" then
		task.defer(function()
			body.CanvasPosition = keepScroll
		end)
	end
end

---------------------------------------------------------------------
-- Сервер
---------------------------------------------------------------------

remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "Hello" then
		for _, l in payload.logs do
			addLog(l)
		end
		table.sort(logs, function(a, b)
			return a.t < b.t
		end)
		tested = payload.tested or {}
		placeNames = payload.placeNames or {}
		updateBadge()
		if win.Visible then
			render()
		end
	elseif kind == "Logs" then
		for _, l in payload do
			addLog(l)
		end
		updateBadge()
		outputDirty = true
	elseif kind == "Snapshot" then
		snapshot = payload
		drawDynamic()
		if win.Visible and (currentTab == "npcs" or currentTab == "cars") and not UserInputService:GetFocusedTextBox() then
			render()
		end
	elseif kind == "Nodes" then
		if overlays.Roads then
			drawRoads(payload)
		end
	elseif kind == "Check" then
		checks = payload
		if currentTab == "check" then
			render()
		end
	elseif kind == "Journal" then
		if payload.model == selectedNPC then
			journal = payload.entries or {}
			if win.Visible and currentTab == "npcs" and not UserInputService:GetFocusedTextBox() then
				render()
			end
		end
	elseif kind == "PathProgress" then
		pathState = { running = true, done = payload.done, total = payload.total, badCount = payload.bad, bad = {} }
		if win.Visible and currentTab == "check" then
			render()
		end
	elseif kind == "PathResult" then
		pathState = payload
		pathState.running = false
		if #(payload.bad or {}) > 0 then
			overlays.PathBad = true
		end
		drawPathBad()
		if win.Visible and currentTab == "check" then
			render()
		end
	elseif kind == "Diag" then
		diag = payload
		if win.Visible and currentTab == "diag" and not diagCopy and not UserInputService:GetFocusedTextBox() then
			render()
		end
	elseif kind == "Result" then
		showResult(payload)
		if win.Visible and currentTab == "world" then
			remote:FireServer("Snapshot")
			task.delay(0.4, function()
				if currentTab == "world" then
					render()
				end
			end)
		end
	end
end)
remote:FireServer("Hello")

---------------------------------------------------------------------
-- Открыть / закрыть, обновления
---------------------------------------------------------------------

---------------------------------------------------------------------
-- 🎥 Свободная камера (F3): летаешь сквозь стены, персонаж стоит на месте
---------------------------------------------------------------------

local fc = { on = false, speed = 40, yaw = 0, pitch = 0, pos = Vector3.zero, saved = nil }
local camBar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(560, 40), BackgroundColor3 = C.bg, BackgroundTransparency = 0.1, Visible = false }, gui)
corner(camBar, 12)
new("UIStroke", { Color = C.accent, Thickness = 1.5 }, camBar)
local camInfo = label(camBar, "", 12, C.text, true, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -200, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Center })
local MOVE_KEYS = { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.LeftShift, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right }

function freeCam(on: boolean)
	if on == fc.on then
		if on then
			freeCam(false)
		end
		return
	end
	fc.on = on
	camBar.Visible = on
	if on then
		if followTarget then
			stopFollow()
		end
		fc.saved = { type = camera.CameraType, subject = camera.CameraSubject }
		local cf = camera.CFrame
		fc.pos = cf.Position
		local look = cf.LookVector
		fc.yaw = math.atan2(-look.X, -look.Z)
		fc.pitch = math.asin(math.clamp(look.Y, -1, 1))
		camera.CameraType = Enum.CameraType.Scriptable
		-- Глушим управление персонажем, пока летает камера
		ContextActionService:BindActionAtPriority("DebugFreeCamSink", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 50, table.unpack(MOVE_KEYS))
	else
		ContextActionService:UnbindAction("DebugFreeCamSink")
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		camera.CameraType = (fc.saved and fc.saved.type) or Enum.CameraType.Custom
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		camera.CameraSubject = humanoid or (fc.saved and fc.saved.subject)
	end
end
btn(camBar, "📍 Сюда", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -54, 0.5, 0), BackgroundColor3 = C.accent }, function()
	remote:FireServer("Action", "TeleportPos", fc.pos)
	freeCam(false)
end)
btn(camBar, "✕", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(32, 28), AutomaticSize = Enum.AutomaticSize.None }, function()
	freeCam(false)
end)
ContextActionService:BindAction("DebugFreeCam", function(_, state)
	if state == Enum.UserInputState.Begin then
		freeCam(not fc.on)
	end
	return Enum.ContextActionResult.Sink
end, false, Config.FreeCamKey)
UserInputService.InputChanged:Connect(function(input)
	if fc.on and input.UserInputType == Enum.UserInputType.MouseWheel then
		fc.speed = math.clamp(fc.speed * (input.Position.Z > 0 and 1.25 or 0.8), 5, 400)
	end
end)
RunService.RenderStepped:Connect(function(dt)
	if not fc.on then
		return
	end
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		local d = UserInputService:GetMouseDelta()
		fc.yaw -= d.X * 0.004
		fc.pitch = math.clamp(fc.pitch - d.Y * 0.004, -1.5, 1.5)
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	local rot = CFrame.Angles(0, fc.yaw, 0) * CFrame.Angles(fc.pitch, 0, 0)
	local move = Vector3.zero
	local function down(k)
		return UserInputService:IsKeyDown(k) and not UserInputService:GetFocusedTextBox()
	end
	if down(Enum.KeyCode.W) or down(Enum.KeyCode.Up) then
		move += rot.LookVector
	end
	if down(Enum.KeyCode.S) or down(Enum.KeyCode.Down) then
		move -= rot.LookVector
	end
	if down(Enum.KeyCode.D) or down(Enum.KeyCode.Right) then
		move += rot.RightVector
	end
	if down(Enum.KeyCode.A) or down(Enum.KeyCode.Left) then
		move -= rot.RightVector
	end
	if down(Enum.KeyCode.Space) then
		move += Vector3.yAxis
	end
	if down(Enum.KeyCode.LeftControl) then
		move -= Vector3.yAxis
	end
	local speed = fc.speed * (down(Enum.KeyCode.LeftShift) and 3 or 1)
	if move.Magnitude > 0 then
		fc.pos += move.Unit * speed * dt
	end
	camera.CFrame = CFrame.new(fc.pos) * rot
	camInfo.Text = string.format("🎥 Свободная камера · скорость %d (колесо) · (%.0f, %.0f, %.0f)", fc.speed, fc.pos.X, fc.pos.Y, fc.pos.Z)
end)

local function fit()
	local view = camera.ViewportSize
	winScale.Scale = math.min(1, (view.Y - 100) / H, (view.X - 90) / W)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
fit()

local function toggleMenu()
	win.Visible = not win.Visible
	if win.Visible then
		remote:FireServer("Snapshot")
		render()
	end
end
toggle.Activated:Connect(toggleMenu)
ContextActionService:BindAction("DebugMenu", function(_, state)
	if state == Enum.UserInputState.Begin then
		toggleMenu()
	end
	return Enum.ContextActionResult.Sink
end, false, Config.Key)

local fpsFrames, fpsTimer, clientFps = 0, 0, 60
local snapTimer, outputTimer, diagTimer = 0, 0, 0
RunService.RenderStepped:Connect(function(dt)
	fpsFrames += 1
	fpsTimer += dt
	if fpsTimer >= 1 then
		clientFps = math.floor(fpsFrames / fpsTimer)
		fpsFrames, fpsTimer = 0, 0
		local p = snapshot.perf or {}
		footer.Text = string.format("FPS: клиент %d · сервер %s   💾 %s МБ   🧑 %s   🚗 %s   🕗 %s ×%s   📶 %d мс",
			clientFps, tostring(p.fps or "?"), tostring(p.memory or "?"), tostring(p.npcs or "?"), tostring(p.cars or "?"),
			tostring(p.hour or "?"), tostring(p.timeScale or 1), math.floor(player:GetNetworkPing() * 1000))
	end
	-- Живые данные: только когда они на экране
	local live = overlays.NPCPaths or overlays.CarRoutes or overlays.NPCLabels or (win.Visible and (currentTab == "npcs" or currentTab == "cars"))
	snapTimer -= dt
	if (live or win.Visible or overlays.Stuck) and snapTimer <= 0 then
		-- живые слои — раз в секунду, строка внизу — раз в 2 с, только подсветка застрявших — раз в 3 с
		snapTimer = live and 1 or win.Visible and 2 or 3
		remote:FireServer("Snapshot")
		if selectedNPC and win.Visible and currentTab == "npcs" then
			remote:FireServer("Journal", selectedNPC)
		end
	end
	diagTimer -= dt
	if win.Visible and currentTab == "diag" and diagTimer <= 0 then
		diagTimer = 2
		remote:FireServer("Diag")
	end
	outputTimer -= dt
	if outputDirty and outputTimer <= 0 and win.Visible and currentTab == "output" and not outputPaused and not copyMode and not UserInputService:GetFocusedTextBox() then
		outputTimer = 0.6
		outputDirty = false
		render()
	end
	if followTarget and not followTarget.Parent then
		stopFollow()
	end
end)

player.CharacterAdded:Connect(function()
	if followTarget then
		task.defer(stopFollow)
	end
end)
