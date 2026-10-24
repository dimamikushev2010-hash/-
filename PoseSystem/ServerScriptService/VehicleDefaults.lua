-- ModuleScript: ServerScriptService > VehicleDefaults
-- Простые шаблоны машин из деталей — на случай, если в ServerStorage > VehicleTemplates
-- ещё нет своих. Собраны строго по правилам из VEHICLE_SETUP.md, поэтому по ним же
-- удобно проверять свои шаблоны.

local VehicleDefaults = {}

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.Parent = model
	return p
end

local function seat(model: Model, name: string, position: Vector3)
	local s = Instance.new("Seat")
	s.Name = name
	s.Size = Vector3.new(1.6, 0.4, 1.6)
	s.CFrame = CFrame.new(position)
	s.Transparency = 1
	s.Anchored = true
	s.Parent = model
	return s
end

local function light(p: BasePart, className: string, face: Enum.NormalId?, range: number, color: Color3)
	local l = Instance.new(className)
	l.Range = range
	l.Color = color
	l.Brightness = 2
	if face and (className == "SpotLight" or className == "SurfaceLight") then
		(l :: any).Face = face
	end
	l.Parent = p
end

local WHEEL = Color3.fromRGB(25, 25, 28)
local GLASS = Color3.fromRGB(150, 200, 230)
local HEAD = Color3.fromRGB(255, 250, 225)
local TAIL = Color3.fromRGB(200, 20, 20)
local AMBER = Color3.fromRGB(255, 160, 20)

