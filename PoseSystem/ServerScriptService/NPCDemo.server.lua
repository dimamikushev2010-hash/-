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

block(street, "Road", Vector3.new(110, 0.1, 12), CFrame.new(0, 0.05, -32), Color3.fromRGB(60, 60, 65), Enum.Material.Asphalt).CanCollide = false
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
