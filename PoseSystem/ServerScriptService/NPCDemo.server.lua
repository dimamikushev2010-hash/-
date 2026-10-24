-- Script: ServerScriptService > NPCDemo
-- Демо-городок для проверки жителей: два дома с дверями, мебелью и окнами,
-- улица с фонтаном, скамейками и фонарями, и все точки для NPC.
-- Строится ТОЛЬКО если на карте ещё нет папки Workspace > NPCSystem.
-- Когда сделаешь свою карту с папкой NPCSystem — демо само перестанет появляться
-- (или выключи NPCConfig.BuildDemoIfMissing).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))

if not Config.BuildDemoIfMissing or workspace:FindFirstChild(Config.FolderName) then
	return
end

local town = Instance.new("Folder")
town.Name = "DemoTown"
town.Parent = workspace

local system = Instance.new("Folder")
system.Name = Config.FolderName
local spawns = Instance.new("Folder")
spawns.Name = "Spawns"
spawns.Parent = system
local points = Instance.new("Folder")
points.Name = "Points"
points.Parent = system
local doors = Instance.new("Folder")
doors.Name = "Doors"
doors.Parent = system

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local MARKER_COLORS = {
	Idle = Color3.fromRGB(80, 200, 255),
	Look = Color3.fromRGB(255, 255, 120),
	Sit = Color3.fromRGB(120, 255, 140),
	Lie = Color3.fromRGB(200, 140, 255),
	Dance = Color3.fromRGB(255, 120, 200),
	Talk = Color3.fromRGB(255, 170, 60),
}

MARKER_COLORS.Work = Color3.fromRGB(255, 255, 255)
MARKER_COLORS.Patrol = Color3.fromRGB(60, 90, 255)

local function point(name: string, pos: Vector3, look: Vector3, activity: string, zone: string?)
	local p = block(points, name, Vector3.new(2, 0.2, 2), CFrame.lookAt(pos, pos + look), MARKER_COLORS[activity] or Color3.new(1, 1, 1), Enum.Material.Neon)
	p.Transparency = 0.4
	p.CanCollide = false
	p:SetAttribute("Activity", activity)
	if zone then
		p:SetAttribute("Zone", zone)
	end
	return p
end

local function seat(parent: Instance, name: string, size: Vector3, pos: Vector3, look: Vector3, zone: string?, color: Color3)
	local s = Instance.new("Seat")
	s.Name = name
	s.Anchored = true
	s.Size = size
	s.CFrame = CFrame.lookAt(pos, pos + look)
	s.Color = color
	s.Material = Enum.Material.Wood
	s.TopSurface = Enum.SurfaceType.Smooth
	if zone then
		s:SetAttribute("Zone", zone)
	end
	s.Parent = parent
	return s
end

local function spawnPoint(name: string, pos: Vector3, count: number, zone: string?)
	local p = block(spawns, name, Vector3.new(3, 0.2, 3), CFrame.new(pos), Color3.fromRGB(255, 80, 80), Enum.Material.Neon)
	p.Transparency = 0.4
	p.CanCollide = false
	p:SetAttribute("Count", count)
	if zone then
		p:SetAttribute("Zone", zone)
	end
	return p
end

local function lamp(parent: Instance, pos: Vector3, range: number, color: Color3?)
	local bulb = block(parent, "Lamp", Vector3.new(1.2, 1.2, 1.2), CFrame.new(pos), color or Color3.fromRGB(255, 235, 190), Enum.Material.Neon)
	bulb.Shape = Enum.PartType.Ball
	bulb.CanCollide = false
	bulb:SetAttribute(Config.NightLightAttribute, true) -- горит только ночью
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = 1.6
	light.Color = bulb.Color
	light.Parent = bulb
	return bulb
end

---------------------------------------------------------------------
-- Дом: фасад смотрит на +Z (на улицу)
---------------------------------------------------------------------

