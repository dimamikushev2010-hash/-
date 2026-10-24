-- Script: ServerScriptService > DayNightServer
-- Смена дня и ночи: время идёт само (NPCConfig.DayLengthMinutes),
-- ночью включаются детали с атрибутом NightLight = true (фонари, окна, вывески).
-- Атрибут Workspace.IsNight подсказывает жителям, что пора спать.
-- Ещё атрибуты Workspace для расписания жителей и часов на экране:
--   Hour (час, дробный), Day (номер дня), WeekDay (1–7), Weekend (true/false), Period (имя периода)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))

if not Config.DayNight then
	return
end

Lighting.ClockTime = Config.StartTime

local function isNightAt(hour: number): boolean
	if Config.NightStart > Config.NightEnd then
		return hour >= Config.NightStart or hour < Config.NightEnd
	end
	return hour >= Config.NightStart and hour < Config.NightEnd
end

-- Фонари: запоминаем исходные материал и яркость, ночью — неон и свет
local lights = {} -- [part] = { material, lights = { [light] = brightness } }

local function registerLight(part: Instance)
	if not part:IsA("BasePart") or lights[part] or part:GetAttribute(Config.NightLightAttribute) ~= true then
		return
	end
	local entry = { material = part.Material, lights = {} }
	for _, d in part:GetDescendants() do
		if d:IsA("Light") then
			entry.lights[d] = d.Brightness
		end
	end
	lights[part] = entry
end

local function applyLights(night: boolean)
	for part, entry in pairs(lights) do
		if not part.Parent then
			lights[part] = nil
			continue
		end
		part.Material = night and Enum.Material.Neon or entry.material
		for light, brightness in pairs(entry.lights) do
			light.Enabled = night
			light.Brightness = brightness
		end
	end
end

task.defer(function()
	task.wait(1) -- даём карте (и демо-городку) построиться
	for _, d in workspace:GetDescendants() do
		registerLight(d)
	end
	workspace.DescendantAdded:Connect(function(d)
		task.defer(function()
			registerLight(d)
			if lights[d] then
				applyLights(workspace:GetAttribute("IsNight") == true)
			end
		end)
	end)
	applyLights(isNightAt(Lighting.ClockTime))
end)

local hoursPerSecond = 24 / (Config.DayLengthMinutes * 60)
local wasNight = nil
local pending = 0
local day = 1

local function periodAt(hour: number): string
	if isNightAt(hour) then
		return "Ночь"
	end
	for _, p in Config.Schedule or {} do
		if hour >= p.From and hour < p.To then
			return p.Name
		end
	end
	return "День"
end

local function publishTime()
	local hour = Lighting.ClockTime
	local weekDay = ((Config.StartWeekDay or 1) - 1 + day - 1) % 7 + 1
	workspace:SetAttribute("Hour", math.floor(hour * 100) / 100)
	workspace:SetAttribute("Day", day)
	workspace:SetAttribute("WeekDay", weekDay)
	workspace:SetAttribute("Weekend", (Config.WeekendDays or {})[weekDay] == true)
	local period = periodAt(hour)
	if workspace:GetAttribute("Period") ~= period then
		workspace:SetAttribute("Period", period)
	end
end
publishTime()
RunService.Heartbeat:Connect(function(dt)
	-- Обновляем время 4 раза в секунду: этого хватает для плавности и не нагружает сеть
	pending += dt
	if pending < 0.25 then
		return
	end
	local before = Lighting.ClockTime
	Lighting.ClockTime = (Lighting.ClockTime + pending * hoursPerSecond) % 24
	pending = 0
	if Lighting.ClockTime < before then
		day += 1 -- полночь: новый день недели
	end
	publishTime()
	local night = isNightAt(Lighting.ClockTime)
	if night ~= wasNight then
		wasNight = night
		workspace:SetAttribute("IsNight", night)
		applyLights(night)
	end
end)
