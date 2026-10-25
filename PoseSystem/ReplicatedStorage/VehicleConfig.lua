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
	Civilian = 5, -- гражданские (у каждой есть хозяин-житель, едут, когда ему далеко идти)
	Cruising = 4, -- «поток»: машины со своими водителями, всё время катаются по городу
	Taxi = 2,
	Bus = 1,
	Police = 2,
}
VehicleConfig.MaxVehicles = 16

-- Поток машин
VehicleConfig.CruiseMinDistance = 60 -- куда ехать: случайная точка дороги не ближе этого
VehicleConfig.CruiseStopChance = 0.25 -- иногда останавливаются у тротуара
VehicleConfig.CruiseStopTime = NumberRange.new(4, 10)

-- Движение
VehicleConfig.LaneOffset = 3 -- насколько правее центра дороги едет машина (правостороннее движение)
VehicleConfig.RoadWidth = 12 -- ширина дороги: по ней строятся зоны, куда жителям ходить нельзя
-- Пешеходные переходы: TrafficSystem > Crosswalks (Part на зебре). Если папки нет — у перекрёстков сами
VehicleConfig.AutoCrosswalks = true
VehicleConfig.DrawCrosswalks = true -- рисовать белую зебру на автоматических переходах
VehicleConfig.CrosswalkWidth = 4
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
-- Развороты: машина не разворачивается посреди дороги — только на точках с
-- атрибутом Turnaround = true (кольцо, разворотная площадка) или в тупике
VehicleConfig.AllowUTurnFallback = true -- если иначе никак не доехать — разрешить разворот (с предупреждением)

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
-- Пассажиров не видно (тело, имя, облачка) — только водитель за рулём
VehicleConfig.HidePassengers = false
-- Водитель автобуса в форме
VehicleConfig.BusDriver = true
VehicleConfig.BusDriverShirt = Color3.fromRGB(40, 110, 70)
VehicleConfig.BusDriverPants = Color3.fromRGB(30, 35, 45)

VehicleConfig.PoliceShirt = Color3.fromRGB(30, 45, 90)
VehicleConfig.PolicePants = Color3.fromRGB(20, 25, 40)

-- Полицейский участок: Workspace > TrafficSystem > PoliceStation
--   Desk  — стойка дежурного (передняя грань — к посетителям)
--   Idle  — где офицеры ждут вызова (сколько угодно точек)
--   Cell  — камера для задержанных
VehicleConfig.DutyOfficerName = "Дежурный"
VehicleConfig.StationWanderTime = NumberRange.new(12, 30) -- как часто офицеры переходят с места на место
VehicleConfig.CellTime = NumberRange.new(60, 100) -- сколько задержанный сидит в камере
VehicleConfig.QuestionGap = 1.2 -- пауза между репликами при опросе
VehicleConfig.OfficerSpacing = 1.4 -- насколько офицеры стоят порознь у двери

-- Виды вызовов (и заявлений игрока). Arrest — шанс, что кого-то задержат.
VehicleConfig.PoliceCallTypes = {
	{
		Name = "Кража", Icon = "🕵️", Arrest = 0.45,
		Officer = { "Здравствуйте, полиция. Поступило сообщение о краже.", "Что именно пропало?" },
		Resident = { "Да! У меня пропал велосипед прямо со двора!", "Утром был, а сейчас нет..." },
		Suspect = { "Это не я! Я просто мимо проходил!", "Велосипед? Какой велосипед?.." },
	},
	{
		Name = "Шум", Icon = "🔊", Arrest = 0.25,
		Officer = { "Добрый день. Жалуются на шум по этому адресу.", "Можно потише, пожалуйста?" },
		Resident = { "Соседи шумят всю ночь, спать невозможно!", "Музыка орёт с самого утра." },
		Suspect = { "У меня день рождения, имею право!", "Да я тихо, честное слово..." },
	},
	{
		Name = "Подозрительный человек", Icon = "👤", Arrest = 0.5,
		Officer = { "Полиция. Сообщили о подозрительном человеке.", "Покажите, пожалуйста, документы." },
		Resident = { "Он ходил вокруг дома и заглядывал в окна!", "Я его раньше никогда не видел." },
		Suspect = { "Я просто ищу своего кота!", "Документы? Ой, дома забыл..." },
	},
	{
		Name = "Драка", Icon = "🥊", Arrest = 0.7,
		Officer = { "Полиция! Что здесь происходит?", "Успокойтесь и расскажите по порядку." },
		Resident = { "Они начали первыми!", "Он толкнул меня без причины!" },
		Suspect = { "Он сам полез!", "Да мы просто разговаривали!" },
	},
	{
		Name = "Потерялась собака", Icon = "🐕", Arrest = 0,
		Officer = { "Здравствуйте. Вы сообщали о пропавшей собаке?", "Опишите её, пожалуйста." },
		Resident = { "Да, рыжая, с красным ошейником!", "Убежала утром, когда я открыл дверь." },
		Suspect = { "" },
	},
}
VehicleConfig.PoliceCloseLines = { "Спасибо, мы всё записали.", "Будем держать вас в курсе.", "Если что — звоните." }
VehicleConfig.ResidentThanks = { "Спасибо вам!", "Хорошо, что вы приехали!", "Буду ждать новостей." }
VehicleConfig.ArrestLines = { "Вы задержаны. Пройдёмте с нами.", "Руки за спину. Едем в участок." }
VehicleConfig.ArrestedLines = { "Что?! Я ничего не делал!", "Это ошибка!", "Ладно, ладно, иду..." }
VehicleConfig.NobodyLines = { "Полиция, откройте!", "Есть кто дома?", "Похоже, никого нет." }
VehicleConfig.CellLines = { "Выпустите меня!", "Я требую адвоката!", "Ну и скукота тут..." }
VehicleConfig.BookingLines = { "Оформляем.", "Посидите пока здесь.", "Заполним протокол." }

-- Вопросы дежурному (ответ — случайный из Answers; %s подставляется по смыслу)
VehicleConfig.DutyGreetings = { "Здравствуйте! Дежурная часть, слушаю вас.", "Добрый день! Чем могу помочь?", "Полиция города. Что случилось?" }
VehicleConfig.DutyQuestions = {
	{ Text = "Что нового в городе?", Answers = { "%s" } }, -- подставляется сводка последних вызовов
	{ Text = "Как стать полицейским?", Answers = { "Сначала научитесь не летать над крышами!", "Приходите, когда подрастёте. А пока — помогайте жителям!" } },
	{ Text = "Можно летать над городом?", Answers = { "Можно, но аккуратно. И без лазеров!", "Только не над дорогой — водители пугаются." } },
	{ Text = "Где ближайшая остановка?", Answers = { "Спросите у жителей — они всё знают.", "Автобус ходит по кругу, ловите на остановке у площади." } },
	{ Text = "Кто сидит в камере?", Answers = { "%s" } }, -- подставляется, кто задержан
}
VehicleConfig.ReportAccepted = { "Заявление принято! Высылаем наряд.", "Записал. Наряд уже выезжает.", "Принято. Ожидайте, разберёмся." }
VehicleConfig.ReportBusy = { "Все наряды заняты, но ваше заявление в очереди.", "Принято, наряд выедет, как только освободится." }

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