local function house(ox: number, oz: number, zone: string, wallColor: Color3)
	local model = Instance.new("Model")
	model.Name = "House_" .. zone
	model.Parent = town
	local o = Vector3.new(ox, 0, oz)
	local function at(x, y, z)
		return o + Vector3.new(x, y, z)
	end
	local H = 12
	local floorTop = 0.2

	block(model, "Floor", Vector3.new(24, 0.2, 20), CFrame.new(at(0, 0.1, 0)), Color3.fromRGB(160, 120, 80), Enum.Material.WoodPlanks)
	block(model, "WallBack", Vector3.new(24, H, 1), CFrame.new(at(0, floorTop + H / 2, -9.5)), wallColor, Enum.Material.Brick)
	block(model, "WallLeft", Vector3.new(1, H, 20), CFrame.new(at(-11.5, floorTop + H / 2, 0)), wallColor, Enum.Material.Brick)
	block(model, "WallRight", Vector3.new(1, H, 20), CFrame.new(at(11.5, floorTop + H / 2, 0)), wallColor, Enum.Material.Brick)
	block(model, "WallFrontL", Vector3.new(9.5, H, 1), CFrame.new(at(-7.25, floorTop + H / 2, 9.5)), wallColor, Enum.Material.Brick)
	block(model, "WallFrontR", Vector3.new(9.5, H, 1), CFrame.new(at(7.25, floorTop + H / 2, 9.5)), wallColor, Enum.Material.Brick)
	block(model, "Lintel", Vector3.new(5, H - 9, 1), CFrame.new(at(0, floorTop + 9 + (H - 9) / 2, 9.5)), wallColor, Enum.Material.Brick)
	block(model, "Roof", Vector3.new(26, 1, 22), CFrame.new(at(0, floorTop + H + 0.5, 0)), Color3.fromRGB(120, 50, 45), Enum.Material.Slate)

	local window = block(model, "Window", Vector3.new(6, 4, 0.2), CFrame.new(at(0, 6, -8.9)), Color3.fromRGB(170, 220, 255), Enum.Material.Glass)
	window.Transparency = 0.3
	window.CanCollide = false
	window:SetAttribute(Config.NightLightAttribute, true) -- ночью окно светится
	local windowLight = Instance.new("SurfaceLight")
	windowLight.Face = Enum.NormalId.Back
	windowLight.Range = 14
	windowLight.Color = Color3.fromRGB(255, 220, 160)
	windowLight.Parent = window
	lamp(model, at(0, floorTop + H - 1, 0), 28)

	-- Дверь (её открывают жители и игроки)
	local door = block(doors, zone .. "_Door", Vector3.new(5, 9, 0.4), CFrame.new(at(0, floorTop + 4.5, 9.5)), Color3.fromRGB(110, 70, 40), Enum.Material.Wood)
	door:SetAttribute("Hinge", "Left")

	-- Кухня: стол и два стула
	block(model, "TableTop", Vector3.new(4, 0.3, 3), CFrame.new(at(-7, floorTop + 2.85, -4)), Color3.fromRGB(140, 95, 60), Enum.Material.Wood)
	block(model, "TableLeg", Vector3.new(0.6, 2.7, 0.6), CFrame.new(at(-7, floorTop + 1.35, -4)), Color3.fromRGB(110, 75, 50), Enum.Material.Wood)
	seat(points, zone .. "_Chair1", Vector3.new(2, 1, 2), at(-7, floorTop + 0.5, -1.2), Vector3.new(0, 0, -1), zone, Color3.fromRGB(150, 100, 60))
	seat(points, zone .. "_Chair2", Vector3.new(2, 1, 2), at(-7, floorTop + 0.5, -6.8), Vector3.new(0, 0, 1), zone, Color3.fromRGB(150, 100, 60))

	-- Гостиная: диван и ковёр
	block(model, "SofaBase", Vector3.new(6, 2, 2.5), CFrame.new(at(7, floorTop + 1, -7.2)), Color3.fromRGB(70, 90, 150), Enum.Material.Fabric)
	block(model, "SofaBack", Vector3.new(6, 3, 0.6), CFrame.new(at(7, floorTop + 2.5, -8.5)), Color3.fromRGB(60, 80, 135), Enum.Material.Fabric)
	block(model, "Rug", Vector3.new(6, 0.05, 6), CFrame.new(at(4, floorTop + 0.03, -0.5)), Color3.fromRGB(180, 70, 70), Enum.Material.Fabric).CanCollide = false

	point(zone .. "_Lie", at(3, floorTop + 0.1, 1), Vector3.new(0, 0, 1), "Lie", zone)
	point(zone .. "_Window", at(0, floorTop + 0.1, -6.5), Vector3.new(0, 0, -1), "Look", zone)
	point(zone .. "_Idle", at(7, floorTop + 0.1, 5), Vector3.new(-1, 0, 0), "Idle", zone)
	point(zone .. "_Dance", at(-6, floorTop + 0.1, 4), Vector3.new(0, 0, 1), "Dance", zone)
	spawnPoint(zone .. "_Spawn", at(0, floorTop + 0.1, 2), 1, zone)