-- Легковая машина: длина вдоль -Z (вперёд), ширина по X
local function car(name: string, vehicleType: string, paint: Color3, extras: ((Model) -> ())?)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("VehicleType", vehicleType)

	local body = part(m, "Body", Vector3.new(5, 1.6, 10), CFrame.new(0, 1.9, 0), paint)
	body:SetAttribute("Paint", true)
	m.PrimaryPart = body
	local cabin = part(m, "Cabin", Vector3.new(4.6, 1.6, 5), CFrame.new(0, 3.5, 0.6), paint)
	cabin:SetAttribute("Paint", true)
	local wind = part(m, "Windshield", Vector3.new(4.3, 1.4, 0.2), CFrame.new(0, 3.5, -1.95), GLASS, Enum.Material.Glass)
	wind.Transparency = 0.4
	local rear = part(m, "RearWindow", Vector3.new(4.3, 1.4, 0.2), CFrame.new(0, 3.5, 3.15), GLASS, Enum.Material.Glass)
	rear.Transparency = 0.4

	-- Двери: петли спереди (Hinge = "Front")
	for _, d in { { "Door_FL", -2.55, -0.9 }, { "Door_FR", 2.55, -0.9 }, { "Door_RL", -2.55, 1.9 }, { "Door_RR", 2.55, 1.9 } } do
		local door = part(m, d[1], Vector3.new(0.2, 1.5, 2.6), CFrame.new(d[2], 2.1, d[3]), paint)
		door:SetAttribute("Paint", true)
		door:SetAttribute("Hinge", "Front")
		local glass = part(m, d[1] .. "_Glass", Vector3.new(0.15, 1.2, 2.2), CFrame.new(d[2], 3.5, d[3]), GLASS, Enum.Material.Glass)
		glass.Transparency = 0.4
		glass:SetAttribute("PartOf", d[1]) -- стекло двигается вместе с дверью
	end

	local trunk = part(m, "Trunk", Vector3.new(4.6, 0.3, 2), CFrame.new(0, 2.85, 4), paint)
	trunk:SetAttribute("Paint", true)

	-- Колёса: цилиндры, ось по X
	for _, w in { { "Wheel_FL", -2.4, -3.2 }, { "Wheel_FR", 2.4, -3.2 }, { "Wheel_RL", -2.4, 3.2 }, { "Wheel_RR", 2.4, 3.2 } } do
		part(m, w[1], Vector3.new(0.8, 2, 2), CFrame.new(w[2], 1, w[3]), WHEEL, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end

	for _, x in { -1.8, 1.8 } do
		local h = part(m, "Headlight", Vector3.new(1, 0.5, 0.2), CFrame.new(x, 2.1, -5.05), HEAD)
		light(h, "SpotLight", Enum.NormalId.Front, 40, HEAD)
		part(m, "Taillight", Vector3.new(1, 0.5, 0.2), CFrame.new(x, 2.1, 5.05), TAIL)
		part(m, x < 0 and "Indicator_L" or "Indicator_R", Vector3.new(0.4, 0.3, 0.2), CFrame.new(x * 1.3, 1.6, -5.05), AMBER)
		part(m, x < 0 and "Indicator_L" or "Indicator_R", Vector3.new(0.4, 0.3, 0.2), CFrame.new(x * 1.3, 1.6, 5.05), AMBER)
	end

	-- Места: водитель слева спереди, пассажиры
	seat(m, "Seat_Driver", Vector3.new(-1.1, 2.6, -0.4))
	seat(m, "Seat_1", Vector3.new(1.1, 2.6, -0.4))
	seat(m, "Seat_2", Vector3.new(-1.1, 2.6, 2))
	seat(m, "Seat_3", Vector3.new(1.1, 2.6, 2))

	if extras then
		extras(m)
	end
	return m
end

local function bus()
	local m = Instance.new("Model")
	m.Name = "DefaultBus"
	m:SetAttribute("VehicleType", "Bus")
	local paint = Color3.fromRGB(240, 190, 40)
	local body = part(m, "Body", Vector3.new(7, 6, 26), CFrame.new(0, 4.4, 0), paint)
	m.PrimaryPart = body
	local stripe = part(m, "Stripe", Vector3.new(7.1, 0.6, 26.1), CFrame.new(0, 3, 0), Color3.fromRGB(40, 90, 200))
	stripe.CanCollide = false
	for i = -4, 4 do
		local win = part(m, "Window", Vector3.new(7.1, 1.8, 2), CFrame.new(0, 5.6, i * 2.6), GLASS, Enum.Material.Glass)
		win.Transparency = 0.35
	end
	local front = part(m, "Windshield", Vector3.new(6.5, 2.5, 0.2), CFrame.new(0, 5.3, -13.05), GLASS, Enum.Material.Glass)
	front.Transparency = 0.35
	-- Сдвижные двери справа (правостороннее движение — к тротуару)
	for _, d in { { "Door_Front", -10 }, { "Door_Rear", 4 } } do
		local door = part(m, d[1], Vector3.new(0.2, 4.6, 2.6), CFrame.new(3.55, 3.9, d[2]), GLASS, Enum.Material.Glass)
		door.Transparency = 0.25
		door:SetAttribute("Hinge", "Slide")
	end
	for _, w in { { -3.3, -8.5 }, { 3.3, -8.5 }, { -3.3, 8 }, { 3.3, 8 } } do
		part(m, "Wheel", Vector3.new(1, 2.8, 2.8), CFrame.new(w[1], 1.4, w[2]), WHEEL, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	for _, x in { -2.6, 2.6 } do
		local h = part(m, "Headlight", Vector3.new(1.2, 0.6, 0.2), CFrame.new(x, 2.6, -13.05), HEAD)
		light(h, "SpotLight", Enum.NormalId.Front, 45, HEAD)
		part(m, "Taillight", Vector3.new(1.2, 0.6, 0.2), CFrame.new(x, 2.6, 13.05), TAIL)
		part(m, x < 0 and "Indicator_L" or "Indicator_R", Vector3.new(0.5, 0.4, 0.2), CFrame.new(x * 1.2, 2, -13.05), AMBER)
		part(m, x < 0 and "Indicator_L" or "Indicator_R", Vector3.new(0.5, 0.4, 0.2), CFrame.new(x * 1.2, 2, 13.05), AMBER)
	end
	local sign = part(m, "RouteSign", Vector3.new(4, 0.8, 0.2), CFrame.new(0, 6.9, -13.05), Color3.fromRGB(255, 140, 30))
	sign:SetAttribute("NightGlow", true)
	seat(m, "Seat_Driver", Vector3.new(-2.2, 3.6, -10.5))
	local n = 1
	for row = 0, 5 do
		for _, x in { -2, 2 } do
			if not (x > 0 and (row == 0 or row == 4)) then -- место у дверей свободно
				seat(m, "Seat_" .. n, Vector3.new(x, 3.6, -7.5 + row * 3.3))
				n += 1
			end
		end
	end
	return m
end

function VehicleDefaults.Build(): { Model }
	local list = {}
	table.insert(list, car("DefaultCar", "Civilian", Color3.fromRGB(200, 40, 40)))
	table.insert(list, car("DefaultTaxi", "Taxi", Color3.fromRGB(250, 200, 30), function(m)
		local sign = part(m, "TaxiSign", Vector3.new(1.8, 0.6, 0.8), CFrame.new(0, 4.6, 0.6), Color3.fromRGB(255, 255, 200))
		sign.CanCollide = false
	end))
	table.insert(list, car("DefaultPolice", "Police", Color3.fromRGB(245, 245, 250), function(m)
		for _, x in { -0.6, 0.6 } do
			local siren = part(m, x < 0 and "SirenRed" or "SirenBlue", Vector3.new(1, 0.4, 0.6), CFrame.new(x, 4.5, 0.6),
				x < 0 and Color3.fromRGB(230, 30, 30) or Color3.fromRGB(30, 80, 255))
			light(siren, "PointLight", nil, 18, siren.Color)
		end
		local stripe = part(m, "Stripe", Vector3.new(5.05, 0.5, 6), CFrame.new(0, 2.2, 0.5), Color3.fromRGB(30, 50, 140))
		stripe.CanCollide = false
	end))
	table.insert(list, bus())
	return list
end

return VehicleDefaults
