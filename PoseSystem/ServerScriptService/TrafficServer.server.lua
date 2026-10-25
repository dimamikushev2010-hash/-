-- Script: ServerScriptService > TrafficServer
-- Транспорт города:
--   * машины едут по дорогам (Workspace > TrafficSystem > Roads) без физики колёс:
--     плавно, по правой полосе, со скруглёнными поворотами и поворотниками;
--   * держат дистанцию, пропускают друг друга на перекрёстках, стоят на красный свет;
--   * тормозят и сигналят перед людьми;
--   * гражданские: жители ездят на своих машинах (дом ↔ работа, магазин...);
--   * поток: машины со своими водителями всё время катаются по городу;
--   * такси: возит жителей и игроков (за монеты);
--   * автобус: ходит по маршруту, на остановках люди выходят и заходят;
--   * полиция: выезжает на вызовы с мигалками и сиреной, офицеры заходят в здание.
-- Анимации дверей, багажника, фар, мигалок и звуки рисует VehicleClient по атрибутам.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))
local Defaults = require(script.Parent:WaitForChild("VehicleDefaults"))

local map = workspace:WaitForChild(Config.MapFolder, 30)
if not map then
	warn("[Traffic] Нет папки Workspace >", Config.MapFolder, "— машины не появятся. См. VEHICLE_SETUP.md")
	return
end
local roadsFolder = map:WaitForChild("Roads", 10)
if not roadsFolder then
	warn("[Traffic] В папке", Config.MapFolder, "нужна папка Roads с точками дорог")
	return
end
task.wait(1) -- даём карте и жителям загрузиться

local function folder(name: string): Instance?
	return map:FindFirstChild(name)
end

local vehiclesFolder = map:FindFirstChild(Config.VehiclesFolder) or Instance.new("Folder")
vehiclesFolder.Name = Config.VehiclesFolder
vehiclesFolder.Parent = map

local remote = ReplicatedStorage:FindFirstChild("VehicleRemote") or Instance.new("RemoteEvent")
remote.Name = "VehicleRemote"
remote.Parent = ReplicatedStorage

