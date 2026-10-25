-- Script: ServerScriptService > DebugServer
-- Меню отладки (клавиша F2) — серверная часть. Доступ только у админов (DebugConfig).
--   * Output: собирает все сообщения сервера (print, warn, ошибки скриптов) и события игры;
--   * Мир: время (час, ускорение, пауза), погода, вызов полиции, монеты, кулдауны, телепорт;
--   * Жители и машины: что делает каждый и куда идёт/едет;
--   * Проверка: ищет ошибки разметки карты и установки скриптов;
--   * Диагностика: застревания, ошибки скриптов по группам, журнал жителей, проверка путей,
--     счётчики событий, кто тормозит (секундомер DebugConfig.connect).
-- Каждое действие сервер проверяет сам: обычный игрок ничего не сможет вызвать.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local DataStoreService = game:GetService("DataStoreService")
local ScriptContext = game:GetService("ScriptContext")
local PathfindingService = game:GetService("PathfindingService")
local StatsService = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DebugConfig"))
if not Config.Enabled then
	return
end
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local SoundConfig = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local remote = Instance.new("RemoteEvent")
remote.Name = "DebugRemote"
remote.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- Кто админ
---------------------------------------------------------------------

local admins = {} -- [player] = true

local function checkAdmin(player: Player): boolean
	if RunService:IsStudio() and Config.AllInStudio then
		return true
	end
	if table.find(Config.Admins, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		if ok and rank >= Config.GroupMinRank then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- Output сервера и события игры
---------------------------------------------------------------------

local logs = {} -- { t, kind, text }
local outbox = {} -- новые строки, которые ещё не отправлены
local KIND = {
	[Enum.MessageType.MessageOutput] = "info",
	[Enum.MessageType.MessageInfo] = "info",
	[Enum.MessageType.MessageWarning] = "warn",
	[Enum.MessageType.MessageError] = "error",
}

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

-- Счётчики за сессию
local counters = {}
local function count(name: string, n: number?)
	counters[name] = (counters[name] or 0) + (n or 1)
end
Registry.debugCount = count

local function addLog(kind: string, text: string)
	if kind == "error" then
		count("Errors")
	elseif kind == "warn" then
		count("Warnings")
	end
	local entry = { t = workspace:GetServerTimeNow(), kind = kind, text = text, src = "S" }
	table.insert(logs, entry)
	if #logs > Config.LogLimit then
		table.remove(logs, 1)
	end
	table.insert(outbox, entry)
end

for _, m in LogService:GetLogHistory() do
	addLog(KIND[m.messageType] or "info", m.message)
end
LogService.MessageOut:Connect(function(message, messageType)
	addLog(KIND[messageType] or "info", message)
end)

-- Ошибки скриптов по группам: одинаковые — в одну строку со счётчиком
local errorGroups = {} -- [текст] = { message, script, line, stack, count, first, last }
local errorOrder = {}
ScriptContext.Error:Connect(function(message, stack, source)
	local g = errorGroups[message]
	local now = workspace:GetServerTimeNow()
	if not g then
		local scriptName = source and source:GetFullName() or "?"
		g = { message = message, script = scriptName, line = tonumber(string.match(message, ":(%d+):")) or 0, stack = stack, count = 0, first = now, last = now, src = "S" }
		errorGroups[message] = g
		table.insert(errorOrder, message)
		if #errorOrder > 60 then
			errorGroups[table.remove(errorOrder, 1)] = nil
		end
	end
	g.count += 1
	g.last = now
end)

-- События игры (полиция, достижения, погода, время) — отдельным цветом
Registry.debugEvent = function(text: string)
	addLog("event", text)
end
workspace:GetAttributeChangedSignal("Period"):Connect(function()
	addLog("event", string.format("🕗 Период: %s (%s)", tostring(workspace:GetAttribute("Period")), tostring(workspace:GetAttribute("Hour"))))
end)
workspace:GetAttributeChangedSignal("Weather"):Connect(function()
	count("WeatherChange")
	addLog("event", "🌦 Погода: " .. tostring(workspace:GetAttribute("WeatherName")))
end)
workspace:GetAttributeChangedSignal("Day"):Connect(function()
	count("Days")
	addLog("event", "📅 Новый день: " .. tostring(workspace:GetAttribute("Day")))
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		if #outbox > 0 then
			local batch = outbox
			outbox = {}
			for player in pairs(admins) do
				if player.Parent then
					remote:FireClient(player, "Logs", batch)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Производительность
---------------------------------------------------------------------

local fps, frames, frameTimer = 60, 0, 0
RunService.Heartbeat:Connect(function(dt)
	frames += 1
	frameTimer += dt
	if frameTimer >= 1 then
		fps = math.floor(frames / frameTimer)
		frames, frameTimer = 0, 0
	end
end)

local function perf()
	local npcCount = 0
	for _ in pairs(Registry.npcs) do
		npcCount += 1
	end
	local root = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local vehicles = root and root:FindFirstChild(VehicleConfig.VehiclesFolder)
	return {
		fps = fps,
		memory = math.floor(game:GetService("Stats"):GetTotalMemoryUsageMb()),
		npcs = npcCount,
		cars = vehicles and #vehicles:GetChildren() or 0,
		players = #Players:GetPlayers(),
		hour = workspace:GetAttribute("Hour"),
		period = workspace:GetAttribute("Period"),
		weather = workspace:GetAttribute("WeatherName"),
		timeScale = workspace:GetAttribute("TimeScale") or 1,
		day = workspace:GetAttribute("Day"),
	}
end

-- Кто тормозит: секундомер скриптов сервера за последнюю секунду
local lastTimings = {}
task.spawn(function()
	while true do
		local start = os.clock()
		task.wait(1)
		lastTimings = Config.takeTimings(os.clock() - start)
	end
end)

local MEMORY_TAGS = { "Script", "Physics", "Animation", "Gui", "Sounds", "Instances", "LuaHeap", "Navigation", "GraphicsParts" }
local function engineStats()
	local out = { memory = {} }
	for _, prop in { "HeartbeatTimeMs", "PhysicsStepTimeMs", "InstanceCount", "PrimitivesCount", "MovingPrimitivesCount", "ContactsCount", "DataSendKbps", "DataReceiveKbps" } do
		local ok, v = pcall(function()
			return (StatsService :: any)[prop]
		end)
		if ok and type(v) == "number" then
			out[prop] = math.floor(v * 100) / 100
		end
	end
	for _, tagName in MEMORY_TAGS do
		local ok, v = pcall(function()
			return StatsService:GetMemoryUsageMbForTag((Enum.DeveloperMemoryTag :: any)[tagName])
		end)
		if ok and type(v) == "number" then
			out.memory[tagName] = math.floor(v * 10) / 10
		end
	end
	return out
end

---------------------------------------------------------------------
-- Журнал жителей и детектор застреваний
---------------------------------------------------------------------

local journals = {} -- [model] = { { hour, action } }
local lastAction = {} -- [model] = текст
local anchors = {} -- [model или машина] = { pos, since }
local stuckNow = {} -- [model] = true
local stuckHistory = {} -- последние случаи
local npcCache, carCache = {}, {}

local function hourText(): string
	local h = workspace:GetAttribute("Hour") or Lighting.ClockTime
	return string.format("%02d:%02d", math.floor(h), math.floor((h % 1) * 60))
end

local function checkStuck(key: Instance, pos: Vector3, moving: boolean, limit: number, minMove: number, describe: () -> string)
	local a = anchors[key]
	local now = os.clock()
	if not moving then
		anchors[key] = nil
		stuckNow[key] = nil
		return false
	end
	if not a or (pos - a.pos).Magnitude > minMove then
		anchors[key] = { pos = pos, since = now }
		if stuckNow[key] then
			stuckNow[key] = nil
			addLog("event", "✅ Поехал/пошёл дальше: " .. describe())
		end
		return false
	end
	if now - a.since > limit and not stuckNow[key] then
		stuckNow[key] = true
		count("Stuck")
		local text = describe()
		addLog("warn", "🚨 Застрял: " .. text)
		table.insert(stuckHistory, 1, { t = workspace:GetServerTimeNow(), text = text, model = key, pos = pos })
		if #stuckHistory > 30 then
			table.remove(stuckHistory)
		end
	end
	return stuckNow[key] == true
end

task.spawn(function()
	while true do
		task.wait(1)
		local list = Registry.debugNPCs and Registry.debugNPCs() or {}
		local alive = {}
		for _, n in list do
			local m = n.model
			alive[m] = true
			if lastAction[m] ~= n.action then
				lastAction[m] = n.action
				local j = journals[m] or {}
				journals[m] = j
				table.insert(j, { hour = hourText(), action = n.action, t = workspace:GetServerTimeNow() })
				if #j > 25 then
					table.remove(j, 1)
				end
			end
			local moving = n.goal ~= nil and not n.seated and (n.goal - n.pos).Magnitude > 4
			n.stuck = checkStuck(m, n.pos, moving, Config.Stuck.NPCSeconds, Config.Stuck.NPCMinMove, function()
				return string.format("житель %s — %s (%.0f, %.0f, %.0f)", n.name, n.action, n.pos.X, n.pos.Y, n.pos.Z)
			end)
		end
		for m in pairs(journals) do
			if not alive[m] and not m.Parent then
				journals[m], lastAction[m], anchors[m], stuckNow[m] = nil, nil, nil, nil
			end
		end
		npcCache = list
		local cars = Registry.debugCars and Registry.debugCars() or {}
		for _, c in cars do
			local moving = c.driving and not c.atStop
			c.stuck = checkStuck(c.model, c.pos, moving, Config.Stuck.CarSeconds, 1.5, function()
				return string.format("машина %s #%d → %s (%.0f, %.0f, %.0f)", tostring(c.kind), c.id, tostring(c.to), c.pos.X, c.pos.Y, c.pos.Z)
			end)
		end
		carCache = cars
	end
end)

---------------------------------------------------------------------
-- Проверка путей жителей (по одной, с паузами — не грузит ПК)
---------------------------------------------------------------------

local pathCheck = { running = false, done = 0, total = 0, bad = {} }

local function runPathCheck(requester: Player)
	if pathCheck.running then
		return
	end
	local npcRoot = workspace:FindFirstChild(NPCConfig.FolderName)
	if not npcRoot then
		remote:FireClient(requester, "PathResult", { done = 0, total = 0, bad = {}, error = "Нет папки " .. NPCConfig.FolderName })
		return
	end
	local spawnsByZone, anySpawn = {}, nil
	for _, sp in partsIn(npcRoot:FindFirstChild("Spawns")) do
		local z = sp:GetAttribute("Zone") or NPCConfig.OutdoorZone
		spawnsByZone[z] = spawnsByZone[z] or sp
		if z == NPCConfig.OutdoorZone or not anySpawn then
			anySpawn = sp
		end
	end
	local points = partsIn(npcRoot:FindFirstChild("Points"))
	if #points > Config.PathCheckMax then
		points = { table.unpack(points, 1, Config.PathCheckMax) }
	end
	pathCheck = { running = true, done = 0, total = #points, bad = {} }
	local path = PathfindingService:CreatePath({
		AgentRadius = NPCConfig.AgentRadius or 2,
		AgentHeight = NPCConfig.AgentHeight or 5,
		AgentCanJump = true,
		Costs = { Door = 1 },
	})
	for i, p in points do
		local zone = p:GetAttribute("Zone") or NPCConfig.OutdoorZone
		local from = spawnsByZone[zone] or anySpawn
		if from then
			-- Та же точка подхода, что у жителей (стул — сбоку от стола, кровать — с края)
			local goal = Registry.debugApproach and Registry.debugApproach(p) or p.Position
			local ok = pcall(function()
				path:ComputeAsync(from.Position + Vector3.new(0, 2, 0), goal + Vector3.new(0, 1, 0))
			end)
			if not ok or path.Status ~= Enum.PathStatus.Success then
				table.insert(pathCheck.bad, {
					name = p:GetFullName(),
					zone = zone,
					activity = p:IsA("Seat") and "Seat" or tostring(p:GetAttribute("Activity")),
					from = from.Name,
					pos = p.Position,
					part = p,
				})
			end
		end
		pathCheck.done = i
		if i % 5 == 0 and requester.Parent then
			remote:FireClient(requester, "PathProgress", { done = i, total = #points, bad = #pathCheck.bad })
		end
		task.wait(Config.PathCheckDelay)
	end
	pathCheck.running = false
	count("PathChecks")
	addLog(#pathCheck.bad == 0 and "event" or "warn", string.format("🧭 Проверка путей: %d из %d точек недоступны", #pathCheck.bad, #points))
	if requester.Parent then
		remote:FireClient(requester, "PathResult", pathCheck)
	end
end

---------------------------------------------------------------------
-- Проверка карты и установки
---------------------------------------------------------------------

local EXPECTED = {
	{ ReplicatedStorage, { "PoseConfig", "InvisibilityConfig", "LaserConfig", "FlightConfig", "CubeConfig", "NPCConfig", "VehicleConfig", "SoundConfig", "WeatherConfig", "CityConfig", "DebugConfig", "WeaponConfig", "AbilityButton", "RigAnimator", "AbilityFx" } },
	{ ServerScriptService, { "AbilityRegistry", "NPCRegistry", "VehicleDefaults", "PoseServer", "InvisibilityServer", "LaserServer", "FlightServer", "CubeServer", "NPCDemo", "NPCServer", "NPCDoors", "DayNightServer", "TrafficServer", "WeatherServer", "PhoneServer", "CityLifeServer", "DebugServer", "WeaponServer", "WantedServer" } },
	{ StarterPlayer:FindFirstChild("StarterPlayerScripts"), { "PoseClient", "InvisibilityClient", "LaserClient", "FlightClient", "CubeClient", "NPCClient", "VehicleClient", "PoliceDeskClient", "WeatherClient", "PhoneClient", "CityLifeClient", "DebugClient", "WeaponClient", "WantedClient" } },
}

local function runChecks()
	local out = {}
	local function add(level: string, group: string, text: string)
		table.insert(out, { level = level, group = group, text = text })
	end

	-- Скрипты
	local missing, dupes = {}, {}
	for _, entry in EXPECTED do
		local container, names = entry[1], entry[2]
		for _, name in names do
			local count = 0
			if container then
				for _, c in container:GetChildren() do
					if c.Name == name then
						count += 1
					end
				end
			end
			if count == 0 then
				table.insert(missing, name)
			elseif count > 1 then
				table.insert(dupes, name)
			end
		end
	end
	if #missing == 0 then
		add("ok", "Скрипты", "Все скрипты на месте")
	else
		add("error", "Скрипты", "Нет скриптов: " .. table.concat(missing, ", "))
	end
	if #dupes > 0 then
		add("error", "Скрипты", "Двойные копии: " .. table.concat(dupes, ", "))
	end
	local errors = 0
	for _, l in logs do
		if l.kind == "error" then
			errors += 1
		end
	end
	add(errors == 0 and "ok" or "error", "Скрипты", errors == 0 and "Ошибок скриптов в Output нет" or ("Ошибок в Output: " .. errors .. " — открой вкладку Output"))

	-- Жители
	local npcRoot = workspace:FindFirstChild(NPCConfig.FolderName)
	if not npcRoot then
		add("warn", "Жители", "Нет папки " .. NPCConfig.FolderName .. " — работает демо-городок")
	else
		local spawns = partsIn(npcRoot:FindFirstChild("Spawns"))
		local points = partsIn(npcRoot:FindFirstChild("Points"))
		local doors = npcRoot:FindFirstChild("Doors")
		add(#spawns > 0 and "ok" or "error", "Жители", "Точек появления: " .. #spawns)
		local byActivity, homes, lieZones, zones, seats = {}, {}, {}, {}, 0
		for _, s in spawns do
			local z = s:GetAttribute("Zone")
			if z and z ~= NPCConfig.OutdoorZone then
				homes[z] = true
			end
		end
		for _, p in points do
			local z = p:GetAttribute("Zone") or NPCConfig.OutdoorZone
			zones[z] = true
			if p:IsA("Seat") then
				seats += 1
			else
				local a = p:GetAttribute("Activity")
				if type(a) ~= "string" then
					add("error", "Жители", "У точки " .. p:GetFullName() .. " нет Activity")
				else
					byActivity[a] = (byActivity[a] or 0) + 1
					if a == "Lie" then
						lieZones[z] = true
					end
				end
			end
		end
		local parts = {}
		for a, n in pairs(byActivity) do
			table.insert(parts, a .. " " .. n)
		end
		table.insert(parts, "стулья " .. seats)
		add(#points > 0 and "ok" or "error", "Жители", "Точек: " .. #points .. " (" .. table.concat(parts, ", ") .. ")")
		for home in pairs(homes) do
			if not lieZones[home] then
				add("error", "Жители", "В доме «" .. home .. "» нет точки Lie — жителям негде спать")
			end
		end
		local other = 0
		for z in pairs(zones) do
			if not homes[z] and z ~= NPCConfig.OutdoorZone then
				other += 1
			end
		end
		add(other > 0 and "ok" or "warn", "Расписание", other > 0 and ("Зон для дня (кафе, магазины...): " .. other) or "Нет зон кафе/магазинов — днём жителям некуда ходить")
		add((doors and #doors:GetChildren() > 0) and "ok" or "warn", "Жители", "Дверей: " .. (doors and #doors:GetChildren() or 0))
	end

	-- Дороги
	local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
	if not map then
		add("warn", "Дороги", "Нет папки " .. VehicleConfig.MapFolder .. " — работают демо-дороги")
	else
		local nodes = Registry.debugNodes and Registry.debugNodes() or {}
		local count, lonely, dead, turn = 0, {}, 0, 0
		for name, n in pairs(nodes) do
			count += 1
			if #n.links == 0 then
				table.insert(lonely, name)
			end
		end
		-- Связность (без учёта направления)
		local adj = {}
		for name, n in pairs(nodes) do
			adj[name] = adj[name] or {}
			for _, o in n.links do
				adj[name][o] = true
				adj[o] = adj[o] or {}
				adj[o][name] = true
			end
		end
		for name in pairs(adj) do
			local k = 0
			for _ in pairs(adj[name]) do
				k += 1
			end
			if k == 1 then
				dead += 1
			end
		end
		local first = next(adj)
		local seen, queue = {}, { first }
		if first then
			seen[first] = true
		end
		while #queue > 0 do
			local cur = table.remove(queue)
			for o in pairs(adj[cur] or {}) do
				if not seen[o] then
					seen[o] = true
					table.insert(queue, o)
				end
			end
		end
		local reached = 0
		for _ in pairs(seen) do
			reached += 1
		end
		local oneWay = 0
		for _, p in partsIn(map:FindFirstChild("Roads")) do
			if p:GetAttribute("Turnaround") == true then
				turn += 1
			end
			if p:GetAttribute("OneWay") == true then
				oneWay += 1
			end
		end
		add(count > 1 and "ok" or "error", "Дороги", "Точек дорог: " .. count)
		if #lonely > 0 then
			add("error", "Дороги", "Точки без связей: " .. table.concat(lonely, ", "))
		end
		add(reached == count and "ok" or "error", "Дороги", reached == count and "Все дороги связаны между собой" or string.format("Дороги разорваны: связано %d из %d точек", reached, count))
		add((turn + dead + oneWay) > 0 and "ok" or "warn", "Развороты", string.format("Кольцо (OneWay): %d точек, Turnaround: %d, тупиков: %d", oneWay, turn, dead))
		local uturn = 0
		for _, l in logs do
			if string.find(l.text, "Без разворота не доехать", 1, true) then
				uturn += 1
			end
		end
		add(uturn == 0 and "ok" or "error", "Развороты", uturn == 0 and "Никто не разворачивался посреди дороги" or ("Машины разворачивались посреди дороги: " .. uturn .. " раз — добавь кольцо или Turnaround"))

		-- Парковки
		local byType = {}
		for _, p in partsIn(map:FindFirstChild("Parking")) do
			local t = p:GetAttribute("Type") or "?"
			byType[t] = (byType[t] or 0) + 1
		end
		for _, t in { "Civilian", "Taxi", "Police", "Bus" } do
			local need = (VehicleConfig.Count[t] or 0) > 0
			local n = byType[t] or 0
			add((n > 0 or not need) and "ok" or "error", "Парковки", t .. ": " .. n)
		end
		local stops = partsIn(map:FindFirstChild("BusStops"))
		add(#stops >= 2 and "ok" or "error", "Автобус", "Остановок: " .. #stops .. (#stops < 2 and " (нужно минимум 2)" or ""))
		for _, s in stops do
			local node = s:GetAttribute("Node")
			if type(node) == "string" and not nodes[node] then
				add("error", "Автобус", "Остановка " .. s.Name .. ": точки дороги «" .. node .. "» нет")
			end
		end
		local zones = map:FindFirstChild("NPCPathZones")
		local cw, road = 0, 0
		for _, z in zones and zones:GetChildren() or {} do
			if z.Name == "Crosswalk" then
				cw += 1
			elseif z.Name == "Road" then
				road += 1
			end
		end
		local ownCw = #partsIn(map:FindFirstChild("Crosswalks"))
		add(road > 0 and "ok" or "warn", "Пешеходы", "Зон проезжей части: " .. road .. (road == 0 and " — жители будут ходить по дорогам" or ""))
		add(cw > 0 and "ok" or "warn", "Пешеходы", string.format("Переходов: %d%s", cw, ownCw == 0 and " (автоматически у перекрёстков — лучше поставить свои в TrafficSystem > Crosswalks)" or ""))
		-- Правосудие: отдел, суд, тюрьма
		for _, name in { "Mugshot", "Fingerprint", "Interview", "Holding" } do
			local found = false
			for _, p in partsIn(map:FindFirstChild("PoliceStation")) do
				if p.Name == name then
					found = true
				end
			end
			add(found and "ok" or "warn", "Правосудие", (found and "Есть метка " or "Нет метки ") .. name .. (found and "" or " (этап пройдёт у стойки дежурного)"))
		end
		local justice = workspace:FindFirstChild("JusticeSystem")
		local function jHas(group: string, prefix: string): number
			local g = justice and justice:FindFirstChild(group)
			local n = 0
			for _, p in partsIn(g) do
				if string.find(p.Name, "^" .. prefix) then
					n += 1
				end
			end
			return n
		end
		for _, item in { { "Court", "Judge" }, { "Court", "Dock" }, { "Court", "CourtDoor" }, { "Prison", "PrisonDoor" }, { "Prison", "PrisonCell" }, { "Prison", "PrisonExit" } } do
			local n = jHas(item[1], item[2])
			add(n > 0 and "ok" or "warn", "Правосудие", string.format("JusticeSystem > %s > %s: %d%s", item[1], item[2], n, n == 0 and " (без суда/тюрьмы приговор и срок — в участке)" or ""))
		end
		local calls = partsIn(map:FindFirstChild("PoliceCalls"))
		add(#calls > 0 and "ok" or "warn", "Полиция", "Вызовов (PoliceCalls): " .. #calls)
		local places = partsIn(map:FindFirstChild("Places"))
		local post = false
		for _, p in places do
			if (p:GetAttribute("PlaceName") or p.Name) == "Почта" then
				post = true
			end
		end
		add(#places > 0 and "ok" or "warn", "Места", "Мест (Places): " .. #places)
		add(post and "ok" or "warn", "Курьер", post and "Есть место «Почта»" or "Нет места «Почта» — посылки будут в случайном месте")
		local station = map:FindFirstChild("PoliceStation")
		local desk, cell, idle = 0, 0, 0
		for _, p in partsIn(station) do
			if string.find(p.Name, "^Desk") then
				desk += 1
			elseif string.find(p.Name, "^Cell") then
				cell += 1
			elseif string.find(p.Name, "^Idle") then
				idle += 1
			end
		end
		add(desk == 1 and "ok" or "error", "Полиция", "Desk (дежурный): " .. desk)
		add(cell >= 1 and "ok" or "error", "Полиция", "Cell (камера): " .. cell)
		add(idle >= 2 and "ok" or "warn", "Полиция", "Idle (кабинеты): " .. idle)
	end

	-- Шаблоны машин
	local templates = ServerStorage:FindFirstChild(VehicleConfig.TemplatesFolder)
	if not templates then
		add("warn", "Машины", "Нет ServerStorage > " .. VehicleConfig.TemplatesFolder .. " — машины-заглушки")
	else
		local byKind = {}
		for _, m in templates:GetChildren() do
			if m:IsA("Model") then
				local k = m:GetAttribute("VehicleType") or "?"
				byKind[k] = (byKind[k] or 0) + 1
				if not (m.PrimaryPart or m:FindFirstChild("Body")) then
					add("error", "Машины", m.Name .. ": нет Body")
				end
				if not m:FindFirstChild("Seat_Driver", true) then
					add("error", "Машины", m.Name .. ": нет Seat_Driver")
				end
			end
		end
		for _, k in { "Civilian", "Taxi", "Police", "Bus" } do
			add((byKind[k] or 0) > 0 and "ok" or "warn", "Машины", "Шаблонов " .. k .. ": " .. (byKind[k] or 0))
		end
	end

	-- Звуки
	for groupName, group in pairs(SoundConfig) do
		if type(group) == "table" and not group.Min then
			local empty = {}
			for key, def in pairs(group) do
				if type(def) == "table" and def.Id == "" then
					table.insert(empty, key)
				end
			end
			if #empty > 0 then
				add("warn", "Звуки", groupName .. ": без звука — " .. table.concat(empty, ", "))
			end
		end
	end

	-- Сохранение
	local ok = pcall(function()
		DataStoreService:GetDataStore("CityDebugCheck"):GetAsync("ping")
	end)
	add(ok and "ok" or "warn", "Сохранение", ok and "DataStore работает" or "DataStore недоступен (в Studio: Game Settings → Security → API Services)")

	return out
end

---------------------------------------------------------------------
-- Действия
---------------------------------------------------------------------

local function teleport(player: Player, position: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root then
		if humanoid and humanoid.SeatPart then
			humanoid.Sit = false
			task.wait(0.1)
		end
		character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	end
end

local function findTeleport(arg: string): (Vector3?, string?)
	local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local kind, name = string.match(arg, "^(%a+):?(.*)$")
	if not map then
		return nil, "Нет папки " .. VehicleConfig.MapFolder
	end
	if kind == "Desk" or kind == "Cell" then
		for _, p in partsIn(map:FindFirstChild("PoliceStation")) do
			if string.find(p.Name, "^" .. kind) then
				-- К дежурному — со стороны посетителей
				return kind == "Desk" and (p.Position + p.CFrame.LookVector * 5) or p.Position
			end
		end
		return nil, "Нет метки " .. kind
	elseif kind == "Place" then
		for _, p in partsIn(map:FindFirstChild("Places")) do
			if (p:GetAttribute("PlaceName") or p.Name) == name then
				return p.Position
			end
		end
		return nil, "Нет места " .. name
	elseif kind == "Stop" then
		local order = tonumber(name)
		for _, p in partsIn(map:FindFirstChild("BusStops")) do
			if p:GetAttribute("Order") == order or p.Name == name then
				return p.Position
			end
		end
		return nil, "Нет остановки " .. name
	elseif kind == "Node" then
		local nodes = Registry.debugNodes and Registry.debugNodes() or {}
		return nodes[name] and nodes[name].pos or nil, "Нет точки " .. name
	end
	return nil, "Не знаю, куда: " .. arg
end

local COOLDOWNS = { "InvisibilityConfig", "LaserConfig", "FlightConfig", "CubeConfig" }

local ACTIONS = {}

function ACTIONS.SetHour(player, arg)
	local h = tonumber(arg)
	if not h then
		return "Нужен час"
	end
	Lighting.ClockTime = h % 24
	return string.format("Время: %02d:%02d", math.floor(h), math.floor((h % 1) * 60))
end
function ACTIONS.TimeScale(player, arg)
	local x = tonumber(arg) or 1
	workspace:SetAttribute("TimeScale", x)
	return x == 0 and "Время на паузе" or ("Скорость времени ×" .. x)
end
function ACTIONS.Weather(player, arg)
	workspace:SetAttribute("ForceWeather", tostring(arg))
	return "Погода: " .. tostring(arg)
end
function ACTIONS.PoliceCall(player, arg)
	if not Registry.debugPoliceCall then
		return "Транспорт не запущен"
	end
	return Registry.debugPoliceCall(player, tonumber(arg) or 1)
end
function ACTIONS.Coins(player, arg)
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild(NPCConfig.CurrencyName)
	if not coins then
		return "Нет монет"
	end
	coins.Value += tonumber(arg) or 100
	return "Монет: " .. coins.Value
end
function ACTIONS.ResetCooldowns(player)
	for _, name in COOLDOWNS do
		local module = ReplicatedStorage:FindFirstChild(name)
		if module then
			player:SetAttribute(require(module).CooldownAttribute, 0)
		end
	end
	return "Кулдауны сброшены"
end
function ACTIONS.ResetCity(player)
	if Registry.cityReset then
		Registry.cityReset(player)
		return "Прогресс сброшен"
	end
	return "CityLifeServer не запущен"
end
function ACTIONS.AddStat(player, arg)
	local stat, n = string.match(tostring(arg), "^(%a+):?(%d*%.?%d*)$")
	if Registry.cityAddStat and stat then
		Registry.cityAddStat(player, stat, tonumber(n) or 1)
		return "+" .. (tonumber(n) or 1) .. " к " .. stat
	end
	return "Не получилось"
end
function ACTIONS.StartJob(player)
	if Registry.cityAction then
		Registry.cityAction(player, "Job")
		return "Заказ курьера"
	end
	return "CityLifeServer не запущен"
end
function ACTIONS.Heal(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	return "Здоровье восстановлено"
end
function ACTIONS.Teleport(player, arg)
	local pos, err = findTeleport(tostring(arg))
	if pos then
		teleport(player, pos)
		return "Телепорт: " .. tostring(arg)
	end
	return err
end
function ACTIONS.Wanted(player, arg)
	if not Registry.debugWanted then
		return "WantedServer не запущен"
	end
	Registry.debugWanted(player, tonumber(arg) or 0)
	return (tonumber(arg) or 0) > 0 and ("Розыск " .. tostring(arg) .. "★ — свидетель «позвонил» с твоего места") or "Розыск снят"
end
function ACTIONS.ArrestMe(player)
	if not Registry.arrestPlayer then
		return "WantedServer не запущен"
	end
	Registry.arrestPlayer(player)
	return "Арест: отдел → КПЗ → суд → тюрьма"
end
function ACTIONS.GiveWeapons(player)
	local p = Registry.weaponProfile and Registry.weaponProfile(player)
	if not p then
		return "WeaponServer не запущен"
	end
	for _, id in { "Pistol", "Rifle" } do
		p.owned[id] = true
		p.ammo[id] = 300
		p.mag[id] = nil
	end
	if Registry.blockWeapons then
		Registry.blockWeapons(player, false)
	end
	return "Пистолет и винтовка + патроны"
end
function ACTIONS.TeleportPos(player, arg)
	if typeof(arg) == "Vector3" then
		teleport(player, arg - Vector3.new(0, 3, 0))
		return "Персонаж перенесён к камере"
	end
	return "Нужна позиция"
end
function ACTIONS.TeleportTo(player, arg)
	if typeof(arg) == "Instance" and arg:IsDescendantOf(workspace) then
		local pivot = arg:IsA("Model") and arg:GetPivot() or (arg :: BasePart).CFrame
		teleport(player, pivot.Position + pivot.LookVector * 5)
		return "Телепорт к " .. arg.Name
	end
	return "Объект не найден"
end

---------------------------------------------------------------------
-- Отметки «проверено» (сохраняются)
---------------------------------------------------------------------

local testStore = nil
pcall(function()
	testStore = DataStoreService:GetDataStore("CityDebug_v1")
end)
local tested = {} -- [player] = { [key] = "ok"/"bug" }

local function loadTested(player: Player)
	local data = {}
	if testStore then
		local ok, result = pcall(function()
			return testStore:GetAsync("tests_" .. player.UserId)
		end)
		if ok and type(result) == "table" then
			data = result
		end
	end
	tested[player] = data
	return data
end

local function saveTested(player: Player)
	if testStore and tested[player] then
		pcall(function()
			testStore:SetAsync("tests_" .. player.UserId, tested[player])
		end)
	end
end

---------------------------------------------------------------------
-- Запросы клиента
---------------------------------------------------------------------

local lastRequest = {}

remote.OnServerEvent:Connect(function(player: Player, request: any, a: any, b: any)
	if not admins[player] then
		return
	end
	if request == "Hello" then
		remote:FireClient(player, "Hello", {
			logs = logs,
			tested = tested[player] or loadTested(player),
			placeNames = (function()
				local names = {}
				local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
				for _, p in partsIn(map and map:FindFirstChild("Places")) do
					table.insert(names, p:GetAttribute("PlaceName") or p.Name)
				end
				return names
			end)(),
		})
	elseif request == "Snapshot" then
		remote:FireClient(player, "Snapshot", {
			npcs = npcCache,
			cars = carCache,
			perf = perf(),
		})
	elseif request == "Journal" and typeof(a) == "Instance" then
		remote:FireClient(player, "Journal", { model = a, entries = journals[a] or {} })
	elseif request == "PathCheck" then
		task.spawn(runPathCheck, player)
	elseif request == "Diag" then
		local errors = {}
		for _, key in errorOrder do
			table.insert(errors, errorGroups[key])
		end
		local stuck = {}
		for _, h in stuckHistory do
			table.insert(stuck, { t = h.t, text = h.text, model = h.model, pos = h.pos, now = stuckNow[h.model] == true })
		end
		remote:FireClient(player, "Diag", {
			counters = counters,
			errors = errors,
			stuck = stuck,
			timings = lastTimings,
			stats = engineStats(),
			perf = perf(),
		})
	elseif request == "Nodes" then
		remote:FireClient(player, "Nodes", Registry.debugNodes and Registry.debugNodes() or {})
	elseif request == "Check" then
		remote:FireClient(player, "Check", runChecks())
	elseif request == "Action" and type(a) == "string" and ACTIONS[a] then
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.2 then
			return
		end
		lastRequest[player] = now
		local ok, result = pcall(ACTIONS[a], player, b)
		local text = ok and tostring(result) or ("Ошибка: " .. tostring(result))
		addLog("debug", "[Debug] " .. player.Name .. ": " .. a .. " → " .. text)
		remote:FireClient(player, "Result", text)
	elseif request == "Tested" and type(a) == "string" and #a < 120 then
		local t = tested[player] or loadTested(player)
		t[a] = (b == "ok" or b == "bug") and b or nil
		task.spawn(saveTested, player)
	end
end)

local function onPlayer(player: Player)
	if checkAdmin(player) then
		admins[player] = true
		player:SetAttribute("DebugAdmin", true)
	end
end
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	admins[player] = nil
	tested[player] = nil
	lastRequest[player] = nil
end)
