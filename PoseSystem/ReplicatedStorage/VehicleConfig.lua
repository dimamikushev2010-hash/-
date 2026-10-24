-- ModuleScript: ReplicatedStorage > VehicleConfig
-- Настройки транспорта: машины, такси, автобус, полиция, дороги и светофоры.
-- Как собрать шаблоны машин и расставить дороги — см. VEHICLE_SETUP.md.

local VehicleConfig = {}

-- Где что лежит
VehicleConfig.TemplatesFolder = "VehicleTemplates" -- ServerStorage > VehicleTemplates (шаблоны машин)
VehicleConfig.MapFolder = "TrafficSystem" -- Workspace > TrafficSystem (дороги, парковки, остановки...)
VehicleConfig.VehiclesFolder = "Vehicles" -- сюда появляются машины (Workspace > TrafficSystem > Vehicles)
VehicleConfig.HideMarkersInGame = true

-- Сколько машин
VehicleConfig.Count = {
	Civilian = 5, -- гражданские (у каждой есть хозяин-житель)
	Taxi = 2,
	Bus = 1,
	Police = 2,
}
VehicleConfig.MaxVehicles = 12

-- Движение
VehicleConfig.LaneOffset = 3 -- насколько правее центра дороги едет машина (правостороннее движение)
VehicleConfig.CitySpeed = 26 -- скорость в городе (стадов в секунду)
VehicleConfig.PoliceSpeed = 40 -- полиция на вызове
VehicleConfig.TurnSpeed = 12 -- скорость в повороте
VehicleConfig.Acceleration = 12
VehicleConfig.Braking = 28
VehicleConfig.CornerRadius = 7 -- насколько плавно скругляются повороты
VehicleConfig.SafeGap = 4 -- дистанция до машины впереди
VehicleConfig.PedestrianStop = 14 -- за сколько стадов тормозить перед человеком
VehicleConfig.HonkCooldown = 4
VehicleConfig.StuckRespawnTime = 30 -- застряла дольше — плавно исчезает и появляется на своей парковке

-- Светофоры: фазы по очереди (1 — зелёный для одних, 2 — для других)
VehicleConfig.GreenTime = 12
VehicleConfig.YellowTime = 3
VehicleConfig.AllRedTime = 1.5

-- Поездки жителей
VehicleConfig.TripMinDistance = 55 -- дальше этого житель поедет, а не пойдёт пешком
VehicleConfig.TaxiChance = 0.4 -- житель без машины возьмёт такси
VehicleConfig.BusChance = 0.4 -- или поедет на автобусе
VehicleConfig.TrunkChance = 0.3 -- перед поездкой что-то кладёт в багажник

-- Такси для игроков
VehicleConfig.TaxiPrice = 5

-- Автобус
VehicleConfig.BusStopTime = 10 -- стоит на остановке
VehicleConfig.BusLoopPause = 60 -- отдых на конечной

-- Полиция
VehicleConfig.PoliceCallInterval = NumberRange.new(60, 180) -- как часто вызовы
VehicleConfig.PoliceNightFactor = 0.6 -- ночью вызовы чаще
VehicleConfig.PoliceInsideTime = NumberRange.new(20, 40) -- сколько полицейские в здании
VehicleConfig.PoliceOfficersPerCar = 2
VehicleConfig.PolicePhrases = { "Что тут у вас?", "Полиция! Всем оставаться на местах!", "Так, разберёмся.", "Поступил вызов." }
VehicleConfig.PoliceDonePhrases = { "Всё в порядке.", "Ложная тревога.", "Разобрались!", "Едем на базу." }
VehicleConfig.PoliceShirt = Color3.fromRGB(30, 45, 90)
VehicleConfig.PolicePants = Color3.fromRGB(20, 25, 40)

-- Цвета гражданских машин, если в шаблоне есть детали с атрибутом Paint = true
VehicleConfig.PaintColors = {
	Color3.fromRGB(200, 40, 40), Color3.fromRGB(40, 90, 200), Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(30, 30, 35), Color3.fromRGB(120, 120, 130), Color3.fromRGB(60, 140, 70),
	Color3.fromRGB(230, 170, 40), Color3.fromRGB(110, 60, 150),
}

-- Анимации дверей и багажника
VehicleConfig.DoorOpenAngle = 70
VehicleConfig.TrunkOpenAngle = 75
VehicleConfig.DoorSpeed = 5
VehicleConfig.SlideDistance = 2.5 -- для сдвижных дверей (автобус)

return VehicleConfig
