-- LocalScript: StarterPlayer > StarterPlayerScripts > WeatherClient
-- Погода на экране игрока:
--   * дождь струями вокруг камеры и брызги на земле (под крышей дождя нет);
--   * шум дождя и ветра, вспышки молний и раскаты грома с задержкой;
--   * часы сверху экрана: время, день недели, период дня и погода.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("WeatherConfig"))
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------------
-- Дождь
---------------------------------------------------------------------

local function emitterPart(name: string, size: Vector3)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = size
	p.Parent = camera
	return p
end

local rainPart = emitterPart("RainEmitter", Vector3.new(140, 1, 140))
local rain = Instance.new("ParticleEmitter")
rain.Color = ColorSequence.new(Color3.fromRGB(190, 205, 225))
rain.LightEmission = 0.1
rain.LightInfluence = 0.6
rain.Transparency = NumberSequence.new(0.45)
rain.Size = NumberSequence.new(0.08)
rain.Squash = NumberSequence.new(2.5) -- вытянутые капли
rain.Orientation = Enum.ParticleOrientation.VelocityParallel
rain.EmissionDirection = Enum.NormalId.Bottom
rain.Speed = NumberRange.new(90, 110)
rain.Lifetime = NumberRange.new(0.8, 1)
rain.SpreadAngle = Vector2.new(4, 4)
rain.Rate = 0
rain.Parent = rainPart

local splashPart = emitterPart("RainSplash", Vector3.new(60, 0.2, 60))
local splash = Instance.new("ParticleEmitter")
splash.Color = ColorSequence.new(Color3.fromRGB(220, 230, 245))
splash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
splash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.35) })
splash.Speed = NumberRange.new(2, 4)
splash.SpreadAngle = Vector2.new(60, 60)
splash.EmissionDirection = Enum.NormalId.Top
splash.Lifetime = NumberRange.new(0.15, 0.3)
splash.Acceleration = Vector3.new(0, -20, 0)
splash.Rate = 0
splash.Parent = splashPart

local function loopSound(def)
	if not def or def.Id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Looped = true
	s.Volume = 0
	s.Parent = workspace
	s:Play()
	return { sound = s, volume = def.Volume or 0.5 }
end
local rainSound = loopSound(Sounds.Weather and Sounds.Weather.Rain)
local windSound = loopSound(Sounds.Weather and Sounds.Weather.Wind)

local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Exclude

-- Под крышей? (дождевые капли проходят сквозь крыши, поэтому внутри их выключаем)
local function underRoof(position: Vector3): boolean
	local ignore = { camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	skyParams.FilterDescendantsInstances = ignore
	return workspace:Raycast(position, Vector3.new(0, 60, 0), skyParams) ~= nil
end

---------------------------------------------------------------------
-- Молнии и гром
---------------------------------------------------------------------

local flash = Instance.new("ColorCorrectionEffect")
flash.Name = "LightningFlash"
flash.Parent = Lighting

workspace:GetAttributeChangedSignal("ThunderId"):Connect(function()
	-- Вспышка: двойное мигание
	for _, power in { 0.55, 0.3 } do
		flash.Brightness = power
		flash.Contrast = power * 0.4
		TweenService:Create(flash, TweenInfo.new(0.25), { Brightness = 0, Contrast = 0 }):Play()
		task.wait(0.12)
	end
	-- Гром приходит позже (как будто молния далеко)
	task.wait(0.4 + math.random() * 1.4)
	local def = Sounds.Weather and Sounds.Weather.Thunder
	if def and def.Id ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = def.Id
		s.Volume = def.Volume or 0.8
		s.PlaybackSpeed = 0.9 + math.random() * 0.2
		s.Parent = workspace
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
end)

---------------------------------------------------------------------
-- Часы и погода сверху экрана
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ClockHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local hud = Instance.new("Frame")
hud.AnchorPoint = Vector2.new(1, 0)
hud.Position = UDim2.new(1, -14, 0, 10)
hud.Size = UDim2.fromOffset(0, 46)
hud.AutomaticSize = Enum.AutomaticSize.X
hud.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
hud.BackgroundTransparency = 0.2
hud.Parent = gui
Instance.new("UICorner", hud).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 110, 160)
stroke.Transparency = 0.4
stroke.Parent = hud
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = hud
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 10)
layout.Parent = hud