local rng = Random.new()
local function pick(list)
	return list[rng:NextInteger(1, #list)]
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
local function isNight(): boolean
	return workspace:GetAttribute("IsNight") == true
end
local function toast(player: Player, text: string)
	local dialog = ReplicatedStorage:FindFirstChild("NPCDialog")
	if dialog then
		dialog:FireClient(player, "Toast", text)
	end
end

---------------------------------------------------------------------
-- Группы столкновений: машины не цепляют дороги и друг друга, но толкают людей
---------------------------------------------------------------------

local VEHICLES, CHARACTERS = "Vehicles", "Characters"
pcall(function()
	PhysicsService:RegisterCollisionGroup(VEHICLES)
	PhysicsService:RegisterCollisionGroup(CHARACTERS)
	PhysicsService:CollisionGroupSetCollidable(VEHICLES, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(VEHICLES, VEHICLES, false)
	PhysicsService:CollisionGroupSetCollidable(VEHICLES, CHARACTERS, true)
	PhysicsService:CollisionGroupSetCollidable(VEHICLES, "NPCs", true)
end)

local function setCharacterGroup(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = CHARACTERS
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = CHARACTERS
		end
	end)
end
local function onPlayer(player: Player)
	player.CharacterAdded:Connect(setCharacterGroup)
	if player.Character then
		setCharacterGroup(player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end

local function hideMarker(part: BasePart)
	if Config.HideMarkersInGame then
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		for _, d in part:GetDescendants() do
			if d:IsA("Decal") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
	end
end

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundY(position: Vector3): number
	local ignore = { vehiclesFolder }
	local npcFolder = workspace:FindFirstChild(NPCConfig.FolderName)
	if npcFolder and npcFolder:FindFirstChild("Live") then
		table.insert(ignore, npcFolder.Live)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	surfaceParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), surfaceParams)
	return hit and hit.Position.Y or position.Y
end

---------------------------------------------------------------------
-- Дороги: граф точек
---------------------------------------------------------------------

local nodes = {} -- [имя] = { name, pos, links = { [имя] = true }, signal }

for _, p in roadsFolder:GetDescendants() do
	if p:IsA("BasePart") then
		if nodes[p.Name] then
			warn("[Traffic] Две точки дороги с одинаковым именем:", p.Name, "— переименуй одну")
		end
		nodes[p.Name] = { name = p.Name, part = p, pos = p.Position, links = {}, signal = nil }
		hideMarker(p)
	end
end

local function split(text: string): { string }
	local out = {}
	for item in string.gmatch(text, "[^,;]+") do
		item = string.gsub(item, "^%s+", "")
		item = string.gsub(item, "%s+$", "")
		if item ~= "" then
			table.insert(out, item)
		end
	end
	return out
end

for name, node in pairs(nodes) do
	local links = node.part:GetAttribute("Links")
	if type(links) == "string" then
		for _, other in split(links) do
			if nodes[other] then
				node.links[other] = true
				if node.part:GetAttribute("OneWay") ~= true then
					nodes[other].links[name] = true
				end
			else
				warn("[Traffic] Точка", name, "ссылается на несуществующую точку", other)
			end
		end
	end
	local group = node.part:GetAttribute("Signal")
	if type(group) == "string" then
		node.signal = {
			group = group,
			phase = node.part:GetAttribute("Phase") or 1,
			toward = node.part:GetAttribute("Toward"),
		}
	end
end

local function linkCount(node): number
	local n = 0
	for _ in pairs(node.links) do
		n += 1
	end
	return n
end

local nodeCount = 0
for _ in pairs(nodes) do
	nodeCount += 1
end
if nodeCount < 2 then
	warn("[Traffic] В папке Roads меньше двух точек — машинам негде ездить")
	return
end

local function nearestNode(position: Vector3): string
	local best, bestDist = nil, math.huge
	for name, node in pairs(nodes) do
		local d = (flat(node.pos - position)).Magnitude
		if d < bestDist and next(node.links) then
			best, bestDist = name, d
		end
	end
	return best
end

-- Точка, с которой начать путь: ближняя, но лучше впереди по ходу (без разворотов)
local function startNode(position: Vector3, look: Vector3): string
	local best, bestScore = nil, math.huge
	local forward = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	for name, node in pairs(nodes) do
		if next(node.links) then
			local rel = flat(node.pos - position)
			local score = rel.Magnitude
			if rel.Magnitude > 3 and rel.Unit:Dot(forward) < 0 then
				score += 45 -- точка за спиной: только если впереди ничего нет
			end
			if score < bestScore then
				best, bestScore = name, score
			end
		end
	end
	return best
end

-- Где можно развернуться: точка с Turnaround = true или тупик
local function canTurnAround(name: string): boolean
	local node = nodes[name]
	return node.part:GetAttribute("Turnaround") == true or linkCount(node) <= 1
end

-- Откуда машина подъехала к точке (сосед «за спиной»)
local function behindNode(from: string, look: Vector3): string?
	local forward = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	local best, bestDot = nil, -0.3
	for nb in pairs(nodes[from].links) do
		local dir = flat(nodes[nb].pos - nodes[from].pos)
		if dir.Magnitude > 0.1 then
			local d = dir.Unit:Dot(forward)
			if d < bestDot then
				best, bestDot = nb, d
			end
		end
	end
	return best
end

-- Кратчайший путь по точкам (Дейкстра) без разворотов посреди дороги:
-- вернуться в точку, из которой приехал, можно только там, где разрешён разворот
local function route(from: string, to: string, prev: string?, allowUTurns: boolean?): { string }?
	if from == to then
		return { from }
	end
	local function key(n: string, p: string?)
		return n .. "|" .. (p or "")
	end
	local startKey = key(from, prev)
	local dist, state, back, done = { [startKey] = 0 }, { [startKey] = { node = from, prev = prev } }, {}, {}
	while true do
		local bestKey, bestD = nil, math.huge
		for k, d in pairs(dist) do
			if not done[k] and d < bestD then
				bestKey, bestD = k, d
			end
		end
		if not bestKey then
			return nil
		end
		local st = state[bestKey]
		if st.node == to then
			local path = {}
			local k = bestKey
			while k do
				table.insert(path, 1, state[k].node)
				k = back[k]
			end
			return path
		end
		done[bestKey] = true
		for nb in pairs(nodes[st.node].links) do
			if allowUTurns or nb ~= st.prev or canTurnAround(st.node) then
				local nk = key(nb, st.node)
				local nd = bestD + (nodes[nb].pos - nodes[st.node].pos).Magnitude
				if nd < (dist[nk] or math.huge) then
					dist[nk] = nd
					state[nk] = { node = nb, prev = st.node }
					back[nk] = bestKey
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Светофоры
---------------------------------------------------------------------

local signalGroups = {} -- [группа] = { phases, current, mode, timer, lights = { {model, phase} } }

local function signalGroup(name: string)
	local g = signalGroups[name]
	if not g then
		g = { phases = 1, current = 1, mode = "green", timer = Config.GreenTime, lights = {} }
		signalGroups[name] = g
	end
	return g
end

for _, node in pairs(nodes) do
	if node.signal then
		local g = signalGroup(node.signal.group)
		g.phases = math.max(g.phases, node.signal.phase)
	end
end

local function lamp(model: Instance, name: string): BasePart?
	local p = model:FindFirstChild(name, true)
	return p and p:IsA("BasePart") and p or nil
end

local lightsFolder = folder("TrafficLights")
if lightsFolder then
	for _, m in lightsFolder:GetDescendants() do
		local group = m:GetAttribute("Group")
		if type(group) == "string" and (m:IsA("Model") or m:IsA("BasePart")) then
			local g = signalGroup(group)
			local phase = m:GetAttribute("Phase") or 1
			g.phases = math.max(g.phases, phase)
			local entry = { phase = phase, lamps = {} }
			for _, color in { "Red", "Yellow", "Green" } do
				local p = lamp(m, color)
				if p then
					entry.lamps[color] = { part = p, color = p.Color, material = p.Material }
				end
			end
			table.insert(g.lights, entry)
		end
	end
end

local function signalState(group: string, phase: number): string
	local g = signalGroups[group]
	if not g then
		return "green"
	end
	if g.mode == "allred" or g.current ~= phase then
		return "red"
	end
	return g.mode
end

local function paintLights(g)
	for _, entry in g.lights do
		local state = (g.mode == "allred" or g.current ~= entry.phase) and "red" or g.mode
		for color, l in pairs(entry.lamps) do
			local on = (color == "Red" and state == "red") or (color == "Yellow" and state == "yellow") or (color == "Green" and state == "green")
			l.part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
			l.part.Color = on and l.color or l.color:Lerp(Color3.new(0, 0, 0), 0.75)
		end
	end
end

for _, g in pairs(signalGroups) do
	paintLights(g)
end

local function updateSignals(dt: number)
	for _, g in pairs(signalGroups) do
		g.timer -= dt
		if g.timer <= 0 then
			if g.mode == "green" then
				g.mode, g.timer = "yellow", Config.YellowTime
			elseif g.mode == "yellow" then
				g.mode, g.timer = "allred", Config.AllRedTime
			else
				g.current = g.current % g.phases + 1
				g.mode, g.timer = "green", Config.GreenTime
			end
			paintLights(g)
		end
	end
end

---------------------------------------------------------------------
-- Маршрут машины: плавная линия по правой полосе
---------------------------------------------------------------------

-- Боковое смещение на правую полосу для точки с направлениями «до» и «после»
local function laneOffset(dirIn: Vector3?, dirOut: Vector3?, amount: number): Vector3
	local d = dirIn and dirOut and (dirIn + dirOut) or dirIn or dirOut
	if not d or d.Magnitude < 0.05 then
		d = dirIn or dirOut or Vector3.new(0, 0, -1)
	end
	d = d.Unit
	local right = d:Cross(Vector3.yAxis)
	local scale = 1
	if dirIn and dirOut then
		local ri = dirIn:Cross(Vector3.yAxis)
		scale = 1 / math.max(0.5, ri:Dot(right))
	end
	return right * amount * scale
end

--[[
	Строим трек:
	  startPos/startLook — откуда (позиция на земле)
	  pathNodes          — имена точек дороги
	  finish             — { spot = парковка } | { node = true, curb = bool }
	  pullOut            — машина стоит на парковке, сначала выезжает вперёд
]]
local function buildTrack(startPos: Vector3, startLook: Vector3, pathNodes: { string }, finish, pullOut: boolean)
	local ctrl = {} -- { pos, node = имя? }
	table.insert(ctrl, { pos = startPos })
	if pullOut then
		table.insert(ctrl, { pos = startPos + flat(startLook).Unit * 5 })
	end

	-- Точки дороги со смещением на правую полосу
	local raw = {}
	for _, name in pathNodes do
		table.insert(raw, nodes[name].pos)
	end
	local endAnchor = finish.spot and (finish.spot.pos - finish.spot.look * 7) or nil
	local lanes = {}
	for i, p in raw do
		local before = raw[i - 1] or (i == 1 and ctrl[#ctrl].pos) or nil
		local after = raw[i + 1] or endAnchor
		local dirIn = before and flat(p - before).Magnitude > 0.5 and flat(p - before).Unit or nil
		local dirOut = after and flat(after - p).Magnitude > 0.5 and flat(after - p).Unit or nil
		local curb = finish.curb == true and 3.5 or (type(finish.curb) == "number" and finish.curb or 0)
		local extra = i == #raw and curb or 0
		lanes[i] = p + laneOffset(dirIn, dirOut, Config.LaneOffset + extra)
	end

	-- Пропускаем точки «за спиной» у начала (чтобы не разворачиваться на месте)
	local first = 1
	local look = flat(startLook).Magnitude > 0.1 and flat(startLook).Unit or Vector3.new(0, 0, -1)
	while first < #lanes do
		local rel = flat(lanes[first] - ctrl[#ctrl].pos)
		if rel.Magnitude < 6 or rel.Unit:Dot(look) < -0.2 then
			first += 1
		else
			break
		end
	end
	for i = first, #lanes do
		table.insert(ctrl, { pos = lanes[i], node = pathNodes[i] })
	end
	if finish.spot then
		table.insert(ctrl, { pos = endAnchor })
		table.insert(ctrl, { pos = finish.spot.pos })
	end

	-- Убираем совпадающие точки (иначе направление не определить)
	local cleaned = { ctrl[1] }
	for i = 2, #ctrl do
		if (ctrl[i].pos - cleaned[#cleaned].pos).Magnitude > 0.5 then
			table.insert(cleaned, ctrl[i])
		elseif ctrl[i].node then
			cleaned[#cleaned].node = ctrl[i].node
		end
	end
	ctrl = cleaned

	-- Скругляем углы кривыми Безье и раскладываем на частые точки
	local samples = {} -- { p, s, slow }
	local nodeS = {} -- [индекс ctrl] = расстояние
	local s = 0
	local function add(p: Vector3, slow: boolean)
		local last = samples[#samples]
		if last then
			local d = (p - last.p).Magnitude
			if d < 0.05 then
				return
			end
			s += d
		end
		table.insert(samples, { p = p, s = s, slow = slow })
	end
	local function line(a: Vector3, b: Vector3, slow: boolean)
		local n = math.max(1, math.ceil((b - a).Magnitude / 2))
		for k = 1, n do
			add(a:Lerp(b, k / n), slow)
		end
	end

	local events = { stops = {}, reserves = {}, indicators = {}, corners = {} }
	add(ctrl[1].pos, false)
	local cursor = ctrl[1].pos
	for i = 2, #ctrl - 1 do
		local a, c, b = ctrl[i - 1].pos, ctrl[i].pos, ctrl[i + 1].pos
		local din, dout = flat(c - a), flat(b - c)
		local r = math.min(Config.CornerRadius, (c - a).Magnitude / 2, (b - c).Magnitude / 2)
		local cutIn = c + (a - c).Unit * r
		local cutOut = c + (b - c).Unit * r
		local angle = 0
		if din.Magnitude > 0.1 and dout.Magnitude > 0.1 then
			angle = math.deg(math.acos(math.clamp(din.Unit:Dot(dout.Unit), -1, 1)))
		end
		local sharp = angle > 25
		line(cursor, cutIn, false)
		local sStart = s
		for k = 1, 8 do
			local t = k / 8
			local p = cutIn:Lerp(c, t):Lerp(c:Lerp(cutOut, t), t)
			add(p, sharp)
			if k == 4 then
				nodeS[i] = s
			end
		end
		cursor = cutOut
		if sharp then
			table.insert(events.corners, { s0 = sStart - 8, s1 = s })
			if ctrl[i].node and angle > 35 then
				local side = din.Unit:Cross(dout.Unit).Y > 0 and "L" or "R"
				table.insert(events.indicators, { s0 = nodeS[i] - 25, s1 = nodeS[i] + 4, side = side })
			end
		end
	end
	line(cursor, ctrl[#ctrl].pos, false)
	nodeS[1] = 0
	nodeS[#ctrl] = s

	-- События: светофоры и перекрёстки
	for i, c in ctrl do
		if c.node then
			local node = nodes[c.node]
			local nextCtrl = ctrl[i + 1]
			local si = nodeS[i] or 0
			if node.signal and nextCtrl and nextCtrl.node == node.signal.toward then
				table.insert(events.stops, { s = si - 1, group = node.signal.group, phase = node.signal.phase })
			end
			if linkCount(node) >= 3 then
				table.insert(events.reserves, { node = c.node, enter = si - 8, exit = si + 8 })
			end
		end
	end

	return { samples = samples, length = s, events = events, index = 1 }
end

local function trackPos(track, s: number): Vector3
	local samples = track.samples
	local i = track.index
	while i < #samples and samples[i + 1].s < s do
		i += 1
	end
	while i > 1 and samples[i].s > s do
		i -= 1
	end
	track.index = i
	local a, b = samples[i], samples[i + 1]
	if not b then
		return a.p
	end
	local t = (s - a.s) / math.max(0.001, b.s - a.s)
	return a.p:Lerp(b.p, math.clamp(t, 0, 1))
end

---------------------------------------------------------------------
-- Парковки, остановки, вызовы, места
---------------------------------------------------------------------

local spots = { Civilian = {}, Taxi = {}, Bus = {}, Police = {} }
local parkingFolder = folder("Parking")
if parkingFolder then
	for _, p in parkingFolder:GetDescendants() do
		if p:IsA("BasePart") then
			local kind = p:GetAttribute("Type") or "Civilian"
			if spots[kind] then
				local look = flat(p.CFrame.LookVector)
				table.insert(spots[kind], {
					part = p,
					pos = Vector3.new(p.Position.X, p.Position.Y, p.Position.Z),
					look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1),
					zone = p:GetAttribute("Zone"),
					kind = kind,
					car = nil,
				})
				hideMarker(p)
			end
		end
	end
end

local function freeSpot(kind: string, near: Vector3, exclude): any
	local best, bestDist = nil, math.huge
	for _, spot in spots[kind] do
		if spot ~= exclude and not spot.car then
			local d = (spot.pos - near).Magnitude
			if d < bestDist then
				best, bestDist = spot, d
			end
		end
	end
	return best
end

local busStops = {}
local stopsFolder = folder("BusStops")
if stopsFolder then
	for _, p in stopsFolder:GetDescendants() do
		if p:IsA("BasePart") then
			local nodeName = p:GetAttribute("Node")
			table.insert(busStops, {
				part = p,
				pos = p.Position,
				order = p:GetAttribute("Order") or #busStops + 1,
				name = p:GetAttribute("StopName") or p.Name,
				node = (type(nodeName) == "string" and nodes[nodeName]) and nodeName or nearestNode(p.Position),
			})
			hideMarker(p)
		end
	end
	table.sort(busStops, function(a, b)
		return a.order < b.order
	end)
end

local policeCalls = {}
local callsFolder = folder("PoliceCalls")
if callsFolder then
	for _, p in callsFolder:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(policeCalls, { part = p, pos = p.Position, zone = p:GetAttribute("Zone") })
			hideMarker(p)
		end
	end
end

-- Места для такси: Places или центры зон жителей
local places = {}
local placesFolder = folder("Places")
if placesFolder then
	for _, p in placesFolder:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(places, { name = p:GetAttribute("PlaceName") or p.Name, pos = p.Position })
			hideMarker(p)
		end
	end
end
if #places == 0 then
	local npcFolder = workspace:FindFirstChild(NPCConfig.FolderName)
	local pointsFolder = npcFolder and npcFolder:FindFirstChild("Points")
	if pointsFolder then
		local sums = {}
		for _, p in pointsFolder:GetDescendants() do
			if p:IsA("BasePart") then
				local zone = p:GetAttribute("Zone") or NPCConfig.OutdoorZone
				sums[zone] = sums[zone] or { sum = Vector3.zero, n = 0 }
				sums[zone].sum += p.Position
				sums[zone].n += 1
			end
		end
		for zone, data in pairs(sums) do
			table.insert(places, { name = zone == NPCConfig.OutdoorZone and "Улица" or zone, pos = data.sum / data.n })
		end
	end
end

---------------------------------------------------------------------
-- Машины: сборка из шаблона
---------------------------------------------------------------------

local templates = { Civilian = {}, Taxi = {}, Bus = {}, Police = {} }
local templatesFolder = ServerStorage:FindFirstChild(Config.TemplatesFolder)
if templatesFolder then
	for _, m in templatesFolder:GetDescendants() do
		if m:IsA("Model") then
			local kind = m:GetAttribute("VehicleType")
			if templates[kind] then
				table.insert(templates[kind], m)
			end
		end
	end
end
local defaults = nil
for kind, list in pairs(templates) do
	if #list == 0 then
		defaults = defaults or Defaults.Build()
		for _, m in defaults do
			if m:GetAttribute("VehicleType") == kind then
				table.insert(list, m)
			end
		end
	end
end

local cars = {} -- список машин
local nextId = 0

-- Группа детали: дверь/багажник (по имени или атрибуту PartOf), колесо, или кузов
local function groupOf(p: BasePart, model: Model): (string?, string?)
	local partOf = p:GetAttribute("PartOf")
	if type(partOf) == "string" then
		return partOf, string.find(partOf, "^Trunk") and "Trunk" or "Door"
	end
	local inst: Instance? = p
	while inst and inst ~= model do
		if string.find(inst.Name, "^Door") then
			return inst.Name, "Door"
		elseif string.find(inst.Name, "^Trunk") then
			return inst.Name, "Trunk"
		elseif string.find(inst.Name, "^Wheel") and inst:IsA("BasePart") then
			return nil, "Wheel"
		end
		inst = inst.Parent
	end
	return nil, nil
end

local function bodyBounds(body: BasePart, parts: { BasePart })
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, p in parts do
		local half = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = body.CFrame:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)))
					minV = minV:Min(corner)
					maxV = maxV:Max(corner)
				end
			end
		end
	end
	return minV, maxV
end

local function setupVehicle(model: Model, kind: string)
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		warn("[Traffic] У шаблона", model.Name, "нет детали Body (PrimaryPart)")
		return nil
	end
	model.PrimaryPart = body

	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local minV, maxV = bodyBounds(body, parts)

	-- Покраска гражданских
	if kind == "Civilian" then
		local color = pick(Config.PaintColors)
		for _, p in parts do
			if p:GetAttribute("Paint") then
				p.Color = color
			end
		end
	end

	local groups = {} -- [имя] = { kind, parts }
	local wheels, seats = {}, {}
	for _, p in parts do
		p.Anchored = false
		p.CollisionGroup = VEHICLES
		if p ~= body then
			p.Massless = true
		end
		if p:IsA("Seat") then
			p.Disabled = true
			p.CanCollide = false
			table.insert(seats, p)
		end
		local groupName, groupKind = groupOf(p, model)
		if groupKind == "Wheel" then
			p.CanCollide = false
			table.insert(wheels, p)
		elseif groupName then
			p.CanCollide = false
			groups[groupName] = groups[groupName] or { kind = groupKind, parts = {} }
			table.insert(groups[groupName].parts, p)
		elseif p ~= body and not p:IsA("Seat") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
		end
	end
	for _, s in seats do
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = s
		w.Parent = s
	end

	-- Двери и багажник: шарнир Motor6D, анимацию крутит клиент
	local doors = {}
	for name, g in pairs(groups) do
		local main = g.parts[1]
		for _, p in g.parts do
			if p.Size.Magnitude > main.Size.Magnitude then
				main = p
			end
		end
		for _, p in g.parts do
			if p ~= main then
				local w = Instance.new("WeldConstraint")
				w.Part0 = main
				w.Part1 = p
				w.Parent = p
			end
		end
		local gMin, gMax = bodyBounds(body, g.parts)
		local center = (gMin + gMax) / 2
		local hinge, axis, angle, slide
		local hingeType = main:GetAttribute("Hinge") or (g.parts[1].Parent and g.parts[1].Parent:GetAttribute("Hinge")) or "Front"
		if g.kind == "Trunk" then
			hinge = Vector3.new(center.X, gMax.Y, gMin.Z) -- передний верхний край
			axis = Vector3.xAxis
			angle = -math.rad(Config.TrunkOpenAngle)
		elseif hingeType == "Slide" then
			local side = center.X >= 0 and 1 or -1
			slide = Vector3.new(side * 0.35, 0, Config.SlideDistance)
		else
			local side = center.X >= 0 and 1 or -1
			local back = hingeType == "Back"
			hinge = Vector3.new(side > 0 and gMax.X or gMin.X, center.Y, back and gMax.Z or gMin.Z)
			axis = Vector3.yAxis
			angle = math.rad(Config.DoorOpenAngle) * side * (back and -1 or 1)
		end

		local motor = Instance.new("Motor6D")
		motor.Name = "Joint_" .. name
		motor.Part0 = body
		motor.Part1 = main
		motor.C0 = body.CFrame:ToObjectSpace(main.CFrame)
		motor:SetAttribute("Group", name)
		motor:SetAttribute("Kind", g.kind)
		local mainCF = main.CFrame
		if hinge then
			local hingeWorld = body.CFrame:PointToWorldSpace(hinge)
			motor:SetAttribute("HingeLocal", mainCF:PointToObjectSpace(hingeWorld))
			motor:SetAttribute("AxisLocal", mainCF:VectorToObjectSpace(body.CFrame:VectorToWorldSpace(axis)))
			motor:SetAttribute("OpenAngle", angle)
		else
			motor:SetAttribute("SlideLocal", mainCF:VectorToObjectSpace(body.CFrame:VectorToWorldSpace(slide)))
		end
		motor.Parent = body
		doors[name] = { motor = motor, center = center }
		model:SetAttribute(name, false)
	end

	-- Колёса: вращает клиент
	for i, w in wheels do
		local motor = Instance.new("Motor6D")
		motor.Name = "Wheel_" .. i
		motor.Part0 = body
		motor.Part1 = w
		motor.C0 = body.CFrame:ToObjectSpace(w.CFrame)
		local axle = w.CFrame:VectorToObjectSpace(body.CFrame.RightVector)
		local a = Vector3.new(math.abs(axle.X), math.abs(axle.Y), math.abs(axle.Z))
		local radius = (w.Size.X * (1 - a.X) + w.Size.Y * (1 - a.Y) + w.Size.Z * (1 - a.Z)) / 4
		motor:SetAttribute("Kind", "Wheel")
		motor:SetAttribute("AxleLocal", axle)
		motor:SetAttribute("Radius", math.max(0.2, radius))
		motor.Parent = body
	end

	if #seats == 0 then
		warn("[Traffic] В шаблоне", model.Name, "нет мест Seat_Driver / Seat_1... — машина не появится")
		return nil
	end

	-- Места
	table.sort(seats, function(a, b)
		return a.Name < b.Name
	end)
	local driverSeat = model:FindFirstChild("Seat_Driver", true)
	if not driverSeat then
		driverSeat = seats[1]
	end
	local passengerSeats = {}
	for _, s in seats do
		if s ~= driverSeat then
			table.insert(passengerSeats, s)
		end
	end

	-- Удержание: «жёсткие» выравниватели ведут машину по треку
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = body
	local alignPos = Instance.new("AlignPosition")
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.Attachment0 = attachment
	alignPos.RigidityEnabled = true
	alignPos.Parent = body
	local alignRot = Instance.new("AlignOrientation")
	alignRot.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignRot.Attachment0 = attachment
	alignRot.RigidityEnabled = true
	alignRot.Parent = body

	nextId += 1
	model:SetAttribute("VehicleType", kind)
	model:SetAttribute("VehicleId", nextId)
	return {
		id = nextId,
		model = model,
		body = body,
		kind = kind,
		doors = doors,
		driverSeat = driverSeat,
		seats = passengerSeats,
		occupants = {},
		ride = -minV.Y, -- высота центра кузова над землёй
		length = maxV.Z - minV.Z,
		width = maxV.X - minV.X,
		alignPos = alignPos,
		alignRot = alignRot,
		pos = body.Position,
		look = body.CFrame.LookVector,
		v = 0,
		s = 0,
		track = nil,
		state = "parked",
		onRoad = false,
		held = {},
		honkAt = 0,
		stuck = 0,
	}
end

local function placeCar(car, position: Vector3, look: Vector3)
	look = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	local cf = CFrame.lookAt(position, position + look) * CFrame.new(0, car.ride, 0)
	car.model:PivotTo(cf)
	car.alignPos.Position = cf.Position
	car.alignRot.CFrame = cf.Rotation
	car.pos = position
	car.look = look
end

local function spawnCar(kind: string, spot)
	if #cars >= Config.MaxVehicles or #templates[kind] == 0 then
		return nil
	end
	local model = pick(templates[kind]):Clone()
	local car = setupVehicle(model, kind)
	if not car then
		model:Destroy()
		return nil
	end
	model.Parent = vehiclesFolder
	car.homeSpot = spot
	car.spot = spot
	if spot then
		spot.car = car
		local ground = groundY(spot.pos)
		placeCar(car, Vector3.new(spot.pos.X, ground, spot.pos.Z), spot.look)
	end
	pcall(function()
		car.body:SetNetworkOwner(nil)
	end)
	table.insert(cars, car)
	return car
end

---------------------------------------------------------------------
-- Езда
---------------------------------------------------------------------

local reservations = {} -- [точка-перекрёсток] = машина

local function releaseAll(car)
	for node in pairs(car.held) do
		if reservations[node] == car then
			reservations[node] = nil
		end
	end
	table.clear(car.held)
end

local function honk(car)
	local now = os.clock()
	if now - car.honkAt > Config.HonkCooldown then
		car.honkAt = now
		car.model:SetAttribute("HornId", (car.model:GetAttribute("HornId") or 0) + 1)
	end
end

local function humansNear(position: Vector3, radius: number)
	local list = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - position).Magnitude < radius then
			table.insert(list, r)
		end
	end
	for model, npc in pairs(Registry.npcs) do
		if npc.alive and not npc.inVehicle and npc.hrp and (npc.hrp.Position - position).Magnitude < radius then
			table.insert(list, npc.hrp)
		end
	end
	return list
end

local function isPassenger(car, hrp: BasePart): boolean
	for _, who in pairs(car.occupants) do
		if (typeof(who) == "Instance" and who.Character and who.Character:FindFirstChild("HumanoidRootPart") == hrp)
			or (type(who) == "table" and who.hrp == hrp) then
			return true
		end
	end
	return false
end

local function finishDrive(car, ok: boolean)
	car.track = nil
	car.v = 0
	releaseAll(car)
	car.model:SetAttribute("Indicator", "")
	car.model:SetAttribute("Brake", true)
	car.driveOk = ok
	car.driveDone = true
end

-- Ехать: spec = { spot = парковка } или { node = имя, curb = true }
local function drive(car, spec): boolean
	local fromNode = startNode(car.pos, car.look)
	local toNode = spec.spot and nearestNode(spec.spot.pos) or spec.node
	local path = fromNode and toNode and route(fromNode, toNode, behindNode(fromNode, car.look))
	if not path and fromNode and toNode and Config.AllowUTurnFallback then
		path = route(fromNode, toNode, nil, true)
		if path then
			warn("[Traffic] Без разворота не доехать от", fromNode, "до", toNode, "— добавь кольцо или точку с Turnaround = true")
		end
	end
	if not path then
		warn("[Traffic] Нет пути от", fromNode, "до", toNode, "— проверь атрибуты Links у точек дороги")
		return false
	end
	local pullOut = car.spot ~= nil
	if car.spot and car.spot.car == car then
		car.spot.car = nil
	end
	car.spot = nil
	if spec.spot then
		spec.spot.car = car -- бронь места
	end
	car.debugTo = toNode
	car.debugPath = path
	car.track = buildTrack(car.pos, car.look, path, spec, pullOut)
	car.s = 0
	car.stuck = 0
	car.onRoad = true
	car.driveDone = false
	car.maxSpeed = (car.kind == "Police" and car.model:GetAttribute("Siren")) and Config.PoliceSpeed or Config.CitySpeed
	-- В дождь и туман — медленнее
	local weather = ReplicatedStorage:FindFirstChild("WeatherConfig")
	if weather and ((workspace:GetAttribute("Rain") or 0) > 0.3 or (workspace:GetAttribute("Fog") or 0) > 0.5) then
		car.maxSpeed *= require(weather).CarSpeedInRain or 0.8
	end
	car.model:SetAttribute("Brake", false)
	while not car.driveDone do
		task.wait(0.1)
	end
	if spec.spot and car.driveOk then
		car.spot = spec.spot
		car.onRoad = false
	elseif spec.spot then
		spec.spot.car = nil
	end
	return car.driveOk
end

-- Застряла надолго — исчезает и появляется на своей парковке
local function rescue(car)
	local home = car.homeSpot
	if home and home.car and home.car ~= car then
		home = freeSpot(car.kind, car.pos, nil)
	end
	if home then
		local ground = groundY(home.pos)
		placeCar(car, Vector3.new(home.pos.X, ground, home.pos.Z), home.look)
		home.car = car
		car.spot = home
		car.onRoad = false
	end
	finishDrive(car, false)
end

local function stepCar(car, dt: number)
	local track = car.track
	if not track then
		car.v = 0
		return
	end
	local model = car.model
	local target = car.maxSpeed or Config.CitySpeed
	local remaining = track.length - car.s
	local function limitTo(distance: number)
		target = math.min(target, math.sqrt(2 * Config.Braking * math.max(0, distance)))
	end
	limitTo(remaining - 0.3)

	-- Повороты: заранее сбавляем скорость
	for _, c in track.events.corners do
		if car.s < c.s1 and c.s0 - car.s < 20 then
			local before = math.max(0, c.s0 - car.s)
			target = math.min(target, math.sqrt(Config.TurnSpeed ^ 2 + 2 * Config.Braking * before))
		end
	end

	-- Светофоры
	for _, stop in track.events.stops do
		local d = stop.s - car.s
		if d > -0.5 and d < 70 then
			local state = signalState(stop.group, stop.phase)
			local canStop = d > (car.v * car.v) / (2 * Config.Braking) + 0.5
			if state == "red" or (state == "yellow" and canStop) then
				limitTo(d - 0.5)
			end
			break
		end
	end

	-- Перекрёстки: один проезжает, остальные ждут
	for _, r in track.events.reserves do
		if car.s > r.exit then
			if car.held[r.node] then
				car.held[r.node] = nil
				if reservations[r.node] == car then
					reservations[r.node] = nil
				end
			end
		elseif car.s < r.enter + 1 and r.enter - car.s < 14 then
			local owner = reservations[r.node]
			if owner == nil or owner == car or not owner.track then
				reservations[r.node] = car
				car.held[r.node] = true
			else
				limitTo(r.enter - car.s - 0.5)
				break
			end
		end
	end

	-- Машина впереди
	local look = car.look
	local right = look:Cross(Vector3.yAxis)
	car.blockedBy = nil
	for _, other in cars do
		if other ~= car and (other.track or other.onRoad) then
			local rel = flat(other.pos - car.pos)
			local forward = rel:Dot(look)
			local lateral = math.abs(rel:Dot(right))
			if forward > 0 and forward < 45 and lateral < (car.width + other.width) / 2 - 0.3 then
				-- Взаимная блокировка: пропускает тот, у кого номер больше
				if not (other.blockedBy == car and car.id < other.id) then
					local gap = forward - (car.length + other.length) / 2 - Config.SafeGap
					limitTo(gap)
					car.blockedBy = other
				end
			end
		end
	end

	-- Люди на дороге: тормозим и сигналим
	local reach = Config.PedestrianStop + car.length / 2
	for _, hrp in humansNear(car.pos, reach + 4) do
		if not isPassenger(car, hrp) then
			local rel = flat(hrp.Position - car.pos)
			local forward = rel:Dot(look)
			local lateral = math.abs(rel:Dot(right))
			if forward > 0 and forward < reach and lateral < car.width / 2 + 0.6 then
				limitTo(forward - car.length / 2 - 2.5)
				if car.v < 3 then
					honk(car)
				end
			end
		end
	end

	-- Разгон и торможение
	local dv = target - car.v
	if dv > 0 then
		car.v = math.min(target, car.v + Config.Acceleration * dt)
	else
		car.v = math.max(target, car.v - Config.Braking * dt)
	end
	car.s = math.min(track.length, car.s + car.v * dt)

	local pos = trackPos(track, car.s)
	local ahead = trackPos(track, math.min(track.length, car.s + 2.5))
	local dir = ahead - pos
	if dir.Magnitude > 0.05 then
		car.look = flat(dir).Magnitude > 0.05 and flat(dir).Unit or car.look
	end
	car.pos = pos
	local lookFull = dir.Magnitude > 0.05 and dir.Unit or car.look
	local cf = CFrame.lookAt(pos, pos + lookFull) * CFrame.new(0, car.ride, 0)
	car.alignPos.Position = cf.Position
	car.alignRot.CFrame = cf.Rotation

	-- Стоп-сигналы и поворотники
	local braking = dv < -0.5 or car.v < 0.5
	if model:GetAttribute("Brake") ~= braking then
		model:SetAttribute("Brake", braking)
	end
	local indicator = ""
	for _, ind in track.events.indicators do
		if car.s >= ind.s0 and car.s <= ind.s1 then
			indicator = ind.side
			break
		end
	end
	if model:GetAttribute("Indicator") ~= indicator then
		model:SetAttribute("Indicator", indicator)
	end

	-- Приехали / застряли
	if remaining < 0.3 and car.v < 0.5 then
		finishDrive(car, true)
	elseif car.v < 0.3 then
		car.stuck += dt
		if car.stuck > Config.StuckRespawnTime then
			warn("[Traffic] Машина", model.Name, "застряла — возвращаю на парковку")
			rescue(car)
		end
	else
		car.stuck = 0
	end
end

local lightTimer = 0
RunService.Heartbeat:Connect(function(dt)
	updateSignals(dt)
	for _, car in cars do
		if car.model.Parent then
			stepCar(car, dt)
		end
	end
	lightTimer += dt
	if lightTimer > 0.25 then
		lightTimer = 0
		local night = isNight()
		for _, car in cars do
			local model = car.model
			local siren = model:GetAttribute("Siren") == true
			local engine = car.occupants[car.driverSeat] ~= nil
			local badWeather = (workspace:GetAttribute("Rain") or 0) > 0.3 or (workspace:GetAttribute("Fog") or 0) > 0.4
			local lights = engine and (night or siren or badWeather) or false
			if model:GetAttribute("Headlights") ~= lights then
				model:SetAttribute("Headlights", lights)
			end
			if model:GetAttribute("Engine") ~= engine then
				model:SetAttribute("Engine", engine)
			end
			local speed = math.floor(car.v * 10) / 10
			if model:GetAttribute("Speed") ~= speed then
				model:SetAttribute("Speed", speed)
			end
		end
	end
end)

---------------------------------------------------------------------
-- Посадка и высадка
---------------------------------------------------------------------

local function doorFor(car, seat: BasePart): string?
	local seatLocal = car.body.CFrame:PointToObjectSpace(seat.Position)
	local best, bestDist = nil, math.huge
	for name, d in pairs(car.doors) do
		local dist = (Vector3.new(d.center.X, 0, d.center.Z) - Vector3.new(seatLocal.X, 0, seatLocal.Z)).Magnitude
		if dist < bestDist then
			best, bestDist = name, dist
		end
	end
	return best
end

local function setDoor(car, name: string?, open: boolean)
	if name then
		car.model:SetAttribute(name, open)
	end
end

-- Где встать у двери (снаружи, на земле)
local function doorSide(car, seat: BasePart, forceSide: number?): Vector3
	local seatLocal = car.body.CFrame:PointToObjectSpace(seat.Position)
	local side = forceSide or (seatLocal.X >= 0 and 1 or -1)
	local out = car.body.CFrame:PointToWorldSpace(Vector3.new(side * (car.width / 2 + 1.8), 0, seatLocal.Z))
	return Vector3.new(out.X, groundY(out), out.Z)
end

local function freeSeat(car): BasePart?
	for _, s in car.seats do
		if not car.occupants[s] and not s.Occupant then
			return s
		end
	end
	return nil
end

local function seatNPC(npc, car, seat: BasePart)
	local door = doorFor(car, seat)
	setDoor(car, door, true)
	task.wait(0.55)
	if not npc.alive then
		setDoor(car, door, false)
		return false
	end
	local hrp = npc.hrp
	local top = seat.Position + seat.CFrame.UpVector * (seat.Size.Y / 2)
	local pos = top + Vector3.new(0, hrp.Size.Y / 2 + 0.3, 0)
	local target = CFrame.lookAt(pos, pos + car.body.CFrame.LookVector)
	npc.humanoid.PlatformStand = true
	hrp.CFrame = target
	local weld = Instance.new("Weld")
	weld.Name = "VehicleSeatWeld"
	weld.Part0 = seat
	weld.Part1 = hrp
	weld.C0 = seat.CFrame:ToObjectSpace(target)
	weld.Parent = seat
	npc.vehicleWeld = weld
	npc.inVehicle = car
	npc.vehicleSeat = seat
	car.occupants[seat] = npc
	if npc.prompt then
		npc.prompt.Enabled = false
	end
	Registry.setPose(npc, "Chair")
	task.wait(0.4)
	setDoor(car, door, false)
	return true
end

local function unseatNPC(npc, forceSide: number?)
	local car, seat = npc.inVehicle, npc.vehicleSeat
	if not car or not seat then
		return
	end
	local door = doorFor(car, seat)
	setDoor(car, door, true)
	task.wait(0.45)
	if npc.vehicleWeld then
		npc.vehicleWeld:Destroy()
		npc.vehicleWeld = nil
	end
	car.occupants[seat] = nil
	npc.inVehicle = nil
	npc.vehicleSeat = nil
	if npc.alive then
		local out = doorSide(car, seat, forceSide)
		local height = npc.humanoid.HipHeight + npc.hrp.Size.Y / 2 + 0.1
		local pos = out + Vector3.new(0, height, 0)
		npc.hrp.CFrame = CFrame.lookAt(pos, pos + car.look)
		npc.humanoid.PlatformStand = false
		Registry.setPose(npc, "Stand")
		if npc.prompt and not npc.officer then
			npc.prompt.Enabled = true
		end
	end
	task.wait(0.35)
	setDoor(car, door, false)
end

local function seatPlayer(player: Player, car, seat)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local door = doorFor(car, seat)
	setDoor(car, door, true)
	task.wait(0.4)
	seat.Disabled = false
	seat:Sit(humanoid)
	car.occupants[seat] = player
	local conn
	conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			conn:Disconnect()
			if car.occupants[seat] == player then
				car.occupants[seat] = nil
			end
			seat.Disabled = true
		end
	end)
	task.delay(0.4, function()
		setDoor(car, door, false)
	end)
	return true
end

local function unseatPlayer(player: Player, car, forceSide: number?)
	for seat, who in pairs(car.occupants) do
		if who == player then
			local door = doorFor(car, seat)
			setDoor(car, door, true)
			task.wait(0.35)
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
			car.occupants[seat] = nil
			seat.Disabled = true
			local character = player.Character
			if character then
				local out = doorSide(car, seat, forceSide)
				character:PivotTo(CFrame.lookAt(out + Vector3.new(0, 3.2, 0), out + Vector3.new(0, 3.2, 0) + car.look))
			end
			task.delay(0.4, function()
				setDoor(car, door, false)
			end)
			return
		end
	end
end

---------------------------------------------------------------------
-- Гражданские машины и поездки жителей
---------------------------------------------------------------------

local function carTrip(npc, car, target: Vector3): boolean
	car.state = "busy"
	local seat = car.driverSeat
	if not Registry.walkTo(npc, doorSide(car, seat)) then
		car.state = "parked"
		return false
	end
	-- Иногда сначала кладёт что-то в багажник
	if car.doors.Trunk and rng:NextNumber() < Config.TrunkChance then
		local behind = car.pos - car.look * (car.length / 2 + 1.5)
		if Registry.walkTo(npc, Vector3.new(behind.X, groundY(behind), behind.Z)) then
			Registry.face(npc, car.look)
			setDoor(car, "Trunk", true)
			task.wait(1.4)
			setDoor(car, "Trunk", false)
			task.wait(0.4)
			Registry.walkTo(npc, doorSide(car, seat))
		end
	end
	if not npc.alive or not seatNPC(npc, car, seat) then
		car.state = "parked"
		return false
	end
	local dest = freeSpot("Civilian", target, car.spot)
	local ok = false
	if dest then
		ok = drive(car, { spot = dest })
	end
	unseatNPC(npc)
	car.state = "parked"
	return ok
end

local function freeTaxi()
	for _, car in cars do
		if car.kind == "Taxi" and car.state == "parked" then
			return car
		end
	end
	return nil
end

local function taxiReturn(car)
	local stand = freeSpot("Taxi", car.pos, nil) or car.homeSpot
	if stand then
		drive(car, { spot = stand })
	end
	car.state = "parked"
	car.model:SetAttribute("TaxiBusy", false)
end

local function taxiTrip(npc, target: Vector3): boolean
	local taxi = freeTaxi()
	if not taxi then
		return false
	end
	taxi.state = "busy"
	taxi.model:SetAttribute("TaxiBusy", true)
	local pickupNode = nearestNode(npc.hrp.Position)
	Registry.say(npc, "Такси!")
	-- Такси едет, житель идёт к дороге
	local arrived = false
	task.spawn(function()
		arrived = drive(taxi, { node = pickupNode, curb = 5 })
	end)
	local away = flat(npc.hrp.Position - nodes[pickupNode].pos)
	Registry.walkTo(npc, nodes[pickupNode].pos + (away.Magnitude > 0.5 and away.Unit or Vector3.xAxis) * 6)
	local deadline = os.clock() + 70
	while not taxi.driveDone and os.clock() < deadline and npc.alive do
		task.wait(0.3)
	end
	if not arrived or not npc.alive then
		task.spawn(taxiReturn, taxi)
		return false
	end
	local seat = taxi.seats[#taxi.seats] or taxi.seats[1]
	if not seat or not Registry.walkTo(npc, doorSide(taxi, seat)) or not seatNPC(npc, taxi, seat) then
		task.spawn(taxiReturn, taxi)
		return false
	end
	local ok = drive(taxi, { node = nearestNode(target), curb = 5 })
	unseatNPC(npc, 1)
	task.spawn(taxiReturn, taxi)
	return ok
end

---------------------------------------------------------------------
-- Автобус
---------------------------------------------------------------------

local bus = nil

local function busTrip(npc, target: Vector3): boolean
	if not bus or #busStops < 2 then
		return false
	end
	local function nearestStop(pos: Vector3)
		local best, bestDist = nil, math.huge
		for _, stop in busStops do
			local d = (stop.pos - pos).Magnitude
			if d < bestDist then
				best, bestDist = stop, d
			end
		end
		return best
	end
	local from, to = nearestStop(npc.hrp.Position), nearestStop(target)
	if from == to then
		return false
	end
	if not Registry.walkTo(npc, from.pos) then
		return false
	end
	Registry.setMood(npc, "Wait")
	-- Ждём автобус с открытыми дверями на этой остановке
	local deadline = os.clock() + 150
	while npc.alive and os.clock() < deadline and not (bus.atStop == from and bus.doorsOpen) do
		task.wait(0.4)
	end
	Registry.setMood(npc, nil)
	if not npc.alive or bus.atStop ~= from then
		return false
	end
	local seat = freeSeat(bus)
	if not seat or not Registry.walkTo(npc, doorSide(bus, seat, 1)) or bus.atStop ~= from then
		return false
	end
	if not seatNPC(npc, bus, seat) then
		return false
	end
	-- Едем до своей остановки
	repeat
		task.wait(0.4)
	until not npc.alive or not npc.inVehicle or (bus.atStop == to and bus.doorsOpen) or (bus.atStop == nil and bus.atTerminal)
	if npc.inVehicle then
		unseatNPC(npc, 1)
	end
	return true
end

local function busLoop()
	while bus and bus.model.Parent do
		for _, stop in busStops do
			bus.atTerminal = false
			bus.model:SetAttribute("NextStop", stop.name)
			bus.model:SetAttribute("AtStop", "")
			drive(bus, { node = stop.node, curb = true })
			bus.atStop = stop
			bus.model:SetAttribute("AtStop", stop.name)
			bus.model:SetAttribute("BusDoors", true)
			for name in pairs(bus.doors) do
				setDoor(bus, name, true)
			end
			bus.doorsOpen = true
			bus.model:SetAttribute("HornId", (bus.model:GetAttribute("HornId") or 0) + 1)
			task.wait(Config.BusStopTime)
			bus.doorsOpen = false
			for name in pairs(bus.doors) do
				setDoor(bus, name, false)
			end
			task.wait(1)
			bus.atStop = nil
			bus.model:SetAttribute("AtStop", "")
		end
		-- Конечная: на стоянку автобуса, отдых
		bus.model:SetAttribute("NextStop", "Конечная")
		if bus.homeSpot then
			drive(bus, { spot = bus.homeSpot })
		end
		bus.atTerminal = true
		bus.model:SetAttribute("AtStop", "Конечная")
		task.wait(Config.BusLoopPause)
	end
end

---------------------------------------------------------------------
-- Полиция
---------------------------------------------------------------------

local policeRemote = ReplicatedStorage:FindFirstChild("PoliceRemote") or Instance.new("RemoteEvent")
policeRemote.Name = "PoliceRemote"
policeRemote.Parent = ReplicatedStorage

-- Участок: стойка дежурного, места ожидания, камера
local station = { desk = nil, idle = {}, cell = nil }
local stationFolder = folder("PoliceStation")
if stationFolder then
	for _, p in stationFolder:GetDescendants() do
		if p:IsA("BasePart") then
			if string.find(p.Name, "^Desk") then
				station.desk = p
			elseif string.find(p.Name, "^Cell") then
				station.cell = p
			elseif string.find(p.Name, "^Idle") then
				table.insert(station.idle, p)
			end
			hideMarker(p)
		end
	end
end

local function onFloor(part: BasePart): Vector3
	return Vector3.new(part.Position.X, groundY(part.Position), part.Position.Z)
end

local function standCFrame(position: Vector3, look: Vector3): CFrame
	local p = position + Vector3.new(0, 3, 0)
	local l = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	return CFrame.lookAt(p, p + l)
end

local callQueue = {} -- вызовы по очереди
local nextTicket = 0
local tickets = {} -- [player] = { заявления }
local recentEvents = {} -- для «Что нового в городе?»
local jailed = {} -- [npc] = true

local function addEvent(text: string)
	if Registry.debugEvent then
		Registry.debugEvent("🚔 " .. text)
	end
	table.insert(recentEvents, 1, text)
	if #recentEvents > 4 then
		table.remove(recentEvents)
	end
end

local function ticketList(player: Player)
	local out = {}
	for _, t in tickets[player] or {} do
		table.insert(out, { id = t.id, icon = t.icon, kind = t.kind, place = t.place, status = t.status, done = t.done })
	end
	return out
end

local function setTicket(ticket, status: string, done: boolean?)
	if not ticket then
		return
	end
	ticket.status = status
	ticket.done = done == true
	local player = ticket.player
	if player and player.Parent then
		policeRemote:FireClient(player, "Tickets", ticketList(player))
		local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
		if phone then
			phone:FireClient(player, "Tickets", ticketList(player))
		end
		toast(player, string.format("🚔 Заявление №%d: %s", ticket.id, status))
	end
end

-- Точка вызова для места: ближайший вход в здание (PoliceCalls) или само место
local function callAt(position: Vector3)
	local best, bestDist = nil, 45
	for _, c in policeCalls do
		local d = (c.pos - position).Magnitude
		if d < bestDist then
			best, bestDist = c, d
		end
	end
	return best and { pos = best.pos, zone = best.zone } or { pos = position, zone = nil }
end

local function spawnOfficer(at: CFrame, title: string?)
	if not Registry.spawnCustom then
		return nil
	end
	local officer = Registry.spawnCustom(at, {
		prefix = title or "Офицер",
		shirt = Config.PoliceShirt,
		pants = Config.PolicePants,
		role = "Полиция",
	})
	if officer then
		officer.officer = true
		officer.noSocial = true
		if officer.prompt then
			officer.prompt.Enabled = false
		end
	end
	return officer
end

-- Офицеры в участке: стоят на местах, иногда переходят, болтают
local function stationLife(officer)
	while officer.alive do
		if not officer.onDuty and #station.idle > 0 then
			local spot = pick(station.idle)
			if Registry.walkTo(officer, onFloor(spot)) and not officer.onDuty then
				Registry.face(officer, spot.CFrame.LookVector)
				if rng:NextNumber() < 0.2 then
					Registry.say(officer, pick({ "Тихо сегодня.", "Кофе будешь?", "Ну и смена...", "Где мой рапорт?" }))
				end
			end
		end
		task.wait(rng:NextNumber(Config.StationWanderTime.Min, Config.StationWanderTime.Max))
	end
end

local function newOfficer(car)
	local at
	if #station.idle > 0 then
		local spot = pick(station.idle)
		at = standCFrame(onFloor(spot), spot.CFrame.LookVector)
	else
		at = standCFrame(doorSide(car, car.driverSeat), car.look)
	end
	local officer = spawnOfficer(at)
	if officer then
		task.spawn(stationLife, officer)
	end
	return officer
end

-- Все садятся по местам; ждём, пока сядут или выйдет время
local function boardAll(car, people)
	local done = 0
	for _, entry in people do
		task.spawn(function()
			local who, seat = entry.npc, entry.seat
			if who and who.alive and seat and not who.inVehicle and Registry.walkTo(who, doorSide(car, seat)) then
				seatNPC(who, car, seat)
			end
			done += 1
		end)
	end
	local deadline = os.clock() + 40
	while done < #people and os.clock() < deadline do
		task.wait(0.3)
	end
end

local function say(npc, text: string?)
	if npc and npc.alive and text and text ~= "" then
		Registry.say(npc, text)
		task.wait(Config.QuestionGap + #text / 30)
	end
end

-- Событие на месте вызова: опрос жителя, иногда задержание
local function workCall(car, call, officers)
	local o1, o2 = officers[1], officers[2] or officers[1]
	local door = call.pos
	local toRoad = flat(car.pos - door)
	toRoad = toRoad.Magnitude > 0.5 and toRoad.Unit or Vector3.new(1, 0, 0)
	local side = toRoad:Cross(Vector3.yAxis)

	-- Встают у двери порознь, лицом к дому
	local arrived = 0
	for i, officer in officers do
		task.spawn(function()
			if officer and officer.alive then
				local offset = (i == 1 and 1 or -1) * Config.OfficerSpacing
				local spot = door + toRoad * 2.4 + side * offset
				Registry.walkTo(officer, Vector3.new(spot.X, groundY(spot), spot.Z))
				Registry.face(officer, -toRoad)
			end
			arrived += 1
		end)
	end
	local deadline = os.clock() + 30
	while arrived < #officers and os.clock() < deadline do
		task.wait(0.3)
	end

	local kind = call.kind
	local resident = Registry.findResident(call.zone, door, 60)
	if resident and not Registry.claim(resident, "police") then
		resident = nil
	end
	if not resident then
		for _, line in Config.NobodyLines do
			say(o1, line)
		end
		return "Никого не оказалось на месте", false
	end

	-- Житель выходит к офицерам
	Registry.setMood(resident, "Police")
	local meet = door + toRoad * 0.6
	Registry.walkTo(resident, Vector3.new(meet.X, groundY(meet), meet.Z))
	Registry.face(resident, toRoad)
	Registry.emote(o1, "Wave")

	local arrest = rng:NextNumber() < (kind.Arrest or 0) and kind.Suspect and kind.Suspect[1] ~= ""
	local answers = arrest and kind.Suspect or kind.Resident
	say(o1, kind.Officer[1])
	say(resident, answers[1])
	Registry.emote(o2, "Point")
	say(o2, kind.Officer[2])
	Registry.emote(resident, rng:NextNumber() < 0.5 and "Point" or "Wave")
	say(resident, answers[2])

	if not arrest then
		say(o1, pick(Config.PoliceCloseLines))
		say(resident, pick(Config.ResidentThanks))
		Registry.release(resident)
		return kind.Name .. ": разобрались на месте", false
	end

	-- Задержание: наручники, в машину, в участок
	say(o1, pick(Config.ArrestLines))
	resident.model:SetAttribute("Cuffed", true)
	Registry.setMood(resident, "Cuffed")
	say(resident, pick(Config.ArrestedLines))
	local rear = car.seats[#car.seats] ~= car.seats[1] and car.seats[#car.seats] or car.seats[2]
	if not rear then
		Registry.release(resident)
		return kind.Name .. ": некуда посадить задержанного", false
	end
	boardAll(car, { { npc = resident, seat = rear } })
	return kind.Name .. ": задержан " .. resident.name, true, resident
end

local function handleCall(car, call)
	car.state = "busy"
	local ticket = call.ticket
	-- Замена погибших офицеров
	for i = 1, Config.PoliceOfficersPerCar do
		local o = car.officers[i]
		if not o or not o.alive then
			car.officers[i] = newOfficer(car)
		end
	end
	local officers = {}
	for _, o in car.officers do
		if o and o.alive then
			o.onDuty = true
			table.insert(officers, o)
		end
	end
	-- Прерываем прогулку по участку
	for _, o in officers do
		o.abort = true
	end
	task.wait(0.4)
	for _, o in officers do
		o.abort = false
	end
	if #officers == 0 then
		table.insert(callQueue, 1, call)
		car.state = "parked"
		task.wait(10)
		return
	end

	-- Из участка — в машину
	setTicket(ticket, "Наряд выезжает")
	local seating = {}
	for i, o in officers do
		table.insert(seating, { npc = o, seat = i == 1 and car.driverSeat or car.seats[i - 1] })
	end
	boardAll(car, seating)

	car.model:SetAttribute("Siren", true)
	car.model:SetAttribute("SirenMuted", false)
	setTicket(ticket, "Наряд в пути 🚨")
	drive(car, { node = nearestNode(call.pos), curb = 5 })
	car.model:SetAttribute("SirenMuted", true) -- мигалки горят, сирена молчит
	setTicket(ticket, "Наряд на месте")

	for _, o in officers do
		task.spawn(unseatNPC, o)
	end
	task.wait(1.4)
	local summary, arrested, suspect = workCall(car, call, officers)
	addEvent(summary)

	-- Обратно в машину и в участок
	local back = {}
	for i, o in officers do
		table.insert(back, { npc = o, seat = i == 1 and car.driverSeat or car.seats[i - 1] })
	end
	boardAll(car, back)
	car.model:SetAttribute("Siren", false)
	car.model:SetAttribute("SirenMuted", false)
	drive(car, { spot = car.homeSpot })

	for _, o in officers do
		task.spawn(unseatNPC, o)
	end
	if arrested and suspect and suspect.alive then
		setTicket(ticket, "Задержанный доставлен в участок")
		if ticket and ticket.player and Registry.playerEvent then
			Registry.playerEvent(ticket.player, "Arrest")
		end
		task.wait(1)
		unseatNPC(suspect)
		if station.cell then
			-- Ведут в камеру и оформляют
			task.spawn(function()
				Registry.walkTo(officers[1], onFloor(station.cell) + station.cell.CFrame.LookVector * 2.5)
			end)
			Registry.walkTo(suspect, onFloor(station.cell))
			Registry.face(suspect, station.cell.CFrame.LookVector)
			say(officers[1], pick(Config.BookingLines))
		end
		jailed[suspect] = true
		task.spawn(function()
			local release = os.clock() + rng:NextNumber(Config.CellTime.Min, Config.CellTime.Max)
			while suspect.alive and os.clock() < release do
				task.wait(rng:NextNumber(12, 25))
				if suspect.alive and os.clock() < release then
					Registry.say(suspect, pick(Config.CellLines))
				end
			end
			jailed[suspect] = nil
			if suspect.alive then
				Registry.say(suspect, "Наконец-то свобода!")
				Registry.release(suspect)
			end
		end)
	elseif arrested and suspect then
		Registry.release(suspect)
	end
	setTicket(ticket, "Закрыто: " .. summary, true)
	task.wait(2)
	for _, o in officers do
		o.onDuty = false
	end
	car.state = "parked"
end

local function policeCarLoop(car)
	car.officers = {}
	for i = 1, Config.PoliceOfficersPerCar do
		car.officers[i] = newOfficer(car)
	end
	while car.model.Parent do
		local call = table.remove(callQueue, 1)
		if call then
			local ok, err = pcall(handleCall, car, call)
			if not ok then
				warn("[Traffic] Ошибка на вызове:", err)
				for _, o in car.officers do
					if o then
						o.onDuty = false
					end
				end
				car.state = "parked"
			end
		else
			task.wait(1)
		end
	end
end

-- Случайные вызовы по городу
local function dispatcher()
	while true do
		local waitTime = rng:NextNumber(Config.PoliceCallInterval.Min, Config.PoliceCallInterval.Max)
		if isNight() then
			waitTime *= Config.PoliceNightFactor
		end
		task.wait(waitTime)
		if #policeCalls > 0 and #callQueue < 2 then
			local c = pick(policeCalls)
			table.insert(callQueue, { pos = c.pos, zone = c.zone, kind = pick(Config.PoliceCallTypes) })
		end
	end
end

-- Дежурный и его меню
local duty = nil
local reportCooldown = {}

local function dutyAnswer(player: Player, text: string)
	if duty and duty.alive then
		Registry.say(duty, text)
	end
	policeRemote:FireClient(player, "Say", text)
end

local function openDesk(player: Player)
	if not duty or not duty.alive then
		return
	end
	local types = {}
	for i, k in Config.PoliceCallTypes do
		types[i] = { name = k.Name, icon = k.Icon }
	end
	local placeNames = {}
	for i, place in places do
		placeNames[i] = place.name
	end
	local questions = {}
	for i, q in Config.DutyQuestions do
		questions[i] = q.Text
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		Registry.face(duty, root.Position - duty.hrp.Position)
	end
	Registry.emote(duty, "Wave")
	local greeting = pick(Config.DutyGreetings)
	Registry.say(duty, greeting)
	policeRemote:FireClient(player, "Open", {
		officer = duty.model,
		name = duty.name,
		greeting = greeting,
		types = types,
		places = placeNames,
		questions = questions,
		tickets = ticketList(player),
	})
end

-- Новое заявление (от дежурного или с телефона). Возвращает ответ дежурного.
local function createReport(player: Player, typeIndex: any, placeIndex: any, force: boolean?): string?
	local kind = type(typeIndex) == "number" and Config.PoliceCallTypes[typeIndex] or nil
	local place = type(placeIndex) == "number" and places[placeIndex] or nil
	if not kind or not place then
		return nil
	end
	local now = os.clock()
	local active = 0
	for _, t in tickets[player] or {} do
		if not t.done then
			active += 1
		end
	end
	if not force and (now < (reportCooldown[player] or 0) or active >= 3) then
		return "Подождите, мы ещё работаем по вашим заявлениям."
	end
	reportCooldown[player] = now + 15
	nextTicket += 1
	local ticket = { id = nextTicket, icon = kind.Icon, kind = kind.Name, place = place.name, status = "Принято", player = player }
	tickets[player] = tickets[player] or {}
	table.insert(tickets[player], 1, ticket)
	if #tickets[player] > 6 then
		table.remove(tickets[player])
	end
	local call = callAt(place.pos)
	call.kind = kind
	call.ticket = ticket
	-- Заявления игроков — вперёд очереди
	table.insert(callQueue, 1, call)
	local free = false
	for _, car in cars do
		if car.kind == "Police" and car.state == "parked" then
			free = true
		end
	end
	policeRemote:FireClient(player, "Tickets", ticketList(player))
	local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
	if phone then
		phone:FireClient(player, "Tickets", ticketList(player))
	end
	if Registry.playerEvent then
		Registry.playerEvent(player, "Report")
	end
	return string.format("%s Номер заявления: %d.", pick(free and Config.ReportAccepted or Config.ReportBusy), ticket.id)
end

policeRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	if not duty or not duty.alive then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - duty.hrp.Position).Magnitude > 20 then
		return
	end
	if action == "Report" then
		local answer = createReport(player, a, b)
		if answer then
			dutyAnswer(player, answer)
			Registry.emote(duty, "Point")
		end
	elseif action == "Ask" and type(a) == "number" then
		local q = Config.DutyQuestions[a]
		if not q then
			return
		end
		local answer = pick(q.Answers)
		if string.find(answer, "%%s") then
			local filler
			if a == 1 then
				filler = #recentEvents > 0 and ("Последние вызовы: " .. table.concat(recentEvents, "; ") .. ".") or "Всё спокойно, вызовов не было."
			else
				local names = {}
				for npc in pairs(jailed) do
					table.insert(names, npc.name)
				end
				filler = #names > 0 and ("Сейчас в камере: " .. table.concat(names, ", ") .. ".") or "Камера пустая. Пока что."
			end
			answer = string.format(answer, filler)
		end
		dutyAnswer(player, answer)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	tickets[player] = nil
	reportCooldown[player] = nil
end)

local function spawnDuty()
	if not station.desk then
		return
	end
	duty = spawnOfficer(standCFrame(onFloor(station.desk), station.desk.CFrame.LookVector), Config.DutyOfficerName)
	if duty then
		duty.onDuty = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DutyPrompt"
		prompt.ActionText = "Обратиться"
		prompt.ObjectText = "Дежурный"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = duty.hrp
		prompt.Triggered:Connect(openDesk)
		-- Дежурный всегда возвращается за стойку
		task.spawn(function()
			while duty and duty.alive do
				task.wait(5)
				local home = onFloor(station.desk)
				if (flat(duty.hrp.Position - home)).Magnitude > 2 then
					Registry.walkTo(duty, home)
				end
				Registry.face(duty, station.desk.CFrame.LookVector)
			end
		end)
	end
end

---------------------------------------------------------------------
-- Такси и автобус для игроков
---------------------------------------------------------------------

local function coins(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild(NPCConfig.CurrencyName) or nil
end

local function addPrompt(car, text: string, onTrigger)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VehiclePrompt"
	prompt.ActionText = text
	prompt.ObjectText = car.kind == "Taxi" and "Такси" or "Автобус"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = car.kind == "Bus" and 14 or 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = car.body
	prompt.Triggered:Connect(onTrigger)
	car.prompt = prompt
	return prompt
end

local playerTaxiBusy = {}

local function playerTaxi(car, player: Player, placeIndex: number)
	local place = places[placeIndex]
	local wallet = coins(player)
	if not place or car.state ~= "parked" or playerTaxiBusy[player] then
		return
	end
	if not wallet or wallet.Value < Config.TaxiPrice then
		toast(player, "Не хватает монет на такси 🪙")
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - car.pos).Magnitude > 20 then
		return
	end
	local seat = freeSeat(car)
	if not seat then
		return
	end
	wallet.Value -= Config.TaxiPrice
	toast(player, string.format("-%d 🪙 Едем: %s", Config.TaxiPrice, place.name))
	playerTaxiBusy[player] = true
	car.state = "busy"
	car.model:SetAttribute("TaxiBusy", true)
	car.prompt.Enabled = false
	seatPlayer(player, car, seat)
	task.wait(0.8)
	drive(car, { node = nearestNode(place.pos), curb = 5 })
	unseatPlayer(player, car, 1)
	toast(player, "Приехали! 🚕")
	if Registry.playerEvent then
		Registry.playerEvent(player, "Taxi")
	end
	playerTaxiBusy[player] = nil
	taxiReturn(car)
	car.prompt.Enabled = true
end

remote.OnServerEvent:Connect(function(player: Player, action: any, model: any, index: any)
	if action ~= "TaxiGo" or typeof(model) ~= "Instance" or type(index) ~= "number" then
		return
	end
	for _, car in cars do
		if car.model == model and car.kind == "Taxi" then
			task.spawn(playerTaxi, car, player, index)
			return
		end
	end
end)

---------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------

-- Гражданские
for i = 1, math.min(Config.Count.Civilian, #spots.Civilian) do
	spawnCar("Civilian", spots.Civilian[i])
end

-- Такси
for i = 1, math.min(Config.Count.Taxi, #spots.Taxi) do
	local car = spawnCar("Taxi", spots.Taxi[i])
	if car then
		local names = {}
		for k, place in places do
			names[k] = place.name
		end
		addPrompt(car, string.format("Такси (%d 🪙)", Config.TaxiPrice), function(player)
			if car.state == "parked" and #names > 0 then
				remote:FireClient(player, "TaxiMenu", car.model, names, Config.TaxiPrice)
			end
		end)
	end
end

-- Автобус
if Config.Count.Bus > 0 and #busStops >= 2 then
	local spot = spots.Bus[1]
	bus = spawnCar("Bus", spot)
	if bus then
		if not spot then
			local first = busStops[1]
			placeCar(bus, nodes[first.node].pos, Vector3.new(0, 0, -1))
		end
		addPrompt(bus, "Сесть в автобус", function(player)
			if bus.atStop or bus.state == "parked" or bus.atTerminal then
				local seat = freeSeat(bus)
				if seat then
					task.spawn(seatPlayer, player, bus, seat)
					if Registry.playerEvent then
						Registry.playerEvent(player, "Bus")
					end
				else
					toast(player, "Автобус полный 🚌")
				end
			end
		end)
		bus.state = "busy"
		task.spawn(busLoop)
	end
elseif Config.Count.Bus > 0 then
	warn("[Traffic] Для автобуса нужно минимум 2 остановки в папке BusStops")
end

-- Полиция
for i = 1, math.min(Config.Count.Police, #spots.Police) do
	local car = spawnCar("Police", spots.Police[i])
	if car then
		task.spawn(policeCarLoop, car)
	end
end
if #spots.Police > 0 then
	task.spawn(dispatcher)
	task.spawn(function()
		-- Дежурный: возрождается, если с ним что-то случилось
		while true do
			if not duty or not duty.alive then
				spawnDuty()
			end
			task.wait(20)
		end
	end)
end

-- Поток машин: свои водители, катаются всё время
local function cruiseDriver(car)
	if not Registry.spawnCustom then
		return nil
	end
	local pos = car.pos + car.look:Cross(Vector3.yAxis) * -(car.width / 2 + 2)
	local driver = Registry.spawnCustom(CFrame.new(pos + Vector3.new(0, 3, 0)), {})
	if driver then
		driver.noSocial = true
		driver.officer = true -- без разговоров и обычного «мозга»
		if driver.prompt then
			driver.prompt.Enabled = false
		end
		seatNPC(driver, car, car.driverSeat)
	end
	return driver
end

local function cruiseLoop(car)
	local names = {}
	for name, node in pairs(nodes) do
		if next(node.links) then
			table.insert(names, name)
		end
	end
	car.state = "busy"
	while car.model.Parent do
		if not car.driver or not car.driver.alive or car.driver.inVehicle ~= car then
			task.wait(car.driver and 15 or 0.5)
			car.driver = cruiseDriver(car)
			if not car.driver then
				task.wait(5)
				continue
			end
		end
		-- Случайная точка подальше
		local dest
		for _ = 1, 10 do
			local candidate = pick(names)
			if (nodes[candidate].pos - car.pos).Magnitude > Config.CruiseMinDistance then
				dest = candidate
				break
			end
		end
		dest = dest or pick(names)
		local stop = rng:NextNumber() < Config.CruiseStopChance
		drive(car, { node = dest, curb = stop and 5 or nil })
		if stop then
			task.wait(rng:NextNumber(Config.CruiseStopTime.Min, Config.CruiseStopTime.Max))
		else
			task.wait(0.2)
		end
	end
end

do
	local list = {}
	for name, node in pairs(nodes) do
		if next(node.links) then
			table.insert(list, name)
		end
	end
	-- Ставим на разные точки, подальше друг от друга
	local used = {}
	for _ = 1, Config.Count.Cruising do
		local best, bestDist = nil, -1
		for _ = 1, 15 do
			local candidate = pick(list)
			local minDist = math.huge
			for _, u in used do
				minDist = math.min(minDist, (nodes[u].pos - nodes[candidate].pos).Magnitude)
			end
			if minDist > bestDist then
				best, bestDist = candidate, minDist
			end
		end
		if not best then
			break
		end
		table.insert(used, best)
		local car = spawnCar("Civilian", nil)
		if car then
			-- Смотрим вдоль дороги к соседней точке и встаём на правую полосу
			local neighbor = next(nodes[best].links)
			local dir = flat(nodes[neighbor].pos - nodes[best].pos).Unit
			local lane = nodes[best].pos + dir:Cross(Vector3.yAxis) * Config.LaneOffset
			placeCar(car, Vector3.new(lane.X, groundY(lane), lane.Z), dir)
			car.onRoad = true
			car.cruiser = true
			task.spawn(cruiseLoop, car)
		end
	end
end

if #cars == 0 then
	warn("[Traffic] Ни одной машины: добавь парковки (Workspace >", Config.MapFolder, "> Parking) с атрибутом Type")
end

---------------------------------------------------------------------
-- Связь с жителями
---------------------------------------------------------------------

function Registry.assignCar(npc)
	if npc.car or npc.officer or not npc.homeZone then
		return
	end
	local best
	for _, car in cars do
		if car.kind == "Civilian" and not car.owner and not car.cruiser then
			if not best or (car.homeSpot and car.homeSpot.zone == npc.homeZone) then
				best = car
			end
		end
	end
	if best then
		best.owner = npc
		npc.car = best
	end
end

function Registry.releaseCar(npc)
	if npc.car and npc.car.owner == npc then
		npc.car.owner = nil
	end
	npc.car = nil
end

function Registry.tryTrip(npc, target: Vector3): boolean
	if not npc.alive or npc.inVehicle or npc.officer then
		return false
	end
	if (flat(target - npc.hrp.Position)).Magnitude < Config.TripMinDistance then
		return false
	end
	local car = npc.car
	if car and car.owner == npc and car.state == "parked" and car.model.Parent then
		return carTrip(npc, car, target)
	end
	if rng:NextNumber() < Config.TaxiChance and freeTaxi() then
		return taxiTrip(npc, target)
	end
	if bus and rng:NextNumber() < Config.BusChance then
		return busTrip(npc, target)
	end
	return false
end

for _, npc in pairs(Registry.npcs) do
	Registry.assignCar(npc)
end

---------------------------------------------------------------------
-- Телефон игрока (PhoneServer вызывает эти функции)
---------------------------------------------------------------------

local function phoneSend(player: Player, action: string, payload)
	local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
	if phone and player.Parent then
		phone:FireClient(player, action, payload)
	end
end

-- Для меню отладки: вызов полиции без ограничений (место — ближайшее к игроку)
function Registry.debugPoliceCall(player: Player, typeIndex: number): string?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local best, bestDist = 1, math.huge
	for i, place in places do
		local d = root and (place.pos - root.Position).Magnitude or i
		if d < bestDist then
			best, bestDist = i, d
		end
	end
	local answer = createReport(player, typeIndex, best, true)
	if answer then
		phoneSend(player, "PoliceAnswer", answer)
	end
	return answer and (places[best].name .. ": " .. answer) or "Нет мест (Places) или такого вида вызова"
end

-- Для меню отладки: все машины и их маршруты
function Registry.debugCars()
	local out = {}
	for i, car in cars do
		if car.model and car.model.Parent then
			local route = {}
			for _, name in car.debugPath or {} do
				local n = nodes[name]
				if n then
					table.insert(route, n.pos)
				end
			end
			table.insert(out, {
				id = i,
				kind = car.kind,
				state = car.state,
				speed = math.floor((car.v or 0) * 10) / 10,
				pos = car.pos,
				to = car.debugTo,
				route = route,
				driver = car.driver and car.driver.name or nil,
				siren = car.model:GetAttribute("Siren") == true,
				model = car.model,
			})
		end
	end
	return out
end
function Registry.debugNodes()
	local out = {}
	for name, n in pairs(nodes) do
		local links = {}
		for other in pairs(n.links) do
			table.insert(links, other)
		end
		out[name] = { pos = n.pos, links = links }
	end
	return out
end

function Registry.phoneData(player: Player)
	local placeNames, types, stops = {}, {}, {}
	for i, place in places do
		placeNames[i] = place.name
	end
	for i, k in Config.PoliceCallTypes do
		types[i] = { name = k.Name, icon = k.Icon }
	end
	for i, stop in busStops do
		stops[i] = stop.name
	end
	return {
		places = placeNames,
		policeTypes = types,
		tickets = ticketList(player),
		taxiPrice = Config.TaxiPrice,
		busStops = stops,
	}
end

function Registry.phoneReport(player: Player, typeIndex: any, placeIndex: any)
	local answer = createReport(player, typeIndex, placeIndex)
	if answer then
		phoneSend(player, "PoliceAnswer", answer)
	end
end

-- Такси по телефону: приезжает к игроку, ждёт, везёт, берёт плату
local phoneTaxiBusy = {}
function Registry.phoneTaxi(player: Player, placeIndex: any)
	local place = type(placeIndex) == "number" and places[placeIndex] or nil
	local wallet = coins(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local function status(text: string, done: boolean?)
		phoneSend(player, "Taxi", { text = text, done = done == true })
	end
	if not place or not root or phoneTaxiBusy[player] or playerTaxiBusy[player] then
		return
	end
	if not wallet or wallet.Value < Config.TaxiPrice then
		status("Не хватает монет 🪙 (нужно " .. Config.TaxiPrice .. ")", true)
		return
	end
	local taxi = freeTaxi()
	if not taxi then
		status("Все такси заняты, попробуйте позже", true)
		return
	end
	phoneTaxiBusy[player] = true
	taxi.state = "busy"
	taxi.model:SetAttribute("TaxiBusy", true)
	taxi.model:SetAttribute("CalledBy", player.UserId)
	if taxi.prompt then
		taxi.prompt.Enabled = false
	end
	status("🚕 Такси едет к вам...")
	local ok = drive(taxi, { node = nearestNode(root.Position), curb = 5 })
	local function finish()
		phoneTaxiBusy[player] = nil
		taxi.model:SetAttribute("CalledBy", nil)
		taxiReturn(taxi)
		if taxi.prompt then
			taxi.prompt.Enabled = true
		end
	end
	if not ok then
		status("Такси не смогло проехать 😕", true)
		finish()
		return
	end
	status("🚕 Такси ждёт вас! Подойдите к машине")
	honk(taxi)
	-- Ждём игрока минуту
	local deadline = os.clock() + 60
	local near = false
	while os.clock() < deadline and player.Parent do
		local c = player.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - taxi.pos).Magnitude < 12 then
			near = true
			break
		end
		task.wait(0.5)
	end
	if not near then
		status("Такси уехало: вы не пришли", true)
		finish()
		return
	end
	local seat = freeSeat(taxi)
	if not seat or not wallet.Parent or wallet.Value < Config.TaxiPrice then
		status("Не получилось сесть", true)
		finish()
		return
	end
	wallet.Value -= Config.TaxiPrice
	seatPlayer(player, taxi, seat)
	status("🚕 Едем: " .. place.name)
	task.wait(0.8)
	drive(taxi, { node = nearestNode(place.pos), curb = 5 })
	unseatPlayer(player, taxi, 1)
	status("Приехали! -" .. Config.TaxiPrice .. " 🪙", true)
	if Registry.playerEvent then
		Registry.playerEvent(player, "Taxi")
	end
	finish()
end