end

house(-35, -50, "Дом1", Color3.fromRGB(230, 210, 180))
house(35, -50, "Дом2", Color3.fromRGB(190, 215, 230))

---------------------------------------------------------------------
-- Улица
---------------------------------------------------------------------

local street = Instance.new("Model")
street.Name = "Street"
street.Parent = town
local Z = "Street"

block(street, "Road", Vector3.new(117, 0.1, 12), CFrame.new(-7.5, 0.05, -32), Color3.fromRGB(60, 60, 65), Enum.Material.Asphalt).CanCollide = false
block(street, "Grass", Vector3.new(20, 0.1, 16), CFrame.new(25, 0.05, 12), Color3.fromRGB(90, 160, 70), Enum.Material.Grass).CanCollide = false

-- Фонтан
local basin = block(street, "FountainBase", Vector3.new(1.4, 12, 12), CFrame.new(0, 0.7, -14) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(180, 180, 190), Enum.Material.Concrete)
basin.Shape = Enum.PartType.Cylinder
local water = block(street, "FountainWater", Vector3.new(0.2, 10.5, 10.5), CFrame.new(0, 1.35, -14) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 170, 255), Enum.Material.Glass)
water.Shape = Enum.PartType.Cylinder
water.Transparency = 0.25
water.CanCollide = false
lamp(street, Vector3.new(0, 4, -14), 20, Color3.fromRGB(150, 210, 255))

