-- Script: ServerScriptService > WeatherServer
-- Погода: ясно, облачно, дождь, гроза, туман. Меняется сама и плавно:
-- облака, туман и яркость солнца перетекают за WeatherConfig.FadeTime секунд.
-- Атрибуты Workspace для всех скриптов:
--   Weather (ключ: Clear/Rain/...), WeatherName, WeatherIcon,
--   Rain, Fog, Clouds (текущая сила 0..1), ThunderId (+1 при каждом громе)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("WeatherConfig"))
if not Config.Enabled then
	return
end

local rng = Random.new()

-- Атмосфера и облака: если в игре их нет — создаём, исходные значения запоминаем
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.2
	atmosphere.Haze = 0
	atmosphere.Glare = 0
	atmosphere.Parent = Lighting
end
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
if not clouds then
	clouds = Instance.new("Clouds")
	clouds.Cover = 0.4
	clouds.Density = 0.6
	clouds.Parent = workspace.Terrain
end

local base = {
	brightness = Lighting.Brightness,
	density = atmosphere.Density,
	haze = atmosphere.Haze,
	color = atmosphere.Color,
	decay = atmosphere.Decay,
	cloudColor = clouds.Color,
}
local FOG_COLOR = Color3.fromRGB(190, 195, 205)
local STORM_CLOUDS = Color3.fromRGB(90, 95, 105)

local function pickWeighted(keys: { string }): string
	local total = 0
	for _, k in keys do
		total += Config.Types[k] and Config.Types[k].Weight or 0
	end
	local roll = rng:NextNumber() * total
	for _, k in keys do
		local t = Config.Types[k]
		if t then
			roll -= t.Weight
			if roll <= 0 then
				return k
			end
		end
	end
	return keys[1]
end

local currentKey = Config.Types[Config.Start] and Config.Start or "Clear"
local state = {} -- текущие значения, плавно догоняют цель
do
	local t = Config.Types[currentKey]
	state = { rain = t.Rain, clouds = t.Clouds, fog = t.Fog, brightness = t.Brightness }
end

local function setWeather(key: string)
	currentKey = key
	local t = Config.Types[key]
	workspace:SetAttribute("Weather", key)
	workspace:SetAttribute("WeatherName", t.Name)
	workspace:SetAttribute("WeatherIcon", t.Icon)
end
setWeather(currentKey)

-- Меню отладки: ForceWeather = ключ — погода включается сразу, без плавного перехода
workspace:GetAttributeChangedSignal("ForceWeather"):Connect(function()
	local key = workspace:GetAttribute("ForceWeather")
	local t = type(key) == "string" and Config.Types[key]
	if t then
		setWeather(key)
		state = { rain = t.Rain, clouds = t.Clouds, fog = t.Fog, brightness = t.Brightness }
		workspace:SetAttribute("ForceWeather", nil)
	end
end)

-- Смена погоды по расписанию
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(Config.ChangeEvery.Min, Config.ChangeEvery.Max))
		local options = Config.Types[currentKey].Next or { "Clear", "Cloudy", "Rain" }
		setWeather(pickWeighted(options))
	end
end)

-- Гром в грозу
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(Config.ThunderEvery.Min, Config.ThunderEvery.Max))
		local t = Config.Types[currentKey]
		if t.Thunder and state.rain > 0.5 then
			workspace:SetAttribute("ThunderId", (workspace:GetAttribute("ThunderId") or 0) + 1)
		end
	end
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.5 then
		return
	end
	local step = accumulator / Config.FadeTime
	accumulator = 0

	local target = Config.Types[currentKey]
	local function approach(cur: number, goal: number): number
		if cur < goal then
			return math.min(goal, cur + step)
		end
		return math.max(goal, cur - step)
	end
	state.rain = approach(state.rain, target.Rain)
	state.clouds = approach(state.clouds, target.Clouds)
	state.fog = approach(state.fog, target.Fog)
	state.brightness = approach(state.brightness, target.Brightness)

	-- Небо и свет
	Lighting.Brightness = base.brightness * state.brightness
	atmosphere.Density = math.clamp(base.density + state.fog * 0.45, 0, 1)
	atmosphere.Haze = base.haze + state.fog * 3
	atmosphere.Color = base.color:Lerp(FOG_COLOR, state.fog)
	atmosphere.Decay = base.decay:Lerp(FOG_COLOR, state.fog * 0.8)
	clouds.Cover = math.clamp(state.clouds, 0, 1)
	clouds.Density = math.clamp(0.4 + state.clouds * 0.5, 0, 1)
	clouds.Color = base.cloudColor:Lerp(STORM_CLOUDS, math.clamp((state.clouds - 0.6) / 0.4, 0, 1) * state.rain)

	workspace:SetAttribute("Rain", math.floor(state.rain * 100) / 100)
	workspace:SetAttribute("Fog", math.floor(state.fog * 100) / 100)
	workspace:SetAttribute("Clouds", math.floor(state.clouds * 100) / 100)
end)