local function hudLabel(order: number, size: number, bold: boolean, color: Color3)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 40)
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.Parent = hud
	return l
end
local timeLabel = hudLabel(1, 22, true, Color3.fromRGB(245, 245, 250))
local dayLabel = hudLabel(2, 15, false, Color3.fromRGB(170, 185, 215))
local weatherLabel = hudLabel(3, 15, false, Color3.fromRGB(200, 215, 240))
local hudScale = Instance.new("UIScale")
hudScale.Parent = hud

local lastWeather = nil
local function updateHud()
	local hour = workspace:GetAttribute("Hour") or Lighting.ClockTime
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60 / 10) * 10 -- шаг 10 минут, чтобы не мельтешило
	timeLabel.Text = string.format("%02d:%02d", h, m)
	local weekDay = workspace:GetAttribute("WeekDay") or 1
	local names = NPCConfig.WeekDays or {}
	local period = workspace:GetAttribute("Period") or ""
	local weekend = workspace:GetAttribute("Weekend") == true
	dayLabel.Text = string.format("%s%s · %s", names[weekDay] or "", weekend and " 🎉" or "", period)
	local key = workspace:GetAttribute("Weather")
	local icon = workspace:GetAttribute("WeatherIcon") or ""
	local name = workspace:GetAttribute("WeatherName") or ""
	weatherLabel.Text = icon .. " " .. name
	if key ~= lastWeather then
		-- Погода сменилась — часы «подпрыгивают»
		if lastWeather ~= nil then
			hudScale.Scale = 1.15
			TweenService:Create(hudScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		lastWeather = key
	end
end

---------------------------------------------------------------------
-- Каждый кадр
---------------------------------------------------------------------

local hudTimer, roofTimer, indoors = 0, 0, false
RunService.RenderStepped:Connect(function(dt)
	local camPos = camera.CFrame.Position
	local intensity = workspace:GetAttribute("Rain") or 0

	roofTimer -= dt
	if roofTimer <= 0 then
		roofTimer = 0.3
		indoors = underRoof(camPos)
	end

	-- Облако капель над камерой, чуть впереди по ходу взгляда
	local ahead = camera.CFrame.LookVector * Vector3.new(1, 0, 1) * 20
	rainPart.CFrame = CFrame.new(camPos + ahead + Vector3.new(0, 45, 0))
	rain.Rate = indoors and 0 or Config.RainDrops * intensity

	local ignore = { camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	skyParams.FilterDescendantsInstances = ignore
	local ground = workspace:Raycast(camPos, Vector3.new(0, -60, 0), skyParams)
	if ground then
		splashPart.CFrame = CFrame.new(ground.Position + Vector3.new(0, 0.1, 0))
	end
	splash.Rate = (indoors or not ground) and 0 or 160 * intensity

	-- Звук: внутри тише
	if rainSound then
		local target = rainSound.volume * intensity * (indoors and 0.35 or 1)
		rainSound.sound.Volume += (target - rainSound.sound.Volume) * math.min(1, dt * 2)
	end
	if windSound then
		local fog = workspace:GetAttribute("Fog") or 0
		local target = windSound.volume * math.max(fog, intensity * 0.8) * (indoors and 0.3 or 1)
		windSound.sound.Volume += (target - windSound.sound.Volume) * math.min(1, dt * 1.5)
	end

	hudTimer -= dt
	if hudTimer <= 0 then
		hudTimer = 0.5
		updateHud()
	end
end)
