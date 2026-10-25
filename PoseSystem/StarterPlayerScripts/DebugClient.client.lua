-- LocalScript: StarterPlayer > StarterPlayerScripts > DebugClient
-- Меню отладки: F2 или кнопка 🛠 (только у админов, см. DebugConfig).
-- Вкладки:
--   📋 Новое     — что добавлено в каждом обновлении + проверки с кнопкой «▶» и отметками ✓ / 🐞
--   🌍 Мир       — время, ускорение, погода, вызов полиции, монеты, кулдауны, телепорт
--   🧑 Жители    — что делает каждый житель, куда идёт; следить камерой, телепорт
--   🚗 Машины    — тип, состояние, скорость, куда едет; следить, телепорт
--   🗺 Метки     — показать на карте дороги, точки, двери, парковки, пути жителей, маршруты машин
--   🖥 Output    — сообщения сервера и клиента, фильтры, копирование
--   ✅ Проверка  — автопроверка разметки карты и установки скриптов

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local LogService = game:GetService("LogService")
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
	{ id = "news", text = "📋 Новое" },
	{ id = "world", text = "🌍 Мир" },
	{ id = "npcs", text = "🧑 Жители" },
	{ id = "cars", text = "🚗 Машины" },
	{ id = "overlay", text = "🗺 Метки" },
	{ id = "output", text = "🖥 Output" },
	{ id = "check", text = "✅ Проверка" },
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
	{ id = "NPCPaths", name = "🧭 Пути жителей (живые)", color = Color3.fromRGB(80, 255, 200) },
	{ id = "CarRoutes", name = "🚗 Маршруты машин (живые)", color = Color3.fromRGB(255, 90, 90) },
	{ id = "NPCLabels", name = "🏷 Ярлыки над жителями (живые)", color = Color3.fromRGB(255, 255, 255) },
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

local function drawDynamic()
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
		if id == "NPCPaths" or id == "CarRoutes" or id == "NPCLabels" then
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
		for _, item in e.Items or {} do
			label(s, "• " .. item, 12, C.dim, false, { LayoutOrder = 1 })
		end
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
	local q = string.lower(npcSearch)
	for i, n in list do
		local hay = string.lower(n.name .. " " .. (n.title or "") .. " " .. n.action .. " " .. tostring(n.zone) .. " " .. tostring(n.home))
		if q == "" or string.find(hay, q, 1, true) then
			local row = new("Frame", { BackgroundColor3 = C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i + 1 }, body)
			corner(row, 8)
			new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 76) }, row)
			vlist(row, 2)
			label(row, string.format("%s%s%s  %s", n.officer and "👮 " or "", n.title or n.name, n.quest and " ❗" or "", tostring(n.mood or "")), 13, C.text, true)
			label(row, n.action, 12, C.debug, false)
			label(row, string.format("зона: %s · дом: %s · ❤ %s", tostring(n.zone or "Street"), tostring(n.home or "—"), tostring(n.health)), 11, C.dim, false)
			local bf = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 72, 0.5, 0), Size = UDim2.fromOffset(66, 26), BackgroundTransparency = 1 }, row)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, bf)
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
		local row = new("Frame", { BackgroundColor3 = C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i }, body)
		corner(row, 8)
		new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 76) }, row)
		vlist(row, 2)
		local stuck = car.state == "busy" and car.speed < 0.1
		label(row, string.format("%s %s #%d %s", CAR_ICON[car.kind] or "🚗", tostring(car.kind), car.id, car.siren and "🚨" or ""), 13, C.text, true)
		label(row, string.format("состояние: %s · скорость: %s%s", tostring(car.state), tostring(car.speed), stuck and "  (стоит)" or ""), 12, stuck and C.warn or C.debug, false)
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

local RENDER = { news = renderNews, world = renderWorld, npcs = renderNPCs, cars = renderCars, overlay = renderOverlay, output = renderOutput, check = renderCheck }
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
local snapTimer, outputTimer = 0, 0
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
	if (live or win.Visible) and snapTimer <= 0 then
		snapTimer = live and 1 or 2 -- строке внизу хватает раза в 2 секунды
		remote:FireServer("Snapshot")
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
