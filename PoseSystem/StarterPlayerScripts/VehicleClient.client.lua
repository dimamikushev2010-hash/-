-- LocalScript: StarterPlayer > StarterPlayerScripts > VehicleClient
-- Внешний вид и звуки машин (у каждого игрока на экране, плавно):
--   * двери и багажник открываются/закрываются, автобусные двери отъезжают;
--   * колёса крутятся по скорости;
--   * фары, стоп-сигналы, поворотники (с тиканьем), мигалки полиции, шашечки такси;
--   * звуки: двигатель, гудок, сирена, двери, багажник, щелчок фар;
--   * меню такси для игрока (куда ехать).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local remote = ReplicatedStorage:WaitForChild("VehicleRemote")

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)

local vehicles = {} -- [model] = состояние

local function makeSound(parent: Instance, def, looped: boolean?): Sound?
	if not def or def.Id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Volume = def.Volume or 0.5
	s.Looped = looped == true
	s.RollOffMaxDistance = 120
	s.RollOffMinDistance = 10
	s.Parent = parent
	return s
end

local function play(sound: Sound?)
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

local LIGHT_PREFIXES = {
	{ "Headlight", "head" },
	{ "Taillight", "tail" },
	{ "Indicator_L", "indL" },
	{ "Indicator_R", "indR" },
	{ "SirenRed", "sirenR" },
	{ "SirenBlue", "sirenB" },
	{ "TaxiSign", "taxi" },
}

local function setLamp(lamp, on: boolean, strength: number?)
	local p = lamp.part
	local k = strength or 1
	p.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	p.Color = on and lamp.color:Lerp(BLACK, 1 - k) or lamp.color:Lerp(BLACK, 0.55)
	for _, l in lamp.lights do
		l.Enabled = on
	end
end

local function setup(model: Model)
	if vehicles[model] or not model:GetAttribute("VehicleId") then
		return
	end
	local body = model.PrimaryPart or model:WaitForChild("Body", 5)
	if not body then
		return
	end
	local kind = model:GetAttribute("VehicleType")
	local state = {
		model = model,
		body = body,
		kind = kind,
		joints = {},
		wheels = {},
		lamps = { head = {}, tail = {}, indL = {}, indR = {}, sirenR = {}, sirenB = {}, taxi = {}, glow = {} },
		last = {},
		blinkOn = false,
	}

	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local kindAttr = d:GetAttribute("Kind")
			if kindAttr == "Wheel" then
				table.insert(state.wheels, { motor = d, axle = d:GetAttribute("AxleLocal") or Vector3.xAxis, radius = d:GetAttribute("Radius") or 1, angle = 0 })
			elseif kindAttr == "Door" or kindAttr == "Trunk" then
				table.insert(state.joints, {
					motor = d,
					kind = kindAttr,
					group = d:GetAttribute("Group"),
					hinge = d:GetAttribute("HingeLocal"),
					axis = d:GetAttribute("AxisLocal"),
					angle = d:GetAttribute("OpenAngle"),
					slide = d:GetAttribute("SlideLocal"),
					alpha = 0,
					open = false,
				})
			end
		elseif d:IsA("BasePart") then
			for _, pair in LIGHT_PREFIXES do
				if string.find(d.Name, "^" .. pair[1]) then
					local lights = {}
					for _, l in d:GetDescendants() do
						if l:IsA("Light") then
							table.insert(lights, l)
						end
					end
					table.insert(state.lamps[pair[2]], { part = d, color = d.Color, lights = lights })
					break
				end
			end
			if d:GetAttribute("NightGlow") then
				table.insert(state.lamps.glow, { part = d, color = d.Color, lights = {} })
			end
		end
	end
	for _, group in state.lamps do
		for _, lamp in group do
			setLamp(lamp, false)
		end
	end

	local isBus = kind == "Bus"
	local V = Sounds.Vehicle
	state.sounds = {
		engine = makeSound(body, (isBus and V.BusEngine.Id ~= "") and V.BusEngine or V.Engine, true),
		horn = makeSound(body, (isBus and V.BusHorn.Id ~= "") and V.BusHorn or V.Horn),
		siren = kind == "Police" and makeSound(body, V.Siren, true) or nil,
		doorOpen = makeSound(body, isBus and V.BusDoor or V.DoorOpen),
		doorClose = makeSound(body, isBus and V.BusDoor or V.DoorClose),
		trunkOpen = makeSound(body, V.TrunkOpen),
		trunkClose = makeSound(body, V.TrunkClose),
		indicator = makeSound(body, V.Indicator),
		lightSwitch = makeSound(body, V.LightSwitch),
		brake = makeSound(body, V.Brake),
	}

	model:GetAttributeChangedSignal("HornId"):Connect(function()
		play(state.sounds.horn)
	end)
	vehicles[model] = state
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			vehicles[model] = nil
		end
	end)
