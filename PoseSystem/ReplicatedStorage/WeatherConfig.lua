-- ModuleScript: ReplicatedStorage > WeatherConfig
-- Погода: сама меняется со временем, плавно переходит из одной в другую.
-- Звуки дождя и грома — в SoundConfig.Weather.

local WeatherConfig = {}

WeatherConfig.Enabled = true
WeatherConfig.Start = "Clear" -- с какой погоды начинается сервер
WeatherConfig.ChangeEvery = NumberRange.new(180, 360) -- как часто меняется, сек
WeatherConfig.FadeTime = 25 -- за сколько секунд одна погода плавно переходит в другую

--[[
	Weight     — как часто выпадает (больше = чаще)
	Rain       — сила дождя 0..1
	Clouds     — облачность 0..1
	Fog        — туман 0..1
	Brightness — яркость солнца (1 = как обычно)
	Thunder    — молнии и гром
	Next       — куда может смениться (чтобы после ясно не начиналась сразу гроза)
]]
WeatherConfig.Types = {
	Clear = { Name = "Ясно", Icon = "☀️", Weight = 4, Rain = 0, Clouds = 0.3, Fog = 0, Brightness = 1, Thunder = false,
		Next = { "Clear", "Cloudy", "Fog" } },
	Cloudy = { Name = "Облачно", Icon = "☁️", Weight = 3, Rain = 0, Clouds = 0.75, Fog = 0.15, Brightness = 0.8, Thunder = false,
		Next = { "Clear", "Cloudy", "Rain" } },
	Rain = { Name = "Дождь", Icon = "🌧️", Weight = 2, Rain = 0.65, Clouds = 0.9, Fog = 0.3, Brightness = 0.6, Thunder = false,
		Next = { "Cloudy", "Rain", "Storm" } },
	Storm = { Name = "Гроза", Icon = "⛈️", Weight = 1, Rain = 1, Clouds = 1, Fog = 0.4, Brightness = 0.4, Thunder = true,
		Next = { "Rain", "Cloudy" } },
	Fog = { Name = "Туман", Icon = "🌫️", Weight = 1, Rain = 0, Clouds = 0.6, Fog = 0.85, Brightness = 0.7, Thunder = false,
		Next = { "Clear", "Cloudy" } },
}

WeatherConfig.ThunderEvery = NumberRange.new(8, 22) -- молнии в грозу, сек
WeatherConfig.CarSpeedInRain = 0.8 -- машины в дождь едут медленнее
WeatherConfig.RainDrops = 900 -- капель в секунду при сильном дожде (меньше — легче для слабых устройств)

return WeatherConfig