-- Скамейки
for i, x in { -20, 20 } do
	seat(points, "Bench" .. i, Vector3.new(4, 1, 2), Vector3.new(x, 0.5, -18), Vector3.new(0, 0, 1), Z, Color3.fromRGB(130, 90, 55))
	block(street, "BenchBack" .. i, Vector3.new(4, 2, 0.4), CFrame.new(x, 1.5, -19.2), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
end

-- Фонари
for _, pos in { Vector3.new(-25, 0, -25), Vector3.new(25, 0, -25), Vector3.new(-25, 0, 5), Vector3.new(25, 0, 0) } do
	block(street, "LampPost", Vector3.new(0.6, 9, 0.6), CFrame.new(pos + Vector3.new(0, 4.5, 0)), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	lamp(street, pos + Vector3.new(0, 9.4, 0), 26)
end

point("Talk1", Vector3.new(-7, 0.1, -24), Vector3.new(1, 0, 0), "Talk", Z)
point("Talk2", Vector3.new(12, 0.1, -10), Vector3.new(-1, 0, 0), "Talk", Z)
point("Fountain", Vector3.new(0, 0.1, -5.5), Vector3.new(0, 0, -1), "Look", Z)
point("Idle1", Vector3.new(-15, 0.1, -6), Vector3.new(0, 0, 1), "Idle", Z)
point("Idle2", Vector3.new(18, 0.1, -22), Vector3.new(-1, 0, 0), "Idle", Z)
point("Idle3", Vector3.new(-3, 0.1, 10), Vector3.new(0, 0, -1), "Idle", Z)
point("StreetDance", Vector3.new(-13, 0.1, 8), Vector3.new(0, 0, -1), "Dance", Z)
point("GrassLie", Vector3.new(22, 0.1, 12), Vector3.new(-1, 0, 0), "Lie", Z)

-- Ларёк с мороженым: продавец стоит за прилавком
block(street, "StallCounter", Vector3.new(6, 3, 1.5), CFrame.new(-30, 1.5, 6), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
block(street, "StallBack", Vector3.new(6, 8, 0.5), CFrame.new(-30, 4, 10), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
for i = -1, 1 do
	block(street, "StallAwning", Vector3.new(2, 0.3, 4.5), CFrame.new(-30 + i * 2, 8.3, 7.5) * CFrame.Angles(math.rad(-12), 0, 0),
		i == 0 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(230, 70, 90), Enum.Material.Fabric)
end
local sign = block(street, "StallSign", Vector3.new(4, 1, 0.2), CFrame.new(-30, 3.6, 5.2), Color3.fromRGB(255, 120, 170), Enum.Material.SmoothPlastic)
sign:SetAttribute(Config.NightLightAttribute, true)
local work = point("IceCreamSeller", Vector3.new(-30, 0.1, 8), Vector3.new(0, 0, -1), "Work", Z)
work:SetAttribute("Role", "Мороженщик")

-- Маршрут охранника: обходит улицу по порядку Order
local route = { Vector3.new(-28, 0.1, -26), Vector3.new(28, 0.1, -26), Vector3.new(28, 0.1, 8), Vector3.new(-20, 0.1, 14) }
for i, pos in route do
	local nextPos = route[i % #route + 1]
	local p = point("Guard" .. i, pos, nextPos - pos, "Patrol", Z)
	p:SetAttribute("Route", "Guard")
	p:SetAttribute("Order", i)
	p:SetAttribute("Role", "Охранник")
end

spawnPoint("StreetSpawnL", Vector3.new(-8, 0.1, 3), 4, Z)
spawnPoint("StreetSpawnR", Vector3.new(8, 0.1, 3), 4, Z)

system.Parent = workspace

---------------------------------------------------------------------
-- Транспорт: дороги, светофор, парковки, остановки, вызовы полиции
---------------------------------------------------------------------

if workspace:FindFirstChild("TrafficSystem") then
	return
end

local traffic = Instance.new("Folder")
traffic.Name = "TrafficSystem"
local function sub(name: string)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = traffic
	return f
end
local roads, parking, stops, calls, lights, places = sub("Roads"), sub("Parking"), sub("BusStops"), sub("PoliceCalls"), sub("TrafficLights"), sub("Places")

local ASPHALT = Color3.fromRGB(60, 60, 65)
local function road(size: Vector3, pos: Vector3)
	block(street, "Road", size, CFrame.new(pos), ASPHALT, Enum.Material.Asphalt).CanCollide = false
end
road(Vector3.new(117, 0.1, 12), Vector3.new(-7.5, 0.05, 30)) -- север
road(Vector3.new(12, 0.1, 74), Vector3.new(-60, 0.05, -1)) -- запад
road(Vector3.new(12, 0.1, 74), Vector3.new(45, 0.05, -1)) -- восток
road(Vector3.new(12, 0.1, 50), Vector3.new(-45, 0.05, -1)) -- поперечная
-- Разметка
for x = -60, 40, 8 do
	block(street, "Marking", Vector3.new(4, 0.12, 0.4), CFrame.new(x, 0.06, -32), Color3.fromRGB(240, 240, 240)).CanCollide = false
	block(street, "Marking", Vector3.new(4, 0.12, 0.4), CFrame.new(x, 0.06, 30), Color3.fromRGB(240, 240, 240)).CanCollide = false
end

-- Точки дороги: по центру, Links — соседние точки (в обе стороны)
local NODE = Color3.fromRGB(255, 255, 255)
local function node(name: string, x: number, z: number, links: string, signal: { any }?)
	local p = block(roads, name, Vector3.new(1.5, 0.3, 1.5), CFrame.new(x, 0.15, z), NODE, Enum.Material.Neon)
	p.Transparency = 0.3
	p.CanCollide = false
	p:SetAttribute("Links", links)
	if signal then
		p:SetAttribute("Signal", signal[1])
		p:SetAttribute("Phase", signal[2])
		p:SetAttribute("Toward", signal[3])
	end
end
node("A", -60, -32, "P1,D")
node("P1", -52, -32, "X1", { "X1", 1, "X1" })
node("X1", -45, -32, "P2,P3")
node("P2", -37, -32, "M1", { "X1", 1, "X1" })
node("M1", 5, -32, "B")
node("B", 45, -32, "C")
node("C", 45, 30, "M2")
node("M2", 5, 30, "X2")
node("X2", -45, 30, "D,P3")
node("P3", -45, -24, "", { "X1", 2, "X1" })
node("D", -60, 30, "")

-- Светофоры: фаза 1 — главная дорога, фаза 2 — поперечная
local function trafficLight(name: string, pos: Vector3, phase: number, facing: Vector3)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("Group", "X1")
	m:SetAttribute("Phase", phase)
	block(m, "Pole", Vector3.new(0.5, 9, 0.5), CFrame.new(pos + Vector3.new(0, 4.5, 0)), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	local head = CFrame.lookAt(pos + Vector3.new(0, 8, 0), pos + Vector3.new(0, 8, 0) + facing)
	block(m, "Housing", Vector3.new(1.4, 3.6, 1), head, Color3.fromRGB(25, 25, 25), Enum.Material.Metal)
	for i, c in { { "Red", Color3.fromRGB(255, 40, 40) }, { "Yellow", Color3.fromRGB(255, 200, 40) }, { "Green", Color3.fromRGB(40, 255, 90) } } do
		local lampPart = block(m, c[1], Vector3.new(0.9, 0.9, 0.3), head * CFrame.new(0, 1.15 - (i - 1) * 1.15, -0.55), c[2], Enum.Material.Neon)
		lampPart.Shape = Enum.PartType.Cylinder
		lampPart.CFrame = head * CFrame.new(0, 1.15 - (i - 1) * 1.15, -0.55) * CFrame.Angles(0, math.rad(90), 0)
		lampPart.Size = Vector3.new(0.3, 0.9, 0.9)
	end
	m.Parent = lights
end
trafficLight("Light_West", Vector3.new(-53, 0, -39), 1, Vector3.new(-1, 0, 0))
trafficLight("Light_East", Vector3.new(-37, 0, -25), 1, Vector3.new(1, 0, 0))
trafficLight("Light_North", Vector3.new(-52, 0, -23), 2, Vector3.new(0, 0, 1))

-- Парковки: передняя грань — куда смотрит машина
local function spot(name: string, pos: Vector3, look: Vector3, kind: string, zone: string?)
	local p = block(parking, name, Vector3.new(5, 0.2, 10), CFrame.lookAt(pos, pos + look), Color3.fromRGB(80, 160, 255), Enum.Material.Neon)
	p.Transparency = 0.6
	p.CanCollide = false
	p:SetAttribute("Type", kind)
	if zone then
		p:SetAttribute("Zone", zone)
	end
end
local EAST, NORTH = Vector3.new(1, 0, 0), Vector3.new(0, 0, -1)
spot("Car_Home1", Vector3.new(-30, 0.1, -20.5), EAST, "Civilian", "Дом1")
spot("Car_Home2", Vector3.new(30, 0.1, -20.5), EAST, "Civilian", "Дом2")
spot("Car_North1", Vector3.new(-20, 0.1, 40), EAST, "Civilian", "Street")
spot("Car_North2", Vector3.new(10, 0.1, 40), EAST, "Civilian", "Street")
spot("Car_North3", Vector3.new(32, 0.1, 40), EAST, "Civilian", "Street")
spot("Taxi_1", Vector3.new(58, 0.1, -2), NORTH, "Taxi")
spot("Taxi_2", Vector3.new(58, 0.1, 10), NORTH, "Taxi")
spot("Police_1", Vector3.new(-73, 0.1, 0), NORTH, "Police")
spot("Police_2", Vector3.new(-73, 0.1, 12), NORTH, "Police")
spot("Bus_Depot", Vector3.new(-74, 0.1, -18), NORTH, "Bus")

-- Полицейский участок: здание с дверью, стойка дежурного, кабинеты, камера
local stationFolder = sub("PoliceStation")
do
	local m = Instance.new("Model")
	m.Name = "PoliceStation"
	m.Parent = town
	local WALL = Color3.fromRGB(70, 90, 150)
	local H = 10
	block(m, "Floor", Vector3.new(16, 0.2, 24), CFrame.new(-86, 0.1, 2), Color3.fromRGB(190, 190, 200), Enum.Material.Concrete)
	block(m, "WallBack", Vector3.new(1, H, 24), CFrame.new(-93.5, 0.2 + H / 2, 2), WALL, Enum.Material.Concrete)
	block(m, "WallLeft", Vector3.new(16, H, 1), CFrame.new(-86, 0.2 + H / 2, -9.5), WALL, Enum.Material.Concrete)
	block(m, "WallRight", Vector3.new(16, H, 1), CFrame.new(-86, 0.2 + H / 2, 13.5), WALL, Enum.Material.Concrete)
	-- Фасад с проёмом под дверь (z от -0.5 до 4.5)
	block(m, "FrontA", Vector3.new(1, H, 10), CFrame.new(-78.5, 0.2 + H / 2, -5), WALL, Enum.Material.Concrete)
	block(m, "FrontB", Vector3.new(1, H, 9), CFrame.new(-78.5, 0.2 + H / 2, 9), WALL, Enum.Material.Concrete)
	block(m, "FrontTop", Vector3.new(1, H - 8.5, 5), CFrame.new(-78.5, 0.2 + 8.5 + (H - 8.5) / 2, 2), WALL, Enum.Material.Concrete)
	block(m, "Roof", Vector3.new(18, 1, 26), CFrame.new(-86, 0.2 + H + 0.5, 2), Color3.fromRGB(40, 45, 60), Enum.Material.Slate)
	lamp(m, Vector3.new(-86, 0.2 + H - 1, -3), 30, Color3.fromRGB(230, 240, 255))
	lamp(m, Vector3.new(-86, 0.2 + H - 1, 8), 30, Color3.fromRGB(230, 240, 255))
	local stationSign = block(m, "PoliceSign", Vector3.new(0.3, 1.5, 8), CFrame.new(-77.9, 9.6, 2), Color3.fromRGB(80, 140, 255), Enum.Material.SmoothPlastic)
	stationSign:SetAttribute(Config.NightLightAttribute, true)

	local door = block(doors, "Station_Door", Vector3.new(0.4, 8.3, 5), CFrame.new(-78.5, 0.2 + 4.15, 2), Color3.fromRGB(40, 60, 110), Enum.Material.Metal)
	door:SetAttribute("Hinge", "Left")

	-- Стойка дежурного: посетитель подходит от входа
	block(m, "Counter", Vector3.new(1.2, 3.2, 6), CFrame.new(-83.5, 1.8, 2), Color3.fromRGB(120, 85, 55), Enum.Material.Wood)
	block(m, "CounterTop", Vector3.new(1.8, 0.2, 6.4), CFrame.new(-83.5, 3.5, 2), Color3.fromRGB(200, 200, 205), Enum.Material.Marble)
	local function marker(name: string, pos: Vector3, look: Vector3, color: Color3)
		local p = block(stationFolder, name, Vector3.new(2, 0.2, 2), CFrame.lookAt(pos, pos + look), color, Enum.Material.Neon)
		p.Transparency = 0.4
		p.CanCollide = false
		return p
	end
	marker("Desk", Vector3.new(-85.3, 0.3, 2), Vector3.new(1, 0, 0), Color3.fromRGB(255, 255, 255))

	-- Кабинеты: столы и места, где офицеры ждут вызова
	block(m, "OfficeDesk1", Vector3.new(3, 2.6, 2), CFrame.new(-90, 1.5, -6.5), Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
	block(m, "OfficeDesk2", Vector3.new(3, 2.6, 2), CFrame.new(-90, 1.5, 10.5), Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
	block(m, "Board", Vector3.new(0.2, 3, 5), CFrame.new(-92.9, 5, -5), Color3.fromRGB(240, 240, 235), Enum.Material.SmoothPlastic)
	marker("Idle_Office1", Vector3.new(-90, 0.3, -4), Vector3.new(0, 0, -1), Color3.fromRGB(60, 120, 255))
	marker("Idle_Office2", Vector3.new(-90, 0.3, 8), Vector3.new(0, 0, 1), Color3.fromRGB(60, 120, 255))
	marker("Idle_Board", Vector3.new(-91, 0.3, -5), Vector3.new(-1, 0, 0), Color3.fromRGB(60, 120, 255))
	marker("Idle_Window", Vector3.new(-81, 0.3, 11), Vector3.new(1, 0, 0), Color3.fromRGB(60, 120, 255))
	marker("Idle_Coffee", Vector3.new(-81, 0.3, -7.5), Vector3.new(0, 0, -1), Color3.fromRGB(60, 120, 255))
	block(m, "CoffeeMachine", Vector3.new(1.5, 2.5, 1), CFrame.new(-81, 1.45, -8.7), Color3.fromRGB(30, 30, 35), Enum.Material.Metal)

	-- Камера: решётка с открытым проходом
	for z = -1, 4 do
		if z ~= 3 then
			block(m, "Bars", Vector3.new(0.2, 8, 0.2), CFrame.new(-89.5, 4.2, z + 0.5), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
		end
	end
	block(m, "CellBench", Vector3.new(2, 1, 4), CFrame.new(-92.5, 0.7, 1.5), Color3.fromRGB(90, 90, 95), Enum.Material.Metal)
	marker("Cell", Vector3.new(-91.5, 0.3, 1), Vector3.new(1, 0, 0), Color3.fromRGB(255, 60, 60))
end

-- Остановки автобуса: на тротуаре, Node — точка дороги, где встаёт автобус
local function busStop(name: string, pos: Vector3, nodeName: string, order: number, title: string)
	local p = block(stops, name, Vector3.new(4, 0.2, 2), CFrame.new(pos), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
	p.Transparency = 0.5
	p.CanCollide = false
	p:SetAttribute("Node", nodeName)
	p:SetAttribute("Order", order)
	p:SetAttribute("StopName", title)
	-- Навес
	block(street, "ShelterRoof", Vector3.new(6, 0.3, 3), CFrame.new(pos + Vector3.new(0, 4, 0)), Color3.fromRGB(70, 130, 200), Enum.Material.Glass).Transparency = 0.3
	block(street, "ShelterPost", Vector3.new(0.3, 4, 0.3), CFrame.new(pos + Vector3.new(-2.8, 2, 0)), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
	block(street, "ShelterPost", Vector3.new(0.3, 4, 0.3), CFrame.new(pos + Vector3.new(2.8, 2, 0)), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
end
busStop("Stop_Square", Vector3.new(5, 0.1, -23.5), "M1", 1, "Площадь")
busStop("Stop_North", Vector3.new(5, 0.1, 21.5), "M2", 2, "Северная")

-- Вызовы полиции: у входа в здание, Zone — куда заходят офицеры
local function call(name: string, pos: Vector3, zone: string)
	local p = block(calls, name, Vector3.new(2, 0.2, 2), CFrame.new(pos), Color3.fromRGB(30, 60, 255), Enum.Material.Neon)
	p.Transparency = 0.5
	p.CanCollide = false
	p:SetAttribute("Zone", zone)
end
call("Call_House1", Vector3.new(-35, 0.1, -38.5), "Дом1")
call("Call_House2", Vector3.new(35, 0.1, -38.5), "Дом2")
call("Call_Stall", Vector3.new(-30, 0.1, 2), "Street")

-- Места для такси
local function place(name: string, pos: Vector3)
	local p = block(places, name, Vector3.new(2, 0.2, 2), CFrame.new(pos), Color3.fromRGB(255, 200, 40), Enum.Material.Neon)
	p.Transparency = 0.5
	p.CanCollide = false
end
place("Дом 1", Vector3.new(-35, 0.1, -36))
place("Дом 2", Vector3.new(35, 0.1, -36))
place("Площадь", Vector3.new(0, 0.1, -5))
place("Ларёк с мороженым", Vector3.new(-30, 0.1, 2))
place("Северная улица", Vector3.new(5, 0.1, 22))

traffic.Parent = workspace