end

local function easeInOut(t: number): number
	return t * t * (3 - 2 * t)
end

local function updateVehicle(state, dt: number, now: number)
	local model, body = state.model, state.body
	local look = body.CFrame.LookVector
	local speed = body.AssemblyLinearVelocity:Dot(look)

	-- Колёса
	for _, w in state.wheels do
		w.angle = (w.angle - speed * dt / w.radius) % (math.pi * 2)
		w.motor.Transform = CFrame.fromAxisAngle(w.axle, w.angle)
	end

	-- Двери и багажник
	for _, j in state.joints do
		local open = model:GetAttribute(j.group) == true
		if open ~= j.open then
			j.open = open
			if j.kind == "Trunk" then
				play(open and state.sounds.trunkOpen or nil)
			else
				play(open and state.sounds.doorOpen or nil)
			end
			j.closingSound = not open
		end
		local targetAlpha = open and 1 or 0
		if j.alpha ~= targetAlpha then
			local step = dt * Config.DoorSpeed * (j.kind == "Trunk" and 0.7 or 1)
			j.alpha = targetAlpha > j.alpha and math.min(1, j.alpha + step) or math.max(0, j.alpha - step)
			local t = easeInOut(j.alpha)
			if j.slide then
				j.motor.Transform = CFrame.new(j.slide * t)
			elseif j.hinge and j.axis then
				j.motor.Transform = CFrame.new(j.hinge) * CFrame.fromAxisAngle(j.axis, j.angle * t) * CFrame.new(-j.hinge)
			end
			if j.alpha == 0 and j.closingSound then
				j.closingSound = false
				play(j.kind == "Trunk" and state.sounds.trunkClose or state.sounds.doorClose)
			end
		end
	end

	-- Фары
	local headlights = model:GetAttribute("Headlights") == true
	if state.last.headlights ~= headlights then
		state.last.headlights = headlights
		for _, lamp in state.lamps.head do
			setLamp(lamp, headlights)
		end
		for _, lamp in state.lamps.glow do
			setLamp(lamp, headlights)
		end
		play(state.sounds.lightSwitch)
	end
	local brake = model:GetAttribute("Brake") == true and model:GetAttribute("Engine") == true
	local tailKey = (brake and "brake") or (headlights and "dim") or "off"
	if state.last.tail ~= tailKey then
		if tailKey == "brake" and state.last.tail ~= nil and math.abs(speed) > 8 then
			play(state.sounds.brake)
		end
		state.last.tail = tailKey
		for _, lamp in state.lamps.tail do
			setLamp(lamp, tailKey ~= "off", tailKey == "brake" and 1 or 0.55)
		end
	end

	-- Поворотники: мигают и тикают
	local indicator = model:GetAttribute("Indicator") or ""
	local blink = indicator ~= "" and (now * 1.6) % 1 < 0.5
	if blink ~= state.blinkOn or indicator ~= state.last.indicator then
		if blink and not state.blinkOn then
			play(state.sounds.indicator)
		end
		state.blinkOn = blink
		state.last.indicator = indicator
		for _, lamp in state.lamps.indL do
			setLamp(lamp, blink and indicator == "L")
		end
		for _, lamp in state.lamps.indR do
			setLamp(lamp, blink and indicator == "R")
		end
	end

	-- Мигалки и сирена
	local siren = model:GetAttribute("Siren") == true
	if siren then
		local phase = (now * 4) % 1 < 0.5
		for _, lamp in state.lamps.sirenR do
			setLamp(lamp, phase)
		end
		for _, lamp in state.lamps.sirenB do
			setLamp(lamp, not phase)
		end
	elseif state.last.siren then
		for _, lamp in state.lamps.sirenR do
			setLamp(lamp, false)
		end
		for _, lamp in state.lamps.sirenB do
			setLamp(lamp, false)
		end
	end
	state.last.siren = siren
	local sirenSound = state.sounds.siren
	if sirenSound then
		local wantSound = siren and model:GetAttribute("SirenMuted") ~= true
		if wantSound and not sirenSound.IsPlaying then
			sirenSound:Play()
		elseif not wantSound and sirenSound.IsPlaying then
			sirenSound:Stop()
		end
	end

	-- Шашечки такси: горят, когда свободно
	local taxiFree = model:GetAttribute("TaxiBusy") ~= true
	if state.last.taxiFree ~= taxiFree then
		state.last.taxiFree = taxiFree
		for _, lamp in state.lamps.taxi do
			setLamp(lamp, taxiFree)
		end
	end

	-- Двигатель
	local engine = state.sounds.engine
	if engine then
		local on = model:GetAttribute("Engine") == true
		if on and not engine.IsPlaying then
			engine:Play()
		elseif not on and engine.IsPlaying then
			engine:Stop()
		end
		engine.PlaybackSpeed = 0.7 + math.min(1, math.abs(speed) / 30) * 0.8
	end
end

task.spawn(function()
	local map = workspace:WaitForChild(Config.MapFolder, 60)
	if not map then
		return
	end
	local folder = map:WaitForChild(Config.VehiclesFolder, 60)
	if not folder then
		return
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			task.spawn(setup, m)
		end
	end
	folder.ChildAdded:Connect(function(m)
		if m:IsA("Model") then
			task.wait(0.2)
			setup(m)
		end
	end)
end)

DebugTimer.connect(RunService.RenderStepped, "VehicleClient", function(dt)
	local now = os.clock()
	for model, state in pairs(vehicles) do
		if state.body.Parent then
			updateVehicle(state, dt, now)
		else
			vehicles[model] = nil
		end
	end
end)

---------------------------------------------------------------------
-- Меню такси
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "TaxiMenu"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(340, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(30, 28, 20)
panel.BackgroundTransparency = 0.05
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 200, 40)
stroke.Thickness = 2
stroke.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 14)
pad.PaddingBottom = UDim.new(0, 14)
pad.PaddingLeft = UDim.new(0, 14)
pad.PaddingRight = UDim.new(0, 14)
pad.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel
local scale = Instance.new("UIScale")
scale.Parent = panel

local title = Instance.new("TextLabel")
title.LayoutOrder = 0
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 28)
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextColor3 = Color3.fromRGB(255, 210, 60)
title.Text = "🚕 Куда едем?"
title.Parent = panel

local function button(text: string, order: number, accent: boolean, onClick)
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 38)
	b.BackgroundColor3 = accent and Color3.fromRGB(70, 45, 45) or Color3.fromRGB(60, 55, 35)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(245, 240, 225)
	b.Text = text
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	b.Activated:Connect(onClick)
end

local function closeMenu()
	gui.Enabled = false
end

remote.OnClientEvent:Connect(function(action, model, names, price)
	if action ~= "TaxiMenu" then
		return
	end
	for _, c in panel:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	title.Text = string.format("🚕 Куда едем? (%d 🪙)", price)
	for i, name in names do
		button(name, i, false, function()
			remote:FireServer("TaxiGo", model, i)
			closeMenu()
		end)
	end
	button("Отмена", #names + 1, true, closeMenu)
	gui.Enabled = true
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end)
