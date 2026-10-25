-- ВСЕ СКРИПТЫ: позы, невидимость, лазеры, полёт, куб, жители города (NPC), транспорт
-- Каждый блок ниже — отдельный скрипт. Создай объект нужного типа в нужном месте,
-- назови его точно как написано и вставь код блока целиком.
-- Проще всего: открыть PoseSystem.rbxlx, там всё уже расставлено.
-- Как расставить точки для жителей — NPC_SETUP.md, транспорт и звуки — VEHICLE_SETUP.md.

-- СПИСОК (43 скриптов):
--    1. ReplicatedStorage > ModuleScript "PoseConfig"
--    2. ReplicatedStorage > ModuleScript "InvisibilityConfig"
--    3. ReplicatedStorage > ModuleScript "LaserConfig"
--    4. ReplicatedStorage > ModuleScript "FlightConfig"
--    5. ReplicatedStorage > ModuleScript "CubeConfig"
--    6. ReplicatedStorage > ModuleScript "NPCConfig"
--    7. ReplicatedStorage > ModuleScript "VehicleConfig"
--    8. ReplicatedStorage > ModuleScript "SoundConfig"
--    9. ReplicatedStorage > ModuleScript "WeatherConfig"
--   10. ReplicatedStorage > ModuleScript "CityConfig"
--   11. ReplicatedStorage > ModuleScript "DebugConfig"
--   12. ReplicatedStorage > ModuleScript "AbilityButton"
--   13. ReplicatedStorage > ModuleScript "RigAnimator"
--   14. ReplicatedStorage > ModuleScript "AbilityFx"
--   15. ServerScriptService > ModuleScript "AbilityRegistry"
--   16. ServerScriptService > ModuleScript "NPCRegistry"
--   17. ServerScriptService > ModuleScript "VehicleDefaults"
--   18. ServerScriptService > Script "PoseServer"
--   19. ServerScriptService > Script "InvisibilityServer"
--   20. ServerScriptService > Script "LaserServer"
--   21. ServerScriptService > Script "FlightServer"
--   22. ServerScriptService > Script "CubeServer"
--   23. ServerScriptService > Script "NPCDemo"
--   24. ServerScriptService > Script "NPCServer"
--   25. ServerScriptService > Script "NPCDoors"
--   26. ServerScriptService > Script "DayNightServer"
--   27. ServerScriptService > Script "TrafficServer"
--   28. ServerScriptService > Script "WeatherServer"
--   29. ServerScriptService > Script "PhoneServer"
--   30. ServerScriptService > Script "CityLifeServer"
--   31. ServerScriptService > Script "DebugServer"
--   32. StarterPlayer → StarterPlayerScripts > LocalScript "PoseClient"
--   33. StarterPlayer → StarterPlayerScripts > LocalScript "InvisibilityClient"
--   34. StarterPlayer → StarterPlayerScripts > LocalScript "LaserClient"
--   35. StarterPlayer → StarterPlayerScripts > LocalScript "FlightClient"
--   36. StarterPlayer → StarterPlayerScripts > LocalScript "CubeClient"
--   37. StarterPlayer → StarterPlayerScripts > LocalScript "NPCClient"
--   38. StarterPlayer → StarterPlayerScripts > LocalScript "VehicleClient"
--   39. StarterPlayer → StarterPlayerScripts > LocalScript "PoliceDeskClient"
--   40. StarterPlayer → StarterPlayerScripts > LocalScript "WeatherClient"
--   41. StarterPlayer → StarterPlayerScripts > LocalScript "PhoneClient"
--   42. StarterPlayer → StarterPlayerScripts > LocalScript "CityLifeClient"
--   43. StarterPlayer → StarterPlayerScripts > LocalScript "DebugClient"


----------------------------------------------------------------------
-- 1. ReplicatedStorage > ModuleScript "PoseConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > PoseConfig
-- Общие настройки системы поз (сидеть / лежать / на коленях).
-- Используется и сервером, и клиентом.

local PoseConfig = {}

-- Имена служебных объектов
PoseConfig.RemoteName = "PoseRequest" -- RemoteEvent в ReplicatedStorage (создаётся сервером)
PoseConfig.AttributeName = "Pose" -- атрибут персонажа с текущей позой

-- Управление: две кнопки
--   Вниз:  Стоя -> Сидя -> Лёжа
--   Вверх: Лёжа -> На коленях -> Стоя
PoseConfig.Keys = {
	Down = { Enum.KeyCode.C, Enum.KeyCode.DPadDown },
	Up = { Enum.KeyCode.X, Enum.KeyCode.DPadUp },
}

-- Прыжок (пробел) в любой позе = сразу встать
PoseConfig.JumpToStand = true

-- Переходы между позами. Можно менять как угодно.
PoseConfig.Transitions = {
	Down = {
		Stand = "Sit",
		Sit = "Lie",
		Kneel = "Sit",
		Lie = "Lie",
	},
	Up = {
		Lie = "Kneel",
		Kneel = "Stand",
		Sit = "Stand",
		Stand = "Stand",
	},
}

-- Подписи (для кнопок на телефоне и подсказки на экране)
PoseConfig.StateNames = {
	Stand = "Стоит",
	Sit = "Сидит",
	Lie = "Лежит",
	Kneel = "На коленях",
}
PoseConfig.ActionNames = {
	Stand = "Встать",
	Sit = "Сесть",
	Lie = "Лечь",
	Kneel = "На колени",
}

PoseConfig.TransitionTime = 0.4 -- длительность анимации перехода, сек
PoseConfig.ClientCooldown = 0.25 -- защита от спама на клиенте
PoseConfig.ServerCooldown = 0.15 -- защита от спама на сервере
PoseConfig.PredictionTimeout = 1 -- сколько клиент ждёт подтверждения сервера
PoseConfig.ShowHint = true -- подсказка внизу экрана
PoseConfig.Debug = true -- писать в Output, что происходит (потом можно выключить)

--[[
	ПОЗЫ (процедурные анимации)

	Все углы — в градусах, Vector3.new(X, Y, Z), относительно родительской части тела:
	  X > 0  — наклон назад для торса/головы, подъём вперёд для рук/ног
	  X < 0  — наклон вперёд для торса/головы, отвод назад для рук/ног, сгиб колена
	  Z      — отвод руки/ноги в сторону (левая: минус = наружу, правая: плюс = наружу)

	HipHeight — высота таза над землёй в долях длины ноги (1 = стоит, 0.3 = почти на полу)
	Shift     — дополнительный сдвиг всего тела (в стадах для стандартного размера)
	Root      — поворот всего тела вокруг таза
	Breath    — амплитуда «дыхания» в градусах (0 — выключено)
	WalkSpeed — скорость ходьбы в этой позе (0 — нельзя ходить)
	R6        — переопределения для R6-персонажей (у них нет коленей и локтей)
]]
PoseConfig.Poses = {
	-- Сидя на стуле/скамейке (используют жители; таз ставит скрипт NPC прямо на сиденье)
	Chair = {
		HipHeight = 1,
		Root = Vector3.new(-3, 0, 0),
		Breath = 1.2,
		WalkSpeed = 0,
		Joints = {
			Waist = Vector3.new(-4, 0, 0),
			Neck = Vector3.new(-3, 0, 0),
			LeftShoulder = Vector3.new(28, 0, -6),
			RightShoulder = Vector3.new(28, 0, 6),
			LeftElbow = Vector3.new(45, 0, 0),
			RightElbow = Vector3.new(40, 0, 0),
			LeftHip = Vector3.new(90, 0, -5),
			RightHip = Vector3.new(87, 0, 5),
			LeftKnee = Vector3.new(-88, 0, 0),
			RightKnee = Vector3.new(-92, 0, 0),
			LeftAnkle = Vector3.new(0, 0, 0),
			RightAnkle = Vector3.new(0, 0, 0),
		},
		R6 = {
			LeftShoulder = Vector3.new(35, 0, -4),
			RightShoulder = Vector3.new(35, 0, 4),
		},
	},

	Sit = {
		HipHeight = 0.3,
		Shift = Vector3.new(0, 0, 0),
		Root = Vector3.new(10, 0, 0),
		Breath = 1.5,
		WalkSpeed = 0,
		Joints = {
			Waist = Vector3.new(-6, 0, 0),
			Neck = Vector3.new(-6, 0, 0),
			LeftShoulder = Vector3.new(35, 0, -6),
			RightShoulder = Vector3.new(35, 0, 6),
			LeftElbow = Vector3.new(35, 0, 0),
			RightElbow = Vector3.new(30, 0, 0),
			LeftHip = Vector3.new(80, 0, -4),
			RightHip = Vector3.new(76, 0, 4),
			LeftKnee = Vector3.new(-12, 0, 0),
			RightKnee = Vector3.new(-22, 0, 0),
			LeftAnkle = Vector3.new(0, 0, 0),
			RightAnkle = Vector3.new(0, 0, 0),
		},
		R6 = {
			LeftShoulder = Vector3.new(45, 0, -4),
			RightShoulder = Vector3.new(45, 0, 4),
		},
	},

	Lie = {
		HipHeight = 0.3,
		Shift = Vector3.new(0, 0, -0.75),
		Root = Vector3.new(90, 0, 0), -- на спину, лицом вверх
		Breath = 2.5,
		WalkSpeed = 0,
		Joints = {
			Waist = Vector3.new(0, 0, 0),
			Neck = Vector3.new(-22, 0, 0), -- голова чуть приподнята
			LeftShoulder = Vector3.new(0, 0, -14),
			RightShoulder = Vector3.new(0, 0, 14),
			LeftElbow = Vector3.new(15, 0, 0),
			RightElbow = Vector3.new(15, 0, 0),
			LeftHip = Vector3.new(0, 0, -4),
			RightHip = Vector3.new(40, 0, 4), -- правое колено согнуто
			LeftKnee = Vector3.new(-5, 0, 0),
			RightKnee = Vector3.new(-80, 0, 0),
			LeftAnkle = Vector3.new(0, 0, 0),
			RightAnkle = Vector3.new(20, 0, 0),
		},
		R6 = {
			RightHip = Vector3.new(12, 0, 4),
		},
	},

	Kneel = {
		HipHeight = 0.6,
		Shift = Vector3.new(0, 0, 0),
		Root = Vector3.new(0, 0, 0),
		Breath = 1.5,
		WalkSpeed = 0,
		Joints = {
			Waist = Vector3.new(-4, 0, 0),
			Neck = Vector3.new(-4, 0, 0),
			LeftShoulder = Vector3.new(15, 0, -5),
			RightShoulder = Vector3.new(15, 0, 5),
			LeftElbow = Vector3.new(25, 0, 0),
			RightElbow = Vector3.new(25, 0, 0),
			LeftHip = Vector3.new(0, 0, -3),
			RightHip = Vector3.new(0, 0, 3),
			LeftKnee = Vector3.new(-90, 0, 0), -- голени лежат на полу
			RightKnee = Vector3.new(-90, 0, 0),
			LeftAnkle = Vector3.new(-90, 0, 0), -- стопы вытянуты назад
			RightAnkle = Vector3.new(-90, 0, 0),
		},
		R6 = {
			HipHeight = 0.65,
			LeftHip = Vector3.new(-45, 0, -3),
			RightHip = Vector3.new(-45, 0, 3),
		},
	},
}

function PoseConfig.IsValidState(state: any): boolean
	return state == "Stand" or (type(state) == "string" and PoseConfig.Poses[state] ~= nil)
end

-- direction: "Down" | "Up" | "Stand"
function PoseConfig.GetNextState(current: string, direction: string): string
	if direction == "Stand" then
		return "Stand"
	end
	local map = PoseConfig.Transitions[direction]
	return (map and map[current]) or current
end

return PoseConfig

----------------------------------------------------------------------
-- 2. ReplicatedStorage > ModuleScript "InvisibilityConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > InvisibilityConfig
-- Настройки способности «Невидимость».

local InvisibilityConfig = {}

InvisibilityConfig.RemoteName = "InvisibilityRequest"

-- Атрибуты (выставляет сервер, читают все клиенты)
InvisibilityConfig.ActiveAttribute = "Invisible" -- на персонаже: true/false
InvisibilityConfig.UntilAttribute = "InvisibleUntil" -- на персонаже: время окончания (серверное)
InvisibilityConfig.CooldownAttribute = "InvisibilityCooldownUntil" -- на игроке: конец кулдауна

-- Время
InvisibilityConfig.Duration = 8 -- сколько длится невидимость, сек
InvisibilityConfig.Cooldown = 20 -- кулдаун, отсчитывается после окончания невидимости
InvisibilityConfig.CanCancelEarly = true -- повторное нажатие = выйти раньше
InvisibilityConfig.FadeTime = 0.5 -- плавное исчезновение/появление, сек

-- Управление
InvisibilityConfig.Keys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonY }

-- Как ты видишь себя: «стекло»
InvisibilityConfig.SelfTransparency = 0.6 -- 0 = как обычно, 1 = совсем не видно
InvisibilityConfig.SelfMaterial = Enum.Material.Glass
InvisibilityConfig.SelfTint = Color3.fromRGB(170, 215, 255) -- голубоватый оттенок
InvisibilityConfig.SelfTintStrength = 0.35 -- 0 = без оттенка, 1 = полностью голубой

-- Лёгкая синева на экране, пока ты невидим
InvisibilityConfig.ScreenTint = Color3.fromRGB(215, 230, 255)
InvisibilityConfig.ScreenSaturation = -0.15

-- Красная подсветка при выходе из невидимости (её видят все)
InvisibilityConfig.FlashColor = Color3.fromRGB(255, 40, 40)
InvisibilityConfig.FlashTime = 1.5 -- сколько держится и гаснет, сек
InvisibilityConfig.FlashFillTransparency = 0.8 -- слабое свечение внутри тела

-- Что скрывать у невидимого игрока от других
InvisibilityConfig.HideName = true -- ник и полоска здоровья
InvisibilityConfig.HideSounds = true -- шаги и прочие звуки персонажа

-- Интерфейс
InvisibilityConfig.ButtonText = "Невидимость"
InvisibilityConfig.ButtonSlot = 1 -- место в ряду кнопок (1 = крайняя справа)
InvisibilityConfig.ActiveColor = Color3.fromRGB(120, 200, 255)

return InvisibilityConfig

----------------------------------------------------------------------
-- 3. ReplicatedStorage > ModuleScript "LaserConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > LaserConfig
-- Настройки способности «Лазеры из глаз».

local LaserConfig = {}

LaserConfig.RemoteName = "LaserRequest" -- включить/выключить
LaserConfig.AimRemoteName = "LaserAim" -- куда целится игрок (часто, без гарантии доставки)

-- Атрибуты (выставляет сервер, читают все клиенты)
LaserConfig.ActiveAttribute = "LaserActive" -- на персонаже: true/false
LaserConfig.UntilAttribute = "LaserUntil" -- на персонаже: время окончания (серверное)
LaserConfig.AimAttribute = "LaserAimPoint" -- на персонаже: точка прицела (Vector3)
LaserConfig.CooldownAttribute = "LaserCooldownUntil" -- на игроке: конец кулдауна

-- Время
LaserConfig.Duration = 3 -- сколько секунд бьют лазеры
LaserConfig.Cooldown = 12 -- кулдаун после окончания
LaserConfig.CanCancelEarly = true -- повторное нажатие = выключить раньше

-- Урон
LaserConfig.DamagePerSecond = 35
LaserConfig.DamageInterval = 0.1 -- как часто сервер наносит урон, сек
LaserConfig.Range = 200 -- дальность, стады
LaserConfig.FriendlyFire = false -- бить игроков своей команды (если есть Teams)

-- Управление: целишься мышкой (на телефоне — центром экрана)
LaserConfig.Keys = { Enum.KeyCode.R, Enum.KeyCode.ButtonX }
LaserConfig.AimSendRate = 20 -- сколько раз в секунду клиент шлёт прицел
LaserConfig.TurnToAim = true -- персонаж разворачивается туда, куда стреляет

-- Внешний вид
LaserConfig.Color = Color3.fromRGB(255, 30, 30) -- внешнее свечение луча
LaserConfig.CoreColor = Color3.fromRGB(255, 220, 220) -- яркая середина луча
LaserConfig.OuterWidth = 0.35
LaserConfig.CoreWidth = 0.1
LaserConfig.ChargeTime = 0.15 -- лучи «разгораются» и гаснут за это время
LaserConfig.EyeLightRange = 5 -- красное свечение у глаз
LaserConfig.ImpactLightRange = 10 -- свечение в точке попадания
LaserConfig.SparkColor = Color3.fromRGB(255, 120, 40)

-- Звук (необязательно): вставь rbxassetid://ID любого звука лазера из Toolbox
LaserConfig.SoundId = ""
LaserConfig.SoundVolume = 0.5

-- Интерфейс
LaserConfig.ButtonText = "Лазеры"
LaserConfig.ButtonIcon = "🔴"
LaserConfig.ButtonSlot = 2 -- левее кнопки невидимости
LaserConfig.ActiveColor = Color3.fromRGB(255, 70, 70)

return LaserConfig

----------------------------------------------------------------------
-- 4. ReplicatedStorage > ModuleScript "FlightConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > FlightConfig
-- Настройки способности «Полёт».

local FlightConfig = {}

FlightConfig.RemoteName = "FlightRequest"

FlightConfig.ActiveAttribute = "Flying" -- на персонаже: true/false
FlightConfig.UntilAttribute = "FlyingUntil" -- на персонаже: время окончания
FlightConfig.CooldownAttribute = "FlightCooldownUntil" -- на игроке: конец кулдауна

-- Время
FlightConfig.Duration = 15 -- сколько секунд можно летать
FlightConfig.Cooldown = 10 -- кулдаун после приземления
FlightConfig.CanCancelEarly = true

-- Управление:
--   WASD / стик — лететь туда, куда смотрит камера (вверх/вниз тоже)
--   Пробел — вверх, Ctrl или C — вниз
FlightConfig.Keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonL1 }
FlightConfig.UpKeys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA }
FlightConfig.DownKeys = { Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB }

-- Физика
FlightConfig.Speed = 45 -- обычная скорость
FlightConfig.MaxSpeed = 95 -- разгон, если долго лететь в одну сторону
FlightConfig.BoostTime = 2.5 -- за сколько секунд разгоняешься до максимума
FlightConfig.Acceleration = 4 -- насколько резко меняется скорость (больше = резче)
FlightConfig.LaunchSpeed = 45 -- рывок вверх при взлёте
FlightConfig.MaxPitch = 165 -- насколько можно наклониться (90 = горизонтально, 165 = пике вниз)
FlightConfig.TurnResponsiveness = 18 -- как быстро тело поворачивается
FlightConfig.BankStrength = 0.35 -- крен в поворотах

-- Эффекты
FlightConfig.FovBoost = 18 -- насколько расширяется обзор на скорости
FlightConfig.TrailColor = Color3.fromRGB(200, 230, 255)
FlightConfig.BoomColor = Color3.fromRGB(220, 240, 255) -- «звуковой удар» на максимальной скорости
FlightConfig.LandingMinFallSpeed = 30 -- с какой скорости падения будет «супергеройское» приземление

-- Интерфейс
FlightConfig.ButtonText = "Полёт"
FlightConfig.ButtonIcon = "🦅"
FlightConfig.ButtonSlot = 3
FlightConfig.ActiveColor = Color3.fromRGB(140, 220, 255)

return FlightConfig

----------------------------------------------------------------------
-- 5. ReplicatedStorage > ModuleScript "CubeConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > CubeConfig
-- Настройки способности «Превращение в куб».

local CubeConfig = {}

CubeConfig.RemoteName = "CubeRequest"

CubeConfig.ActiveAttribute = "CubeForm" -- на персонаже: true/false
CubeConfig.UntilAttribute = "CubeFormUntil" -- на персонаже: время окончания
CubeConfig.CooldownAttribute = "CubeCooldownUntil" -- на игроке: конец кулдауна
CubeConfig.PartName = "AbilityCube" -- деталь-куб внутри персонажа

-- Время
CubeConfig.Duration = 15
CubeConfig.Cooldown = 15
CubeConfig.CanCancelEarly = true
CubeConfig.PopTime = 0.5 -- «выпрыгивание» куба с пружинкой
CubeConfig.PopOutTime = 0.35 -- сжатие куба при выходе

CubeConfig.Keys = { Enum.KeyCode.T, Enum.KeyCode.ButtonR1 }

-- Внешний вид
CubeConfig.Size = 4 -- размер куба для персонажа обычного роста
CubeConfig.Colors = { -- цвет выбирается случайно при каждом превращении
	Color3.fromRGB(255, 170, 40),
	Color3.fromRGB(60, 200, 255),
	Color3.fromRGB(255, 80, 160),
	Color3.fromRGB(120, 230, 90),
	Color3.fromRGB(170, 110, 255),
	Color3.fromRGB(255, 225, 60),
}
CubeConfig.EdgeColor = Color3.fromRGB(255, 255, 255) -- светящиеся рёбра
CubeConfig.EdgeThickness = 0.08

-- Движение в форме куба
CubeConfig.WalkSpeed = 22
CubeConfig.JumpPower = 65 -- куб прыгучий
CubeConfig.HopHeight = 0.9 -- высота подскоков при ходьбе
CubeConfig.HopRate = 2.6 -- подскоков в секунду

-- Интерфейс
CubeConfig.ButtonText = "Куб"
CubeConfig.ButtonIcon = "🧊"
CubeConfig.ButtonSlot = 4
CubeConfig.ActiveColor = Color3.fromRGB(255, 190, 70)

return CubeConfig

----------------------------------------------------------------------
-- 6. ReplicatedStorage > ModuleScript "NPCConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > NPCConfig
-- Настройки жителей города (NPC). Как расставить точки на карте — см. NPC_SETUP.md.

local NPCConfig = {}

-- Структура на карте:
--   Workspace > NPCSystem > Spawns  — где появляются жители
--   Workspace > NPCSystem > Points  — куда они ходят и что там делают
--   Workspace > NPCSystem > Doors   — двери, которые они открывают сами
NPCConfig.FolderName = "NPCSystem"
NPCConfig.Tag = "NPC" -- тег CollectionService на каждом жителе

-- Сколько жителей
NPCConfig.MaxNPCs = 20 -- всего на карте
NPCConfig.DefaultSpawnCount = 2 -- сколько жителей от одной точки, если у неё нет атрибута Count
NPCConfig.RespawnTime = 12 -- через сколько секунд погибший житель возрождается
NPCConfig.CorpseTime = 4 -- сколько секунд лежит тело

-- Точки на карте видны только в Studio, а в игре прячутся
NPCConfig.HideMarkersInGame = true

-- Демо-городок, если на карте ещё нет папки NPCSystem (для проверки)
NPCConfig.BuildDemoIfMissing = true

-- Движение
NPCConfig.WalkSpeed = NumberRange.new(8, 11) -- у каждого жителя своя
NPCConfig.RunSpeed = 22 -- когда убегают от опасности
NPCConfig.AgentRadius = 1.6
NPCConfig.AgentHeight = 5

-- Выбор следующей точки:
--   SameZoneChance — остаться в своей зоне (дом, магазин…)
--   OutdoorChance  — выйти на улицу (точки с Zone = "Street" или без Zone)
--   остальное      — любая точка на карте
NPCConfig.SameZoneChance = 0.55
NPCConfig.OutdoorChance = 0.3
NPCConfig.OutdoorZone = "Street"

-- Сколько секунд длятся занятия в точках
NPCConfig.ActivityTime = {
	Idle = NumberRange.new(4, 9), -- просто стоит, осматривается
	Look = NumberRange.new(5, 10), -- смотрит туда, куда «смотрит» точка (окно, витрина)
	Sit = NumberRange.new(10, 22), -- сидит (на Seat — на стуле, иначе на полу)
	Lie = NumberRange.new(12, 25), -- лежит (диван, кровать, газон)
	Dance = NumberRange.new(6, 12),
	Talk = NumberRange.new(8, 15), -- ждёт собеседника и болтает
}

-- Разговоры
NPCConfig.ChatChance = 0.35 -- шанс заговорить со встречным жителем
NPCConfig.ChatDistance = 9
NPCConfig.GreetPlayerChance = 0.4 -- шанс помахать проходящему игроку
NPCConfig.GreetDistance = 12
NPCConfig.BubbleTime = 3.5 -- сколько висит облачко с текстом

NPCConfig.FirstNames = {
	"Аня", "Миша", "Катя", "Дима", "Оля", "Саша", "Лена", "Ваня", "Маша", "Костя",
	"Юля", "Артём", "Настя", "Егор", "Света", "Никита", "Вика", "Паша", "Даша", "Рома",
}

-- Цвета кожи и одежды (одежда без ID ассетов — просто цвета частей тела)
NPCConfig.SkinColors = {
	Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 104, 72), Color3.fromRGB(105, 64, 40),
}
NPCConfig.ShirtColors = {
	Color3.fromRGB(220, 60, 60), Color3.fromRGB(60, 120, 220), Color3.fromRGB(70, 170, 90),
	Color3.fromRGB(240, 200, 60), Color3.fromRGB(150, 80, 200), Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(40, 40, 45), Color3.fromRGB(255, 140, 60),
}
NPCConfig.PantsColors = {
	Color3.fromRGB(40, 50, 90), Color3.fromRGB(30, 30, 35), Color3.fromRGB(110, 80, 60),
	Color3.fromRGB(90, 90, 100), Color3.fromRGB(60, 80, 50),
}
-- Можно вписать UserId реальных аватаров Roblox — жители будут выглядеть как они.
-- Пусто — жители собираются из цветов выше.
NPCConfig.AvatarUserIds = {}

-- Стандартные анимации Roblox (R15)
NPCConfig.Animations = {
	Idle = "rbxassetid://507766388",
	Idle2 = "rbxassetid://507766666",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
	SitChair = "rbxassetid://2506281703",
	Wave = "rbxassetid://507770239",
	Point = "rbxassetid://507770453",
	Laugh = "rbxassetid://507770818",
	Cheer = "rbxassetid://507770677",
	Dance = "rbxassetid://507771019",
	Dance2 = "rbxassetid://507776043",
}

-- Фразы
NPCConfig.Phrases = {
	Greet = { "Привет!", "Здравствуй!", "О, привет!", "Хорошего дня!", "Йо!" },
	Hurt = { "Ай!", "Эй, больно!", "Помогите!", "Ты что делаешь?!", "А-а-а!" },
	Wake = { "Где я?..", "Ох, голова...", "Снова здесь." },
	Idle = { "Хм...", "Какая погода сегодня!", "Куда же я шёл...", "Надо бы в магазин." },
	Door = { "Так, дверь...", "Пройду-ка." },
	Sleep = { "Zzz...", "Хррр...", "Мм... пирожки...", "Zzz... zzz..." },
	Morning = { "Доброе утро!", "Ох, уже утро...", "Новый день!", "Выспался!" },
	Night = { "Поздно уже, пора домой.", "Спать хочется...", "Пойду-ка я домой." },
	Grumpy = { "Ммм... я же сплю!", "Кто меня разбудил?", "Ну что такое?.." },
	-- Реакции на суперспособности игроков
	Flying = { "Смотрите, он летает!", "Ого, супергерой!", "Это птица? Самолёт?", "Вот это да!" },
	Cube = { "Ха-ха, кубик!", "Какой милый куб!", "Он что, прыгает?", "Кубик, привет!" },
	Invisible = { "Кто здесь?..", "Мне показалось...", "Тут кто-то есть?", "Странно..." },
	Laser = { "Бегите!", "Лазеры!", "Спасайся кто может!", "А-а-а, глаза светятся!" },
	-- Знакомый игрок (%s — его имя)
	KnownGreet = { "О, %s! Рад снова видеть!", "%s, привет-привет!", "А, это ты, %s!" },
	FollowStart = { "Пошли!", "Веди!", "Ладно, иду за тобой." },
	FollowEnd = { "Ладно, пока!", "Было весело!", "Я пойду по делам." },
	Rain = { "Ну и ливень!", "Где мой зонт?", "Бегу домой!", "Промок до нитки!", "Опять дождь..." },
	Thunder = { "Ой!", "Ничего себе гром!", "Страшно...", "Ух!" },
	Fog = { "Ничего не видно...", "Ну и туман!" },
	-- Работа
	Work = { "Заходите!", "Свежие булочки!", "Чем могу помочь?", "Лучшие цены в городе!", "Хорошего дня!" },
	Patrol = { "Всё спокойно.", "Порядок.", "Так, проверим...", "Никаких нарушений." },
	-- Задания (%s — название вещи)
	QuestAsk = { "Ох, я потерял(а) %s! Поможешь найти?", "Слушай, я где-то оставил(а) %s. Найдёшь?" },
	QuestWaiting = { "Ну что, нашёл?", "Ищи, ищи, я жду!", "Я отметил(а), где видел(а) в последний раз!" },
	QuestThanks = { "Ура, спасибо огромное!", "Ты лучший! Держи награду!", "Спасибо, выручил(а)!" },
	-- Дружба (%s — имя игрока)
	Friend = { "О, мой друг %s!", "%s! Как же я рад тебя видеть!", "Привет, дружище %s!" },
	Gift = { "Мы теперь друзья! Держи подарок!", "Это тебе, друг!" },
}

-- Диалоги жителей между собой: пары реплик (A, B, A, B...)
NPCConfig.Conversations = {
	{ "Привет! Как дела?", "Отлично! А у тебя?", "Тоже хорошо, иду гулять.", "Удачи!" },
	{ "Видел летающего человека?", "Да! Прямо над домами!", "Чудеса какие-то.", "Ага..." },
	{ "Ты слышал про лазеры из глаз?", "Слышал. Страшно выходить!", "Держись подальше от них.", "Точно!" },
	{ "Какой сегодня день?", "Вроде бы суббота.", "Отлично, можно отдохнуть!" },
	{ "Не знаешь, где тут кафе?", "Прямо и направо.", "Спасибо!", "Не за что!" },
	{ "Опять этот куб прыгает...", "Да, милый он!", "Ну такое.", "Ха-ха!" },
}

-- Диалог с игроком: игрок выбирает тему, житель отвечает одной из фраз
NPCConfig.PlayerTopics = {
	{ Text = "Как дела?", Answers = { "Отлично, спасибо!", "Нормально, работаю.", "Устал немного, а ты как?" }, Emote = "Laugh" },
	{ Text = "Что тут интересного?", Answers = { "Говорят, тут кто-то летает!", "Загляни в дома, там уютно.", "Погуляй по улице, тут красиво." }, Emote = "Point" },
	{ Text = "Расскажи о себе", Answers = { "Я живу тут недалеко.", "Люблю гулять и болтать с соседями.", "Я самый обычный житель!" }, Emote = "Wave" },
	{ Text = "Станцуем?", Answers = { "Давай!", "Только недолго!", "Ну смотри!" }, Emote = "Dance" },
	{ Text = "Пойдём со мной!", Answers = { "Пошли!", "Веди!", "Ладно, иду за тобой." }, Emote = "Cheer", Follow = true },
}

-- Задания: житель теряет вещь, игрок находит и приносит
NPCConfig.QuestChance = 0.35 -- шанс, что у жителя есть задание (❗ над головой)
NPCConfig.QuestCooldown = 90 -- через сколько секунд после выполнения может появиться новое
NPCConfig.QuestTime = 180 -- сколько секунд даётся на поиски
NPCConfig.QuestMinDistance = 35 -- вещь лежит не ближе этого
NPCConfig.QuestReward = { Min = 15, Max = 40 }
NPCConfig.QuestTopic = "Тебе нужна помощь?"
NPCConfig.QuestReturnTopic = "Вот, держи %s!"
NPCConfig.QuestItems = {
	{ Name = "ключи", Icon = "🔑", Color = Color3.fromRGB(255, 210, 60) },
	{ Name = "кошелёк", Icon = "👛", Color = Color3.fromRGB(200, 80, 160) },
	{ Name = "телефон", Icon = "📱", Color = Color3.fromRGB(40, 40, 50) },
	{ Name = "шапку", Icon = "🧢", Color = Color3.fromRGB(60, 120, 220) },
	{ Name = "книгу", Icon = "📕", Color = Color3.fromRGB(200, 50, 50) },
	{ Name = "мячик", Icon = "⚽", Color = Color3.fromRGB(245, 245, 245) },
}

-- Сообщения в телефоне: пишут знакомые жители (от уровня «Знакомый»)
NPCConfig.Phone = {
	MessageEvery = NumberRange.new(70, 150), -- как часто кто-то из знакомых пишет, сек
	Messages = {
		"Привет! Как дела?",
		"Видел сегодня автобус? Опять опаздывает 🙄",
		"Заходи в гости!",
		"Говорят, кто-то летал над домами. Это был ты? 😄",
		"Ну и погодка сегодня!",
		"Спасибо, что помог(ла) тогда!",
		"Пойдём вечером погуляем?",
		"У меня в квартире опять шумят соседи...",
		"Ты не видел мою собаку? Шучу, она рядом 🐕",
		"Слышал сирены? Полиция опять куда-то ехала.",
	},
	-- Быстрые ответы игрока и что на них отвечает житель
	Replies = {
		{ Text = "Привет! 👋", Answers = { "Привет-привет!", "О, рад(а) тебя слышать!", "Хей! 😊" } },
		{ Text = "Как дела?", Answers = { "Отлично, спасибо!", "Нормально, работаю.", "Устал(а), но держусь 😅" } },
		{ Text = "Пойдём гулять?", Answers = { "Давай! Встретимся на площади.", "Сегодня не могу, давай завтра?", "С радостью!" } },
		{ Text = "😂", Answers = { "Ахаха 😂", "😄", "Вот-вот!" } },
		{ Text = "Пока!", Answers = { "Пока! До встречи!", "Удачи! 👋", "Спишемся!" } },
	},
	FriendPointsPerChat = 1, -- дружба за переписку (не чаще раза в 2 минуты)
}

-- Монеты (показываются в таблице игроков)
NPCConfig.CurrencyName = "Монеты"

-- Дружба: очки за разговоры (+1, не чаще раза в минуту) и задания (+5)
NPCConfig.FriendLevels = {
	{ Points = 0, Name = "Незнакомец", Icon = "" },
	{ Points = 1, Name = "Знакомый", Icon = "" },
	{ Points = 4, Name = "Приятель", Icon = "🙂" },
	{ Points = 8, Name = "Друг", Icon = "❤️" },
}
NPCConfig.FriendGift = 20 -- монет в подарок, когда становитесь друзьями

-- Работа: точки Activity = "Work" (прилавок) и маршруты Activity = "Patrol"
NPCConfig.WorkShift = NumberRange.new(40, 80) -- сколько секунд работает до перерыва
NPCConfig.PatrolPause = NumberRange.new(2, 4) -- остановка на каждой точке маршрута
NPCConfig.DefaultWorkRole = "Продавец"
NPCConfig.DefaultPatrolRole = "Охранник"

-- Собаки и вещи в руках
NPCConfig.DogChance = 0.25
NPCConfig.DogColors = {
	Color3.fromRGB(150, 100, 60), Color3.fromRGB(230, 220, 200), Color3.fromRGB(40, 35, 30),
	Color3.fromRGB(210, 160, 90), Color3.fromRGB(120, 120, 125),
}
NPCConfig.PropChance = 0.45 -- шанс, что у жителя что-то в руках (кофе, телефон, мороженое, сумка)
NPCConfig.PlayerGreeting = { "Привет! Чем могу помочь?", "О, здравствуй!", "Да-да?", "Привет-привет!" }
NPCConfig.PlayerBye = { "Пока!", "Удачи!", "Заходи ещё!", "До встречи!" }
NPCConfig.TalkPromptText = "Поговорить"
NPCConfig.TalkDistance = 10

-- Смена дня и ночи
NPCConfig.DayNight = true
NPCConfig.DayLengthMinutes = 20 -- сколько реальных минут длятся одни игровые сутки (1 игровой час = 50 сек)
NPCConfig.StartTime = 9 -- со скольки часов начинается сервер
NPCConfig.NightStart = 21 -- с этого часа жители идут домой спать
NPCConfig.NightEnd = 6.5 -- в это время просыпаются
-- Детали с этим атрибутом (true) светятся только ночью: фонари, окна, вывески
NPCConfig.NightLightAttribute = "NightLight"

-- Неделя: каждые игровые сутки — следующий день, Сб и Вс — выходные
NPCConfig.WeekDays = { "Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс" }
NPCConfig.WeekendDays = { [6] = true, [7] = true }
NPCConfig.StartWeekDay = 1

--[[
	РАСПИСАНИЕ ДНЯ
	Для каждого периода — куда жители ходят чаще:
	  Home   — точки своего дома (зона точки появления)
	  Street — улица (Zone = "Street" или без зоны)
	  Other  — другие зоны: магазины, кафе, гости у соседей
	Prefer — какие занятия в этот период любят больше (множитель)
	Speed  — насколько быстрее/медленнее ходят (утром спешат)
	Phrases — что иногда говорят, когда период начинается
	Ночь (NightStart–NightEnd) — сон дома, как раньше.
]]
NPCConfig.Schedule = {
	{ Name = "Утро", From = 6.5, To = 9, Home = 0.6, Street = 0.3, Other = 0.1, Prefer = { Look = 2, Sit = 1.5 }, Speed = 1.15,
		Phrases = { "Пора на работу!", "Доброе утро, соседи!", "Опять проспал...", "Кофе бы..." } },
	{ Name = "День", From = 9, To = 13, Home = 0.15, Street = 0.4, Other = 0.45, Prefer = { Idle = 1.2 }, Speed = 1,
		Phrases = { "Какой хороший день!", "Столько дел сегодня..." } },
	{ Name = "Обед", From = 13, To = 14, Home = 0.2, Street = 0.2, Other = 0.6, Prefer = { Sit = 3 }, Speed = 1,
		Phrases = { "Время обеда!", "Пойду перекушу.", "Ням!" } },
	{ Name = "После обеда", From = 14, To = 18, Home = 0.2, Street = 0.4, Other = 0.4, Prefer = {}, Speed = 1,
		Phrases = { "Ещё немного — и домой.", "Скорее бы вечер." } },
	{ Name = "Вечер", From = 18, To = 21, Home = 0.35, Street = 0.45, Other = 0.2, Prefer = { Talk = 2.5, Dance = 2 }, Speed = 0.95,
		Phrases = { "Наконец-то вечер!", "Пойдём погуляем?", "Какой закат!" } },
}
-- В выходные: больше гуляют и отдыхают, меньше сидят дома
NPCConfig.Weekend = { Home = 0.6, Street = 1.6, Other = 1.3, Prefer = { Dance = 2, Talk = 1.5, Lie = 1.5 },
	Phrases = { "Ура, выходной!", "Отдыхаем!", "Никакой работы сегодня!" } }

-- Рабочие часы продавцов (точки Work). Охранники обходят маршрут весь день.
NPCConfig.WorkHours = { Start = 8.5, End = 17.5, LunchStart = 13, LunchEnd = 14 }
NPCConfig.WorkersRestOnWeekend = true
NPCConfig.WorkPhrases = { Start = { "На работу!", "Открываемся!" }, Lunch = { "Обед! Скоро вернусь." }, End = { "Смена окончена!", "Закрываемся, до завтра!" } }

-- Погода и жители
NPCConfig.RainStreetFactor = 0.25 -- в дождь на улицу ходят в 4 раза реже
NPCConfig.RainSpeed = 1.2 -- в дождь ускоряют шаг
NPCConfig.UmbrellaChance = 0.65 -- у скольких жителей есть зонт
NPCConfig.UmbrellaColors = {
	Color3.fromRGB(200, 40, 50), Color3.fromRGB(40, 80, 180), Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(240, 200, 40), Color3.fromRGB(120, 60, 160), Color3.fromRGB(40, 150, 90),
}

-- Реакции на суперспособности
NPCConfig.ReactDistance = 30
NPCConfig.ReactCooldown = 20 -- не чаще раза в N секунд на одного игрока

-- «Пойдём со мной!»
NPCConfig.FollowTime = 90 -- сколько секунд житель ходит за игроком
NPCConfig.FollowDistance = 5 -- на каком расстоянии держится

-- Значки настроения над головой
NPCConfig.Moods = {
	Sleep = "💤",
	Talk = "💬",
	Dance = "🎵",
	Follow = "😊",
	Scared = "😱",
	Angry = "😠",
	Wow = "😮",
	Laugh = "😂",
	Quest = "❗",
	Wait = "🚏",
	Cuffed = "🔒",
	Rain = "🌧",
	Work = "💼",
	Lunch = "🍔",
	Police = "🚔",
	Happy = "❤️",
}

-- Двери
NPCConfig.DoorOpenDistance = 6 -- на каком расстоянии житель открывает дверь
NPCConfig.DoorCloseDelay = 2.5 -- через сколько секунд после ухода дверь закрывается
NPCConfig.DoorOpenAngle = 95 -- на сколько градусов открывается
NPCConfig.DoorSpeed = 4 -- скорость открывания (больше = быстрее)

return NPCConfig

----------------------------------------------------------------------
-- 7. ReplicatedStorage > ModuleScript "VehicleConfig"
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- 8. ReplicatedStorage > ModuleScript "SoundConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > SoundConfig
-- ВСЕ ЗВУКИ ИГРЫ В ОДНОМ МЕСТЕ.
-- Вставь сюда ID звуков из Creator Store (Toolbox → Audio): "rbxassetid://123456789".
-- Пустая строка "" — звука нет (всё остальное работает).
--
-- Требования к звукам:
--   * только живые, естественные звуки (настоящий голос, настоящая машина), без «пиканья» и 8-бит;
--   * Engine, BusEngine и Siren — зацикленные (без паузы в начале и конце);
--   * короткие эффекты (двери, гудок, смех) — до 2–3 секунд.
--
-- Кандидаты из интернета (НЕ проверены — их нужно проверить в Studio, многие старые звуки удалены):
--   Horn:   5945905639, 7224945138
--   Siren:  1334940365 (NYPD Rumbler, loop), 523543734, 156721873
--   Engine: 532147820
--   Snore:  8191363542
--   Scream: 6467894576
--   Laugh:  265201042

local SoundConfig = {}

-- Машины
SoundConfig.Vehicle = {
	Engine = { Id = "", Volume = 0.35 }, -- зацикленный гул двигателя (высота меняется со скоростью)
	BusEngine = { Id = "", Volume = 0.5 }, -- двигатель автобуса (если пусто — берётся Engine)
	Horn = { Id = "", Volume = 0.7 }, -- гудок «би-бип»
	BusHorn = { Id = "", Volume = 0.8 },
	Siren = { Id = "", Volume = 0.6 }, -- зацикленная сирена полиции
	DoorOpen = { Id = "", Volume = 0.6 },
	DoorClose = { Id = "", Volume = 0.7 }, -- хлопок двери
	BusDoor = { Id = "", Volume = 0.6 }, -- «пшш» дверей автобуса
	TrunkOpen = { Id = "", Volume = 0.6 },
	TrunkClose = { Id = "", Volume = 0.7 },
	Indicator = { Id = "", Volume = 0.15 }, -- тиканье поворотника
	LightSwitch = { Id = "", Volume = 0.3 }, -- щелчок фар
	Brake = { Id = "", Volume = 0.3 }, -- скрип тормозов при резкой остановке
}

-- Жители
SoundConfig.NPC = {
	Footstep = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0.25 }, -- шаг по асфальту/полу
	Voice = { Id = "", Volume = 0.3 }, -- короткий слог/бормотание живым голосом (звучит во время реплики, высота у всех разная)
	Laugh = { Id = "", Volume = 0.5 },
	Hurt = { Id = "", Volume = 0.6 }, -- короткое «ай!» живым голосом
	Scream = { Id = "", Volume = 0.6 }, -- короткий крик испуга
	Snore = { Id = "", Volume = 0.3 }, -- храп ночью
	Cheer = { Id = "", Volume = 0.5 }, -- радостное «ура!»
	Wave = { Id = "", Volume = 0.4 }, -- «приве-ет!» / «хей!»
	DogBark = { Id = "", Volume = 0.5 },
	HouseDoorOpen = { Id = "", Volume = 0.5 }, -- скрип двери дома
	HouseDoorClose = { Id = "", Volume = 0.6 },
}

-- Погода
SoundConfig.Weather = {
	Rain = { Id = "", Volume = 0.5 }, -- зацикленный шум дождя (rain loop)
	Thunder = { Id = "", Volume = 0.8 }, -- раскат грома
	Wind = { Id = "", Volume = 0.3 }, -- зацикленный ветер (в грозу и туман)
}

-- Телефон
SoundConfig.Phone = {
	Notify = { Id = "", Volume = 0.5 }, -- новое сообщение / уведомление
	Tap = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25 }, -- нажатие
	Unlock = { Id = "", Volume = 0.4 }, -- разблокировка
	Send = { Id = "", Volume = 0.4 }, -- отправка сообщения
	Shutter = { Id = "", Volume = 0.5 }, -- щелчок затвора камеры (если пусто — звук нажатия)
}

-- Голоса жителей: у каждого своя высота (случайная в этом диапазоне).
-- Для живого голоса диапазон небольшой: 0.9–1.15 звучит естественно.
SoundConfig.VoicePitch = NumberRange.new(0.9, 1.15)
SoundConfig.VoiceSpeed = 5 -- сколько «слогов» в секунду при печати реплики

return SoundConfig

----------------------------------------------------------------------
-- 9. ReplicatedStorage > ModuleScript "WeatherConfig"
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- 10. ReplicatedStorage > ModuleScript "CityConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > CityConfig
-- Новые механики города. Работают на уже расставленных метках, новых меток не нужно.
--   📦 Курьер      — забери посылку и отнеси жителю (телефон → «Работа»)
--   🛍 Магазин     — аксессуары за монеты: шляпы, очки, корона, нимб, след, шарик...
--   🏆 Достижения  — награды за полёт, такси, друзей, доставки и многое другое
--   📷 Фоторежим   — камера телефона: фильтры, зум, селфи; жители позируют
--   💾 Сохранение  — монеты, покупки и достижения сохраняются (в опубликованной игре)

local CityConfig = {}

---------------------------------------------------------------------
-- 📦 Курьер
---------------------------------------------------------------------
-- Где брать посылки: место из TrafficSystem > Places с таким названием.
-- Если такого нет — случайное место из Places. Если Places пустая — посылка сразу в руках.
CityConfig.Job = {
	DepotName = "Почта",
	Reward = NumberRange.new(8, 14), -- монет за доставку
	FastBonus = 6, -- бонус, если успел за FastTime
	FastTime = 60,
	TimeLimit = 180, -- секунд на доставку, потом заказ отменяется
	DeliverDistance = 8, -- как близко подойти к жителю
	FriendPoints = 2, -- дружба с получателем
	Cooldown = 4, -- пауза между заказами
	Thanks = { "Ой, моя посылка! Спасибо!", "Наконец-то! Держи на чай 🪙", "Как быстро! Ты лучший курьер!", "Ура, я так ждал!" },
	Items = { "📚 Книги", "🍕 Пицца", "🎁 Подарок", "👟 Кроссовки", "🧸 Игрушка", "💐 Цветы", "📱 Новый телефон", "🎂 Торт" },
}

---------------------------------------------------------------------
-- 🛍 Магазин аксессуаров
---------------------------------------------------------------------
-- Kind: Hat (на голову), Face (на лицо), Halo (над головой), Trail (след), Aura (искры), Balloon (шарик)
-- Slot: в одном слоте можно носить только одну вещь
CityConfig.Shop = {
	{ Id = "Cap", Name = "Кепка", Icon = "🧢", Price = 15, Kind = "Hat", Slot = "Head", Color = Color3.fromRGB(220, 50, 50) },
	{ Id = "TopHat", Name = "Цилиндр", Icon = "🎩", Price = 30, Kind = "TopHat", Slot = "Head", Color = Color3.fromRGB(25, 25, 30) },
	{ Id = "Crown", Name = "Корона", Icon = "👑", Price = 80, Kind = "Crown", Slot = "Head", Color = Color3.fromRGB(255, 200, 40) },
	{ Id = "Glasses", Name = "Очки", Icon = "🕶️", Price = 20, Kind = "Face", Slot = "Face", Color = Color3.fromRGB(20, 20, 25) },
	{ Id = "Halo", Name = "Нимб", Icon = "😇", Price = 60, Kind = "Halo", Slot = "Above", Color = Color3.fromRGB(255, 240, 150) },
	{ Id = "Balloon", Name = "Шарик", Icon = "🎈", Price = 25, Kind = "Balloon", Slot = "Hand", Color = Color3.fromRGB(255, 80, 120) },
	{ Id = "Trail", Name = "Радужный след", Icon = "🌈", Price = 50, Kind = "Trail", Slot = "Trail" },
	{ Id = "Sparkles", Name = "Искры", Icon = "✨", Price = 40, Kind = "Aura", Slot = "Aura", Color = Color3.fromRGB(255, 230, 120) },
	{ Id = "Hearts", Name = "Сердечки", Icon = "💖", Price = 45, Kind = "Aura", Slot = "Aura", Color = Color3.fromRGB(255, 90, 150) },
}

---------------------------------------------------------------------
-- 🏆 Достижения
---------------------------------------------------------------------
-- Stat — что считаем, Goal — сколько нужно, Reward — монет
-- Счётчики: Fly (секунды полёта), Invisible, Laser, Cube (сколько раз включил), Walk (стадов пешком),
-- Taxi, Bus, Report, Arrest (по твоему заявлению задержали), Friend, Quest, Delivery, Buy, Photo, Night (минут ночью)
CityConfig.Achievements = {
	{ Id = "FirstFlight", Name = "Первый полёт", Icon = "🦅", Desc = "Пролетай 30 секунд", Stat = "Fly", Goal = 30, Reward = 10 },
	{ Id = "Pilot", Name = "Пилот", Icon = "✈️", Desc = "Пролетай 5 минут", Stat = "Fly", Goal = 300, Reward = 40 },
	{ Id = "Ghost", Name = "Призрак", Icon = "👻", Desc = "Стань невидимым 5 раз", Stat = "Invisible", Goal = 5, Reward = 15 },
	{ Id = "LaserEyes", Name = "Лазерный взгляд", Icon = "🔴", Desc = "Используй лазеры 10 раз", Stat = "Laser", Goal = 10, Reward = 15 },
	{ Id = "Cube", Name = "Кубизм", Icon = "🟥", Desc = "Превратись в куб 3 раза", Stat = "Cube", Goal = 3, Reward = 10 },
	{ Id = "Walker", Name = "Путешественник", Icon = "🚶", Desc = "Пройди пешком 3000 стадов", Stat = "Walk", Goal = 3000, Reward = 20 },
	{ Id = "Passenger", Name = "Пассажир", Icon = "🚕", Desc = "Прокатись на такси", Stat = "Taxi", Goal = 1, Reward = 10 },
	{ Id = "BusFan", Name = "Любитель автобусов", Icon = "🚌", Desc = "Сядь в автобус 3 раза", Stat = "Bus", Goal = 3, Reward = 15 },
	{ Id = "Citizen", Name = "Сознательный житель", Icon = "🚔", Desc = "Подай заявление в полицию", Stat = "Report", Goal = 1, Reward = 10 },
	{ Id = "Detective", Name = "Детектив", Icon = "🕵️", Desc = "По твоему заявлению кого-то задержали", Stat = "Arrest", Goal = 1, Reward = 25 },
	{ Id = "Friendly", Name = "Душа компании", Icon = "❤️", Desc = "Подружись с 3 жителями", Stat = "Friend", Goal = 3, Reward = 30 },
	{ Id = "Helper", Name = "Помощник", Icon = "❗", Desc = "Выполни 5 заданий жителей", Stat = "Quest", Goal = 5, Reward = 30 },
	{ Id = "Courier", Name = "Курьер", Icon = "📦", Desc = "Доставь 1 посылку", Stat = "Delivery", Goal = 1, Reward = 10 },
	{ Id = "CourierPro", Name = "Лучший курьер", Icon = "🏅", Desc = "Доставь 15 посылок", Stat = "Delivery", Goal = 15, Reward = 60 },
	{ Id = "Shopper", Name = "Модник", Icon = "🛍️", Desc = "Купи вещь в магазине", Stat = "Buy", Goal = 1, Reward = 5 },
	{ Id = "Photographer", Name = "Фотограф", Icon = "📷", Desc = "Сделай 10 фото", Stat = "Photo", Goal = 10, Reward = 15 },
	{ Id = "NightOwl", Name = "Сова", Icon = "🦉", Desc = "Проведи в игре 5 минут ночью", Stat = "Night", Goal = 5, Reward = 15 },
}

---------------------------------------------------------------------
-- 📷 Фоторежим
---------------------------------------------------------------------
CityConfig.Photo = {
	PoseRadius = 35, -- жители в этом радиусе позируют
	PoseChance = 0.8,
	Lines = { "Сыр!", "Я красиво получился?", "Ещё разок!", "Покажи потом!", "✌️" },
	Filters = {
		{ Name = "Обычный" },
		{ Name = "Ч/Б", Saturation = -1, Contrast = 0.15 },
		{ Name = "Тёплый", Tint = Color3.fromRGB(255, 225, 190), Saturation = 0.15 },
		{ Name = "Холодный", Tint = Color3.fromRGB(190, 215, 255), Saturation = -0.1 },
		{ Name = "Ретро", Tint = Color3.fromRGB(255, 220, 160), Saturation = -0.4, Contrast = 0.2, Brightness = 0.03 },
		{ Name = "Яркий", Saturation = 0.6, Contrast = 0.2 },
	},
}

---------------------------------------------------------------------
-- 💾 Сохранение
---------------------------------------------------------------------
-- Работает в опубликованной игре. В Studio: Game Settings → Security → Enable Studio Access to API Services.
CityConfig.SaveEnabled = true
CityConfig.DataStoreName = "CityLife_v1"

return CityConfig

----------------------------------------------------------------------
-- 11. ReplicatedStorage > ModuleScript "DebugConfig"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > DebugConfig
-- Меню отладки для владельца игры: клавиша F2 или кнопка 🛠 (видна только админам).
--
-- Кто видит меню:
--   * в Roblox Studio — все (это твой тест);
--   * в опубликованной игре — владелец игры (или владелец группы) и UserId из списка Admins.

local DebugConfig = {}

DebugConfig.Enabled = true
DebugConfig.Key = Enum.KeyCode.F2
DebugConfig.Admins = {
	-- 123456789, -- впиши сюда UserId тех, кому можно открывать меню
}
DebugConfig.AllInStudio = true -- в Studio меню доступно всем
DebugConfig.GroupMinRank = 255 -- если игра группы: с какого ранга группы открывается (255 = только владелец)
DebugConfig.LogLimit = 400 -- сколько строк Output хранить

-- Теги в Output, по которым удобно фильтровать
DebugConfig.LogTags = { "[NPC]", "[Traffic]", "[CityLife]", "[RigAnimator]", "[Debug]" }

--[[
	ЧТО НОВОГО — список обновлений с проверками.
	Каждое обновление: Version, Title, Items (что добавлено) и Tests (что проверить).
	Тест: Text — что сделать и что должно получиться;
	      Action (необязательно) — кнопка «▶», которая сразу всё подготовит:
	        SetHour (Arg = час), TimeScale (Arg = множитель), Weather (Arg = ключ погоды),
	        PoliceCall (Arg = номер вида вызова из VehicleConfig.PoliceCallTypes),
	        Coins (Arg = сколько), Teleport (Arg = "Desk" / "Cell" / "Place:Почта" / "Stop:1" / "Node:N1"),
	        StartJob, ResetCooldowns, ResetCity, AddStat (Arg = "Fly:30"), Overlay (Arg = слой карты), Tab (Arg = вкладка)
	Новое обновление — добавь в НАЧАЛО списка.
]]
DebugConfig.Changelog = {
	{
		Version = "1.9",
		Title = "Меню отладки",
		Items = { "Меню F2: обновления, мир, жители, машины, метки, Output, проверка карты" },
		Tests = {
			{ Text = "Включи слой «Дороги»: видны точки, связи и имена", Action = "Overlay", Arg = "Roads" },
			{ Text = "Вкладка «Жители»: у каждого видно, что делает", Action = "Tab", Arg = "npcs" },
			{ Text = "Время ×20: сутки пролетают за минуту", Action = "TimeScale", Arg = 20 },
			{ Text = "Вкладка «Проверка»: нет красных пунктов", Action = "Tab", Arg = "check" },
		},
	},
	{
		Version = "1.8",
		Title = "Жизнь в городе",
		Items = { "📦 Курьер", "🛍 Магазин аксессуаров", "🏆 17 достижений", "📷 Фоторежим", "💾 Сохранение" },
		Tests = {
			{ Text = "Начни заказ: коробка на «Почте», по E — в руках, получатель подсвечен", Action = "StartJob" },
			{ Text = "Получи 200 монет и купи кепку в 🛍 Магазине — она ровно на голове", Action = "Coins", Arg = 200 },
			{ Text = "Достижение «Первый полёт»: выезжает золотое окно", Action = "AddStat", Arg = "Fly:30" },
			{ Text = "📷 Камера в телефоне: фильтры, селфи, жители машут" },
			{ Text = "Невидимость (Q) прячет аксессуары" },
			{ Text = "Сбросить прогресс — вещи и награды пропали", Action = "ResetCity" },
		},
	},
	{
		Version = "1.7",
		Title = "Телефон",
		Items = { "📱 Телефон на P: карта, такси, полиция, автобус, сообщения, погода, задания, настройки" },
		Tests = {
			{ Text = "P: экран блокировки → нажать → рабочий стол" },
			{ Text = "🗺 Карта: дороги, ты, машины движутся" },
			{ Text = "🚕 Такси: вызов, такси приезжает к тебе", Action = "Coins", Arg = 20 },
			{ Text = "💬 Сообщения: знакомый житель пишет сам (подожди 1–2 мин)" },
		},
	},
	{
		Version = "1.6",
		Title = "Расписание и погода",
		Items = { "Утро, день, обед, вечер, ночь, выходные", "Ясно, облачно, дождь, гроза, туман" },
		Tests = {
			{ Text = "Обед 13:30: жители в кафе садятся за столы", Action = "SetHour", Arg = 13.5 },
			{ Text = "Ночь 22:00: жители идут спать домой, горят фонари", Action = "SetHour", Arg = 22 },
			{ Text = "Утро 7:00: просыпаются, «Доброе утро!»", Action = "SetHour", Arg = 7 },
			{ Text = "Гроза: дождь, молнии, зонты, жители уходят под крышу", Action = "Weather", Arg = "Storm" },
			{ Text = "Туман: дымка, машины медленнее и с фарами", Action = "Weather", Arg = "Fog" },
			{ Text = "Ясно — вернуть погоду", Action = "Weather", Arg = "Clear" },
		},
	},
	{
		Version = "1.5",
		Title = "Полиция",
		Items = { "Участок: дежурный за стойкой, офицеры ходят по кабинетам", "Вызовы, опрос, задержания, камера", "Без разворотов на дороге" },
		Tests = {
			{ Text = "Телепорт к дежурному: стоит за стойкой лицом к входу, по E — меню", Action = "Teleport", Arg = "Desk" },
			{ Text = "Вызов «Драка»: наряд выезжает, встаёт порознь у двери, опрос", Action = "PoliceCall", Arg = 4 },
			{ Text = "Камера: задержанный сидит, потом выходит", Action = "Teleport", Arg = "Cell" },
			{ Text = "Слой «Маршруты машин»: никто не разворачивается посреди дороги", Action = "Overlay", Arg = "CarRoutes" },
		},
	},
	{
		Version = "1.4",
		Title = "Транспорт",
		Items = { "Машины жителей, поток машин, такси, автобус, полиция, светофоры, звуки" },
		Tests = {
			{ Text = "Вкладка «Машины»: все едут, нет «застрявших» со скоростью 0 надолго", Action = "Tab", Arg = "cars" },
			{ Text = "Остановка 1: автобус приезжает, открывает двери", Action = "Teleport", Arg = "Stop:1" },
			{ Text = "Слой «Парковки»: у каждой видно тип", Action = "Overlay", Arg = "Parking" },
		},
	},
	{
		Version = "1.3",
		Title = "Жители",
		Items = { "Ходят по домам, двери, стулья, болтовня, разговоры, задания, дружба, работа, собаки, реакции" },
		Tests = {
			{ Text = "Слой «Точки жителей»: у каждой точки видно Activity и Zone", Action = "Overlay", Arg = "Points" },
			{ Text = "Слой «Пути жителей»: линии к цели, без застреваний", Action = "Overlay", Arg = "NPCPaths" },
			{ Text = "Садятся на стул лицом вперёд, по одному на место" },
			{ Text = "E у жителя: окно разговора, «Пойдём со мной!» работает" },
		},
	},
	{
		Version = "1.0",
		Title = "Способности",
		Items = { "Позы (C/X), невидимость (Q), лазеры (R), полёт (F), куб (T)" },
		Tests = {
			{ Text = "Сбросить кулдауны и проверить все способности подряд", Action = "ResetCooldowns" },
			{ Text = "Лазер по жителю: вскрикивает и убегает" },
			{ Text = "Жители реагируют на полёт и куб" },
		},
	},
}

return DebugConfig

----------------------------------------------------------------------
-- 12. ReplicatedStorage > ModuleScript "AbilityButton"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > AbilityButton
-- Общая кнопка способности: иконка, клавиша, затемнение и секунды кулдауна,
-- полоска оставшегося действия. Кнопки выстраиваются в ряд справа внизу по Slot.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local AbilityButton = {}
AbilityButton.__index = AbilityButton

local SIZE = 78
local GAP = 14
local BAR_HEIGHT = 6
local WHITE = Color3.new(1, 1, 1)
local IDLE_STROKE = Color3.fromRGB(150, 165, 190)
local COOLDOWN_STROKE = Color3.fromRGB(90, 100, 120)

local function getGui(): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("AbilitiesGui")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "AbilitiesGui"
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
	end
	return gui
end

--[[
	opts = {
		Name = "Невидимость",
		Icon = "👻",
		KeyName = "Q",
		Slot = 1,            -- 1 = крайняя справа, 2 = левее и т.д.
		Duration = 8,        -- для полоски действия
		Cooldown = 20,       -- для затемнения
		ActiveColor = Color3,
		OnActivate = function() end,
	}
]]
function AbilityButton.new(opts)
	local self = setmetatable({}, AbilityButton)
	self.duration = opts.Duration
	self.cooldown = opts.Cooldown
	self.activeColor = opts.ActiveColor

	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local slotOffset = (opts.Slot - 1) * (SIZE + GAP)

	-- Контейнер: кнопка сверху, полоска под ней
	local holder = Instance.new("Frame")
	holder.Name = opts.Name
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Size = UDim2.fromOffset(SIZE, SIZE + BAR_HEIGHT + 6)
	holder.Position = isTouch and UDim2.new(1, -20 - slotOffset, 1, -165)
		or UDim2.new(1, -24 - slotOffset, 1, -24)
	holder.Parent = getGui()

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(SIZE, SIZE)
	button.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	button.BackgroundTransparency = 0.2
	button.Text = ""
	button.ClipsDescendants = true
	button.Parent = holder
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 14)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = IDLE_STROKE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 1, -18)
	icon.Text = opts.Icon
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBold
	icon.TextColor3 = WHITE
	icon.ZIndex = 2
	icon.Parent = button
	local iconPad = Instance.new("UIPadding")
	iconPad.PaddingTop = UDim.new(0, 8)
	iconPad.PaddingLeft = UDim.new(0, 14)
	iconPad.PaddingRight = UDim.new(0, 14)
	iconPad.Parent = icon

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.AnchorPoint = Vector2.new(0, 1)
	nameLabel.Position = UDim2.new(0, 0, 1, -4)
	nameLabel.Size = UDim2.new(1, 0, 0, 14)
	nameLabel.Text = opts.Name
	nameLabel.TextColor3 = Color3.fromRGB(210, 220, 235)
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 11
	nameLabel.ZIndex = 2
	nameLabel.Parent = button

	if not isTouch and opts.KeyName then
		local keyLabel = Instance.new("TextLabel")
		keyLabel.BackgroundColor3 = Color3.new(0, 0, 0)
		keyLabel.BackgroundTransparency = 0.4
		keyLabel.Position = UDim2.fromOffset(5, 5)
		keyLabel.Size = UDim2.fromOffset(18, 18)
		keyLabel.Text = opts.KeyName
		keyLabel.TextColor3 = WHITE
		keyLabel.Font = Enum.Font.GothamBold
		keyLabel.TextSize = 12
		keyLabel.ZIndex = 4
		keyLabel.Parent = button
		Instance.new("UICorner", keyLabel).CornerRadius = UDim.new(0, 4)
	end

	-- Затемнение кулдауна: уменьшается снизу вверх по мере отката
	local shade = Instance.new("Frame")
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.ZIndex = 3
	shade.Parent = button

	local cooldownText = Instance.new("TextLabel")
	cooldownText.BackgroundTransparency = 1
	cooldownText.Size = UDim2.fromScale(1, 1)
	cooldownText.Text = ""
	cooldownText.TextColor3 = WHITE
	cooldownText.Font = Enum.Font.GothamBlack
	cooldownText.TextSize = 28
	cooldownText.TextStrokeTransparency = 0.5
	cooldownText.ZIndex = 4
	cooldownText.Parent = button

	-- Полоска оставшегося действия
	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0, 1)
	barBack.Position = UDim2.fromScale(0, 1)
	barBack.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	barBack.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	barBack.BackgroundTransparency = 0.2
	barBack.BorderSizePixel = 0
	barBack.Visible = false
	barBack.Parent = holder
	Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = opts.ActiveColor
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = holder

	-- Нажатие: кнопка «проседает» и пружинит обратно
	button.Activated:Connect(function()
		self:Pulse(0.86)
		opts.OnActivate()
	end)

	self.uiScale = uiScale
	self.wasCooling = false
	self.stroke = stroke
	self.icon = icon
	self.shade = shade
	self.cooldownText = cooldownText
	self.barBack = barBack
	self.barFill = barFill
	return self
end

function AbilityButton:Pulse(from: number)
	self.uiScale.Scale = from
	TweenService:Create(self.uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Вспышка «способность готова»
function AbilityButton:ReadyFlash()
	self:Pulse(1.18)
	self.stroke.Thickness = 5
	TweenService:Create(self.stroke, TweenInfo.new(0.5), { Thickness = 2 }):Play()
end

-- activeLeft: сколько секунд ещё действует способность (nil — не активна)
-- cooldownLeft: сколько секунд осталось до готовности
function AbilityButton:Update(activeLeft: number?, cooldownLeft: number)
	local cooling = activeLeft == nil and cooldownLeft > 0
	if self.wasCooling and not cooling and activeLeft == nil then
		self:ReadyFlash()
	end
	self.wasCooling = cooling
	if self.wasActive and not activeLeft then
		self.stroke.Thickness = 2
	end
	self.wasActive = activeLeft ~= nil

	if activeLeft then
		-- Пока способность действует, обводка «дышит»
		self.stroke.Thickness = 2.5 + math.sin(os.clock() * 8) * 1.2
		self.barBack.Visible = true
		self.barFill.Size = UDim2.fromScale(math.clamp(activeLeft / self.duration, 0, 1), 1)
		self.stroke.Color = self.activeColor
		self.shade.Size = UDim2.fromScale(1, 0)
		self.cooldownText.Text = ""
		self.icon.TextTransparency = 0.4
	elseif cooldownLeft > 0 then
		self.barBack.Visible = false
		self.shade.Size = UDim2.fromScale(1, math.clamp(cooldownLeft / self.cooldown, 0, 1))
		self.cooldownText.Text = tostring(math.ceil(cooldownLeft))
		self.stroke.Color = COOLDOWN_STROKE
		self.icon.TextTransparency = 0.5
	else
		self.barBack.Visible = false
		self.shade.Size = UDim2.fromScale(1, 0)
		self.cooldownText.Text = ""
		self.stroke.Color = IDLE_STROKE
		self.icon.TextTransparency = 0
	end
end

-- Всё сразу: кнопка, клавиши, запрос на сервер и таймеры по атрибутам.
-- opts — как у new(), плюс Remote, Keys, ActionName,
-- ActiveAttribute, UntilAttribute, CooldownAttribute.
function AbilityButton.Create(opts)
	local player = Players.LocalPlayer
	local lastRequest = 0
	local button

	local function request()
		local t = os.clock()
		if t - lastRequest < 0.25 then
			return
		end
		lastRequest = t
		opts.Remote:FireServer()
	end

	opts.OnActivate = request
	opts.KeyName = opts.KeyName or opts.Keys[1].Name
	button = AbilityButton.new(opts)

	ContextActionService:BindAction(opts.ActionName, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			button:Pulse(0.86)
			request()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(opts.Keys))

	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		local character = player.Character
		local active = character ~= nil and character:GetAttribute(opts.ActiveAttribute) == true
		local activeLeft = active and math.max(0, (character:GetAttribute(opts.UntilAttribute) or 0) - now) or nil
		local cooldownLeft = math.max(0, (player:GetAttribute(opts.CooldownAttribute) or 0) - now)
		button:Update(activeLeft, cooldownLeft)
	end)

	return button
end

return AbilityButton

----------------------------------------------------------------------
-- 13. ReplicatedStorage > ModuleScript "RigAnimator"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > RigAnimator
-- Общий движок процедурных анимаций для способностей.
-- Каждая способность добавляет персонажу «слой» анимации; движок раз в кадр
-- смешивает слои поверх обычных анимаций Roblox и выставляет суставы.
-- Работает с Motor6D и AnimationConstraint, для R15 и R6.
--
-- Слой:
--   {
--     Priority = 10,          -- кто выше, тот поверх
--     Additive = false,       -- true: добавляется к позе, false: заменяет её с весом
--     Update = function(rig, dt, now) return frames, weight, done end,
--   }
--   frames: { ИмяСустава = CFrame (поворот в пространстве родительской части),
--             Root = CFrame (смещение всего тела в пространстве HumanoidRootPart) }
--   done = true — слой закончился и будет удалён.

local RunService = game:GetService("RunService")

local RigAnimator = {}

local POSE_ATTRIBUTE = "Pose" -- пока персонаж сидит/лежит, анимации поз главнее
local IDENTITY = CFrame.identity

local JOINTS = {
	R15 = {
		Root = { "LowerTorso", "Root" },
		Waist = { "UpperTorso", "Waist" },
		Neck = { "Head", "Neck" },
		LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
		RightShoulder = { "RightUpperArm", "RightShoulder" },
		LeftElbow = { "LeftLowerArm", "LeftElbow" },
		RightElbow = { "RightLowerArm", "RightElbow" },
		LeftHip = { "LeftUpperLeg", "LeftHip" },
		RightHip = { "RightUpperLeg", "RightHip" },
		LeftKnee = { "LeftLowerLeg", "LeftKnee" },
		RightKnee = { "RightLowerLeg", "RightKnee" },
		LeftAnkle = { "LeftFoot", "LeftAnkle" },
		RightAnkle = { "RightFoot", "RightAnkle" },
	},
	R6 = {
		Root = { "HumanoidRootPart", "RootJoint" },
		Neck = { "Torso", "Neck" },
		LeftShoulder = { "Torso", "Left Shoulder" },
		RightShoulder = { "Torso", "Right Shoulder" },
		LeftHip = { "Torso", "Left Hip" },
		RightHip = { "Torso", "Right Hip" },
	},
}

local function isJoint(obj: Instance): boolean
	return obj:IsA("Motor6D") or obj:IsA("AnimationConstraint")
end

local function buildRig(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		return nil
	end
	local rigType = humanoid.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"
	local motors = {}
	for name, path in pairs(JOINTS[rigType]) do
		local part = character:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		if motor and isJoint(motor) then
			motors[name] = motor
		end
	end
	if not motors.Root then
		return nil
	end
	local legLength
	if rigType == "R15" then
		legLength = humanoid.HipHeight
	else
		local leg = character:FindFirstChild("Left Leg")
		legLength = leg and leg.Size.Y or 2
	end
	if legLength <= 0 then
		legLength = 2
	end
	return {
		character = character,
		rigType = rigType,
		motors = motors,
		hrpHalf = hrp.Size.Y / 2,
		legLength = legLength,
		scale = legLength / 2,
	}
end

local function toJointSpace(name: string, motor: any, frame: CFrame): CFrame
	if name == "Root" then
		local c0 = motor.C0
		return c0:Inverse() * frame * c0
	end
	local q = motor.C0.Rotation
	return q:Inverse() * frame * q
end

---------------------------------------------------------------------
-- Помощники для описания поз
---------------------------------------------------------------------

function RigAnimator.Angles(v: Vector3): CFrame
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

-- Таблица {Сустав = Vector3 градусов} -> {Сустав = CFrame}; R6-переопределения по ключу R6
function RigAnimator.Frames(rig, pose: { [string]: any }): { [string]: CFrame }
	local frames = {}
	local overrides = (rig.rigType == "R6" and pose.R6) or {}
	for name, value in pairs(pose) do
		if typeof(value) == "Vector3" and rig.motors[name] then
			frames[name] = RigAnimator.Angles(overrides[name] or value)
		end
	end
	for name, value in pairs(overrides) do
		if typeof(value) == "Vector3" and rig.motors[name] and not frames[name] then
			frames[name] = RigAnimator.Angles(value)
		end
	end
	return frames
end

-- Смешать две позы (таблицы Vector3) с коэффициентом t
function RigAnimator.Blend(a, b, t: number)
	local out = {}
	for name, va in pairs(a) do
		local vb = b[name]
		if typeof(va) == "Vector3" then
			out[name] = typeof(vb) == "Vector3" and va:Lerp(vb, t) or va:Lerp(Vector3.zero, t)
		end
	end
	for name, vb in pairs(b) do
		if typeof(vb) == "Vector3" and out[name] == nil then
			out[name] = Vector3.zero:Lerp(vb, t)
		end
	end
	return out
end

-- Смещение всего тела: высота таза (доля длины ноги, 1 = стоит) и поворот вокруг таза
function RigAnimator.RootFrame(rig, hipHeight: number, rootAngles: Vector3?, shift: Vector3?): CFrame
	local drop = Vector3.new(0, (hipHeight - 1) * rig.legLength, 0)
	local pivot = Vector3.new(0, -rig.hrpHalf, 0)
	local offset = (shift or Vector3.zero) * rig.scale + drop
	return CFrame.new(offset) * CFrame.new(pivot) * RigAnimator.Angles(rootAngles or Vector3.zero) * CFrame.new(-pivot)
end

-- Огибающая веса: плавно появиться за fadeIn, держаться, плавно уйти за fadeOut
function RigAnimator.Envelope(elapsed: number, total: number, fadeIn: number, fadeOut: number): number
	if elapsed <= 0 or elapsed >= total then
		return 0
	end
	local w = 1
	if elapsed < fadeIn then
		w = elapsed / fadeIn
	elseif elapsed > total - fadeOut then
		w = (total - elapsed) / fadeOut
	end
	return w * w * (3 - 2 * w)
end

function RigAnimator.Smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

---------------------------------------------------------------------
-- Слои
---------------------------------------------------------------------

local entries = {} -- [character] = { rig, layers }

function RigAnimator.SetLayer(character: Model, name: string, layer)
	local entry = entries[character]
	if not entry then
		entry = { rig = nil, layers = {} }
		entries[character] = entry
	end
	entry.layers[name] = layer
end

function RigAnimator.RemoveLayer(character: Model, name: string)
	local entry = entries[character]
	if entry then
		entry.layers[name] = nil
	end
end

function RigAnimator.HasLayer(character: Model, name: string): boolean
	local entry = entries[character]
	return entry ~= nil and entry.layers[name] ~= nil
end

local function ensureRig(character: Model, entry)
	local rig = entry.rig
	if rig then
		for _, motor in pairs(rig.motors) do
			if not motor:IsDescendantOf(character) then
				rig = nil
				break
			end
		end
	end
	if not rig then
		rig = buildRig(character)
		entry.rig = rig
	end
	return rig
end

local function byPriority(a, b)
	return a.layer.Priority < b.layer.Priority
end

-- PreSimulation идёт после стандартных анимаций: наши значения перекрывают их
RunService.PreSimulation:Connect(function(dt)
	local now = os.clock()
	for character, entry in pairs(entries) do
		if not character.Parent or next(entry.layers) == nil then
			entries[character] = nil
			continue
		end
		local pose = character:GetAttribute(POSE_ATTRIBUTE)
		if pose ~= nil and pose ~= "Stand" then
			continue
		end
		local rig = ensureRig(character, entry)
		if not rig then
			continue
		end

		local list = {}
		for name, layer in pairs(entry.layers) do
			table.insert(list, { name = name, layer = layer })
		end
		table.sort(list, byPriority)

		local finals = {}
		for name, motor in pairs(rig.motors) do
			finals[name] = motor.Transform
		end

		local wrote = false
		for _, item in list do
			local ok, frames, weight, done = pcall(item.layer.Update, rig, dt, now)
			if not ok then
				warn("[RigAnimator] ошибка в слое", item.name, frames)
				entry.layers[item.name] = nil
			elseif done then
				entry.layers[item.name] = nil
			elseif frames and weight and weight > 0.001 then
				wrote = true
				for jointName, frame in pairs(frames) do
					local motor = rig.motors[jointName]
					if motor then
						local target = toJointSpace(jointName, motor, frame)
						if item.layer.Additive then
							finals[jointName] = finals[jointName] * IDENTITY:Lerp(target, weight)
						else
							finals[jointName] = finals[jointName]:Lerp(target, weight)
						end
					end
				end
			end
		end

		if wrote then
			for name, motor in pairs(rig.motors) do
				motor.Transform = finals[name]
			end
		end
	end
end)

return RigAnimator

----------------------------------------------------------------------
-- 14. ReplicatedStorage > ModuleScript "AbilityFx"
----------------------------------------------------------------------

-- ModuleScript: ReplicatedStorage > AbilityFx
-- Общие эффекты для способностей (только на клиенте):
-- вспышки частиц, тряска камеры, плавные функции.

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local AbilityFx = {}

---------------------------------------------------------------------
-- Вспышка частиц в точке
---------------------------------------------------------------------
--[[
	opts = {
		Color = Color3 или ColorSequence,
		Count = 30,
		Speed = NumberRange.new(6, 14),
		Size = 0.5,               -- начальный размер, к концу уменьшается до 0
		Lifetime = NumberRange.new(0.3, 0.7),
		LightEmission = 1,
		Drag = 3,
		Acceleration = Vector3.zero,
		Spread = Vector2.new(180, 180),
		Direction = Enum.NormalId.Top,
	}
]]
function AbilityFx.Burst(position: Vector3, opts)
	opts = opts or {}
	local part = Instance.new("Part")
	part.Name = "AbilityBurst"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	part.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local lifetime = opts.Lifetime or NumberRange.new(0.3, 0.7)
	local color = opts.Color or Color3.new(1, 1, 1)
	local size = opts.Size or 0.5

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = typeof(color) == "ColorSequence" and color or ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = lifetime
	emitter.Speed = opts.Speed or NumberRange.new(6, 14)
	emitter.SpreadAngle = opts.Spread or Vector2.new(180, 180)
	emitter.EmissionDirection = opts.Direction or Enum.NormalId.Top
	emitter.LightEmission = opts.LightEmission or 1
	emitter.Drag = opts.Drag or 3
	emitter.Acceleration = opts.Acceleration or Vector3.zero
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(opts.Count or 30)

	if opts.Light then
		local light = Instance.new("PointLight")
		light.Color = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
		light.Range = opts.Light
		light.Brightness = 3
		light.Parent = attachment
		task.spawn(function()
			local start = os.clock()
			while light.Parent and os.clock() - start < 0.35 do
				light.Brightness = 3 * (1 - (os.clock() - start) / 0.35)
				RunService.Heartbeat:Wait()
			end
			light:Destroy()
		end)
	end

	Debris:AddItem(part, lifetime.Max + 0.3)
	return part
end

-- Пыль у ног персонажа
function AbilityFx.Dust(character: Model, count: number?, color: Color3?)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return
	end
	local legLength = humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.HipHeight or 2
	local feet = hrp.Position - Vector3.new(0, hrp.Size.Y / 2 + legLength - 0.2, 0)
	AbilityFx.Burst(feet, {
		Color = color or Color3.fromRGB(200, 190, 175),
		Count = count or 24,
		Speed = NumberRange.new(10, 18),
		Size = 1.2,
		Lifetime = NumberRange.new(0.4, 0.8),
		LightEmission = 0,
		Drag = 5,
		Spread = Vector2.new(85, 85),
		Acceleration = Vector3.new(0, 4, 0),
	})
end

---------------------------------------------------------------------
-- Тряска камеры
---------------------------------------------------------------------

local shakes = {}

function AbilityFx.Shake(intensity: number, duration: number)
	table.insert(shakes, { intensity = intensity, duration = duration, start = os.clock() })
end

RunService:BindToRenderStep("AbilityCameraShake", Enum.RenderPriority.Camera.Value + 1, function()
	if #shakes == 0 then
		return
	end
	local now = os.clock()
	local amount = 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local k = 1 - (now - s.start) / s.duration
		if k <= 0 then
			table.remove(shakes, i)
		else
			amount += s.intensity * k
		end
	end
	if amount > 0 then
		local camera = workspace.CurrentCamera
		local x = math.noise(now * 25, 1.3) * amount
		local y = math.noise(now * 25, 7.1) * amount
		local z = math.noise(now * 25, 3.7) * amount * 0.5
		camera.CFrame = camera.CFrame * CFrame.Angles(x, y, z)
	end
end)

---------------------------------------------------------------------
-- Плавные функции
---------------------------------------------------------------------

function AbilityFx.ElasticOut(t: number): number
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

function AbilityFx.BackIn(t: number): number
	t = math.clamp(t, 0, 1)
	local c1 = 1.70158
	return (c1 + 1) * t * t * t - c1 * t * t
end

function AbilityFx.Approach(current: number, target: number, step: number): number
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

return AbilityFx

----------------------------------------------------------------------
-- 15. ServerScriptService > ModuleScript "AbilityRegistry"
----------------------------------------------------------------------

-- ModuleScript: ServerScriptService > AbilityRegistry
-- Связывает серверные скрипты способностей между собой:
--   * одна способность может мгновенно выключить другую (куб выключает полёт и невидимость);
--   * способности могут поднять персонажа из позы (сидя/лёжа).

local AbilityRegistry = {}

local stoppers = {} -- [имя] = function(player, character)
local poseStandHandler = nil

-- Атрибуты, при которых нельзя садиться/ложиться
AbilityRegistry.BlockPoseAttributes = { "Flying", "CubeForm" }

function AbilityRegistry.RegisterStopper(name: string, stop: (Player, Model) -> ())
	stoppers[name] = stop
end

function AbilityRegistry.Stop(name: string, player: Player, character: Model)
	local stop = stoppers[name]
	if stop then
		stop(player, character)
	end
end

function AbilityRegistry.SetPoseStandHandler(handler: (Model) -> ())
	poseStandHandler = handler
end

function AbilityRegistry.ForcePoseStand(character: Model)
	if poseStandHandler then
		poseStandHandler(character)
	end
end

function AbilityRegistry.BlocksPose(character: Model): boolean
	for _, attribute in AbilityRegistry.BlockPoseAttributes do
		if character:GetAttribute(attribute) == true then
			return true
		end
	end
	return false
end

return AbilityRegistry

----------------------------------------------------------------------
-- 16. ServerScriptService > ModuleScript "NPCRegistry"
----------------------------------------------------------------------

-- ModuleScript: ServerScriptService > NPCRegistry
-- Мост между жителями (NPCServer) и транспортом (TrafficServer).
-- NPCServer кладёт сюда свои функции, TrafficServer — свои, и они вызывают друг друга.

local NPCRegistry = {}

-- Заполняет NPCServer:
--   npcs                         — таблица [model] = npc
--   walkTo(npc, position) → bool
--   say(npc, text, duration?)
--   setMood(npc, moodKey?, duration?)
--   setPose(npc, pose)
--   face(npc, direction, time?)
--   spawnCustom(cframe, options) → npc   (жители без обычного «мозга», например полицейские)
NPCRegistry.npcs = {}

-- Заполняет TrafficServer:
--   assignCar(npc)                         — дать жителю машину, если есть свободная
--   tryTrip(npc, targetPosition) → bool    — доехать (своя машина, такси или автобус); false — идти пешком
NPCRegistry.assignCar = nil
NPCRegistry.tryTrip = nil

return NPCRegistry

----------------------------------------------------------------------
-- 17. ServerScriptService > ModuleScript "VehicleDefaults"
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- 18. ServerScriptService > Script "PoseServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > PoseServer
-- Сервер: принимает запросы «вниз/вверх/встать», проверяет их,
-- выставляет атрибут позы персонажу (его видят все игроки) и блокирует ходьбу.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PoseConfig = require(ReplicatedStorage:WaitForChild("PoseConfig"))
local AbilityRegistry = require(script.Parent:WaitForChild("AbilityRegistry"))
local ATTR = PoseConfig.AttributeName

local remote = ReplicatedStorage:FindFirstChild(PoseConfig.RemoteName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = PoseConfig.RemoteName
	remote.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}

local SAVED = {
	WalkSpeed = "PoseSavedWalkSpeed",
	JumpPower = "PoseSavedJumpPower",
	JumpHeight = "PoseSavedJumpHeight",
	AutoRotate = "PoseSavedAutoRotate",
}

local function applyMovement(humanoid: Humanoid, state: string)
	local pose = PoseConfig.Poses[state]
	if pose then
		-- Запоминаем исходные значения только при выходе из положения «стоя»
		if humanoid:GetAttribute(SAVED.WalkSpeed) == nil then
			humanoid:SetAttribute(SAVED.WalkSpeed, humanoid.WalkSpeed)
			humanoid:SetAttribute(SAVED.JumpPower, humanoid.JumpPower)
			humanoid:SetAttribute(SAVED.JumpHeight, humanoid.JumpHeight)
			humanoid:SetAttribute(SAVED.AutoRotate, humanoid.AutoRotate)
		end
		humanoid.WalkSpeed = pose.WalkSpeed or 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = (pose.WalkSpeed or 0) > 0
	else
		local walkSpeed = humanoid:GetAttribute(SAVED.WalkSpeed)
		if walkSpeed ~= nil then
			humanoid.WalkSpeed = walkSpeed
			humanoid.JumpPower = humanoid:GetAttribute(SAVED.JumpPower)
			humanoid.JumpHeight = humanoid:GetAttribute(SAVED.JumpHeight)
			humanoid.AutoRotate = humanoid:GetAttribute(SAVED.AutoRotate)
			for _, name in pairs(SAVED) do
				humanoid:SetAttribute(name, nil)
			end
		end
	end
end

local function setPose(character: Model, state: string)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	character:SetAttribute(ATTR, state)
	applyMovement(humanoid, state)
end

-- Полёт и куб поднимают персонажа из позы
AbilityRegistry.SetPoseStandHandler(function(character: Model)
	if character:GetAttribute(ATTR) ~= "Stand" then
		setPose(character, "Stand")
	end
end)

remote.OnServerEvent:Connect(function(player: Player, direction: any)
	if direction ~= "Down" and direction ~= "Up" and direction ~= "Stand" then
		return
	end

	local now = os.clock()
	-- «Встать» пропускаем без кулдауна, чтобы игрок не застревал в позе
	if direction ~= "Stand" then
		if lastRequest[player] and now - lastRequest[player] < PoseConfig.ServerCooldown then
			return
		end
		lastRequest[player] = now
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local current = character:GetAttribute(ATTR)
	if not PoseConfig.IsValidState(current) then
		current = "Stand"
	end

	local nextState = PoseConfig.GetNextState(current, direction)
	if nextState == current or not PoseConfig.IsValidState(nextState) then
		return
	end

	-- Нельзя садиться, если персонаж уже сидит на сиденье (Seat), летит или стал кубом
	if current == "Stand" and (humanoid.Sit or AbilityRegistry.BlocksPose(character)) then
		return
	end

	setPose(character, nextState)
end)

local function onCharacterAdded(character: Model)
	character:SetAttribute(ATTR, "Stand")
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	-- Сел на настоящее сиденье — выходим из позы
	humanoid.Seated:Connect(function(active)
		if active and character:GetAttribute(ATTR) ~= "Stand" then
			setPose(character, "Stand")
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

----------------------------------------------------------------------
-- 19. ServerScriptService > Script "InvisibilityServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > InvisibilityServer
-- Сервер ведёт таймеры невидимости и кулдауна. Сами эффекты рисует
-- каждый клиент по атрибутам: себе — «стекло», другим — полная невидимость.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("InvisibilityConfig"))
local AbilityRegistry = require(script.Parent:WaitForChild("AbilityRegistry"))

local remote = ReplicatedStorage:FindFirstChild(Config.RemoteName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = Config.RemoteName
	remote.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}
local tokens: { [Player]: number } = {} -- чтобы старый таймер не выключил новую невидимость

local function now(): number
	return workspace:GetServerTimeNow()
end

local function endInvisibility(player: Player, character: Model)
	if character:GetAttribute(Config.ActiveAttribute) ~= true then
		return
	end
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	player:SetAttribute(Config.CooldownAttribute, now() + Config.Cooldown)
end

local function startInvisibility(player: Player, character: Model)
	AbilityRegistry.Stop("Cube", player, character) -- куб и невидимость вместе не работают
	local token = (tokens[player] or 0) + 1
	tokens[player] = token
	character:SetAttribute(Config.ActiveAttribute, true)
	character:SetAttribute(Config.UntilAttribute, now() + Config.Duration)

	task.delay(Config.Duration, function()
		if tokens[player] == token and character.Parent then
			endInvisibility(player, character)
		end
	end)
end

AbilityRegistry.RegisterStopper("Invisibility", endInvisibility)

remote.OnServerEvent:Connect(function(player: Player)
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < 0.25 then
		return
	end
	lastRequest[player] = t

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if character:GetAttribute(Config.ActiveAttribute) == true then
		if Config.CanCancelEarly then
			endInvisibility(player, character)
		end
		return
	end

	if now() < (player:GetAttribute(Config.CooldownAttribute) or 0) then
		return
	end

	startInvisibility(player, character)
end)

local function onCharacterAdded(player: Player, character: Model)
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			endInvisibility(player, character)
		end)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Config.CooldownAttribute, 0)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	tokens[player] = nil
end)

----------------------------------------------------------------------
-- 20. ServerScriptService > Script "LaserServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > LaserServer
-- Сервер ведёт таймеры лазеров, принимает прицел от игрока и наносит урон.
-- Лучи и искры рисует каждый клиент по атрибутам персонажа.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LaserConfig"))

local function getRemote(name: string, className: string)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local remote = getRemote(Config.RemoteName, "RemoteEvent")
local aimRemote = getRemote(Config.AimRemoteName, "UnreliableRemoteEvent")

local lastRequest: { [Player]: number } = {}
local tokens: { [Player]: number } = {}
local firing: { [Player]: Model } = {} -- кто сейчас стреляет

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stopLaser(player: Player, character: Model)
	firing[player] = nil
	if character:GetAttribute(Config.ActiveAttribute) ~= true then
		return
	end
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	player:SetAttribute(Config.CooldownAttribute, now() + Config.Cooldown)
end

local function startLaser(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local token = (tokens[player] or 0) + 1
	tokens[player] = token

	character:SetAttribute(Config.AimAttribute, head.Position + head.CFrame.LookVector * Config.Range)
	character:SetAttribute(Config.UntilAttribute, now() + Config.Duration)
	character:SetAttribute(Config.ActiveAttribute, true)
	firing[player] = character

	task.delay(Config.Duration, function()
		if tokens[player] == token and character.Parent then
			stopLaser(player, character)
		end
	end)
end

remote.OnServerEvent:Connect(function(player: Player)
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < 0.25 then
		return
	end
	lastRequest[player] = t

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if character:GetAttribute(Config.ActiveAttribute) == true then
		if Config.CanCancelEarly then
			stopLaser(player, character)
		end
		return
	end

	if now() < (player:GetAttribute(Config.CooldownAttribute) or 0) then
		return
	end

	startLaser(player, character)
end)

aimRemote.OnServerEvent:Connect(function(player: Player, point: any)
	local character = firing[player]
	if not character or typeof(point) ~= "Vector3" or point ~= point then
		return -- не стреляет, мусор или NaN
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	-- Ограничиваем дальность, чтобы нельзя было «бить» через всю карту
	local offset = point - head.Position
	if offset.Magnitude > Config.Range then
		point = head.Position + offset.Unit * Config.Range
	end
	character:SetAttribute(Config.AimAttribute, point)
end)

local function isFriendly(attacker: Player, victimModel: Model): boolean
	if Config.FriendlyFire then
		return false
	end
	local victim = Players:GetPlayerFromCharacter(victimModel)
	return victim ~= nil
		and not attacker.Neutral
		and not victim.Neutral
		and attacker.Team ~= nil
		and attacker.Team == victim.Team
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < Config.DamageInterval then
		return
	end
	local interval = accumulator
	accumulator = 0

	for player, character in pairs(firing) do
		local head = character:FindFirstChild("Head")
		local aim = character:GetAttribute(Config.AimAttribute)
		if head and typeof(aim) == "Vector3" then
			local direction = aim - head.Position
			if direction.Magnitude > 0.01 then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { character }
				local result = workspace:Raycast(head.Position, direction.Unit * Config.Range, params)
				if result then
					local model = result.Instance:FindFirstAncestorWhichIsA("Model")
					local humanoid = model and model:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 and not isFriendly(player, model) then
						humanoid:TakeDamage(Config.DamagePerSecond * interval)
					end
				end
			end
		end
	end
end)

local function onCharacterAdded(player: Player, character: Model)
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			stopLaser(player, character)
		end)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Config.CooldownAttribute, 0)
	player.CharacterAdded:Connect(function(character)
		firing[player] = nil
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	tokens[player] = nil
	firing[player] = nil
end)

----------------------------------------------------------------------
-- 21. ServerScriptService > Script "FlightServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > FlightServer
-- Сервер ведёт таймеры полёта. Саму физику полёта считает клиент игрока
-- (персонаж принадлежит ему), анимации рисует каждый клиент.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FlightConfig"))
local AbilityRegistry = require(script.Parent:WaitForChild("AbilityRegistry"))

local remote = ReplicatedStorage:FindFirstChild(Config.RemoteName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = Config.RemoteName
	remote.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}
local tokens: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stopFlight(player: Player, character: Model)
	if character:GetAttribute(Config.ActiveAttribute) ~= true then
		return
	end
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	player:SetAttribute(Config.CooldownAttribute, now() + Config.Cooldown)
end

local function startFlight(player: Player, character: Model)
	AbilityRegistry.Stop("Cube", player, character)
	AbilityRegistry.ForcePoseStand(character)

	local token = (tokens[player] or 0) + 1
	tokens[player] = token
	character:SetAttribute(Config.UntilAttribute, now() + Config.Duration)
	character:SetAttribute(Config.ActiveAttribute, true)

	task.delay(Config.Duration, function()
		if tokens[player] == token and character.Parent then
			stopFlight(player, character)
		end
	end)
end

AbilityRegistry.RegisterStopper("Flight", stopFlight)

remote.OnServerEvent:Connect(function(player: Player)
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < 0.25 then
		return
	end
	lastRequest[player] = t

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if character:GetAttribute(Config.ActiveAttribute) == true then
		if Config.CanCancelEarly then
			stopFlight(player, character)
		end
		return
	end

	if humanoid.Sit or now() < (player:GetAttribute(Config.CooldownAttribute) or 0) then
		return
	end

	startFlight(player, character)
end)

local function onCharacterAdded(player: Player, character: Model)
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			stopFlight(player, character)
		end)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Config.CooldownAttribute, 0)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	tokens[player] = nil
end)

----------------------------------------------------------------------
-- 22. ServerScriptService > Script "CubeServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > CubeServer
-- Превращение в куб. Сервер создаёт сам куб (его видят все), с лицом и
-- светящимися рёбрами, и меняет скорость/прыжок. Тело прячут клиенты,
-- а подскоки, сплющивание и сальто куба тоже рисуются на клиентах.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CubeConfig"))
local AbilityRegistry = require(script.Parent:WaitForChild("AbilityRegistry"))

local remote = ReplicatedStorage:FindFirstChild(Config.RemoteName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = Config.RemoteName
	remote.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}
local tokens: { [Player]: number } = {}

local SAVED_SPEED = "CubeSavedWalkSpeed"
local SAVED_JUMP = "CubeSavedJumpPower"
local SAVED_HEIGHT = "CubeSavedJumpHeight"

local function now(): number
	return workspace:GetServerTimeNow()
end

local function makeFace(cube: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(200, 200)
	gui.Parent = cube

	for i, x in { 0.32, 0.68 } do
		local eye = Instance.new("Frame")
		eye.Name = "Eye" .. i
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(x, 0.4)
		eye.Size = UDim2.fromScale(0.13, 0.2)
		eye.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		eye.BorderSizePixel = 0
		eye.Parent = gui
		Instance.new("UICorner", eye).CornerRadius = UDim.new(0.5, 0)

		local shine = Instance.new("Frame")
		shine.Position = UDim2.fromScale(0.2, 0.15)
		shine.Size = UDim2.fromScale(0.35, 0.3)
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BorderSizePixel = 0
		shine.Parent = eye
		Instance.new("UICorner", shine).CornerRadius = UDim.new(0.5, 0)
	end

	local mouth = Instance.new("Frame")
	mouth.Name = "Mouth"
	mouth.AnchorPoint = Vector2.new(0.5, 0.5)
	mouth.Position = UDim2.fromScale(0.5, 0.66)
	mouth.Size = UDim2.fromScale(0.2, 0.06)
	mouth.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	mouth.BorderSizePixel = 0
	mouth.Parent = gui
	Instance.new("UICorner", mouth).CornerRadius = UDim.new(0.5, 0)
end

local function createCube(character: Model, humanoid: Humanoid, hrp: BasePart): BasePart
	local legLength = humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.HipHeight or 2
	local scale = legLength / 2
	local size = Config.Size * scale
	local groundY = -(hrp.Size.Y / 2 + legLength) -- уровень земли относительно центра HumanoidRootPart
	local offsetY = groundY + size / 2

	local cube = Instance.new("Part")
	cube.Name = Config.PartName
	cube.Size = Vector3.new(size, size, size)
	cube.Color = Config.Colors[math.random(1, #Config.Colors)]
	cube.Material = Enum.Material.SmoothPlastic
	cube.TopSurface = Enum.SurfaceType.Smooth
	cube.BottomSurface = Enum.SurfaceType.Smooth
	cube.CanCollide = false
	cube.CanTouch = false
	cube.Massless = true
	cube.CFrame = hrp.CFrame * CFrame.new(0, offsetY, 0)
	cube:SetAttribute("BaseSize", size)
	cube:SetAttribute("OffsetY", offsetY)

	local weld = Instance.new("Weld")
	weld.Name = "CubeWeld"
	weld.Part0 = hrp
	weld.Part1 = cube
	weld.C0 = CFrame.new(0, offsetY, 0)
	weld.Parent = cube

	local edges = Instance.new("SelectionBox")
	edges.Name = "Edges"
	edges.Adornee = cube
	edges.LineThickness = Config.EdgeThickness * scale
	edges.Color3 = Config.EdgeColor
	edges.SurfaceTransparency = 1
	edges.Parent = cube

	local glow = Instance.new("PointLight")
	glow.Color = cube.Color
	glow.Range = 10 * scale
	glow.Brightness = 1.2
	glow.Parent = cube

	makeFace(cube)
	cube.Parent = character
	return cube
end

local function stopCube(player: Player, character: Model)
	if character:GetAttribute(Config.ActiveAttribute) ~= true then
		return
	end
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	player:SetAttribute(Config.CooldownAttribute, now() + Config.Cooldown)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:GetAttribute(SAVED_SPEED) ~= nil then
		humanoid.WalkSpeed = humanoid:GetAttribute(SAVED_SPEED)
		humanoid.JumpPower = humanoid:GetAttribute(SAVED_JUMP)
		humanoid.JumpHeight = humanoid:GetAttribute(SAVED_HEIGHT)
		humanoid:SetAttribute(SAVED_SPEED, nil)
		humanoid:SetAttribute(SAVED_JUMP, nil)
		humanoid:SetAttribute(SAVED_HEIGHT, nil)
	end

	-- Даём клиентам анимировать сжатие куба, потом убираем его
	local cube = character:FindFirstChild(Config.PartName)
	if cube then
		task.delay(Config.PopOutTime, function()
			if character:GetAttribute(Config.ActiveAttribute) ~= true then
				cube:Destroy()
			end
		end)
	end
end

local function startCube(player: Player, character: Model, humanoid: Humanoid)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	AbilityRegistry.Stop("Invisibility", player, character)
	AbilityRegistry.Stop("Flight", player, character)
	AbilityRegistry.ForcePoseStand(character)

	-- Старый куб (если ещё не успел исчезнуть) убираем сразу
	local old = character:FindFirstChild(Config.PartName)
	if old then
		old:Destroy()
	end
	createCube(character, humanoid, hrp)

	humanoid:SetAttribute(SAVED_SPEED, humanoid.WalkSpeed)
	humanoid:SetAttribute(SAVED_JUMP, humanoid.JumpPower)
	humanoid:SetAttribute(SAVED_HEIGHT, humanoid.JumpHeight)
	humanoid.WalkSpeed = Config.WalkSpeed
	humanoid.JumpPower = Config.JumpPower
	humanoid.JumpHeight = Config.JumpPower * Config.JumpPower / (2 * workspace.Gravity)

	local token = (tokens[player] or 0) + 1
	tokens[player] = token
	character:SetAttribute(Config.UntilAttribute, now() + Config.Duration)
	character:SetAttribute(Config.ActiveAttribute, true)

	task.delay(Config.Duration, function()
		if tokens[player] == token and character.Parent then
			stopCube(player, character)
		end
	end)
end

AbilityRegistry.RegisterStopper("Cube", stopCube)

remote.OnServerEvent:Connect(function(player: Player)
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < 0.25 then
		return
	end
	lastRequest[player] = t

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if character:GetAttribute(Config.ActiveAttribute) == true then
		if Config.CanCancelEarly then
			stopCube(player, character)
		end
		return
	end

	if humanoid.Sit or now() < (player:GetAttribute(Config.CooldownAttribute) or 0) then
		return
	end

	startCube(player, character, humanoid)
end)

local function onCharacterAdded(player: Player, character: Model)
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			stopCube(player, character)
		end)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Config.CooldownAttribute, 0)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	tokens[player] = nil
end)

----------------------------------------------------------------------
-- 23. ServerScriptService > Script "NPCDemo"
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- 24. ServerScriptService > Script "NPCServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > NPCServer
-- Жители города (NPC):
--   * появляются на точках Spawns, «просыпаются» (лёжа → на колени → встают);
--   * ходят по точкам Points с поиском пути: по дому, потом на улицу, в другие дома;
--   * в точках занимаются делами: стоят, смотрят в окно, сидят, лежат, танцуют, ждут собеседника;
--   * болтают друг с другом (облачка с текстом и жесты), машут проходящим игрокам;
--   * с ними можно поговорить (кнопка E) и выбрать тему;
--   * получив урон, вскрикивают и убегают; погибнув — возрождаются на своей точке;
--   * ночью идут домой спать (💤), утром просыпаются (DayNightServer);
--   * реагируют на суперспособности: показывают на летящего, смеются над кубом,
--     оглядываются на невидимку, разбегаются от лазеров;
--   * помнят игроков по имени и могут пойти следом («Пойдём со мной!»);
--   * над головой значок настроения;
--   * живут по расписанию: утро, день, обед, вечер, ночь; в выходные отдыхают
--     (NPCConfig.Schedule), продавцы работают по часам с обедом;
--   * погода: в дождь раскрывают зонты, прячутся по домам и ускоряют шаг, пугаются грома;
--   * дают задания (❗): найти потерянную вещь за монеты;
--   * дружат с игроками (Знакомый → Приятель → Друг ❤️), друзьям дарят подарок;
--   * работают: продавцы стоят за прилавком (Activity = "Work"), охранники обходят маршрут ("Patrol");
--   * гуляют с собаками и носят вещи в руках (кофе, телефон, мороженое, сумка).
-- Анимации — стандартные анимации Roblox (их видят все), сидение/лежание на полу —
-- через систему поз (PoseClient).

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local SoundConfig = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local folder = workspace:WaitForChild(Config.FolderName, 30)
if not folder then
	warn("[NPC] Нет папки Workspace >", Config.FolderName, "— жители не появятся. См. NPC_SETUP.md")
	return
end
local spawnsFolder = folder:WaitForChild("Spawns", 10)
local pointsFolder = folder:WaitForChild("Points", 10)
if not spawnsFolder or not pointsFolder then
	warn("[NPC] В папке", Config.FolderName, "нужны папки Spawns и Points")
	return
end

local liveFolder = folder:FindFirstChild("Live") or Instance.new("Folder")
liveFolder.Name = "Live"
liveFolder.Parent = folder

local dialogRemote = ReplicatedStorage:FindFirstChild("NPCDialog") or Instance.new("RemoteEvent")
dialogRemote.Name = "NPCDialog"
dialogRemote.Parent = ReplicatedStorage

-- Жители не толкают друг друга в дверях
local COLLISION_GROUP = "NPCs"
pcall(function()
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
end)

-- Атрибуты суперспособностей (если таких скриптов нет — берём стандартные имена)
local function abilityAttribute(moduleName: string, default: string): string
	local module = ReplicatedStorage:FindFirstChild(moduleName)
	if module then
		local ok, cfg = pcall(require, module)
		if ok and type(cfg) == "table" and cfg.ActiveAttribute then
			return cfg.ActiveAttribute
		end
	end
	return default
end
local ATTR_FLYING = abilityAttribute("FlightConfig", "Flying")
local ATTR_CUBE = abilityAttribute("CubeConfig", "CubeForm")
local ATTR_INVISIBLE = abilityAttribute("InvisibilityConfig", "Invisible")
local ATTR_LASER = abilityAttribute("LaserConfig", "LaserActive")

local memory = {} -- [имя жителя] = { [UserId] = true } — с кем уже знакомы

local rng = Random.new()
local function pick(list)
	return list[rng:NextInteger(1, #list)]
end
local function randomIn(range: NumberRange): number
	return rng:NextNumber(range.Min, range.Max)
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

---------------------------------------------------------------------
-- Маркеры на карте
---------------------------------------------------------------------

local function hideMarker(part: BasePart)
	if Config.HideMarkersInGame and not part:IsA("Seat") then
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		for _, d in part:GetDescendants() do
			if d:IsA("Decal") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
	end
end

local points = {} -- [part] = { part, activity, zone, occupants }
local routes = {} -- [имя маршрута] = { points = {...по Order}, guard = npc }

local function registerPoint(part: Instance)
	if not part:IsA("BasePart") or points[part] then
		return
	end
	hideMarker(part)
	local activity = part:GetAttribute("Activity") or (part:IsA("Seat") and "Sit") or "Idle"
	local info = {
		part = part,
		activity = activity,
		zone = part:GetAttribute("Zone"),
		occupants = 0,
		capacity = activity == "Talk" and 2 or 1,
		role = part:GetAttribute("Role"),
		route = part:GetAttribute("Route"),
		order = part:GetAttribute("Order") or 0,
		worker = nil,
	}
	points[part] = info
	if activity == "Patrol" then
		local name = info.route or "Patrol"
		local route = routes[name] or { points = {}, guard = nil }
		routes[name] = route
		info.route = name
		table.insert(route.points, info)
		table.sort(route.points, function(a, b)
			return a.order < b.order
		end)
	end
end

for _, d in pointsFolder:GetDescendants() do
	registerPoint(d)
end
pointsFolder.DescendantAdded:Connect(registerPoint)
pointsFolder.DescendantRemoving:Connect(function(d)
	local info = points[d]
	points[d] = nil
	if info and info.route and routes[info.route] then
		local list = routes[info.route].points
		local i = table.find(list, info)
		if i then
			table.remove(list, i)
		end
	end
end)

for _, d in spawnsFolder:GetDescendants() do
	if d:IsA("BasePart") then
		hideMarker(d)
	end
end

---------------------------------------------------------------------
-- Внешность
---------------------------------------------------------------------

local function makeDescription(opts): HumanoidDescription
	if opts and opts.shirt then
		-- Форма (например, полиция)
		local desc = Instance.new("HumanoidDescription")
		local skin = pick(Config.SkinColors)
		desc.HeadColor = skin
		desc.TorsoColor = opts.shirt
		desc.LeftArmColor = opts.shirt
		desc.RightArmColor = opts.shirt
		desc.LeftLegColor = opts.pants or opts.shirt
		desc.RightLegColor = opts.pants or opts.shirt
		return desc
	end
	if #Config.AvatarUserIds > 0 then
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(pick(Config.AvatarUserIds))
		end)
		if ok and desc then
			return desc
		end
	end
	local desc = Instance.new("HumanoidDescription")
	local skin = pick(Config.SkinColors)
	local shirt = pick(Config.ShirtColors)
	local pants = pick(Config.PantsColors)
	local longSleeves = rng:NextNumber() < 0.5
	desc.HeadColor = skin
	desc.TorsoColor = shirt
	desc.LeftArmColor = longSleeves and shirt or skin
	desc.RightArmColor = longSleeves and shirt or skin
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	desc.HeightScale = rng:NextNumber(0.92, 1.05)
	desc.WidthScale = rng:NextNumber(0.9, 1.05)
	return desc
end

---------------------------------------------------------------------
-- Анимации (на сервере — видны всем)
---------------------------------------------------------------------

local function newAnimator(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks = {}

	local function track(name: string, priority: Enum.AnimationPriority, looped: boolean)
		if tracks[name] == nil then
			local animation = Instance.new("Animation")
			animation.AnimationId = Config.Animations[name]
			local ok, t = pcall(animator.LoadAnimation, animator, animation)
			if ok and t then
				t.Priority = priority
				t.Looped = looped
				tracks[name] = t
			else
				tracks[name] = false
			end
		end
		return tracks[name] or nil
	end

	local self = { current = nil }

	local function setLocomotion(name: string, speed: number)
		local t = track(name, name == "Idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement, true)
		if self.current ~= t then
			if self.current then
				self.current:Stop(0.25)
			end
			if t then
				t:Play(0.25)
			end
			self.current = t
		end
		if t then
			t:AdjustSpeed(speed)
		end
	end

	humanoid.Running:Connect(function(speed)
		if speed < 0.5 then
			setLocomotion("Idle", 1)
		elseif speed < 15 then
			setLocomotion("Walk", speed / 14)
		else
			setLocomotion("Run", speed / 20)
		end
	end)

	humanoid.StateChanged:Connect(function(_, new)
		local fall = track("Fall", Enum.AnimationPriority.Movement, true)
		if new == Enum.HumanoidStateType.Freefall then
			if fall then
				fall:Play(0.2)
			end
		elseif fall and fall.IsPlaying then
			fall:Stop(0.2)
		end
		if new == Enum.HumanoidStateType.Jumping then
			local jump = track("Jump", Enum.AnimationPriority.Movement, false)
			if jump then
				jump:Play(0.1)
			end
		end
	end)

	humanoid.Seated:Connect(function(active)
		local sit = track("SitChair", Enum.AnimationPriority.Action, true)
		if sit then
			if active then
				sit:Play(0.3)
			else
				sit:Stop(0.3)
			end
		end
	end)

	-- Жест/эмоция: проигрывается поверх, duration — для зацикленных (танец)
	function self.emote(name: string, duration: number?)
		local looped = duration ~= nil
		local t = track(name, Enum.AnimationPriority.Action, looped)
		if t then
			t:Play(0.2)
			if duration then
				task.delay(duration, function()
					t:Stop(0.4)
				end)
			end
		end
		return t
	end

	function self.stopAll()
		for _, t in pairs(tracks) do
			if t then
				t:Stop(0.2)
			end
		end
	end

	setLocomotion("Idle", 1)
	return self
end

---------------------------------------------------------------------
-- Жители
---------------------------------------------------------------------

local npcs = Registry.npcs -- [model] = npc (общая таблица с транспортом)
local total = 0

local function say(npc, text: string, duration: number?)
	if not npc.alive then
		return
	end
	npc.model:SetAttribute("SayDuration", duration or Config.BubbleTime)
	npc.model:SetAttribute("SayText", text)
	npc.model:SetAttribute("SayId", (npc.model:GetAttribute("SayId") or 0) + 1)
end

-- Звук жителя (имя из SoundConfig.NPC), играют клиенты
local function sfx(npc, name: string)
	if npc.alive and SoundConfig.NPC[name] then
		npc.model:SetAttribute("SoundEvent", name)
		npc.model:SetAttribute("SoundEventId", (npc.model:GetAttribute("SoundEventId") or 0) + 1)
	end
end

-- Значок настроения над головой (ключ из NPCConfig.Moods, nil — убрать)
-- Если временного настроения нет — показываем «постоянное» (например, ❗ задание)
local function moodValue(npc, mood: string?)
	local key = mood or npc.baseMood
	return key and Config.Moods[key] or nil
end

local function setMood(npc, mood: string?, duration: number?)
	npc.moodToken = (npc.moodToken or 0) + 1
	npc.activeMood = mood
	local token = npc.moodToken
	npc.model:SetAttribute("Mood", moodValue(npc, mood))
	if duration then
		task.delay(duration, function()
			if npc.moodToken == token and npc.model.Parent then
				npc.activeMood = nil
				npc.model:SetAttribute("Mood", moodValue(npc, nil))
			end
		end)
	end
end

local function setBaseMood(npc, mood: string?)
	npc.baseMood = mood
	if npc.activeMood == nil then
		npc.model:SetAttribute("Mood", moodValue(npc, nil))
	end
end

local function isNight(): boolean
	return workspace:GetAttribute("IsNight") == true
end

---------------------------------------------------------------------
-- Расписание и погода
---------------------------------------------------------------------

local Lighting = game:GetService("Lighting")

local function hourNow(): number
	return workspace:GetAttribute("Hour") or Lighting.ClockTime
end

local function isWeekend(): boolean
	return workspace:GetAttribute("Weekend") == true
end

local function rainNow(): number
	return workspace:GetAttribute("Rain") or 0
end

local function currentPeriod()
	local hour = hourNow()
	for _, p in Config.Schedule or {} do
		if hour >= p.From and hour < p.To then
			return p
		end
	end
	return nil
end

-- Продавцы работают в рабочие часы, кроме обеда (и выходных, если так настроено)
local function isWorkTime(): boolean
	local h, w = hourNow(), Config.WorkHours
	if not w then
		return true
	end
	if Config.WorkersRestOnWeekend and isWeekend() then
		return false
	end
	return h >= w.Start and h < w.End and not (h >= w.LunchStart and h < w.LunchEnd)
end

local function walkSpeedOf(npc): number
	return npc.speed * (npc.speedMul or 1)
end

---------------------------------------------------------------------
-- Монеты и дружба
---------------------------------------------------------------------

local function getCoins(player: Player): IntValue
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local coins = stats:FindFirstChild(Config.CurrencyName)
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = Config.CurrencyName
		coins.Parent = stats
	end
	return coins
end
Players.PlayerAdded:Connect(getCoins)
for _, player in Players:GetPlayers() do
	getCoins(player)
end

local function toast(player: Player, text: string)
	if player.Parent then
		dialogRemote:FireClient(player, "Toast", text)
	end
end

local function addCoins(player: Player, amount: number)
	getCoins(player).Value += amount
	toast(player, string.format("+%d 🪙 %s", amount, Config.CurrencyName))
end

local FRIEND_POINTS = Config.FriendLevels[#Config.FriendLevels].Points

local function friendPoints(npc, player: Player): number
	local m = memory[npc.name]
	return m and m[player.UserId] or 0
end

local function friendLevel(amount: number)
	local level = Config.FriendLevels[1]
	for _, l in Config.FriendLevels do
		if amount >= l.Points then
			level = l
		end
	end
	return level
end

local function addFriendship(npc, player: Player, amount: number)
	memory[npc.name] = memory[npc.name] or {}
	local before = memory[npc.name][player.UserId] or 0
	local after = before + amount
	memory[npc.name][player.UserId] = after
	-- Стали друзьями — подарок
	if before < FRIEND_POINTS and after >= FRIEND_POINTS then
		task.delay(2.5, function()
			if npc.alive then
				say(npc, pick(Config.Phrases.Gift))
				npc.anim.emote("Cheer")
				setMood(npc, "Happy", 4)
			end
			if player.Parent then
				addCoins(player, Config.FriendGift)
				toast(player, "❤️ " .. npc.name .. " теперь твой друг!")
				if Registry.playerEvent then
					Registry.playerEvent(player, "Friend")
				end
			end
		end)
	end
end

---------------------------------------------------------------------
-- Задания: найти потерянную вещь
---------------------------------------------------------------------

local playerQuests = {} -- [player] = задание

local function clearQuest(quest, reason: string?)
	if quest.done then
		return
	end
	quest.done = true
	local player = quest.player
	if playerQuests[player] == quest then
		playerQuests[player] = nil
	end
	if quest.item and quest.item.Parent then
		quest.item:Destroy()
	end
	if quest.npc.activeQuest == quest then
		quest.npc.activeQuest = nil
	end
	if player.Parent then
		player:SetAttribute("QuestText", nil)
		if reason then
			toast(player, reason)
		end
	end
end

local function offerQuestLater(npc, delay: number)
	task.delay(delay, function()
		if npc.alive and not npc.activeQuest and not npc.route and rng:NextNumber() < math.min(1, Config.QuestChance * 1.5) then
			npc.hasQuest = true
			setBaseMood(npc, "Quest")
		end
	end)
end

local function questSpot(npc)
	local far, any = {}, {}
	for _, p in pairs(points) do
		if p.part.Parent and not p.part:IsA("Seat") then
			table.insert(any, p)
			if (p.part.Position - npc.hrp.Position).Magnitude >= Config.QuestMinDistance then
				table.insert(far, p)
			end
		end
	end
	local list = #far > 0 and far or any
	return #list > 0 and pick(list) or nil
end

local function startQuest(npc, player: Player)
	local spot = questSpot(npc)
	if not spot then
		return nil
	end
	local def = pick(Config.QuestItems)

	local item = Instance.new("Part")
	item.Name = "QuestItem"
	item.Shape = Enum.PartType.Ball
	item.Size = Vector3.new(1, 1, 1)
	item.Color = def.Color
	item.Material = Enum.Material.SmoothPlastic
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CFrame = CFrame.new(spot.part.Position + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.8, rng:NextNumber(-1.5, 1.5)))
	item:SetAttribute("QuestOwner", player.UserId)
	item:SetAttribute("QuestIcon", def.Icon)
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = def.Color
	sparkles.Parent = item
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Подобрать"
	prompt.ObjectText = def.Name
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = item
	CollectionService:AddTag(item, "QuestItem")
	item.Parent = liveFolder

	local quest = { npc = npc, player = player, def = def, item = item, carrying = false, done = false }
	prompt.Triggered:Connect(function(who)
		if who ~= player or quest.done or quest.carrying then
			return
		end
		quest.carrying = true
		item:Destroy()
		quest.item = nil
		player:SetAttribute("QuestText", string.format("Верни %s %s — %s", def.Icon, def.Name, npc.name))
		toast(player, string.format("%s Нашёл %s!", def.Icon, def.Name))
	end)

	npc.hasQuest = false
	setBaseMood(npc, nil)
	npc.activeQuest = quest
	playerQuests[player] = quest
	player:SetAttribute("QuestText", string.format("Найди %s %s для: %s", def.Icon, def.Name, npc.name))

	task.delay(Config.QuestTime, function()
		if not quest.done then
			clearQuest(quest, "⌛ Время вышло, задание отменено")
			offerQuestLater(npc, Config.QuestCooldown)
		end
	end)
	return quest
end

local function finishQuest(npc, player: Player, quest): number
	clearQuest(quest, nil)
	local reward = rng:NextInteger(Config.QuestReward.Min, Config.QuestReward.Max)
	addCoins(player, reward)
	addFriendship(npc, player, 5)
	setMood(npc, "Happy", 4)
	npc.anim.emote("Cheer")
	sfx(npc, "Cheer")
	offerQuestLater(npc, Config.QuestCooldown)
	if Registry.playerEvent then
		Registry.playerEvent(player, "Quest")
	end
	return reward
end

Players.PlayerRemoving:Connect(function(player)
	local quest = playerQuests[player]
	if quest then
		clearQuest(quest, nil)
		offerQuestLater(quest.npc, 5)
	end
end)

local function shouldStop(npc): boolean
	-- controlled — жителем управляет другой скрипт (например, полиция): свои дела он бросает
	return not npc.alive or npc.abort or npc.lock ~= nil or (npc.controlled ~= nil and not npc.externalWalking)
end

local function stopMoving(npc)
	if npc.alive then
		npc.humanoid:MoveTo(npc.hrp.Position)
	end
end

local function setPose(npc, pose: string)
	npc.model:SetAttribute("Pose", pose)
end

-- Плавный поворот лицом в сторону
local function face(npc, direction: Vector3, time: number?)
	direction = flat(direction)
	if direction.Magnitude < 0.05 or not npc.alive then
		return
	end
	local hrp = npc.hrp
	local from = hrp.CFrame
	local goal = CFrame.lookAt(hrp.Position, hrp.Position + direction.Unit)
	local duration = time or 0.3
	local start = os.clock()
	npc.humanoid.AutoRotate = false
	while npc.alive do
		local t = math.min(1, (os.clock() - start) / duration)
		hrp.CFrame = CFrame.new(hrp.Position) * from.Rotation:Lerp(goal.Rotation, t * t * (3 - 2 * t))
		if t >= 1 then
			break
		end
		task.wait()
	end
	npc.humanoid.AutoRotate = true
end

-- Подняться из позы (сидя на стуле, на полу или лёжа)
---------------------------------------------------------------------
-- Стулья, диваны, скамейки (Seat)
-- Жители садятся сами, без физики Seat: так они всегда смотрят от спинки,
-- сидят ровно на сиденье и не занимают одно место вдвоём.
---------------------------------------------------------------------

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Exclude

local function ignoreList(extra: Instance?)
	local list = { liveFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	if extra then
		table.insert(list, extra)
	end
	return list
end

-- Верх сиденья: если сам Seat невидимый (служебный), берём видимую подушку под ним
local function seatTop(seat: BasePart): Vector3
	local cf, size = seat.CFrame, seat.Size
	local halfY = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
	local top = seat.Position + Vector3.new(0, halfY, 0)
	if seat.Transparency >= 0.9 then
		surfaceParams.FilterDescendantsInstances = ignoreList(seat)
		local hit = workspace:Raycast(top + Vector3.new(0, 0.1, 0), Vector3.new(0, -3, 0), surfaceParams)
		if hit then
			top = Vector3.new(top.X, hit.Position.Y, top.Z)
		end
	end
	return top
end

-- Куда смотреть сидя: от спинки. Спинку ищем лучами на уровне спины,
-- если её нет — по передней грани Seat.
local function seatFacing(seat: BasePart, top: Vector3): Vector3
	local cf = seat.CFrame
	local dirs = { cf.LookVector, -cf.LookVector, cf.RightVector, -cf.RightVector }
	surfaceParams.FilterDescendantsInstances = ignoreList(seat)
	local origin = top + Vector3.new(0, 2.3, 0) -- выше столов, на уровне спинки
	local best, bestDist = nil, math.huge
	for _, d in dirs do
		local flatDir = Vector3.new(d.X, 0, d.Z)
		if flatDir.Magnitude > 0.1 then
			local hit = workspace:Raycast(origin, flatDir.Unit * 2.5, surfaceParams)
			if hit and hit.Distance < bestDist then
				best, bestDist = flatDir.Unit, hit.Distance
			end
		end
	end
	if best then
		return -best
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	return look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
end

local function floorBelow(position: Vector3, ignore: Instance?): number
	surfaceParams.FilterDescendantsInstances = ignoreList(ignore)
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), surfaceParams)
	return hit and hit.Position.Y or position.Y
end

-- Куда подойти, чтобы сесть: на пол перед сиденьем
local function seatApproach(seat: BasePart): Vector3
	local top = seatTop(seat)
	local facing = seatFacing(seat, top)
	local depth = math.max(seat.Size.X, seat.Size.Z) / 2
	local front = top + facing * math.min(depth, 1.2) + facing * 1.4
	return Vector3.new(front.X, floorBelow(front, seat), front.Z)
end

local function sitOnChair(npc, seat: BasePart): boolean
	if seat.Occupant or seat:GetAttribute("NPCSeated") then
		return false
	end
	local top = seatTop(seat)
	local facing = seatFacing(seat, top)
	local hrp = npc.hrp
	local hrpHalf = hrp.Size.Y / 2
	-- Таз ровно на сиденье, спиной к спинке
	local position = top + Vector3.new(0, hrpHalf + 0.3, 0) - facing * 0.15
	local target = CFrame.lookAt(position, position + facing)

	seat:SetAttribute("NPCSeated", true)
	seat.Disabled = true -- игрок не сядет «внутрь» жителя
	npc.humanoid.PlatformStand = true
	hrp.CFrame = target
	local weld = Instance.new("Weld")
	weld.Name = "NPCChairWeld"
	weld.Part0 = seat
	weld.Part1 = hrp
	weld.C0 = seat.CFrame:ToObjectSpace(target)
	weld.Parent = seat
	npc.chair = { seat = seat, weld = weld, facing = facing, top = top }
	setPose(npc, "Chair")
	return true
end

local function leaveChair(npc)
	local chair = npc.chair
	if not chair then
		return
	end
	npc.chair = nil
	chair.weld:Destroy()
	chair.seat:SetAttribute("NPCSeated", nil)
	chair.seat.Disabled = false
	if npc.alive then
		setPose(npc, "Stand")
		-- Встаём перед стулом
		local front = chair.top + chair.facing * 1.6
		local floorY = floorBelow(front, chair.seat)
		local height = npc.humanoid.HipHeight + npc.hrp.Size.Y / 2
		local position = Vector3.new(front.X, floorY + height, front.Z)
		npc.hrp.CFrame = CFrame.lookAt(position, position + chair.facing)
		npc.humanoid.PlatformStand = false
		task.wait(0.35)
	end
end

-- Точка (или место рядом) уже занята другим жителем или игроком?
local function spotTaken(point): boolean
	local part = point.part
	if part:IsA("Seat") and (part.Occupant or part:GetAttribute("NPCSeated")) then
		return true
	end
	for _, other in pairs(points) do
		if other ~= point and other.occupants > 0 and (other.part.Position - part.Position).Magnitude < 1.6 then
			return true
		end
	end
	return false
end

local function standUp(npc)
	if npc.inVehicle then
		return
	end
	if npc.chair then
		leaveChair(npc)
	end
	if npc.humanoid.Sit then
		npc.humanoid.Sit = false
		npc.humanoid.Jump = true
		task.wait(0.4)
	end
	local pose = npc.model:GetAttribute("Pose")
	if pose == "Lie" then
		setPose(npc, "Kneel")
		task.wait(0.7)
	end
	if pose and pose ~= "Stand" then
		setPose(npc, "Stand")
		task.wait(0.45)
	end
	npc.humanoid.WalkSpeed = walkSpeedOf(npc)
end

local function pause(npc, seconds: number): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if shouldStop(npc) then
			return false
		end
		task.wait(0.2)
	end
	return true
end

---------------------------------------------------------------------
-- Общение
---------------------------------------------------------------------

local react -- объявлена ниже

local snapToPoint -- объявлена ниже

local function freeForChat(npc, now: number): boolean
	return npc.alive
		and npc.lock == nil
		and now >= npc.chatCooldown
		and npc.model:GetAttribute("Pose") ~= "Lie"
		and not npc.humanoid.Sit
		and now >= npc.fleeUntil
		and not npc.sleeping
		and not npc.inVehicle
		and not npc.noSocial
		and not npc.controlled
end

local function runConversation(a, b, lines)
	a.lock, b.lock = "chat", "chat"
	setMood(a, "Talk")
	setMood(b, "Talk")
	stopMoving(a)
	stopMoving(b)
	task.spawn(face, a, b.hrp.Position - a.hrp.Position)
	face(b, a.hrp.Position - b.hrp.Position)

	for i, line in lines do
		local speaker = (i % 2 == 1) and a or b
		if not (a.alive and b.alive) or a.lock ~= "chat" or b.lock ~= "chat" then
			break
		end
		say(speaker, line)
		local r = rng:NextNumber()
		if r < 0.25 then
			speaker.anim.emote("Point")
		elseif r < 0.45 then
			speaker.anim.emote("Laugh")
		elseif i == 1 and r < 0.7 then
			speaker.anim.emote("Wave")
		end
		task.wait(Config.BubbleTime * 0.85)
	end

	local now = os.clock()
	for _, npc in { a, b } do
		if npc.lock == "chat" then
			npc.lock = nil
			setMood(npc, nil)
		end
		npc.chatCooldown = now + rng:NextNumber(30, 60)
		npc.abort = true -- после разговора выбираем новое дело
	end
end

-- Реакция на суперспособность игрока
function react(npc, kind: string, target: BasePart)
	if not npc.alive then
		return
	end
	say(npc, pick(Config.Phrases[kind]), 2.5)
	if kind == "Laser" then
		setMood(npc, "Scared", 6)
		npc.fleeUntil = os.clock() + 5
		npc.abort = true
		return
	end
	-- Остановиться и посмотреть
	npc.lock = "react"
	stopMoving(npc)
	if kind == "Invisible" then
		setMood(npc, "Wow", 3)
		for _ = 1, 2 do
			face(npc, (npc.hrp.CFrame * CFrame.Angles(0, rng:NextNumber(-2, 2), 0)).LookVector, 0.5)
			task.wait(0.4)
		end
	else
		setMood(npc, kind == "Cube" and "Laugh" or "Wow", 3)
		if kind == "Cube" then
			sfx(npc, "Laugh")
		end
		face(npc, target.Position - npc.hrp.Position, 0.3)
		npc.anim.emote(kind == "Cube" and "Laugh" or "Point")
		task.wait(2)
	end
	if npc.lock == "react" then
		npc.lock = nil
	end
	npc.abort = true
end

local function tryStartChat(npc, now: number)
	if now < npc.nextSocialCheck or npc.inVehicle or npc.noSocial or npc.controlled then
		return
	end
	npc.nextSocialCheck = now + 0.6

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or npc.sleeping then
			continue
		end
		local dist = (hrp.Position - npc.hrp.Position).Magnitude
		local invisible = character:GetAttribute(ATTR_INVISIBLE) == true

		-- Реакция на суперспособности
		if dist < Config.ReactDistance and now >= (npc.reacted[player] or 0) and npc.lock == nil then
			local kind
			if character:GetAttribute(ATTR_LASER) == true then
				kind = "Laser"
			elseif character:GetAttribute(ATTR_FLYING) == true then
				kind = "Flying"
			elseif character:GetAttribute(ATTR_CUBE) == true and dist < 18 then
				kind = "Cube"
			elseif invisible and dist < 8 then
				kind = "Invisible"
			end
			if kind then
				npc.reacted[player] = now + Config.ReactCooldown
				task.spawn(react, npc, kind, hrp)
				continue
			end
		end

		-- Помахать проходящему игроку (знакомого — назвать по имени)
		if not invisible and dist < Config.GreetDistance and now >= (npc.greeted[player] or 0) then
			npc.greeted[player] = now + 45
			if rng:NextNumber() < Config.GreetPlayerChance then
				local known = memory[npc.name] and memory[npc.name][player.UserId]
				local text = known and string.format(pick(Config.Phrases.KnownGreet) :: string, player.DisplayName)
					or pick(Config.Phrases.Greet)
				task.spawn(function()
					npc.anim.emote("Wave")
					sfx(npc, "Wave")
					say(npc, text, 2.5)
				end)
			end
		end
	end

	-- Заговорить с соседом
	if not freeForChat(npc, now) then
		return
	end
	for _, other in pairs(npcs) do
		if other ~= npc and freeForChat(other, now)
			and (other.hrp.Position - npc.hrp.Position).Magnitude < Config.ChatDistance then
			local key = other.model
			if now >= (npc.chatChecked[key] or 0) then
				npc.chatChecked[key] = now + 20
				other.chatChecked[npc.model] = now + 20
				if rng:NextNumber() < Config.ChatChance then
					task.spawn(runConversation, npc, other, pick(Config.Conversations))
					return
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Ходьба
---------------------------------------------------------------------

local function walkTo(npc, target: Vector3): boolean
	npc.debugGoal = target
	local humanoid, hrp = npc.humanoid, npc.hrp
	local path = PathfindingService:CreatePath({
		AgentRadius = Config.AgentRadius,
		AgentHeight = Config.AgentHeight,
		AgentCanJump = true,
		WaypointSpacing = 4,
		Costs = { Door = 1 },
	})

	for _ = 1, 3 do
		if shouldStop(npc) then
			return false
		end
		local ok = pcall(path.ComputeAsync, path, hrp.Position, target)
		local waypoints
		if ok and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
		elseif (flat(target - hrp.Position)).Magnitude < 14 then
			waypoints = { { Position = hrp.Position }, { Position = target, Action = Enum.PathWaypointAction.Walk } }
		else
			task.wait(1)
			continue
		end

		local blocked = false
		local conn
		if ok then
			conn = path.Blocked:Connect(function()
				blocked = true
			end)
		end

		local reachedAll = true
		for i = 2, #waypoints do
			local wp = waypoints[i]
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			humanoid:MoveTo(wp.Position)

			local start = os.clock()
			local lastPos, lastMove = hrp.Position, os.clock()
			local reached = false
			while true do
				if shouldStop(npc) then
					if conn then
						conn:Disconnect()
					end
					stopMoving(npc)
					return false
				end
				local now = os.clock()
				tryStartChat(npc, now)
				if (flat(wp.Position - hrp.Position)).Magnitude < 2.2 then
					reached = true
					break
				end
				-- Застрял: подпрыгнуть, потом пересчитать путь
				if (hrp.Position - lastPos).Magnitude > 0.5 then
					lastPos, lastMove = hrp.Position, now
				elseif now - lastMove > 1.2 then
					humanoid.Jump = true
					lastMove = now
				end
				if blocked or now - start > 4 then
					break
				end
				humanoid:MoveTo(wp.Position)
				task.wait(0.1)
			end
			if not reached then
				reachedAll = false
				break
			end
		end
		if conn then
			conn:Disconnect()
		end
		if reachedAll then
			return true
		end
		-- Почти дошли (точка на кровати/диване, куда не залезть) — считаем, что пришли
		if (flat(target - hrp.Position)).Magnitude < 4 then
			return true
		end
	end
	return (flat(target - hrp.Position)).Magnitude < 4
end

---------------------------------------------------------------------
-- Выбор дела
---------------------------------------------------------------------

-- Дойти — или доехать (своя машина, такси, автобус), если далеко
local function travelTo(npc, target: Vector3): boolean
	if Registry.tryTrip and not shouldStop(npc) then
		local ok, used = pcall(Registry.tryTrip, npc, target)
		if not ok then
			warn("[NPC] Ошибка поездки:", used)
		end
		if not npc.alive then
			return false
		end
	end
	return walkTo(npc, target)
end

local function pointCategory(npc, point): string
	if point.zone == nil or point.zone == Config.OutdoorZone then
		return "Street"
	elseif npc.homeZone and point.zone == npc.homeZone then
		return "Home"
	end
	return "Other"
end

-- Куда пойти: по расписанию (дом / улица / другие места), выходным и погоде
local function choosePoint(npc)
	local period = currentPeriod()
	local weights = {
		Home = period and period.Home or 0.4,
		Street = period and period.Street or 0.35,
		Other = period and period.Other or 0.25,
	}
	local prefer = {}
	for k, v in pairs(period and period.Prefer or {}) do
		prefer[k] = v
	end
	if isWeekend() and Config.Weekend then
		local w = Config.Weekend
		weights.Home *= w.Home or 1
		weights.Street *= w.Street or 1
		weights.Other *= w.Other or 1
		for k, v in pairs(w.Prefer or {}) do
			prefer[k] = (prefer[k] or 1) * v
		end
	end
	if rainNow() > 0.3 then
		weights.Street *= Config.RainStreetFactor or 0.25
		weights.Home *= 1.5
	end
	if not npc.homeZone then
		weights.Street += weights.Home
		weights.Home = 0
	end

	local buckets = { Home = {}, Street = {}, Other = {} }
	local sums = { Home = 0, Street = 0, Other = 0 }
	for _, point in pairs(points) do
		if point ~= npc.point and point.occupants < point.capacity and point.part.Parent
			and point.activity ~= "Work" and point.activity ~= "Patrol"
			and not spotTaken(point) then
			local cat = pointCategory(npc, point)
			-- Ближние точки чуть вероятнее, любимые занятия периода — тоже
			local dist = (point.part.Position - npc.hrp.Position).Magnitude
			local weight = (1 / (1 + dist / 80)) * (prefer[point.activity] or 1)
			table.insert(buckets[cat], { point = point, weight = weight })
			sums[cat] += weight
		end
	end

	local total = 0
	for cat, w in pairs(weights) do
		if #buckets[cat] > 0 then
			total += w
		end
	end
	local chosen
	if total > 0 then
		local roll = rng:NextNumber() * total
		for cat, w in pairs(weights) do
			if #buckets[cat] > 0 then
				roll -= w
				if roll <= 0 then
					chosen = cat
					break
				end
			end
		end
	end
	if not chosen then
		for cat, list in pairs(buckets) do
			if #list > 0 then
				chosen = cat
				break
			end
		end
	end
	if not chosen then
		return nil
	end

	local list = buckets[chosen]
	local roll = rng:NextNumber() * sums[chosen]
	for _, c in list do
		roll -= c.weight
		if roll <= 0 then
			return c.point
		end
	end
	return list[#list].point
end

-- Встать точно на точку (например, на кровать) и повернуться, как она смотрит
function snapToPoint(npc, part: BasePart)
	local hrp = npc.hrp
	local top = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
	if (flat(top - hrp.Position)).Magnitude > 4.5 then
		face(npc, part.CFrame.LookVector)
		return
	end
	local look = flat(part.CFrame.LookVector)
	local position = top + Vector3.new(0, npc.humanoid.HipHeight + hrp.Size.Y / 2 + 0.05, 0)
	hrp.CFrame = CFrame.lookAt(position, position + (look.Magnitude > 0.1 and look.Unit or hrp.CFrame.LookVector))
end

-- Куда идти к точке: к стулу — на пол перед ним
local function approachPosition(point): Vector3
	if point.part:IsA("Seat") then
		return seatApproach(point.part)
	end
	return point.part.Position
end

local function doActivity(npc, point)
	local part = point.part
	local activity = point.activity
	local range = Config.ActivityTime[activity] or Config.ActivityTime.Idle
	local duration = randomIn(range)

	if part:IsA("Seat") then
		if not sitOnChair(npc, part) then
			return
		end
		pause(npc, duration)
		standUp(npc)
	elseif activity == "Sit" or activity == "Lie" then
		snapToPoint(npc, part)
		npc.humanoid.WalkSpeed = 0
		setPose(npc, activity)
		pause(npc, duration)
		if npc.alive then
			standUp(npc)
		end
	elseif activity == "Look" then
		face(npc, part.CFrame.LookVector, 0.5)
		pause(npc, duration)
	elseif activity == "Dance" then
		face(npc, part.CFrame.LookVector)
		setMood(npc, "Dance", duration)
		local t = npc.anim.emote(rng:NextNumber() < 0.5 and "Dance" or "Dance2", duration)
		if not pause(npc, duration) and t then
			t:Stop(0.3)
		end
	elseif activity == "Talk" then
		-- Ждём собеседника: tryStartChat сам заведёт разговор
		face(npc, part.CFrame.LookVector)
		local deadline = os.clock() + duration
		while os.clock() < deadline and not shouldStop(npc) do
			npc.chatChecked = {} -- в точке для болтовни шанс встречи выше
			tryStartChat(npc, os.clock())
			task.wait(0.5)
		end
	else -- Idle: стоит, иногда осматривается и бормочет
		local elapsed = 0
		while elapsed < duration and not shouldStop(npc) do
			local step = rng:NextNumber(1.5, 3)
			if rng:NextNumber() < 0.5 then
				local angle = rng:NextNumber(-1.2, 1.2)
				face(npc, (npc.hrp.CFrame * CFrame.Angles(0, angle, 0)).LookVector, 0.6)
			end
			if rng:NextNumber() < 0.12 then
				say(npc, pick(Config.Phrases.Idle))
			end
			pause(npc, step)
			elapsed += step
		end
	end
end

local function fleePoint(npc)
	local best, bestDist = nil, 0
	for _, point in pairs(points) do
		local dist = (point.part.Position - npc.hrp.Position).Magnitude
		if dist > bestDist and dist < 250 then
			best, bestDist = point, dist
		end
	end
	return best
end

---------------------------------------------------------------------
-- Ночь: домой спать
---------------------------------------------------------------------

local function sleepPoint(npc)
	for _, wanted in { "Lie", "Sit", "Idle" } do
		for _, p in pairs(points) do
			if p.zone == npc.homeZone and p.activity == wanted and p.occupants < p.capacity
				and not spotTaken(p) then
				return p
			end
		end
	end
	return nil
end

local function goSleep(npc): boolean
	local point = sleepPoint(npc)
	if not point then
		return false
	end
	if not npc.saidNight then
		npc.saidNight = true
		say(npc, pick(Config.Phrases.Night))
	end
	point.occupants += 1
	npc.point = point
	local arrived = travelTo(npc, approachPosition(point))
	if arrived and not shouldStop(npc) then
		npc.zone = npc.homeZone
		npc.sleeping = true
		setMood(npc, "Sleep")
		if point.part:IsA("Seat") then
			if not sitOnChair(npc, point.part) then
				npc.sleeping = false
				setMood(npc, nil)
				point.occupants = math.max(0, point.occupants - 1)
				return false
			end
		else
			snapToPoint(npc, point.part)
			npc.humanoid.WalkSpeed = 0
			setPose(npc, point.activity == "Lie" and "Lie" or "Sit")
		end
		local nextSnore = os.clock() + rng:NextNumber(3, 8)
		while isNight() and not shouldStop(npc) do
			if os.clock() > nextSnore then
				say(npc, pick(Config.Phrases.Sleep), 2.5)
				sfx(npc, "Snore")
				nextSnore = os.clock() + rng:NextNumber(6, 14)
			end
			task.wait(0.5)
		end
		npc.sleeping = false
		setMood(npc, nil)
		if npc.alive then
			standUp(npc)
			if not isNight() then
				npc.saidNight = false
				say(npc, pick(Config.Phrases.Morning))
				npc.anim.emote("Cheer")
			end
		end
	end
	point.occupants = math.max(0, point.occupants - 1)
	return true
end

---------------------------------------------------------------------
-- Работа и патрули
---------------------------------------------------------------------

local function someoneNear(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local c = player.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - position).Magnitude < radius then
			return true
		end
	end
	return false
end

local function doWork(npc)
	local point = npc.job
	if not point.part.Parent then
		npc.job = nil
		return
	end
	if not travelTo(npc, point.part.Position) or shouldStop(npc) then
		npc.onBreak = not shouldStop(npc) -- не дошёл до прилавка — займётся чем-то другим
		return
	end
	face(npc, point.part.CFrame.LookVector)
	if not npc.atWork then
		npc.atWork = true
		say(npc, pick(Config.WorkPhrases.Start))
		setMood(npc, "Work", 4)
	end
	local shiftEnd = os.clock() + randomIn(Config.WorkShift)
	while os.clock() < shiftEnd and not shouldStop(npc) and not (isNight() and npc.homeZone) and isWorkTime() do
		if someoneNear(npc.hrp.Position, 16) and rng:NextNumber() < 0.5 then
			say(npc, pick(Config.Phrases.Work))
			npc.anim.emote(rng:NextNumber() < 0.5 and "Wave" or "Point")
		elseif rng:NextNumber() < 0.35 then
			face(npc, (point.part.CFrame * CFrame.Angles(0, rng:NextNumber(-0.7, 0.7), 0)).LookVector, 0.6)
		else
			face(npc, point.part.CFrame.LookVector, 0.5)
		end
		pause(npc, rng:NextNumber(4, 8))
	end
	if not isWorkTime() and npc.atWork then
		-- Обед или конец смены
		npc.atWork = false
		local h = hourNow()
		local lunch = Config.WorkHours and h >= Config.WorkHours.LunchStart and h < Config.WorkHours.LunchEnd
		say(npc, pick(lunch and Config.WorkPhrases.Lunch or Config.WorkPhrases.End))
		if lunch then
			setMood(npc, "Lunch", 10)
		end
	elseif not shouldStop(npc) then
		npc.onBreak = true -- перерыв: одно обычное дело, потом снова за работу
	end
end

local function doPatrol(npc)
	local route = routes[npc.route]
	if not route or #route.points == 0 then
		npc.route = nil
		return
	end
	for _, p in route.points do
		if shouldStop(npc) or (isNight() and npc.homeZone) then
			return
		end
		if p.part.Parent and walkTo(npc, p.part.Position) then
			face(npc, p.part.CFrame.LookVector, 0.4)
			if rng:NextNumber() < 0.25 then
				say(npc, pick(Config.Phrases.Patrol))
			end
			if not pause(npc, randomIn(Config.PatrolPause)) then
				return
			end
		end
	end
	if rng:NextNumber() < 0.3 then
		npc.onBreak = true
	end
end

local function assignJob(npc): string?
	local best
	for _, p in pairs(points) do
		if p.activity == "Work" and not p.worker and p.part.Parent then
			if not best or (p.zone == npc.homeZone and best.zone ~= npc.homeZone) then
				best = p
			end
		end
	end
	if best then
		best.worker = npc
		npc.job = best
		return best.role or Config.DefaultWorkRole
	end
	for name, route in pairs(routes) do
		if not route.guard and #route.points > 0 then
			route.guard = npc
			npc.route = name
			return route.points[1].role or Config.DefaultPatrolRole
		end
	end
	return nil
end

local function brain(npc)
	-- Просыпаемся: лёжа → на колени → встаём
	setPose(npc, "Lie")
	task.wait(1.4)
	if rng:NextNumber() < 0.35 then
		say(npc, pick(Config.Phrases.Wake))
	end
	setPose(npc, "Kneel")
	task.wait(0.9)
	setPose(npc, "Stand")
	task.wait(0.5)

	while npc.alive do
		while npc.alive and (npc.lock ~= nil or npc.controlled ~= nil) do
			task.wait(0.2)
		end
		if not npc.alive then
			break
		end
		npc.abort = false

		local now = os.clock()
		if now < npc.fleeUntil then
			-- Убегаем подальше
			npc.debugAction = "😱 Убегает"
			standUp(npc)
			setMood(npc, "Scared", 5)
			sfx(npc, "Scream")
			npc.humanoid.WalkSpeed = Config.RunSpeed
			local target = fleePoint(npc)
			if target then
				walkTo(npc, target.part.Position)
			else
				task.wait(1)
			end
			npc.humanoid.WalkSpeed = walkSpeedOf(npc)
			continue
		end

		-- Ночью у кого есть дом — идут спать
		npc.debugAction = "🤔 Выбирает, куда пойти"
		if isNight() and npc.homeZone then
			npc.debugAction = "💤 Сон (ночь)"
		end
		if isNight() and npc.homeZone and goSleep(npc) then
			continue
		end

		-- Работа или обход маршрута (между ними — перерывы)
		if not npc.onBreak then
			if npc.job and isWorkTime() then
				npc.debugAction = "💼 Работа"
				doWork(npc)
				continue
			elseif npc.route then
				npc.debugAction = "🛡 Обход маршрута"
				doPatrol(npc)
				continue
			end
		end
		npc.onBreak = false

		local point = choosePoint(npc)
		if not point then
			task.wait(2)
			continue
		end
		point.occupants += 1
		npc.point = point
		npc.debugAction = string.format("🚶 Идёт: %s (%s)", point.part:IsA("Seat") and "Стул" or tostring(point.activity), tostring(point.zone or "Street"))
		local arrived = travelTo(npc, approachPosition(point))
		if arrived and not shouldStop(npc) then
			if point.zone ~= nil then
				npc.zone = point.zone
			end
			npc.debugAction = string.format("📍 %s (%s)", point.part:IsA("Seat") and "Сидит на стуле" or tostring(point.activity), tostring(point.zone or "Street"))
			npc.debugGoal = nil
			doActivity(npc, point)
		end
		point.occupants = math.max(0, point.occupants - 1)
		task.wait(rng:NextNumber(0.2, 1))
	end
end

---------------------------------------------------------------------
-- Разговор с игроком
---------------------------------------------------------------------

local dialogTitle, refreshTopics -- объявлены ниже

local function endPlayerTalk(npc, sayBye: boolean)
	local player = npc.talkingTo
	if not player then
		return
	end
	npc.talkingTo = nil
	if sayBye and npc.alive then
		say(npc, pick(Config.PlayerBye), 2.5)
		npc.anim.emote("Wave")
	end
	if npc.lock == "player" then
		npc.lock = nil
		setMood(npc, nil)
	end
	npc.abort = true
	npc.chatCooldown = os.clock() + 10
	if npc.prompt then
		npc.prompt.Enabled = true
	end
	if player.Parent then
		dialogRemote:FireClient(player, "Close", npc.model)
	end
end

-- Заголовок окна: имя, работа и уровень дружбы
function dialogTitle(npc, player: Player): string
	local level = friendLevel(friendPoints(npc, player))
	return string.format("%s  ·  %s %s", npc.title, level.Name, level.Icon)
end

-- Темы разговора: задание (если есть) + обычные темы
function refreshTopics(npc, player: Player): { string }
	local list = {}
	local quest = playerQuests[player]
	if quest and quest.npc == npc and quest.carrying then
		table.insert(list, { text = string.format(Config.QuestReturnTopic, quest.def.Name), kind = "QuestReturn" })
	elseif npc.hasQuest and not quest then
		table.insert(list, { text = Config.QuestTopic, kind = "QuestAsk" })
	end
	for _, topic in Config.PlayerTopics do
		table.insert(list, { text = topic.Text, kind = "Topic", topic = topic })
	end
	npc.topics = list
	local texts = {}
	for i, entry in list do
		texts[i] = entry.text
	end
	return texts
end

local function startPlayerTalk(npc, player: Player)
	if not npc.alive or npc.talkingTo or npc.inVehicle or npc.officer then
		return
	end
	if npc.controlled then
		say(npc, "Извините, не сейчас...", 2)
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	if npc.lock == "chat" then
		say(npc, "Секунду, я разговариваю!", 2)
		return
	end

	local wasSleeping = npc.sleeping
	npc.lock = "player"
	npc.talkingTo = player
	npc.lastTalk = os.clock()
	npc.prompt.Enabled = false
	stopMoving(npc)
	setMood(npc, "Talk")

	local points0 = friendPoints(npc, player)
	if os.clock() >= (npc.friendCooldown[player] or 0) then
		npc.friendCooldown[player] = os.clock() + 60
		addFriendship(npc, player, 1)
	end
	local quest = playerQuests[player]
	local greeting
	if wasSleeping then
		greeting = pick(Config.Phrases.Grumpy)
	elseif quest and quest.npc == npc and not quest.carrying then
		greeting = pick(Config.Phrases.QuestWaiting)
	elseif points0 >= FRIEND_POINTS then
		greeting = string.format(pick(Config.Phrases.Friend) :: string, player.DisplayName)
	elseif points0 > 0 then
		greeting = string.format(pick(Config.Phrases.KnownGreet) :: string, player.DisplayName)
	else
		greeting = pick(Config.PlayerGreeting)
	end
	dialogRemote:FireClient(player, "Open", npc.model, dialogTitle(npc, player), greeting, refreshTopics(npc, player))

	task.spawn(function()
		standUp(npc)
		face(npc, hrp.Position - npc.hrp.Position)
		npc.anim.emote("Wave")
		say(npc, greeting)

		-- Следим, не ушёл ли игрок
		while npc.talkingTo == player and npc.alive do
			local c = player.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if not r or (r.Position - npc.hrp.Position).Magnitude > Config.TalkDistance + 8
				or os.clock() - npc.lastTalk > 40 then
				endPlayerTalk(npc, true)
				break
			end
			if (flat(r.Position - npc.hrp.Position)).Magnitude > 1 then
				local look = flat(npc.hrp.CFrame.LookVector)
				local want = flat(r.Position - npc.hrp.Position).Unit
				if look:Dot(want) < 0.9 then
					face(npc, want, 0.25)
				end
			end
			task.wait(0.3)
		end
	end)
end

---------------------------------------------------------------------
-- «Пойдём со мной!»
---------------------------------------------------------------------

local function stopFollow(npc, sayBye: boolean)
	if not npc.following then
		return
	end
	npc.following = nil
	if npc.lock == "follow" then
		npc.lock = nil
	end
	setMood(npc, nil)
	if npc.alive then
		npc.humanoid.WalkSpeed = npc.speed
		npc.prompt.ActionText = Config.TalkPromptText
		npc.prompt.Enabled = true
		if sayBye then
			say(npc, pick(Config.Phrases.FollowEnd))
			npc.anim.emote("Wave")
		end
	end
	npc.abort = true
end

local function startFollow(npc, player: Player)
	npc.talkingTo = nil
	npc.lock = "follow"
	npc.following = player
	setMood(npc, "Follow")
	npc.prompt.ActionText = "Отпустить"
	npc.prompt.Enabled = true
	dialogRemote:FireClient(player, "Close", npc.model)

	task.spawn(function()
		local deadline = os.clock() + Config.FollowTime
		local lastPos, lastMove = npc.hrp.Position, os.clock()
		while npc.alive and npc.following == player and os.clock() < deadline do
			local c = player.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if not r or (r.Position - npc.hrp.Position).Magnitude > 90 or os.clock() < npc.fleeUntil then
				break
			end
			local offset = flat(r.Position - npc.hrp.Position)
			local dist = offset.Magnitude
			if dist > Config.FollowDistance then
				npc.humanoid.WalkSpeed = dist > 16 and Config.RunSpeed or math.max(npc.speed, 13)
				local goal = r.Position - offset.Unit * (Config.FollowDistance - 1)
				-- Застрял за стеной — идём по найденному пути
				if os.clock() - lastMove > 1.5 then
					local path = PathfindingService:CreatePath({ AgentRadius = Config.AgentRadius, AgentHeight = Config.AgentHeight, AgentCanJump = true })
					if pcall(path.ComputeAsync, path, npc.hrp.Position, r.Position) and path.Status == Enum.PathStatus.Success then
						local wps = path:GetWaypoints()
						goal = (wps[math.min(3, #wps)] or wps[#wps]).Position
					end
					npc.humanoid.Jump = true
					lastMove = os.clock()
				end
				npc.humanoid:MoveTo(goal)
			else
				stopMoving(npc)
				lastMove = os.clock()
			end
			if (npc.hrp.Position - lastPos).Magnitude > 0.5 then
				lastPos, lastMove = npc.hrp.Position, os.clock()
			end
			task.wait(0.25)
		end
		stopFollow(npc, npc.alive)
	end)
end

dialogRemote.OnServerEvent:Connect(function(player: Player, action: any, model: any, index: any)
	local npc = typeof(model) == "Instance" and npcs[model] or nil
	if not npc or npc.talkingTo ~= player then
		return
	end
	if action == "Bye" then
		endPlayerTalk(npc, true)
	elseif action == "Ask" and type(index) == "number" then
		local entry = npc.topics and npc.topics[index]
		if not entry or os.clock() - (npc.lastAsk or 0) < 0.6 then
			return
		end
		npc.lastAsk = os.clock()
		npc.lastTalk = os.clock()

		if entry.kind == "QuestAsk" then
			local answer
			local quest = npc.hasQuest and not playerQuests[player] and startQuest(npc, player)
			if quest then
				answer = string.format(pick(Config.Phrases.QuestAsk) :: string, quest.def.Name)
				npc.anim.emote("Point")
			else
				answer = "Уже не нужно, спасибо!"
			end
			say(npc, answer)
			dialogRemote:FireClient(player, "Answer", model, answer, refreshTopics(npc, player))
			return
		elseif entry.kind == "QuestReturn" then
			local quest = playerQuests[player]
			if quest and quest.npc == npc and quest.carrying then
				local reward = finishQuest(npc, player, quest)
				local answer = pick(Config.Phrases.QuestThanks) .. string.format(" (+%d)", reward)
				say(npc, answer)
				dialogRemote:FireClient(player, "Answer", model, answer, refreshTopics(npc, player))
				dialogRemote:FireClient(player, "Title", model, dialogTitle(npc, player))
			end
			return
		end

		local topic = entry.topic
		local answer = pick(topic.Answers)
		say(npc, answer)
		if topic.Emote == "Dance" then
			npc.anim.emote(rng:NextNumber() < 0.5 and "Dance" or "Dance2", 4)
		elseif topic.Emote then
			npc.anim.emote(topic.Emote)
		end
		dialogRemote:FireClient(player, "Answer", model, answer)
		if topic.Follow then
			task.delay(0.8, function()
				if npc.alive and npc.talkingTo == player then
					startFollow(npc, player)
				end
			end)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, npc in pairs(npcs) do
		if npc.talkingTo == player then
			endPlayerTalk(npc, false)
		end
		if npc.following == player then
			stopFollow(npc, false)
		end
		npc.greeted[player] = nil
		npc.reacted[player] = nil
	end
end)

---------------------------------------------------------------------
-- Появление и возрождение
---------------------------------------------------------------------

local spawnNPC

local function onDied(npc)
	if not npc.alive then
		return
	end
	npc.alive = false
	if npc.talkingTo then
		endPlayerTalk(npc, false)
	end
	if npc.point then
		npc.point.occupants = math.max(0, npc.point.occupants - 1)
	end
	if npc.following then
		stopFollow(npc, false)
	end
	if npc.chair then
		npc.chair.weld:Destroy()
		npc.chair.seat:SetAttribute("NPCSeated", nil)
		npc.chair.seat.Disabled = false
		npc.chair = nil
	end
	if npc.job then
		npc.job.worker = nil
	end
	if npc.route and routes[npc.route] and routes[npc.route].guard == npc then
		routes[npc.route].guard = nil
	end
	if npc.activeQuest then
		clearQuest(npc.activeQuest, "😢 " .. npc.name .. " пропал(а) — задание отменено")
	end
	npc.anim.stopAll()
	task.delay(Config.CorpseTime, function()
		npcs[npc.model] = nil
		total -= 1
		npc.model:Destroy()
	end)
	if npc.inVehicle then
		local car = npc.inVehicle
		if npc.vehicleWeld then
			npc.vehicleWeld:Destroy()
		end
		if car.occupants and npc.vehicleSeat then
			car.occupants[npc.vehicleSeat] = nil
		end
		npc.inVehicle = nil
	end
	if Registry.releaseCar then
		Registry.releaseCar(npc)
	end
	task.delay(Config.RespawnTime, function()
		if npc.spawn and npc.spawn.Parent then
			spawnNPC(npc.spawn)
		end
	end)
end

-- Вещи в руках (приварены к кисти и двигаются вместе с анимацией)
local PROP_KINDS = { "Cup", "Phone", "IceCream", "Bag" }

local function addProp(model: Model, kind: string)
	local hand = model:FindFirstChild(kind == "Bag" and "LeftHand" or "RightHand")
	if not hand then
		return
	end
	local function piece(size: Vector3, color: Color3, offset: CFrame, shape: Enum.PartType?, material: Enum.Material?)
		local p = Instance.new("Part")
		p.Name = "Prop"
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CollisionGroup = COLLISION_GROUP
		p.CFrame = hand.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- ось цилиндра — вертикально
	if kind == "Cup" then
		piece(Vector3.new(0.7, 0.45, 0.45), Color3.fromRGB(245, 245, 240), CFrame.new(0, -0.3, -0.2) * upright, Enum.PartType.Cylinder)
		piece(Vector3.new(0.1, 0.48, 0.48), Color3.fromRGB(120, 75, 45), CFrame.new(0, 0.07, -0.2) * upright, Enum.PartType.Cylinder)
	elseif kind == "Phone" then
		piece(Vector3.new(0.35, 0.7, 0.08), Color3.fromRGB(25, 25, 30), CFrame.new(0, -0.3, -0.25))
		piece(Vector3.new(0.3, 0.6, 0.02), Color3.fromRGB(120, 190, 255), CFrame.new(0, -0.3, -0.3), nil, Enum.Material.Neon)
	elseif kind == "IceCream" then
		piece(Vector3.new(0.7, 0.3, 0.3), Color3.fromRGB(210, 160, 90), CFrame.new(0, -0.3, -0.2) * upright, Enum.PartType.Cylinder)
		piece(Vector3.new(0.5, 0.5, 0.5), pick({ Color3.fromRGB(255, 170, 200), Color3.fromRGB(250, 240, 210), Color3.fromRGB(120, 80, 50) }), CFrame.new(0, 0.15, -0.2), Enum.PartType.Ball)
	elseif kind == "Bag" then
		piece(Vector3.new(1.1, 0.9, 0.4), pick(Config.ShirtColors), CFrame.new(0, -0.8, 0), nil, Enum.Material.Fabric)
	end
end

-- Создать жителя. spawnPart — точка появления (обычные жители),
-- opts.custom — без «мозга» (им управляет другой скрипт, например полиция)
local function createNPC(spawnPart: BasePart?, opts)
	opts = opts or {}
	if total >= Config.MaxNPCs + (opts.custom and 14 or 0) then
		return nil
	end
	total += 1

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(makeDescription(opts), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		total -= 1
		warn("[NPC] Не удалось создать модель жителя:", model)
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		total -= 1
		model:Destroy()
		return nil
	end
	local oldAnimate = model:FindFirstChild("Animate")
	if oldAnimate then
		oldAnimate:Destroy() -- анимации ведёт сервер
	end

	local name = pick(Config.FirstNames)
	if opts.prefix then
		name = opts.prefix .. " " .. name
	end
	model.Name = name
	model:SetAttribute("VoicePitch", rng:NextNumber(SoundConfig.VoicePitch.Min, SoundConfig.VoicePitch.Max))
	humanoid.DisplayName = name
	humanoid.NameDisplayDistance = 40
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	local speed = randomIn(Config.WalkSpeed)
	humanoid.WalkSpeed = speed
	-- Сиденья не «затягивают» проходящих мимо жителей: садятся они только сами
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = COLLISION_GROUP
		end
	end

	-- Ставим на точку появления
	if opts.cframe then
		model:PivotTo(opts.cframe)
	else
		local offset = (rng:NextNumber() - 0.5) * 2
		local top = spawnPart.Position + Vector3.new(offset, spawnPart.Size.Y / 2, offset)
		local look = flat(spawnPart.CFrame.LookVector)
		local height = humanoid.HipHeight + hrp.Size.Y / 2 + 0.1
		model:PivotTo(CFrame.lookAt(top + Vector3.new(0, height, 0), top + Vector3.new(0, height, 0) + (look.Magnitude > 0 and look or Vector3.new(0, 0, -1))))
	end
	model:SetAttribute("Pose", opts.custom and "Stand" or "Lie")
	if not opts.custom and rng:NextNumber() < Config.PropChance then
		addProp(model, pick(PROP_KINDS))
	end
	CollectionService:AddTag(model, Config.Tag)
	model.Parent = liveFolder
	pcall(function()
		hrp:SetNetworkOwner(nil)
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = Config.TalkPromptText
	prompt.ObjectText = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.TalkDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = hrp

	local npc = {
		model = model,
		humanoid = humanoid,
		hrp = hrp,
		name = name,
		spawn = spawnPart,
		zone = spawnPart and spawnPart:GetAttribute("Zone") or nil,
		homeZone = spawnPart and (spawnPart:GetAttribute("Zone") ~= Config.OutdoorZone) and spawnPart:GetAttribute("Zone") or nil,
		sleeping = false,
		saidNight = false,
		following = nil,
		reacted = {},
		friendCooldown = {},
		hasUmbrellaItem = rng:NextNumber() < (Config.UmbrellaChance or 0.6),
		title = name,
		job = nil,
		route = nil,
		onBreak = false,
		hasQuest = false,
		activeQuest = nil,
		baseMood = nil,
		speed = speed,
		anim = newAnimator(humanoid),
		prompt = prompt,
		alive = true,
		lock = nil, -- "chat" / "player"
		abort = false,
		point = nil,
		talkingTo = nil,
		lastTalk = 0,
		chatCooldown = os.clock() + rng:NextNumber(5, 15),
		chatChecked = {},
		greeted = {},
		nextSocialCheck = 0,
		fleeUntil = 0,
		lastHurt = 0,
	}
	npcs[model] = npc

	-- Работа, задание, собака
	local role = (not opts.custom) and assignJob(npc) or opts.role
	if opts.custom and role then
		npc.title = name
		humanoid.DisplayName = name .. " · " .. role
	elseif role then
		npc.title = name .. " · " .. role
		humanoid.DisplayName = npc.title
		prompt.ObjectText = npc.title
	elseif not opts.custom then
		if rng:NextNumber() < Config.DogChance then
			model:SetAttribute("DogColor", pick(Config.DogColors))
		end
	end
	if not opts.custom and not npc.route and rng:NextNumber() < Config.QuestChance then
		npc.hasQuest = true
		setBaseMood(npc, "Quest")
	end

	prompt.Triggered:Connect(function(player)
		if npc.following == player then
			stopFollow(npc, true)
		elseif not npc.following then
			startPlayerTalk(npc, player)
		end
	end)

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth and health > 0 then
			local now = os.clock()
			if now - npc.lastHurt > 2 then
				npc.lastHurt = now
				say(npc, pick(Config.Phrases.Hurt), 2)
				sfx(npc, "Hurt")
			end
			if npc.inVehicle or npc.officer or npc.controlled then
				lastHealth = health
				return -- в машине и под присмотром полиции не убегает
			end
			npc.fleeUntil = now + 6
			setMood(npc, "Scared", 6)
			if npc.talkingTo then
				endPlayerTalk(npc, false)
			end
			if npc.lock == "chat" then
				npc.lock = nil
			end
			npc.abort = true
		end
		lastHealth = health
	end)
	humanoid.Died:Connect(function()
		onDied(npc)
	end)

	if not opts.custom then
		task.spawn(brain, npc)
		if Registry.assignCar then
			task.spawn(Registry.assignCar, npc)
		end
	end
	return npc
end

function spawnNPC(spawnPart: BasePart)
	createNPC(spawnPart, nil)
end

---------------------------------------------------------------------
-- Зонты, скорость по расписанию, реакции на погоду
---------------------------------------------------------------------

local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Exclude

local function outdoors(npc): boolean
	local ignore = { liveFolder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	roofParams.FilterDescendantsInstances = ignore
	return workspace:Raycast(npc.hrp.Position + Vector3.new(0, 2, 0), Vector3.new(0, 50, 0), roofParams) == nil
end

local function addUmbrella(npc)
	local torso = npc.model:FindFirstChild("UpperTorso")
	if not torso or npc.umbrella then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Umbrella"
	local color = pick(Config.UmbrellaColors)
	local function piece(size: Vector3, offset: CFrame, c: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Size = size
		p.Color = c
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CollisionGroup = COLLISION_GROUP
		p.CFrame = torso.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = p
		w.Parent = p
		p.Parent = m
		return p
	end
	local upright = CFrame.Angles(0, 0, math.rad(90))
	piece(Vector3.new(3.2, 0.12, 0.12), CFrame.new(0.75, 1.3, -0.9) * upright, Color3.fromRGB(40, 40, 45), Enum.PartType.Cylinder) -- ручка
	piece(Vector3.new(0.25, 4.4, 4.4), CFrame.new(0.4, 3, -0.4) * upright, color, Enum.PartType.Cylinder) -- купол
	piece(Vector3.new(0.6, 0.6, 0.6), CFrame.new(0.4, 3.2, -0.4), color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.PartType.Ball)
	m.Parent = npc.model
	npc.umbrella = m
	npc.model:SetAttribute("Umbrella", true) -- клиент поднимает руку
end

local function removeUmbrella(npc)
	if npc.umbrella then
		npc.umbrella:Destroy()
		npc.umbrella = nil
		npc.model:SetAttribute("Umbrella", nil)
	end
end

task.spawn(function()
	local wasRaining = false
	while true do
		task.wait(1.5)
		local raining = rainNow() > 0.25
		local period = currentPeriod()
		local now = os.clock()
		for _, npc in pairs(npcs) do
			if npc.alive and not npc.officer then
				local out = not npc.inVehicle and outdoors(npc)
				-- Зонт
				local standing = (npc.model:GetAttribute("Pose") or "Stand") == "Stand" and not npc.chair and not npc.inVehicle
				if raining and out and standing and npc.hasUmbrellaItem and not npc.model:GetAttribute("Cuffed") then
					addUmbrella(npc)
				else
					removeUmbrella(npc)
				end
				-- Скорость: утром спешат, в дождь бегут
				npc.speedMul = (period and period.Speed or 1) * ((raining and out) and (Config.RainSpeed or 1) or 1)
				if npc.humanoid.WalkSpeed > 0 and now >= npc.fleeUntil and not npc.following then
					npc.humanoid.WalkSpeed = walkSpeedOf(npc)
				end
				-- Начался дождь — жалуются (особенно без зонта)
				if raining and not wasRaining and out and not npc.controlled and rng:NextNumber() < (npc.hasUmbrellaItem and 0.2 or 0.6) then
					say(npc, pick(Config.Phrases.Rain))
					setMood(npc, "Rain", 4)
				end
			end
		end
		if raining and not wasRaining then
			-- Под дождём бросают дела на улице и идут под крышу
			for _, npc in pairs(npcs) do
				local outsidePoint = npc.point and (npc.point.zone == nil or npc.point.zone == Config.OutdoorZone)
				if npc.alive and not npc.officer and outsidePoint then
					if not npc.hasUmbrellaItem and npc.lock == nil and not npc.controlled then
						npc.abort = true
					end
				end
			end
		end
		wasRaining = raining
	end
end)

-- Новый период дня — жители это замечают
workspace:GetAttributeChangedSignal("Period"):Connect(function()
	local period = currentPeriod()
	local phrases = period and period.Phrases
	if isWeekend() and period and period.Name == "Утро" and Config.Weekend then
		phrases = Config.Weekend.Phrases
	end
	if not phrases then
		return
	end
	for _, npc in pairs(npcs) do
		if npc.alive and not npc.officer and not npc.sleeping and not npc.controlled and not npc.inVehicle and rng:NextNumber() < 0.3 then
			task.delay(rng:NextNumber(0, 6), function()
				say(npc, pick(phrases))
			end)
		end
	end
end)

-- Гром: пугаются те, кто на улице
workspace:GetAttributeChangedSignal("ThunderId"):Connect(function()
	task.wait(0.8)
	for _, npc in pairs(npcs) do
		if npc.alive and not npc.officer and not npc.sleeping and not npc.inVehicle and rng:NextNumber() < 0.3 and outdoors(npc) then
			say(npc, pick(Config.Phrases.Thunder), 1.8)
			setMood(npc, "Scared", 2)
		end
	end
end)

workspace:GetAttributeChangedSignal("Weather"):Connect(function()
	if workspace:GetAttribute("Weather") == "Fog" then
		for _, npc in pairs(npcs) do
			if npc.alive and not npc.officer and not npc.sleeping and rng:NextNumber() < 0.2 then
				say(npc, pick(Config.Phrases.Fog))
			end
		end
	end
end)

---------------------------------------------------------------------
-- Телефон: знакомые жители пишут сообщения
---------------------------------------------------------------------

local function npcByName(name: string)
	for _, npc in pairs(npcs) do
		if npc.name == name and npc.alive then
			return npc
		end
	end
	return nil
end

-- Знакомые игрока (по памяти жителей)
Registry.friendsOf = function(player: Player)
	local list = {}
	for name, known in pairs(memory) do
		local pts = known[player.UserId]
		if pts and pts > 0 then
			local level = friendLevel(pts)
			table.insert(list, { name = name, level = level.Name, icon = level.Icon, points = pts, online = npcByName(name) ~= nil })
		end
	end
	table.sort(list, function(a, b)
		return a.points > b.points
	end)
	return list
end

local chatCooldown = {} -- [player][name] = время
Registry.phoneReply = function(player: Player, name: any, replyIndex: any)
	if type(name) ~= "string" or type(replyIndex) ~= "number" then
		return
	end
	local reply = Config.Phone.Replies[replyIndex]
	local known = memory[name] and memory[name][player.UserId]
	if not reply or not known then
		return
	end
	local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
	task.spawn(function()
		task.wait(rng:NextNumber(0.6, 1.2))
		if phone and player.Parent then
			phone:FireClient(player, "Typing", name)
		end
		task.wait(rng:NextNumber(1.2, 2.6))
		if phone and player.Parent then
			phone:FireClient(player, "Message", { from = name, text = pick(reply.Answers) })
		end
		local now = os.clock()
		chatCooldown[player] = chatCooldown[player] or {}
		if now >= (chatCooldown[player][name] or 0) then
			chatCooldown[player][name] = now + 120
			local npc = npcByName(name)
			if npc then
				addFriendship(npc, player, Config.Phone.FriendPointsPerChat or 1)
			end
		end
	end)
end

-- Иногда кто-то из знакомых пишет сам
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(Config.Phone.MessageEvery.Min, Config.Phone.MessageEvery.Max))
		local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
		for _, player in Players:GetPlayers() do
			local friends = Registry.friendsOf(player)
			if phone and #friends > 0 and rng:NextNumber() < 0.7 then
				local friend = friends[rng:NextInteger(1, math.min(#friends, 4))]
				phone:FireClient(player, "Typing", friend.name)
				task.delay(rng:NextNumber(1.5, 3), function()
					if player.Parent then
						phone:FireClient(player, "Message", { from = friend.name, text = pick(Config.Phone.Messages) })
					end
				end)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	chatCooldown[player] = nil
end)

-- API для транспорта
Registry.walkTo = function(npc, position: Vector3): boolean
	npc.externalWalking = true
	local ok = walkTo(npc, position)
	npc.externalWalking = false
	return ok
end
Registry.emote = function(npc, name: string, duration: number?)
	if npc.alive then
		npc.anim.emote(name, duration)
	end
end
Registry.sfx = sfx
Registry.standUp = standUp

-- Взять жителя под управление (полиция): он бросает свои дела и ждёт команд
Registry.claim = function(npc, reason: string): boolean
	if not npc.alive or npc.inVehicle or npc.controlled or npc.officer or npc.lock ~= nil or npc.following or npc.talkingTo then
		return false
	end
	npc.controlled = reason
	stopMoving(npc)
	task.wait(0.3)
	npc.externalWalking = true
	standUp(npc)
	npc.externalWalking = false
	if npc.prompt then
		npc.prompt.Enabled = false
	end
	return true
end
Registry.release = function(npc)
	npc.controlled = nil
	npc.model:SetAttribute("Cuffed", nil)
	setMood(npc, nil)
	npc.abort = true
	if npc.prompt and npc.alive then
		npc.prompt.Enabled = true
	end
end
-- Найти жителя: из зоны zone или рядом с точкой
Registry.findResident = function(zone: string?, near: Vector3, radius: number)
	local best, bestDist = nil, math.huge
	for _, npc in pairs(npcs) do
		if npc.alive and not npc.officer and not npc.controlled and not npc.inVehicle and npc.lock == nil
			and not npc.following and not npc.talkingTo and not npc.job and not npc.route then
			local dist = (npc.hrp.Position - near).Magnitude
			local inZone = zone ~= nil and (npc.homeZone == zone or npc.zone == zone)
			local score = inZone and dist or dist + 1000
			if (inZone or dist < radius) and score < bestDist then
				best, bestDist = npc, score
			end
		end
	end
	return best
end
-- Для меню отладки: что делает каждый житель
Registry.debugNPCs = function()
	local out = {}
	for model, npc in pairs(npcs) do
		if npc.alive and model.Parent then
			local action = npc.debugAction or "—"
			if npc.controlled then
				action = "👮 Под контролем: " .. tostring(npc.controlled)
			elseif npc.inVehicle then
				action = "🚗 В машине"
			elseif npc.lock == "chat" then
				action = "💬 Болтает"
			elseif npc.lock == "player" or npc.talkingTo then
				action = "🗨 Говорит с игроком"
			elseif npc.following then
				action = "😊 Идёт за игроком"
			elseif npc.sleeping then
				action = "💤 Спит"
			end
			table.insert(out, {
				name = npc.name,
				title = npc.title,
				model = model,
				pos = npc.hrp.Position,
				goal = npc.debugGoal,
				action = action,
				zone = npc.zone,
				home = npc.homeZone,
				mood = model:GetAttribute("Mood"),
				officer = npc.officer and true or false,
				quest = npc.hasQuest,
				health = math.floor(npc.humanoid.Health),
			})
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end
Registry.say = say
Registry.toast = toast
Registry.addCoins = addCoins
Registry.getCoins = getCoins
Registry.addFriendship = addFriendship
Registry.setMood = setMood
Registry.setPose = setPose
Registry.face = face
Registry.spawnCustom = function(cframe: CFrame, options)
	options = options or {}
	options.custom = true
	options.cframe = cframe
	return createNPC(nil, options)
end

-- Расселяем жителей по точкам появления
task.wait(1)
local spawnList = {}
for _, d in spawnsFolder:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(spawnList, d)
	end
end
if #spawnList == 0 then
	warn("[NPC] В папке Spawns нет ни одной точки появления")
end
for _, spawnPart in spawnList do
	local count = spawnPart:GetAttribute("Count") or Config.DefaultSpawnCount
	for _ = 1, count do
		task.spawn(spawnNPC, spawnPart)
		task.wait(0.3)
	end
end

----------------------------------------------------------------------
-- 25. ServerScriptService > Script "NPCDoors"
----------------------------------------------------------------------

-- Script: ServerScriptService > NPCDoors
-- Двери из Workspace > NPCSystem > Doors:
--   * жители открывают их сами, когда подходят, и закрывают за собой;
--   * игроки открывают и закрывают кнопкой E;
--   * дверь всегда открывается «от себя» — в сторону от того, кто открыл;
--   * поиск пути у жителей проходит сквозь закрытые двери (PathfindingModifier).
--
-- Дверь — это Part или Model (несколько деталей, например полотно + ручка).
-- Атрибуты двери (необязательно):
--   Hinge  = "Left" / "Right" — с какой стороны петли (по умолчанию "Left")
--   Locked = true            — заперта: жители не ходят через неё, игроки не открывают

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))

local folder = workspace:WaitForChild(Config.FolderName, 30)
if not folder then
	return
end
local doorsFolder = folder:WaitForChild("Doors", 10)
if not doorsFolder then
	return
end

local doors = {} -- [instance] = состояние двери

local function getParts(door: Instance): { BasePart }
	if door:IsA("BasePart") then
		return { door }
	end
	local parts = {}
	for _, d in door:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function setupDoor(door: Instance)
	if doors[door] or not (door:IsA("BasePart") or door:IsA("Model")) then
		return
	end
	local parts = getParts(door)
	if #parts == 0 then
		return
	end

	local boxCF, boxSize
	if door:IsA("BasePart") then
		boxCF, boxSize = door.CFrame, door.Size
	else
		boxCF, boxSize = (door :: Model):GetBoundingBox()
	end

	-- Ширина двери — по большей горизонтальной оси
	local widthAxis, width
	if boxSize.X >= boxSize.Z then
		widthAxis, width = boxCF.RightVector, boxSize.X
	else
		widthAxis, width = boxCF.LookVector, boxSize.Z
	end
	local side = door:GetAttribute("Hinge") == "Right" and 1 or -1
	local hinge = boxCF.Position + widthAxis * (width / 2) * side
	local freeEnd = boxCF.Position - hinge
	local locked = door:GetAttribute("Locked") == true

	local collide = {}
	for _, part in parts do
		part.Anchored = true
		collide[part] = part.CanCollide
		-- Поиск пути считает дверь проходимой (если она не заперта)
		local modifier = part:FindFirstChildOfClass("PathfindingModifier") or Instance.new("PathfindingModifier")
		modifier.Label = "Door"
		modifier.PassThrough = not locked
		modifier.Parent = part
	end

	-- Кнопка для игроков — на самой большой детали
	local main = parts[1]
	for _, part in parts do
		if part.Size.Magnitude > main.Size.Magnitude then
			main = part
		end
	end
	local prompt
	if not locked then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DoorPrompt"
		prompt.ActionText = "Открыть"
		prompt.ObjectText = "Дверь"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = main
	end

	local state = {
		door = door,
		parts = parts,
		collide = collide,
		closedPivot = door:GetPivot(),
		hingeCF = CFrame.new(hinge),
		center = boxCF.Position,
		swingDir = Vector3.yAxis:Cross(freeEnd), -- куда идёт край двери при повороте на +угол
		angle = 0,
		target = 0,
		openedByPlayer = false,
		lastNpcNear = 0,
		locked = locked,
		prompt = prompt,
	}
	doors[door] = state

	if prompt then
		prompt.Triggered:Connect(function(player)
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if state.target ~= 0 then
				state.target = 0
				state.openedByPlayer = false
			elseif hrp then
				state.openedByPlayer = true
				state.target = math.rad(Config.DoorOpenAngle) * (state.swingDir:Dot(hrp.Position - state.center) > 0 and -1 or 1)
			end
		end)
	end
end

for _, door in doorsFolder:GetChildren() do
	setupDoor(door)
end
doorsFolder.ChildAdded:Connect(function(door)
	task.wait(0.1) -- даём детали модели догрузиться
	setupDoor(door)
end)
doorsFolder.ChildRemoved:Connect(function(door)
	doors[door] = nil
end)

-- Кто из жителей рядом с дверью
local function nearestNpc(state): Vector3?
	for _, npc in CollectionService:GetTagged(Config.Tag) do
		local hrp = npc:FindFirstChild("HumanoidRootPart")
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		if hrp and humanoid and humanoid.Health > 0 then
			if (hrp.Position - state.center).Magnitude < Config.DoorOpenDistance then
				return hrp.Position
			end
		end
	end
	return nil
end

local scanTimer = 0
RunService.Heartbeat:Connect(function(dt)
	scanTimer += dt
	local scan = scanTimer >= 0.15
	if scan then
		scanTimer = 0
	end
	local now = os.clock()

	for door, state in pairs(doors) do
		if not door.Parent then
			doors[door] = nil
			continue
		end

		-- Жители открывают и закрывают сами
		if scan and not state.locked and not state.openedByPlayer then
			local npcPos = nearestNpc(state)
			if npcPos then
				state.lastNpcNear = now
				if state.target == 0 then
					state.target = math.rad(Config.DoorOpenAngle) * (state.swingDir:Dot(npcPos - state.center) > 0 and -1 or 1)
				end
			elseif state.target ~= 0 and now - state.lastNpcNear > Config.DoorCloseDelay then
				state.target = 0
			end
		end

		-- Плавное движение створки
		if state.angle ~= state.target then
			local diff = state.target - state.angle
			local step = diff * math.min(1, dt * Config.DoorSpeed)
			if math.abs(diff) < 0.01 then
				state.angle = state.target
			else
				state.angle += step
			end
			door:PivotTo(state.hingeCF * CFrame.Angles(0, state.angle, 0) * state.hingeCF:Inverse() * state.closedPivot)

			local open = math.abs(state.angle) > math.rad(5)
			for _, part in state.parts do
				part.CanCollide = (not open) and state.collide[part]
			end
			if state.prompt then
				state.prompt.ActionText = state.target ~= 0 and "Закрыть" or "Открыть"
			end
			-- Для звука скрипа (NPCClient)
			local opening = state.target ~= 0
			if door:GetAttribute("DoorOpen") ~= opening then
				door:SetAttribute("DoorOpen", opening)
			end
		end
	end
end)

----------------------------------------------------------------------
-- 26. ServerScriptService > Script "DayNightServer"
----------------------------------------------------------------------

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
	-- TimeScale — ускорение времени из меню отладки (1 = обычно, 0 = пауза)
	local scale = workspace:GetAttribute("TimeScale")
	scale = type(scale) == "number" and scale or 1
	Lighting.ClockTime = (Lighting.ClockTime + pending * hoursPerSecond * scale) % 24
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

----------------------------------------------------------------------
-- 27. ServerScriptService > Script "TrafficServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > TrafficServer
-- Транспорт города:
--   * машины едут по дорогам (Workspace > TrafficSystem > Roads) без физики колёс:
--     плавно, по правой полосе, со скруглёнными поворотами и поворотниками;
--   * держат дистанцию, пропускают друг друга на перекрёстках, стоят на красный свет;
--   * тормозят и сигналят перед людьми;
--   * гражданские: жители ездят на своих машинах (дом ↔ работа, магазин...);
--   * поток: машины со своими водителями всё время катаются по городу;
--   * такси: возит жителей и игроков (за монеты);
--   * автобус: ходит по маршруту, на остановках люди выходят и заходят;
--   * полиция: выезжает на вызовы с мигалками и сиреной, офицеры заходят в здание.
-- Анимации дверей, багажника, фар, мигалок и звуки рисует VehicleClient по атрибутам.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))
local Defaults = require(script.Parent:WaitForChild("VehicleDefaults"))

local map = workspace:WaitForChild(Config.MapFolder, 30)
if not map then
	warn("[Traffic] Нет папки Workspace >", Config.MapFolder, "— машины не появятся. См. VEHICLE_SETUP.md")
	return
end
local roadsFolder = map:WaitForChild("Roads", 10)
if not roadsFolder then
	warn("[Traffic] В папке", Config.MapFolder, "нужна папка Roads с точками дорог")
	return
end
task.wait(1) -- даём карте и жителям загрузиться

local function folder(name: string): Instance?
	return map:FindFirstChild(name)
end

local vehiclesFolder = map:FindFirstChild(Config.VehiclesFolder) or Instance.new("Folder")
vehiclesFolder.Name = Config.VehiclesFolder
vehiclesFolder.Parent = map

local remote = ReplicatedStorage:FindFirstChild("VehicleRemote") or Instance.new("RemoteEvent")
remote.Name = "VehicleRemote"
remote.Parent = ReplicatedStorage

local rng = Random.new()
local function pick(list)
	return list[rng:NextInteger(1, #list)]
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
local function isNight(): boolean
	return workspace:GetAttribute("IsNight") == true
end
local function toast(player: Player, text: string)
	local dialog = ReplicatedStorage:FindFirstChild("NPCDialog")
	if dialog then
		dialog:FireClient(player, "Toast", text)
	end
end

---------------------------------------------------------------------
-- Группы столкновений: машины не цепляют дороги и друг друга, но толкают людей
---------------------------------------------------------------------

local VEHICLES, CHARACTERS = "Vehicles", "Characters"
pcall(function()
	PhysicsService:RegisterCollisionGroup(VEHICLES)
	PhysicsService:RegisterCollisionGroup(CHARACTERS)
	PhysicsService:CollisionGroupSetCollidable(VEHICLES, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(VEHICLES, VEHICLES, false)
	PhysicsService:CollisionGroupSetCollidable(VEHICLES, CHARACTERS, true)
	PhysicsService:CollisionGroupSetCollidable(VEHICLES, "NPCs", true)
end)

local function setCharacterGroup(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = CHARACTERS
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = CHARACTERS
		end
	end)
end
local function onPlayer(player: Player)
	player.CharacterAdded:Connect(setCharacterGroup)
	if player.Character then
		setCharacterGroup(player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end

local function hideMarker(part: BasePart)
	if Config.HideMarkersInGame then
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		for _, d in part:GetDescendants() do
			if d:IsA("Decal") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
	end
end

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundY(position: Vector3): number
	local ignore = { vehiclesFolder }
	local npcFolder = workspace:FindFirstChild(NPCConfig.FolderName)
	if npcFolder and npcFolder:FindFirstChild("Live") then
		table.insert(ignore, npcFolder.Live)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	surfaceParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), surfaceParams)
	return hit and hit.Position.Y or position.Y
end

---------------------------------------------------------------------
-- Дороги: граф точек
---------------------------------------------------------------------

local nodes = {} -- [имя] = { name, pos, links = { [имя] = true }, signal }

for _, p in roadsFolder:GetDescendants() do
	if p:IsA("BasePart") then
		if nodes[p.Name] then
			warn("[Traffic] Две точки дороги с одинаковым именем:", p.Name, "— переименуй одну")
		end
		nodes[p.Name] = { name = p.Name, part = p, pos = p.Position, links = {}, signal = nil }
		hideMarker(p)
	end
end

local function split(text: string): { string }
	local out = {}
	for item in string.gmatch(text, "[^,;]+") do
		item = string.gsub(item, "^%s+", "")
		item = string.gsub(item, "%s+$", "")
		if item ~= "" then
			table.insert(out, item)
		end
	end
	return out
end

for name, node in pairs(nodes) do
	local links = node.part:GetAttribute("Links")
	if type(links) == "string" then
		for _, other in split(links) do
			if nodes[other] then
				node.links[other] = true
				if node.part:GetAttribute("OneWay") ~= true then
					nodes[other].links[name] = true
				end
			else
				warn("[Traffic] Точка", name, "ссылается на несуществующую точку", other)
			end
		end
	end
	local group = node.part:GetAttribute("Signal")
	if type(group) == "string" then
		node.signal = {
			group = group,
			phase = node.part:GetAttribute("Phase") or 1,
			toward = node.part:GetAttribute("Toward"),
		}
	end
end

local function linkCount(node): number
	local n = 0
	for _ in pairs(node.links) do
		n += 1
	end
	return n
end

local nodeCount = 0
for _ in pairs(nodes) do
	nodeCount += 1
end
if nodeCount < 2 then
	warn("[Traffic] В папке Roads меньше двух точек — машинам негде ездить")
	return
end

local function nearestNode(position: Vector3): string
	local best, bestDist = nil, math.huge
	for name, node in pairs(nodes) do
		local d = (flat(node.pos - position)).Magnitude
		if d < bestDist and next(node.links) then
			best, bestDist = name, d
		end
	end
	return best
end

-- Точка, с которой начать путь: ближняя, но лучше впереди по ходу (без разворотов)
local function startNode(position: Vector3, look: Vector3): string
	local best, bestScore = nil, math.huge
	local forward = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	for name, node in pairs(nodes) do
		if next(node.links) then
			local rel = flat(node.pos - position)
			local score = rel.Magnitude
			if rel.Magnitude > 3 and rel.Unit:Dot(forward) < 0 then
				score += 45 -- точка за спиной: только если впереди ничего нет
			end
			if score < bestScore then
				best, bestScore = name, score
			end
		end
	end
	return best
end

-- Где можно развернуться: точка с Turnaround = true или тупик
local function canTurnAround(name: string): boolean
	local node = nodes[name]
	return node.part:GetAttribute("Turnaround") == true or linkCount(node) <= 1
end

-- Откуда машина подъехала к точке (сосед «за спиной»)
local function behindNode(from: string, look: Vector3): string?
	local forward = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	local best, bestDot = nil, -0.3
	for nb in pairs(nodes[from].links) do
		local dir = flat(nodes[nb].pos - nodes[from].pos)
		if dir.Magnitude > 0.1 then
			local d = dir.Unit:Dot(forward)
			if d < bestDot then
				best, bestDot = nb, d
			end
		end
	end
	return best
end

-- Кратчайший путь по точкам (Дейкстра) без разворотов посреди дороги:
-- вернуться в точку, из которой приехал, можно только там, где разрешён разворот
local function route(from: string, to: string, prev: string?, allowUTurns: boolean?): { string }?
	if from == to then
		return { from }
	end
	local function key(n: string, p: string?)
		return n .. "|" .. (p or "")
	end
	local startKey = key(from, prev)
	local dist, state, back, done = { [startKey] = 0 }, { [startKey] = { node = from, prev = prev } }, {}, {}
	while true do
		local bestKey, bestD = nil, math.huge
		for k, d in pairs(dist) do
			if not done[k] and d < bestD then
				bestKey, bestD = k, d
			end
		end
		if not bestKey then
			return nil
		end
		local st = state[bestKey]
		if st.node == to then
			local path = {}
			local k = bestKey
			while k do
				table.insert(path, 1, state[k].node)
				k = back[k]
			end
			return path
		end
		done[bestKey] = true
		for nb in pairs(nodes[st.node].links) do
			if allowUTurns or nb ~= st.prev or canTurnAround(st.node) then
				local nk = key(nb, st.node)
				local nd = bestD + (nodes[nb].pos - nodes[st.node].pos).Magnitude
				if nd < (dist[nk] or math.huge) then
					dist[nk] = nd
					state[nk] = { node = nb, prev = st.node }
					back[nk] = bestKey
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Светофоры
---------------------------------------------------------------------

local signalGroups = {} -- [группа] = { phases, current, mode, timer, lights = { {model, phase} } }

local function signalGroup(name: string)
	local g = signalGroups[name]
	if not g then
		g = { phases = 1, current = 1, mode = "green", timer = Config.GreenTime, lights = {} }
		signalGroups[name] = g
	end
	return g
end

for _, node in pairs(nodes) do
	if node.signal then
		local g = signalGroup(node.signal.group)
		g.phases = math.max(g.phases, node.signal.phase)
	end
end

local function lamp(model: Instance, name: string): BasePart?
	local p = model:FindFirstChild(name, true)
	return p and p:IsA("BasePart") and p or nil
end

local lightsFolder = folder("TrafficLights")
if lightsFolder then
	for _, m in lightsFolder:GetDescendants() do
		local group = m:GetAttribute("Group")
		if type(group) == "string" and (m:IsA("Model") or m:IsA("BasePart")) then
			local g = signalGroup(group)
			local phase = m:GetAttribute("Phase") or 1
			g.phases = math.max(g.phases, phase)
			local entry = { phase = phase, lamps = {} }
			for _, color in { "Red", "Yellow", "Green" } do
				local p = lamp(m, color)
				if p then
					entry.lamps[color] = { part = p, color = p.Color, material = p.Material }
				end
			end
			table.insert(g.lights, entry)
		end
	end
end

local function signalState(group: string, phase: number): string
	local g = signalGroups[group]
	if not g then
		return "green"
	end
	if g.mode == "allred" or g.current ~= phase then
		return "red"
	end
	return g.mode
end

local function paintLights(g)
	for _, entry in g.lights do
		local state = (g.mode == "allred" or g.current ~= entry.phase) and "red" or g.mode
		for color, l in pairs(entry.lamps) do
			local on = (color == "Red" and state == "red") or (color == "Yellow" and state == "yellow") or (color == "Green" and state == "green")
			l.part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
			l.part.Color = on and l.color or l.color:Lerp(Color3.new(0, 0, 0), 0.75)
		end
	end
end

for _, g in pairs(signalGroups) do
	paintLights(g)
end

local function updateSignals(dt: number)
	for _, g in pairs(signalGroups) do
		g.timer -= dt
		if g.timer <= 0 then
			if g.mode == "green" then
				g.mode, g.timer = "yellow", Config.YellowTime
			elseif g.mode == "yellow" then
				g.mode, g.timer = "allred", Config.AllRedTime
			else
				g.current = g.current % g.phases + 1
				g.mode, g.timer = "green", Config.GreenTime
			end
			paintLights(g)
		end
	end
end

---------------------------------------------------------------------
-- Маршрут машины: плавная линия по правой полосе
---------------------------------------------------------------------

-- Боковое смещение на правую полосу для точки с направлениями «до» и «после»
local function laneOffset(dirIn: Vector3?, dirOut: Vector3?, amount: number): Vector3
	local d = dirIn and dirOut and (dirIn + dirOut) or dirIn or dirOut
	if not d or d.Magnitude < 0.05 then
		d = dirIn or dirOut or Vector3.new(0, 0, -1)
	end
	d = d.Unit
	local right = d:Cross(Vector3.yAxis)
	local scale = 1
	if dirIn and dirOut then
		local ri = dirIn:Cross(Vector3.yAxis)
		scale = 1 / math.max(0.5, ri:Dot(right))
	end
	return right * amount * scale
end

--[[
	Строим трек:
	  startPos/startLook — откуда (позиция на земле)
	  pathNodes          — имена точек дороги
	  finish             — { spot = парковка } | { node = true, curb = bool }
	  pullOut            — машина стоит на парковке, сначала выезжает вперёд
]]
local function buildTrack(startPos: Vector3, startLook: Vector3, pathNodes: { string }, finish, pullOut: boolean)
	local ctrl = {} -- { pos, node = имя? }
	table.insert(ctrl, { pos = startPos })
	if pullOut then
		table.insert(ctrl, { pos = startPos + flat(startLook).Unit * 5 })
	end

	-- Точки дороги со смещением на правую полосу
	local raw = {}
	for _, name in pathNodes do
		table.insert(raw, nodes[name].pos)
	end
	local endAnchor = finish.spot and (finish.spot.pos - finish.spot.look * 7) or nil
	local lanes = {}
	for i, p in raw do
		local before = raw[i - 1] or (i == 1 and ctrl[#ctrl].pos) or nil
		local after = raw[i + 1] or endAnchor
		local dirIn = before and flat(p - before).Magnitude > 0.5 and flat(p - before).Unit or nil
		local dirOut = after and flat(after - p).Magnitude > 0.5 and flat(after - p).Unit or nil
		local curb = finish.curb == true and 3.5 or (type(finish.curb) == "number" and finish.curb or 0)
		local extra = i == #raw and curb or 0
		lanes[i] = p + laneOffset(dirIn, dirOut, Config.LaneOffset + extra)
	end

	-- Пропускаем точки «за спиной» у начала (чтобы не разворачиваться на месте)
	local first = 1
	local look = flat(startLook).Magnitude > 0.1 and flat(startLook).Unit or Vector3.new(0, 0, -1)
	while first < #lanes do
		local rel = flat(lanes[first] - ctrl[#ctrl].pos)
		if rel.Magnitude < 6 or rel.Unit:Dot(look) < -0.2 then
			first += 1
		else
			break
		end
	end
	for i = first, #lanes do
		table.insert(ctrl, { pos = lanes[i], node = pathNodes[i] })
	end
	if finish.spot then
		table.insert(ctrl, { pos = endAnchor })
		table.insert(ctrl, { pos = finish.spot.pos })
	end

	-- Убираем совпадающие точки (иначе направление не определить)
	local cleaned = { ctrl[1] }
	for i = 2, #ctrl do
		if (ctrl[i].pos - cleaned[#cleaned].pos).Magnitude > 0.5 then
			table.insert(cleaned, ctrl[i])
		elseif ctrl[i].node then
			cleaned[#cleaned].node = ctrl[i].node
		end
	end
	ctrl = cleaned

	-- Скругляем углы кривыми Безье и раскладываем на частые точки
	local samples = {} -- { p, s, slow }
	local nodeS = {} -- [индекс ctrl] = расстояние
	local s = 0
	local function add(p: Vector3, slow: boolean)
		local last = samples[#samples]
		if last then
			local d = (p - last.p).Magnitude
			if d < 0.05 then
				return
			end
			s += d
		end
		table.insert(samples, { p = p, s = s, slow = slow })
	end
	local function line(a: Vector3, b: Vector3, slow: boolean)
		local n = math.max(1, math.ceil((b - a).Magnitude / 2))
		for k = 1, n do
			add(a:Lerp(b, k / n), slow)
		end
	end

	local events = { stops = {}, reserves = {}, indicators = {}, corners = {} }
	add(ctrl[1].pos, false)
	local cursor = ctrl[1].pos
	for i = 2, #ctrl - 1 do
		local a, c, b = ctrl[i - 1].pos, ctrl[i].pos, ctrl[i + 1].pos
		local din, dout = flat(c - a), flat(b - c)
		local r = math.min(Config.CornerRadius, (c - a).Magnitude / 2, (b - c).Magnitude / 2)
		local cutIn = c + (a - c).Unit * r
		local cutOut = c + (b - c).Unit * r
		local angle = 0
		if din.Magnitude > 0.1 and dout.Magnitude > 0.1 then
			angle = math.deg(math.acos(math.clamp(din.Unit:Dot(dout.Unit), -1, 1)))
		end
		local sharp = angle > 25
		line(cursor, cutIn, false)
		local sStart = s
		for k = 1, 8 do
			local t = k / 8
			local p = cutIn:Lerp(c, t):Lerp(c:Lerp(cutOut, t), t)
			add(p, sharp)
			if k == 4 then
				nodeS[i] = s
			end
		end
		cursor = cutOut
		if sharp then
			table.insert(events.corners, { s0 = sStart - 8, s1 = s })
			if ctrl[i].node and angle > 35 then
				local side = din.Unit:Cross(dout.Unit).Y > 0 and "L" or "R"
				table.insert(events.indicators, { s0 = nodeS[i] - 25, s1 = nodeS[i] + 4, side = side })
			end
		end
	end
	line(cursor, ctrl[#ctrl].pos, false)
	nodeS[1] = 0
	nodeS[#ctrl] = s

	-- События: светофоры и перекрёстки
	for i, c in ctrl do
		if c.node then
			local node = nodes[c.node]
			local nextCtrl = ctrl[i + 1]
			local si = nodeS[i] or 0
			if node.signal and nextCtrl and nextCtrl.node == node.signal.toward then
				table.insert(events.stops, { s = si - 1, group = node.signal.group, phase = node.signal.phase })
			end
			if linkCount(node) >= 3 then
				table.insert(events.reserves, { node = c.node, enter = si - 8, exit = si + 8 })
			end
		end
	end

	return { samples = samples, length = s, events = events, index = 1 }
end

local function trackPos(track, s: number): Vector3
	local samples = track.samples
	local i = track.index
	while i < #samples and samples[i + 1].s < s do
		i += 1
	end
	while i > 1 and samples[i].s > s do
		i -= 1
	end
	track.index = i
	local a, b = samples[i], samples[i + 1]
	if not b then
		return a.p
	end
	local t = (s - a.s) / math.max(0.001, b.s - a.s)
	return a.p:Lerp(b.p, math.clamp(t, 0, 1))
end

---------------------------------------------------------------------
-- Парковки, остановки, вызовы, места
---------------------------------------------------------------------

local spots = { Civilian = {}, Taxi = {}, Bus = {}, Police = {} }
local parkingFolder = folder("Parking")
if parkingFolder then
	for _, p in parkingFolder:GetDescendants() do
		if p:IsA("BasePart") then
			local kind = p:GetAttribute("Type") or "Civilian"
			if spots[kind] then
				local look = flat(p.CFrame.LookVector)
				table.insert(spots[kind], {
					part = p,
					pos = Vector3.new(p.Position.X, p.Position.Y, p.Position.Z),
					look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1),
					zone = p:GetAttribute("Zone"),
					kind = kind,
					car = nil,
				})
				hideMarker(p)
			end
		end
	end
end

local function freeSpot(kind: string, near: Vector3, exclude): any
	local best, bestDist = nil, math.huge
	for _, spot in spots[kind] do
		if spot ~= exclude and not spot.car then
			local d = (spot.pos - near).Magnitude
			if d < bestDist then
				best, bestDist = spot, d
			end
		end
	end
	return best
end

local busStops = {}
local stopsFolder = folder("BusStops")
if stopsFolder then
	for _, p in stopsFolder:GetDescendants() do
		if p:IsA("BasePart") then
			local nodeName = p:GetAttribute("Node")
			table.insert(busStops, {
				part = p,
				pos = p.Position,
				order = p:GetAttribute("Order") or #busStops + 1,
				name = p:GetAttribute("StopName") or p.Name,
				node = (type(nodeName) == "string" and nodes[nodeName]) and nodeName or nearestNode(p.Position),
			})
			hideMarker(p)
		end
	end
	table.sort(busStops, function(a, b)
		return a.order < b.order
	end)
end

local policeCalls = {}
local callsFolder = folder("PoliceCalls")
if callsFolder then
	for _, p in callsFolder:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(policeCalls, { part = p, pos = p.Position, zone = p:GetAttribute("Zone") })
			hideMarker(p)
		end
	end
end

-- Места для такси: Places или центры зон жителей
local places = {}
local placesFolder = folder("Places")
if placesFolder then
	for _, p in placesFolder:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(places, { name = p:GetAttribute("PlaceName") or p.Name, pos = p.Position })
			hideMarker(p)
		end
	end
end
if #places == 0 then
	local npcFolder = workspace:FindFirstChild(NPCConfig.FolderName)
	local pointsFolder = npcFolder and npcFolder:FindFirstChild("Points")
	if pointsFolder then
		local sums = {}
		for _, p in pointsFolder:GetDescendants() do
			if p:IsA("BasePart") then
				local zone = p:GetAttribute("Zone") or NPCConfig.OutdoorZone
				sums[zone] = sums[zone] or { sum = Vector3.zero, n = 0 }
				sums[zone].sum += p.Position
				sums[zone].n += 1
			end
		end
		for zone, data in pairs(sums) do
			table.insert(places, { name = zone == NPCConfig.OutdoorZone and "Улица" or zone, pos = data.sum / data.n })
		end
	end
end

---------------------------------------------------------------------
-- Машины: сборка из шаблона
---------------------------------------------------------------------

local templates = { Civilian = {}, Taxi = {}, Bus = {}, Police = {} }
local templatesFolder = ServerStorage:FindFirstChild(Config.TemplatesFolder)
if templatesFolder then
	for _, m in templatesFolder:GetDescendants() do
		if m:IsA("Model") then
			local kind = m:GetAttribute("VehicleType")
			if templates[kind] then
				table.insert(templates[kind], m)
			end
		end
	end
end
local defaults = nil
for kind, list in pairs(templates) do
	if #list == 0 then
		defaults = defaults or Defaults.Build()
		for _, m in defaults do
			if m:GetAttribute("VehicleType") == kind then
				table.insert(list, m)
			end
		end
	end
end

local cars = {} -- список машин
local nextId = 0

-- Группа детали: дверь/багажник (по имени или атрибуту PartOf), колесо, или кузов
local function groupOf(p: BasePart, model: Model): (string?, string?)
	local partOf = p:GetAttribute("PartOf")
	if type(partOf) == "string" then
		return partOf, string.find(partOf, "^Trunk") and "Trunk" or "Door"
	end
	local inst: Instance? = p
	while inst and inst ~= model do
		if string.find(inst.Name, "^Door") then
			return inst.Name, "Door"
		elseif string.find(inst.Name, "^Trunk") then
			return inst.Name, "Trunk"
		elseif string.find(inst.Name, "^Wheel") and inst:IsA("BasePart") then
			return nil, "Wheel"
		end
		inst = inst.Parent
	end
	return nil, nil
end

local function bodyBounds(body: BasePart, parts: { BasePart })
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, p in parts do
		local half = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = body.CFrame:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)))
					minV = minV:Min(corner)
					maxV = maxV:Max(corner)
				end
			end
		end
	end
	return minV, maxV
end

local function setupVehicle(model: Model, kind: string)
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		warn("[Traffic] У шаблона", model.Name, "нет детали Body (PrimaryPart)")
		return nil
	end
	model.PrimaryPart = body

	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local minV, maxV = bodyBounds(body, parts)

	-- Покраска гражданских
	if kind == "Civilian" then
		local color = pick(Config.PaintColors)
		for _, p in parts do
			if p:GetAttribute("Paint") then
				p.Color = color
			end
		end
	end

	local groups = {} -- [имя] = { kind, parts }
	local wheels, seats = {}, {}
	for _, p in parts do
		p.Anchored = false
		p.CollisionGroup = VEHICLES
		if p ~= body then
			p.Massless = true
		end
		if p:IsA("Seat") then
			p.Disabled = true
			p.CanCollide = false
			table.insert(seats, p)
		end
		local groupName, groupKind = groupOf(p, model)
		if groupKind == "Wheel" then
			p.CanCollide = false
			table.insert(wheels, p)
		elseif groupName then
			p.CanCollide = false
			groups[groupName] = groups[groupName] or { kind = groupKind, parts = {} }
			table.insert(groups[groupName].parts, p)
		elseif p ~= body and not p:IsA("Seat") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
		end
	end
	for _, s in seats do
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = s
		w.Parent = s
	end

	-- Двери и багажник: шарнир Motor6D, анимацию крутит клиент
	local doors = {}
	for name, g in pairs(groups) do
		local main = g.parts[1]
		for _, p in g.parts do
			if p.Size.Magnitude > main.Size.Magnitude then
				main = p
			end
		end
		for _, p in g.parts do
			if p ~= main then
				local w = Instance.new("WeldConstraint")
				w.Part0 = main
				w.Part1 = p
				w.Parent = p
			end
		end
		local gMin, gMax = bodyBounds(body, g.parts)
		local center = (gMin + gMax) / 2
		local hinge, axis, angle, slide
		local hingeType = main:GetAttribute("Hinge") or (g.parts[1].Parent and g.parts[1].Parent:GetAttribute("Hinge")) or "Front"
		if g.kind == "Trunk" then
			hinge = Vector3.new(center.X, gMax.Y, gMin.Z) -- передний верхний край
			axis = Vector3.xAxis
			angle = -math.rad(Config.TrunkOpenAngle)
		elseif hingeType == "Slide" then
			local side = center.X >= 0 and 1 or -1
			slide = Vector3.new(side * 0.35, 0, Config.SlideDistance)
		else
			local side = center.X >= 0 and 1 or -1
			local back = hingeType == "Back"
			hinge = Vector3.new(side > 0 and gMax.X or gMin.X, center.Y, back and gMax.Z or gMin.Z)
			axis = Vector3.yAxis
			angle = math.rad(Config.DoorOpenAngle) * side * (back and -1 or 1)
		end

		local motor = Instance.new("Motor6D")
		motor.Name = "Joint_" .. name
		motor.Part0 = body
		motor.Part1 = main
		motor.C0 = body.CFrame:ToObjectSpace(main.CFrame)
		motor:SetAttribute("Group", name)
		motor:SetAttribute("Kind", g.kind)
		local mainCF = main.CFrame
		if hinge then
			local hingeWorld = body.CFrame:PointToWorldSpace(hinge)
			motor:SetAttribute("HingeLocal", mainCF:PointToObjectSpace(hingeWorld))
			motor:SetAttribute("AxisLocal", mainCF:VectorToObjectSpace(body.CFrame:VectorToWorldSpace(axis)))
			motor:SetAttribute("OpenAngle", angle)
		else
			motor:SetAttribute("SlideLocal", mainCF:VectorToObjectSpace(body.CFrame:VectorToWorldSpace(slide)))
		end
		motor.Parent = body
		doors[name] = { motor = motor, center = center }
		model:SetAttribute(name, false)
	end

	-- Колёса: вращает клиент
	for i, w in wheels do
		local motor = Instance.new("Motor6D")
		motor.Name = "Wheel_" .. i
		motor.Part0 = body
		motor.Part1 = w
		motor.C0 = body.CFrame:ToObjectSpace(w.CFrame)
		local axle = w.CFrame:VectorToObjectSpace(body.CFrame.RightVector)
		local a = Vector3.new(math.abs(axle.X), math.abs(axle.Y), math.abs(axle.Z))
		local radius = (w.Size.X * (1 - a.X) + w.Size.Y * (1 - a.Y) + w.Size.Z * (1 - a.Z)) / 4
		motor:SetAttribute("Kind", "Wheel")
		motor:SetAttribute("AxleLocal", axle)
		motor:SetAttribute("Radius", math.max(0.2, radius))
		motor.Parent = body
	end

	if #seats == 0 then
		warn("[Traffic] В шаблоне", model.Name, "нет мест Seat_Driver / Seat_1... — машина не появится")
		return nil
	end

	-- Места
	table.sort(seats, function(a, b)
		return a.Name < b.Name
	end)
	local driverSeat = model:FindFirstChild("Seat_Driver", true)
	if not driverSeat then
		driverSeat = seats[1]
	end
	local passengerSeats = {}
	for _, s in seats do
		if s ~= driverSeat then
			table.insert(passengerSeats, s)
		end
	end

	-- Удержание: «жёсткие» выравниватели ведут машину по треку
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = body
	local alignPos = Instance.new("AlignPosition")
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.Attachment0 = attachment
	alignPos.RigidityEnabled = true
	alignPos.Parent = body
	local alignRot = Instance.new("AlignOrientation")
	alignRot.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignRot.Attachment0 = attachment
	alignRot.RigidityEnabled = true
	alignRot.Parent = body

	nextId += 1
	model:SetAttribute("VehicleType", kind)
	model:SetAttribute("VehicleId", nextId)
	return {
		id = nextId,
		model = model,
		body = body,
		kind = kind,
		doors = doors,
		driverSeat = driverSeat,
		seats = passengerSeats,
		occupants = {},
		ride = -minV.Y, -- высота центра кузова над землёй
		length = maxV.Z - minV.Z,
		width = maxV.X - minV.X,
		alignPos = alignPos,
		alignRot = alignRot,
		pos = body.Position,
		look = body.CFrame.LookVector,
		v = 0,
		s = 0,
		track = nil,
		state = "parked",
		onRoad = false,
		held = {},
		honkAt = 0,
		stuck = 0,
	}
end

local function placeCar(car, position: Vector3, look: Vector3)
	look = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	local cf = CFrame.lookAt(position, position + look) * CFrame.new(0, car.ride, 0)
	car.model:PivotTo(cf)
	car.alignPos.Position = cf.Position
	car.alignRot.CFrame = cf.Rotation
	car.pos = position
	car.look = look
end

local function spawnCar(kind: string, spot)
	if #cars >= Config.MaxVehicles or #templates[kind] == 0 then
		return nil
	end
	local model = pick(templates[kind]):Clone()
	local car = setupVehicle(model, kind)
	if not car then
		model:Destroy()
		return nil
	end
	model.Parent = vehiclesFolder
	car.homeSpot = spot
	car.spot = spot
	if spot then
		spot.car = car
		local ground = groundY(spot.pos)
		placeCar(car, Vector3.new(spot.pos.X, ground, spot.pos.Z), spot.look)
	end
	pcall(function()
		car.body:SetNetworkOwner(nil)
	end)
	table.insert(cars, car)
	return car
end

---------------------------------------------------------------------
-- Езда
---------------------------------------------------------------------

local reservations = {} -- [точка-перекрёсток] = машина

local function releaseAll(car)
	for node in pairs(car.held) do
		if reservations[node] == car then
			reservations[node] = nil
		end
	end
	table.clear(car.held)
end

local function honk(car)
	local now = os.clock()
	if now - car.honkAt > Config.HonkCooldown then
		car.honkAt = now
		car.model:SetAttribute("HornId", (car.model:GetAttribute("HornId") or 0) + 1)
	end
end

local function humansNear(position: Vector3, radius: number)
	local list = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - position).Magnitude < radius then
			table.insert(list, r)
		end
	end
	for model, npc in pairs(Registry.npcs) do
		if npc.alive and not npc.inVehicle and npc.hrp and (npc.hrp.Position - position).Magnitude < radius then
			table.insert(list, npc.hrp)
		end
	end
	return list
end

local function isPassenger(car, hrp: BasePart): boolean
	for _, who in pairs(car.occupants) do
		if (typeof(who) == "Instance" and who.Character and who.Character:FindFirstChild("HumanoidRootPart") == hrp)
			or (type(who) == "table" and who.hrp == hrp) then
			return true
		end
	end
	return false
end

local function finishDrive(car, ok: boolean)
	car.track = nil
	car.v = 0
	releaseAll(car)
	car.model:SetAttribute("Indicator", "")
	car.model:SetAttribute("Brake", true)
	car.driveOk = ok
	car.driveDone = true
end

-- Ехать: spec = { spot = парковка } или { node = имя, curb = true }
local function drive(car, spec): boolean
	local fromNode = startNode(car.pos, car.look)
	local toNode = spec.spot and nearestNode(spec.spot.pos) or spec.node
	local path = fromNode and toNode and route(fromNode, toNode, behindNode(fromNode, car.look))
	if not path and fromNode and toNode and Config.AllowUTurnFallback then
		path = route(fromNode, toNode, nil, true)
		if path then
			warn("[Traffic] Без разворота не доехать от", fromNode, "до", toNode, "— добавь кольцо или точку с Turnaround = true")
		end
	end
	if not path then
		warn("[Traffic] Нет пути от", fromNode, "до", toNode, "— проверь атрибуты Links у точек дороги")
		return false
	end
	local pullOut = car.spot ~= nil
	if car.spot and car.spot.car == car then
		car.spot.car = nil
	end
	car.spot = nil
	if spec.spot then
		spec.spot.car = car -- бронь места
	end
	car.debugTo = toNode
	car.debugPath = path
	car.track = buildTrack(car.pos, car.look, path, spec, pullOut)
	car.s = 0
	car.stuck = 0
	car.onRoad = true
	car.driveDone = false
	car.maxSpeed = (car.kind == "Police" and car.model:GetAttribute("Siren")) and Config.PoliceSpeed or Config.CitySpeed
	-- В дождь и туман — медленнее
	local weather = ReplicatedStorage:FindFirstChild("WeatherConfig")
	if weather and ((workspace:GetAttribute("Rain") or 0) > 0.3 or (workspace:GetAttribute("Fog") or 0) > 0.5) then
		car.maxSpeed *= require(weather).CarSpeedInRain or 0.8
	end
	car.model:SetAttribute("Brake", false)
	while not car.driveDone do
		task.wait(0.1)
	end
	if spec.spot and car.driveOk then
		car.spot = spec.spot
		car.onRoad = false
	elseif spec.spot then
		spec.spot.car = nil
	end
	return car.driveOk
end

-- Застряла надолго — исчезает и появляется на своей парковке
local function rescue(car)
	local home = car.homeSpot
	if home and home.car and home.car ~= car then
		home = freeSpot(car.kind, car.pos, nil)
	end
	if home then
		local ground = groundY(home.pos)
		placeCar(car, Vector3.new(home.pos.X, ground, home.pos.Z), home.look)
		home.car = car
		car.spot = home
		car.onRoad = false
	end
	finishDrive(car, false)
end

local function stepCar(car, dt: number)
	local track = car.track
	if not track then
		car.v = 0
		return
	end
	local model = car.model
	local target = car.maxSpeed or Config.CitySpeed
	local remaining = track.length - car.s
	local function limitTo(distance: number)
		target = math.min(target, math.sqrt(2 * Config.Braking * math.max(0, distance)))
	end
	limitTo(remaining - 0.3)

	-- Повороты: заранее сбавляем скорость
	for _, c in track.events.corners do
		if car.s < c.s1 and c.s0 - car.s < 20 then
			local before = math.max(0, c.s0 - car.s)
			target = math.min(target, math.sqrt(Config.TurnSpeed ^ 2 + 2 * Config.Braking * before))
		end
	end

	-- Светофоры
	for _, stop in track.events.stops do
		local d = stop.s - car.s
		if d > -0.5 and d < 70 then
			local state = signalState(stop.group, stop.phase)
			local canStop = d > (car.v * car.v) / (2 * Config.Braking) + 0.5
			if state == "red" or (state == "yellow" and canStop) then
				limitTo(d - 0.5)
			end
			break
		end
	end

	-- Перекрёстки: один проезжает, остальные ждут
	for _, r in track.events.reserves do
		if car.s > r.exit then
			if car.held[r.node] then
				car.held[r.node] = nil
				if reservations[r.node] == car then
					reservations[r.node] = nil
				end
			end
		elseif car.s < r.enter + 1 and r.enter - car.s < 14 then
			local owner = reservations[r.node]
			if owner == nil or owner == car or not owner.track then
				reservations[r.node] = car
				car.held[r.node] = true
			else
				limitTo(r.enter - car.s - 0.5)
				break
			end
		end
	end

	-- Машина впереди
	local look = car.look
	local right = look:Cross(Vector3.yAxis)
	car.blockedBy = nil
	for _, other in cars do
		if other ~= car and (other.track or other.onRoad) then
			local rel = flat(other.pos - car.pos)
			local forward = rel:Dot(look)
			local lateral = math.abs(rel:Dot(right))
			if forward > 0 and forward < 45 and lateral < (car.width + other.width) / 2 - 0.3 then
				-- Взаимная блокировка: пропускает тот, у кого номер больше
				if not (other.blockedBy == car and car.id < other.id) then
					local gap = forward - (car.length + other.length) / 2 - Config.SafeGap
					limitTo(gap)
					car.blockedBy = other
				end
			end
		end
	end

	-- Люди на дороге: тормозим и сигналим
	local reach = Config.PedestrianStop + car.length / 2
	for _, hrp in humansNear(car.pos, reach + 4) do
		if not isPassenger(car, hrp) then
			local rel = flat(hrp.Position - car.pos)
			local forward = rel:Dot(look)
			local lateral = math.abs(rel:Dot(right))
			if forward > 0 and forward < reach and lateral < car.width / 2 + 0.6 then
				limitTo(forward - car.length / 2 - 2.5)
				if car.v < 3 then
					honk(car)
				end
			end
		end
	end

	-- Разгон и торможение
	local dv = target - car.v
	if dv > 0 then
		car.v = math.min(target, car.v + Config.Acceleration * dt)
	else
		car.v = math.max(target, car.v - Config.Braking * dt)
	end
	car.s = math.min(track.length, car.s + car.v * dt)

	local pos = trackPos(track, car.s)
	local ahead = trackPos(track, math.min(track.length, car.s + 2.5))
	local dir = ahead - pos
	if dir.Magnitude > 0.05 then
		car.look = flat(dir).Magnitude > 0.05 and flat(dir).Unit or car.look
	end
	car.pos = pos
	local lookFull = dir.Magnitude > 0.05 and dir.Unit or car.look
	local cf = CFrame.lookAt(pos, pos + lookFull) * CFrame.new(0, car.ride, 0)
	car.alignPos.Position = cf.Position
	car.alignRot.CFrame = cf.Rotation

	-- Стоп-сигналы и поворотники
	local braking = dv < -0.5 or car.v < 0.5
	if model:GetAttribute("Brake") ~= braking then
		model:SetAttribute("Brake", braking)
	end
	local indicator = ""
	for _, ind in track.events.indicators do
		if car.s >= ind.s0 and car.s <= ind.s1 then
			indicator = ind.side
			break
		end
	end
	if model:GetAttribute("Indicator") ~= indicator then
		model:SetAttribute("Indicator", indicator)
	end

	-- Приехали / застряли
	if remaining < 0.3 and car.v < 0.5 then
		finishDrive(car, true)
	elseif car.v < 0.3 then
		car.stuck += dt
		if car.stuck > Config.StuckRespawnTime then
			warn("[Traffic] Машина", model.Name, "застряла — возвращаю на парковку")
			rescue(car)
		end
	else
		car.stuck = 0
	end
end

local lightTimer = 0
RunService.Heartbeat:Connect(function(dt)
	updateSignals(dt)
	for _, car in cars do
		if car.model.Parent then
			stepCar(car, dt)
		end
	end
	lightTimer += dt
	if lightTimer > 0.25 then
		lightTimer = 0
		local night = isNight()
		for _, car in cars do
			local model = car.model
			local siren = model:GetAttribute("Siren") == true
			local engine = car.occupants[car.driverSeat] ~= nil
			local badWeather = (workspace:GetAttribute("Rain") or 0) > 0.3 or (workspace:GetAttribute("Fog") or 0) > 0.4
			local lights = engine and (night or siren or badWeather) or false
			if model:GetAttribute("Headlights") ~= lights then
				model:SetAttribute("Headlights", lights)
			end
			if model:GetAttribute("Engine") ~= engine then
				model:SetAttribute("Engine", engine)
			end
			local speed = math.floor(car.v * 10) / 10
			if model:GetAttribute("Speed") ~= speed then
				model:SetAttribute("Speed", speed)
			end
		end
	end
end)

---------------------------------------------------------------------
-- Посадка и высадка
---------------------------------------------------------------------

local function doorFor(car, seat: BasePart): string?
	local seatLocal = car.body.CFrame:PointToObjectSpace(seat.Position)
	local best, bestDist = nil, math.huge
	for name, d in pairs(car.doors) do
		local dist = (Vector3.new(d.center.X, 0, d.center.Z) - Vector3.new(seatLocal.X, 0, seatLocal.Z)).Magnitude
		if dist < bestDist then
			best, bestDist = name, dist
		end
	end
	return best
end

local function setDoor(car, name: string?, open: boolean)
	if name then
		car.model:SetAttribute(name, open)
	end
end

-- Где встать у двери (снаружи, на земле)
local function doorSide(car, seat: BasePart, forceSide: number?): Vector3
	local seatLocal = car.body.CFrame:PointToObjectSpace(seat.Position)
	local side = forceSide or (seatLocal.X >= 0 and 1 or -1)
	local out = car.body.CFrame:PointToWorldSpace(Vector3.new(side * (car.width / 2 + 1.8), 0, seatLocal.Z))
	return Vector3.new(out.X, groundY(out), out.Z)
end

local function freeSeat(car): BasePart?
	for _, s in car.seats do
		if not car.occupants[s] and not s.Occupant then
			return s
		end
	end
	return nil
end

local function seatNPC(npc, car, seat: BasePart)
	local door = doorFor(car, seat)
	setDoor(car, door, true)
	task.wait(0.55)
	if not npc.alive then
		setDoor(car, door, false)
		return false
	end
	local hrp = npc.hrp
	local top = seat.Position + seat.CFrame.UpVector * (seat.Size.Y / 2)
	local pos = top + Vector3.new(0, hrp.Size.Y / 2 + 0.3, 0)
	local target = CFrame.lookAt(pos, pos + car.body.CFrame.LookVector)
	npc.humanoid.PlatformStand = true
	hrp.CFrame = target
	local weld = Instance.new("Weld")
	weld.Name = "VehicleSeatWeld"
	weld.Part0 = seat
	weld.Part1 = hrp
	weld.C0 = seat.CFrame:ToObjectSpace(target)
	weld.Parent = seat
	npc.vehicleWeld = weld
	npc.inVehicle = car
	npc.vehicleSeat = seat
	car.occupants[seat] = npc
	if npc.prompt then
		npc.prompt.Enabled = false
	end
	Registry.setPose(npc, "Chair")
	task.wait(0.4)
	setDoor(car, door, false)
	return true
end

local function unseatNPC(npc, forceSide: number?)
	local car, seat = npc.inVehicle, npc.vehicleSeat
	if not car or not seat then
		return
	end
	local door = doorFor(car, seat)
	setDoor(car, door, true)
	task.wait(0.45)
	if npc.vehicleWeld then
		npc.vehicleWeld:Destroy()
		npc.vehicleWeld = nil
	end
	car.occupants[seat] = nil
	npc.inVehicle = nil
	npc.vehicleSeat = nil
	if npc.alive then
		local out = doorSide(car, seat, forceSide)
		local height = npc.humanoid.HipHeight + npc.hrp.Size.Y / 2 + 0.1
		local pos = out + Vector3.new(0, height, 0)
		npc.hrp.CFrame = CFrame.lookAt(pos, pos + car.look)
		npc.humanoid.PlatformStand = false
		Registry.setPose(npc, "Stand")
		if npc.prompt and not npc.officer then
			npc.prompt.Enabled = true
		end
	end
	task.wait(0.35)
	setDoor(car, door, false)
end

local function seatPlayer(player: Player, car, seat)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local door = doorFor(car, seat)
	setDoor(car, door, true)
	task.wait(0.4)
	seat.Disabled = false
	seat:Sit(humanoid)
	car.occupants[seat] = player
	local conn
	conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			conn:Disconnect()
			if car.occupants[seat] == player then
				car.occupants[seat] = nil
			end
			seat.Disabled = true
		end
	end)
	task.delay(0.4, function()
		setDoor(car, door, false)
	end)
	return true
end

local function unseatPlayer(player: Player, car, forceSide: number?)
	for seat, who in pairs(car.occupants) do
		if who == player then
			local door = doorFor(car, seat)
			setDoor(car, door, true)
			task.wait(0.35)
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
			car.occupants[seat] = nil
			seat.Disabled = true
			local character = player.Character
			if character then
				local out = doorSide(car, seat, forceSide)
				character:PivotTo(CFrame.lookAt(out + Vector3.new(0, 3.2, 0), out + Vector3.new(0, 3.2, 0) + car.look))
			end
			task.delay(0.4, function()
				setDoor(car, door, false)
			end)
			return
		end
	end
end

---------------------------------------------------------------------
-- Гражданские машины и поездки жителей
---------------------------------------------------------------------

local function carTrip(npc, car, target: Vector3): boolean
	car.state = "busy"
	local seat = car.driverSeat
	if not Registry.walkTo(npc, doorSide(car, seat)) then
		car.state = "parked"
		return false
	end
	-- Иногда сначала кладёт что-то в багажник
	if car.doors.Trunk and rng:NextNumber() < Config.TrunkChance then
		local behind = car.pos - car.look * (car.length / 2 + 1.5)
		if Registry.walkTo(npc, Vector3.new(behind.X, groundY(behind), behind.Z)) then
			Registry.face(npc, car.look)
			setDoor(car, "Trunk", true)
			task.wait(1.4)
			setDoor(car, "Trunk", false)
			task.wait(0.4)
			Registry.walkTo(npc, doorSide(car, seat))
		end
	end
	if not npc.alive or not seatNPC(npc, car, seat) then
		car.state = "parked"
		return false
	end
	local dest = freeSpot("Civilian", target, car.spot)
	local ok = false
	if dest then
		ok = drive(car, { spot = dest })
	end
	unseatNPC(npc)
	car.state = "parked"
	return ok
end

local function freeTaxi()
	for _, car in cars do
		if car.kind == "Taxi" and car.state == "parked" then
			return car
		end
	end
	return nil
end

local function taxiReturn(car)
	local stand = freeSpot("Taxi", car.pos, nil) or car.homeSpot
	if stand then
		drive(car, { spot = stand })
	end
	car.state = "parked"
	car.model:SetAttribute("TaxiBusy", false)
end

local function taxiTrip(npc, target: Vector3): boolean
	local taxi = freeTaxi()
	if not taxi then
		return false
	end
	taxi.state = "busy"
	taxi.model:SetAttribute("TaxiBusy", true)
	local pickupNode = nearestNode(npc.hrp.Position)
	Registry.say(npc, "Такси!")
	-- Такси едет, житель идёт к дороге
	local arrived = false
	task.spawn(function()
		arrived = drive(taxi, { node = pickupNode, curb = 5 })
	end)
	local away = flat(npc.hrp.Position - nodes[pickupNode].pos)
	Registry.walkTo(npc, nodes[pickupNode].pos + (away.Magnitude > 0.5 and away.Unit or Vector3.xAxis) * 6)
	local deadline = os.clock() + 70
	while not taxi.driveDone and os.clock() < deadline and npc.alive do
		task.wait(0.3)
	end
	if not arrived or not npc.alive then
		task.spawn(taxiReturn, taxi)
		return false
	end
	local seat = taxi.seats[#taxi.seats] or taxi.seats[1]
	if not seat or not Registry.walkTo(npc, doorSide(taxi, seat)) or not seatNPC(npc, taxi, seat) then
		task.spawn(taxiReturn, taxi)
		return false
	end
	local ok = drive(taxi, { node = nearestNode(target), curb = 5 })
	unseatNPC(npc, 1)
	task.spawn(taxiReturn, taxi)
	return ok
end

---------------------------------------------------------------------
-- Автобус
---------------------------------------------------------------------

local bus = nil

local function busTrip(npc, target: Vector3): boolean
	if not bus or #busStops < 2 then
		return false
	end
	local function nearestStop(pos: Vector3)
		local best, bestDist = nil, math.huge
		for _, stop in busStops do
			local d = (stop.pos - pos).Magnitude
			if d < bestDist then
				best, bestDist = stop, d
			end
		end
		return best
	end
	local from, to = nearestStop(npc.hrp.Position), nearestStop(target)
	if from == to then
		return false
	end
	if not Registry.walkTo(npc, from.pos) then
		return false
	end
	Registry.setMood(npc, "Wait")
	-- Ждём автобус с открытыми дверями на этой остановке
	local deadline = os.clock() + 150
	while npc.alive and os.clock() < deadline and not (bus.atStop == from and bus.doorsOpen) do
		task.wait(0.4)
	end
	Registry.setMood(npc, nil)
	if not npc.alive or bus.atStop ~= from then
		return false
	end
	local seat = freeSeat(bus)
	if not seat or not Registry.walkTo(npc, doorSide(bus, seat, 1)) or bus.atStop ~= from then
		return false
	end
	if not seatNPC(npc, bus, seat) then
		return false
	end
	-- Едем до своей остановки
	repeat
		task.wait(0.4)
	until not npc.alive or not npc.inVehicle or (bus.atStop == to and bus.doorsOpen) or (bus.atStop == nil and bus.atTerminal)
	if npc.inVehicle then
		unseatNPC(npc, 1)
	end
	return true
end

local function busLoop()
	while bus and bus.model.Parent do
		for _, stop in busStops do
			bus.atTerminal = false
			bus.model:SetAttribute("NextStop", stop.name)
			bus.model:SetAttribute("AtStop", "")
			drive(bus, { node = stop.node, curb = true })
			bus.atStop = stop
			bus.model:SetAttribute("AtStop", stop.name)
			bus.model:SetAttribute("BusDoors", true)
			for name in pairs(bus.doors) do
				setDoor(bus, name, true)
			end
			bus.doorsOpen = true
			bus.model:SetAttribute("HornId", (bus.model:GetAttribute("HornId") or 0) + 1)
			task.wait(Config.BusStopTime)
			bus.doorsOpen = false
			for name in pairs(bus.doors) do
				setDoor(bus, name, false)
			end
			task.wait(1)
			bus.atStop = nil
			bus.model:SetAttribute("AtStop", "")
		end
		-- Конечная: на стоянку автобуса, отдых
		bus.model:SetAttribute("NextStop", "Конечная")
		if bus.homeSpot then
			drive(bus, { spot = bus.homeSpot })
		end
		bus.atTerminal = true
		bus.model:SetAttribute("AtStop", "Конечная")
		task.wait(Config.BusLoopPause)
	end
end

---------------------------------------------------------------------
-- Полиция
---------------------------------------------------------------------

local policeRemote = ReplicatedStorage:FindFirstChild("PoliceRemote") or Instance.new("RemoteEvent")
policeRemote.Name = "PoliceRemote"
policeRemote.Parent = ReplicatedStorage

-- Участок: стойка дежурного, места ожидания, камера
local station = { desk = nil, idle = {}, cell = nil }
local stationFolder = folder("PoliceStation")
if stationFolder then
	for _, p in stationFolder:GetDescendants() do
		if p:IsA("BasePart") then
			if string.find(p.Name, "^Desk") then
				station.desk = p
			elseif string.find(p.Name, "^Cell") then
				station.cell = p
			elseif string.find(p.Name, "^Idle") then
				table.insert(station.idle, p)
			end
			hideMarker(p)
		end
	end
end

local function onFloor(part: BasePart): Vector3
	return Vector3.new(part.Position.X, groundY(part.Position), part.Position.Z)
end

local function standCFrame(position: Vector3, look: Vector3): CFrame
	local p = position + Vector3.new(0, 3, 0)
	local l = flat(look).Magnitude > 0.1 and flat(look).Unit or Vector3.new(0, 0, -1)
	return CFrame.lookAt(p, p + l)
end

local callQueue = {} -- вызовы по очереди
local nextTicket = 0
local tickets = {} -- [player] = { заявления }
local recentEvents = {} -- для «Что нового в городе?»
local jailed = {} -- [npc] = true

local function addEvent(text: string)
	if Registry.debugEvent then
		Registry.debugEvent("🚔 " .. text)
	end
	table.insert(recentEvents, 1, text)
	if #recentEvents > 4 then
		table.remove(recentEvents)
	end
end

local function ticketList(player: Player)
	local out = {}
	for _, t in tickets[player] or {} do
		table.insert(out, { id = t.id, icon = t.icon, kind = t.kind, place = t.place, status = t.status, done = t.done })
	end
	return out
end

local function setTicket(ticket, status: string, done: boolean?)
	if not ticket then
		return
	end
	ticket.status = status
	ticket.done = done == true
	local player = ticket.player
	if player and player.Parent then
		policeRemote:FireClient(player, "Tickets", ticketList(player))
		local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
		if phone then
			phone:FireClient(player, "Tickets", ticketList(player))
		end
		toast(player, string.format("🚔 Заявление №%d: %s", ticket.id, status))
	end
end

-- Точка вызова для места: ближайший вход в здание (PoliceCalls) или само место
local function callAt(position: Vector3)
	local best, bestDist = nil, 45
	for _, c in policeCalls do
		local d = (c.pos - position).Magnitude
		if d < bestDist then
			best, bestDist = c, d
		end
	end
	return best and { pos = best.pos, zone = best.zone } or { pos = position, zone = nil }
end

local function spawnOfficer(at: CFrame, title: string?)
	if not Registry.spawnCustom then
		return nil
	end
	local officer = Registry.spawnCustom(at, {
		prefix = title or "Офицер",
		shirt = Config.PoliceShirt,
		pants = Config.PolicePants,
		role = "Полиция",
	})
	if officer then
		officer.officer = true
		officer.noSocial = true
		if officer.prompt then
			officer.prompt.Enabled = false
		end
	end
	return officer
end

-- Офицеры в участке: стоят на местах, иногда переходят, болтают
local function stationLife(officer)
	while officer.alive do
		if not officer.onDuty and #station.idle > 0 then
			local spot = pick(station.idle)
			if Registry.walkTo(officer, onFloor(spot)) and not officer.onDuty then
				Registry.face(officer, spot.CFrame.LookVector)
				if rng:NextNumber() < 0.2 then
					Registry.say(officer, pick({ "Тихо сегодня.", "Кофе будешь?", "Ну и смена...", "Где мой рапорт?" }))
				end
			end
		end
		task.wait(rng:NextNumber(Config.StationWanderTime.Min, Config.StationWanderTime.Max))
	end
end

local function newOfficer(car)
	local at
	if #station.idle > 0 then
		local spot = pick(station.idle)
		at = standCFrame(onFloor(spot), spot.CFrame.LookVector)
	else
		at = standCFrame(doorSide(car, car.driverSeat), car.look)
	end
	local officer = spawnOfficer(at)
	if officer then
		task.spawn(stationLife, officer)
	end
	return officer
end

-- Все садятся по местам; ждём, пока сядут или выйдет время
local function boardAll(car, people)
	local done = 0
	for _, entry in people do
		task.spawn(function()
			local who, seat = entry.npc, entry.seat
			if who and who.alive and seat and not who.inVehicle and Registry.walkTo(who, doorSide(car, seat)) then
				seatNPC(who, car, seat)
			end
			done += 1
		end)
	end
	local deadline = os.clock() + 40
	while done < #people and os.clock() < deadline do
		task.wait(0.3)
	end
end

local function say(npc, text: string?)
	if npc and npc.alive and text and text ~= "" then
		Registry.say(npc, text)
		task.wait(Config.QuestionGap + #text / 30)
	end
end

-- Событие на месте вызова: опрос жителя, иногда задержание
local function workCall(car, call, officers)
	local o1, o2 = officers[1], officers[2] or officers[1]
	local door = call.pos
	local toRoad = flat(car.pos - door)
	toRoad = toRoad.Magnitude > 0.5 and toRoad.Unit or Vector3.new(1, 0, 0)
	local side = toRoad:Cross(Vector3.yAxis)

	-- Встают у двери порознь, лицом к дому
	local arrived = 0
	for i, officer in officers do
		task.spawn(function()
			if officer and officer.alive then
				local offset = (i == 1 and 1 or -1) * Config.OfficerSpacing
				local spot = door + toRoad * 2.4 + side * offset
				Registry.walkTo(officer, Vector3.new(spot.X, groundY(spot), spot.Z))
				Registry.face(officer, -toRoad)
			end
			arrived += 1
		end)
	end
	local deadline = os.clock() + 30
	while arrived < #officers and os.clock() < deadline do
		task.wait(0.3)
	end

	local kind = call.kind
	local resident = Registry.findResident(call.zone, door, 60)
	if resident and not Registry.claim(resident, "police") then
		resident = nil
	end
	if not resident then
		for _, line in Config.NobodyLines do
			say(o1, line)
		end
		return "Никого не оказалось на месте", false
	end

	-- Житель выходит к офицерам
	Registry.setMood(resident, "Police")
	local meet = door + toRoad * 0.6
	Registry.walkTo(resident, Vector3.new(meet.X, groundY(meet), meet.Z))
	Registry.face(resident, toRoad)
	Registry.emote(o1, "Wave")

	local arrest = rng:NextNumber() < (kind.Arrest or 0) and kind.Suspect and kind.Suspect[1] ~= ""
	local answers = arrest and kind.Suspect or kind.Resident
	say(o1, kind.Officer[1])
	say(resident, answers[1])
	Registry.emote(o2, "Point")
	say(o2, kind.Officer[2])
	Registry.emote(resident, rng:NextNumber() < 0.5 and "Point" or "Wave")
	say(resident, answers[2])

	if not arrest then
		say(o1, pick(Config.PoliceCloseLines))
		say(resident, pick(Config.ResidentThanks))
		Registry.release(resident)
		return kind.Name .. ": разобрались на месте", false
	end

	-- Задержание: наручники, в машину, в участок
	say(o1, pick(Config.ArrestLines))
	resident.model:SetAttribute("Cuffed", true)
	Registry.setMood(resident, "Cuffed")
	say(resident, pick(Config.ArrestedLines))
	local rear = car.seats[#car.seats] ~= car.seats[1] and car.seats[#car.seats] or car.seats[2]
	if not rear then
		Registry.release(resident)
		return kind.Name .. ": некуда посадить задержанного", false
	end
	boardAll(car, { { npc = resident, seat = rear } })
	return kind.Name .. ": задержан " .. resident.name, true, resident
end

local function handleCall(car, call)
	car.state = "busy"
	local ticket = call.ticket
	-- Замена погибших офицеров
	for i = 1, Config.PoliceOfficersPerCar do
		local o = car.officers[i]
		if not o or not o.alive then
			car.officers[i] = newOfficer(car)
		end
	end
	local officers = {}
	for _, o in car.officers do
		if o and o.alive then
			o.onDuty = true
			table.insert(officers, o)
		end
	end
	-- Прерываем прогулку по участку
	for _, o in officers do
		o.abort = true
	end
	task.wait(0.4)
	for _, o in officers do
		o.abort = false
	end
	if #officers == 0 then
		table.insert(callQueue, 1, call)
		car.state = "parked"
		task.wait(10)
		return
	end

	-- Из участка — в машину
	setTicket(ticket, "Наряд выезжает")
	local seating = {}
	for i, o in officers do
		table.insert(seating, { npc = o, seat = i == 1 and car.driverSeat or car.seats[i - 1] })
	end
	boardAll(car, seating)

	car.model:SetAttribute("Siren", true)
	car.model:SetAttribute("SirenMuted", false)
	setTicket(ticket, "Наряд в пути 🚨")
	drive(car, { node = nearestNode(call.pos), curb = 5 })
	car.model:SetAttribute("SirenMuted", true) -- мигалки горят, сирена молчит
	setTicket(ticket, "Наряд на месте")

	for _, o in officers do
		task.spawn(unseatNPC, o)
	end
	task.wait(1.4)
	local summary, arrested, suspect = workCall(car, call, officers)
	addEvent(summary)

	-- Обратно в машину и в участок
	local back = {}
	for i, o in officers do
		table.insert(back, { npc = o, seat = i == 1 and car.driverSeat or car.seats[i - 1] })
	end
	boardAll(car, back)
	car.model:SetAttribute("Siren", false)
	car.model:SetAttribute("SirenMuted", false)
	drive(car, { spot = car.homeSpot })

	for _, o in officers do
		task.spawn(unseatNPC, o)
	end
	if arrested and suspect and suspect.alive then
		setTicket(ticket, "Задержанный доставлен в участок")
		if ticket and ticket.player and Registry.playerEvent then
			Registry.playerEvent(ticket.player, "Arrest")
		end
		task.wait(1)
		unseatNPC(suspect)
		if station.cell then
			-- Ведут в камеру и оформляют
			task.spawn(function()
				Registry.walkTo(officers[1], onFloor(station.cell) + station.cell.CFrame.LookVector * 2.5)
			end)
			Registry.walkTo(suspect, onFloor(station.cell))
			Registry.face(suspect, station.cell.CFrame.LookVector)
			say(officers[1], pick(Config.BookingLines))
		end
		jailed[suspect] = true
		task.spawn(function()
			local release = os.clock() + rng:NextNumber(Config.CellTime.Min, Config.CellTime.Max)
			while suspect.alive and os.clock() < release do
				task.wait(rng:NextNumber(12, 25))
				if suspect.alive and os.clock() < release then
					Registry.say(suspect, pick(Config.CellLines))
				end
			end
			jailed[suspect] = nil
			if suspect.alive then
				Registry.say(suspect, "Наконец-то свобода!")
				Registry.release(suspect)
			end
		end)
	elseif arrested and suspect then
		Registry.release(suspect)
	end
	setTicket(ticket, "Закрыто: " .. summary, true)
	task.wait(2)
	for _, o in officers do
		o.onDuty = false
	end
	car.state = "parked"
end

local function policeCarLoop(car)
	car.officers = {}
	for i = 1, Config.PoliceOfficersPerCar do
		car.officers[i] = newOfficer(car)
	end
	while car.model.Parent do
		local call = table.remove(callQueue, 1)
		if call then
			local ok, err = pcall(handleCall, car, call)
			if not ok then
				warn("[Traffic] Ошибка на вызове:", err)
				for _, o in car.officers do
					if o then
						o.onDuty = false
					end
				end
				car.state = "parked"
			end
		else
			task.wait(1)
		end
	end
end

-- Случайные вызовы по городу
local function dispatcher()
	while true do
		local waitTime = rng:NextNumber(Config.PoliceCallInterval.Min, Config.PoliceCallInterval.Max)
		if isNight() then
			waitTime *= Config.PoliceNightFactor
		end
		task.wait(waitTime)
		if #policeCalls > 0 and #callQueue < 2 then
			local c = pick(policeCalls)
			table.insert(callQueue, { pos = c.pos, zone = c.zone, kind = pick(Config.PoliceCallTypes) })
		end
	end
end

-- Дежурный и его меню
local duty = nil
local reportCooldown = {}

local function dutyAnswer(player: Player, text: string)
	if duty and duty.alive then
		Registry.say(duty, text)
	end
	policeRemote:FireClient(player, "Say", text)
end

local function openDesk(player: Player)
	if not duty or not duty.alive then
		return
	end
	local types = {}
	for i, k in Config.PoliceCallTypes do
		types[i] = { name = k.Name, icon = k.Icon }
	end
	local placeNames = {}
	for i, place in places do
		placeNames[i] = place.name
	end
	local questions = {}
	for i, q in Config.DutyQuestions do
		questions[i] = q.Text
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		Registry.face(duty, root.Position - duty.hrp.Position)
	end
	Registry.emote(duty, "Wave")
	local greeting = pick(Config.DutyGreetings)
	Registry.say(duty, greeting)
	policeRemote:FireClient(player, "Open", {
		officer = duty.model,
		name = duty.name,
		greeting = greeting,
		types = types,
		places = placeNames,
		questions = questions,
		tickets = ticketList(player),
	})
end

-- Новое заявление (от дежурного или с телефона). Возвращает ответ дежурного.
local function createReport(player: Player, typeIndex: any, placeIndex: any, force: boolean?): string?
	local kind = type(typeIndex) == "number" and Config.PoliceCallTypes[typeIndex] or nil
	local place = type(placeIndex) == "number" and places[placeIndex] or nil
	if not kind or not place then
		return nil
	end
	local now = os.clock()
	local active = 0
	for _, t in tickets[player] or {} do
		if not t.done then
			active += 1
		end
	end
	if not force and (now < (reportCooldown[player] or 0) or active >= 3) then
		return "Подождите, мы ещё работаем по вашим заявлениям."
	end
	reportCooldown[player] = now + 15
	nextTicket += 1
	local ticket = { id = nextTicket, icon = kind.Icon, kind = kind.Name, place = place.name, status = "Принято", player = player }
	tickets[player] = tickets[player] or {}
	table.insert(tickets[player], 1, ticket)
	if #tickets[player] > 6 then
		table.remove(tickets[player])
	end
	local call = callAt(place.pos)
	call.kind = kind
	call.ticket = ticket
	-- Заявления игроков — вперёд очереди
	table.insert(callQueue, 1, call)
	local free = false
	for _, car in cars do
		if car.kind == "Police" and car.state == "parked" then
			free = true
		end
	end
	policeRemote:FireClient(player, "Tickets", ticketList(player))
	local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
	if phone then
		phone:FireClient(player, "Tickets", ticketList(player))
	end
	if Registry.playerEvent then
		Registry.playerEvent(player, "Report")
	end
	return string.format("%s Номер заявления: %d.", pick(free and Config.ReportAccepted or Config.ReportBusy), ticket.id)
end

policeRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	if not duty or not duty.alive then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - duty.hrp.Position).Magnitude > 20 then
		return
	end
	if action == "Report" then
		local answer = createReport(player, a, b)
		if answer then
			dutyAnswer(player, answer)
			Registry.emote(duty, "Point")
		end
	elseif action == "Ask" and type(a) == "number" then
		local q = Config.DutyQuestions[a]
		if not q then
			return
		end
		local answer = pick(q.Answers)
		if string.find(answer, "%%s") then
			local filler
			if a == 1 then
				filler = #recentEvents > 0 and ("Последние вызовы: " .. table.concat(recentEvents, "; ") .. ".") or "Всё спокойно, вызовов не было."
			else
				local names = {}
				for npc in pairs(jailed) do
					table.insert(names, npc.name)
				end
				filler = #names > 0 and ("Сейчас в камере: " .. table.concat(names, ", ") .. ".") or "Камера пустая. Пока что."
			end
			answer = string.format(answer, filler)
		end
		dutyAnswer(player, answer)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	tickets[player] = nil
	reportCooldown[player] = nil
end)

local function spawnDuty()
	if not station.desk then
		return
	end
	duty = spawnOfficer(standCFrame(onFloor(station.desk), station.desk.CFrame.LookVector), Config.DutyOfficerName)
	if duty then
		duty.onDuty = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DutyPrompt"
		prompt.ActionText = "Обратиться"
		prompt.ObjectText = "Дежурный"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = duty.hrp
		prompt.Triggered:Connect(openDesk)
		-- Дежурный всегда возвращается за стойку
		task.spawn(function()
			while duty and duty.alive do
				task.wait(5)
				local home = onFloor(station.desk)
				if (flat(duty.hrp.Position - home)).Magnitude > 2 then
					Registry.walkTo(duty, home)
				end
				Registry.face(duty, station.desk.CFrame.LookVector)
			end
		end)
	end
end

---------------------------------------------------------------------
-- Такси и автобус для игроков
---------------------------------------------------------------------

local function coins(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild(NPCConfig.CurrencyName) or nil
end

local function addPrompt(car, text: string, onTrigger)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VehiclePrompt"
	prompt.ActionText = text
	prompt.ObjectText = car.kind == "Taxi" and "Такси" or "Автобус"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = car.kind == "Bus" and 14 or 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = car.body
	prompt.Triggered:Connect(onTrigger)
	car.prompt = prompt
	return prompt
end

local playerTaxiBusy = {}

local function playerTaxi(car, player: Player, placeIndex: number)
	local place = places[placeIndex]
	local wallet = coins(player)
	if not place or car.state ~= "parked" or playerTaxiBusy[player] then
		return
	end
	if not wallet or wallet.Value < Config.TaxiPrice then
		toast(player, "Не хватает монет на такси 🪙")
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - car.pos).Magnitude > 20 then
		return
	end
	local seat = freeSeat(car)
	if not seat then
		return
	end
	wallet.Value -= Config.TaxiPrice
	toast(player, string.format("-%d 🪙 Едем: %s", Config.TaxiPrice, place.name))
	playerTaxiBusy[player] = true
	car.state = "busy"
	car.model:SetAttribute("TaxiBusy", true)
	car.prompt.Enabled = false
	seatPlayer(player, car, seat)
	task.wait(0.8)
	drive(car, { node = nearestNode(place.pos), curb = 5 })
	unseatPlayer(player, car, 1)
	toast(player, "Приехали! 🚕")
	if Registry.playerEvent then
		Registry.playerEvent(player, "Taxi")
	end
	playerTaxiBusy[player] = nil
	taxiReturn(car)
	car.prompt.Enabled = true
end

remote.OnServerEvent:Connect(function(player: Player, action: any, model: any, index: any)
	if action ~= "TaxiGo" or typeof(model) ~= "Instance" or type(index) ~= "number" then
		return
	end
	for _, car in cars do
		if car.model == model and car.kind == "Taxi" then
			task.spawn(playerTaxi, car, player, index)
			return
		end
	end
end)

---------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------

-- Гражданские
for i = 1, math.min(Config.Count.Civilian, #spots.Civilian) do
	spawnCar("Civilian", spots.Civilian[i])
end

-- Такси
for i = 1, math.min(Config.Count.Taxi, #spots.Taxi) do
	local car = spawnCar("Taxi", spots.Taxi[i])
	if car then
		local names = {}
		for k, place in places do
			names[k] = place.name
		end
		addPrompt(car, string.format("Такси (%d 🪙)", Config.TaxiPrice), function(player)
			if car.state == "parked" and #names > 0 then
				remote:FireClient(player, "TaxiMenu", car.model, names, Config.TaxiPrice)
			end
		end)
	end
end

-- Автобус
if Config.Count.Bus > 0 and #busStops >= 2 then
	local spot = spots.Bus[1]
	bus = spawnCar("Bus", spot)
	if bus then
		if not spot then
			local first = busStops[1]
			placeCar(bus, nodes[first.node].pos, Vector3.new(0, 0, -1))
		end
		addPrompt(bus, "Сесть в автобус", function(player)
			if bus.atStop or bus.state == "parked" or bus.atTerminal then
				local seat = freeSeat(bus)
				if seat then
					task.spawn(seatPlayer, player, bus, seat)
					if Registry.playerEvent then
						Registry.playerEvent(player, "Bus")
					end
				else
					toast(player, "Автобус полный 🚌")
				end
			end
		end)
		bus.state = "busy"
		task.spawn(busLoop)
	end
elseif Config.Count.Bus > 0 then
	warn("[Traffic] Для автобуса нужно минимум 2 остановки в папке BusStops")
end

-- Полиция
for i = 1, math.min(Config.Count.Police, #spots.Police) do
	local car = spawnCar("Police", spots.Police[i])
	if car then
		task.spawn(policeCarLoop, car)
	end
end
if #spots.Police > 0 then
	task.spawn(dispatcher)
	task.spawn(function()
		-- Дежурный: возрождается, если с ним что-то случилось
		while true do
			if not duty or not duty.alive then
				spawnDuty()
			end
			task.wait(20)
		end
	end)
end

-- Поток машин: свои водители, катаются всё время
local function cruiseDriver(car)
	if not Registry.spawnCustom then
		return nil
	end
	local pos = car.pos + car.look:Cross(Vector3.yAxis) * -(car.width / 2 + 2)
	local driver = Registry.spawnCustom(CFrame.new(pos + Vector3.new(0, 3, 0)), {})
	if driver then
		driver.noSocial = true
		driver.officer = true -- без разговоров и обычного «мозга»
		if driver.prompt then
			driver.prompt.Enabled = false
		end
		seatNPC(driver, car, car.driverSeat)
	end
	return driver
end

local function cruiseLoop(car)
	local names = {}
	for name, node in pairs(nodes) do
		if next(node.links) then
			table.insert(names, name)
		end
	end
	car.state = "busy"
	while car.model.Parent do
		if not car.driver or not car.driver.alive or car.driver.inVehicle ~= car then
			task.wait(car.driver and 15 or 0.5)
			car.driver = cruiseDriver(car)
			if not car.driver then
				task.wait(5)
				continue
			end
		end
		-- Случайная точка подальше
		local dest
		for _ = 1, 10 do
			local candidate = pick(names)
			if (nodes[candidate].pos - car.pos).Magnitude > Config.CruiseMinDistance then
				dest = candidate
				break
			end
		end
		dest = dest or pick(names)
		local stop = rng:NextNumber() < Config.CruiseStopChance
		drive(car, { node = dest, curb = stop and 5 or nil })
		if stop then
			task.wait(rng:NextNumber(Config.CruiseStopTime.Min, Config.CruiseStopTime.Max))
		else
			task.wait(0.2)
		end
	end
end

do
	local list = {}
	for name, node in pairs(nodes) do
		if next(node.links) then
			table.insert(list, name)
		end
	end
	-- Ставим на разные точки, подальше друг от друга
	local used = {}
	for _ = 1, Config.Count.Cruising do
		local best, bestDist = nil, -1
		for _ = 1, 15 do
			local candidate = pick(list)
			local minDist = math.huge
			for _, u in used do
				minDist = math.min(minDist, (nodes[u].pos - nodes[candidate].pos).Magnitude)
			end
			if minDist > bestDist then
				best, bestDist = candidate, minDist
			end
		end
		if not best then
			break
		end
		table.insert(used, best)
		local car = spawnCar("Civilian", nil)
		if car then
			-- Смотрим вдоль дороги к соседней точке и встаём на правую полосу
			local neighbor = next(nodes[best].links)
			local dir = flat(nodes[neighbor].pos - nodes[best].pos).Unit
			local lane = nodes[best].pos + dir:Cross(Vector3.yAxis) * Config.LaneOffset
			placeCar(car, Vector3.new(lane.X, groundY(lane), lane.Z), dir)
			car.onRoad = true
			car.cruiser = true
			task.spawn(cruiseLoop, car)
		end
	end
end

if #cars == 0 then
	warn("[Traffic] Ни одной машины: добавь парковки (Workspace >", Config.MapFolder, "> Parking) с атрибутом Type")
end

---------------------------------------------------------------------
-- Связь с жителями
---------------------------------------------------------------------

function Registry.assignCar(npc)
	if npc.car or npc.officer or not npc.homeZone then
		return
	end
	local best
	for _, car in cars do
		if car.kind == "Civilian" and not car.owner and not car.cruiser then
			if not best or (car.homeSpot and car.homeSpot.zone == npc.homeZone) then
				best = car
			end
		end
	end
	if best then
		best.owner = npc
		npc.car = best
	end
end

function Registry.releaseCar(npc)
	if npc.car and npc.car.owner == npc then
		npc.car.owner = nil
	end
	npc.car = nil
end

function Registry.tryTrip(npc, target: Vector3): boolean
	if not npc.alive or npc.inVehicle or npc.officer then
		return false
	end
	if (flat(target - npc.hrp.Position)).Magnitude < Config.TripMinDistance then
		return false
	end
	local car = npc.car
	if car and car.owner == npc and car.state == "parked" and car.model.Parent then
		return carTrip(npc, car, target)
	end
	if rng:NextNumber() < Config.TaxiChance and freeTaxi() then
		return taxiTrip(npc, target)
	end
	if bus and rng:NextNumber() < Config.BusChance then
		return busTrip(npc, target)
	end
	return false
end

for _, npc in pairs(Registry.npcs) do
	Registry.assignCar(npc)
end

---------------------------------------------------------------------
-- Телефон игрока (PhoneServer вызывает эти функции)
---------------------------------------------------------------------

local function phoneSend(player: Player, action: string, payload)
	local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
	if phone and player.Parent then
		phone:FireClient(player, action, payload)
	end
end

-- Для меню отладки: вызов полиции без ограничений (место — ближайшее к игроку)
function Registry.debugPoliceCall(player: Player, typeIndex: number): string?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local best, bestDist = 1, math.huge
	for i, place in places do
		local d = root and (place.pos - root.Position).Magnitude or i
		if d < bestDist then
			best, bestDist = i, d
		end
	end
	local answer = createReport(player, typeIndex, best, true)
	if answer then
		phoneSend(player, "PoliceAnswer", answer)
	end
	return answer and (places[best].name .. ": " .. answer) or "Нет мест (Places) или такого вида вызова"
end

-- Для меню отладки: все машины и их маршруты
function Registry.debugCars()
	local out = {}
	for i, car in cars do
		if car.model and car.model.Parent then
			local route = {}
			for _, name in car.debugPath or {} do
				local n = nodes[name]
				if n then
					table.insert(route, n.pos)
				end
			end
			table.insert(out, {
				id = i,
				kind = car.kind,
				state = car.state,
				speed = math.floor((car.v or 0) * 10) / 10,
				pos = car.pos,
				to = car.debugTo,
				route = route,
				driver = car.driver and car.driver.name or nil,
				siren = car.model:GetAttribute("Siren") == true,
				model = car.model,
			})
		end
	end
	return out
end
function Registry.debugNodes()
	local out = {}
	for name, n in pairs(nodes) do
		local links = {}
		for other in pairs(n.links) do
			table.insert(links, other)
		end
		out[name] = { pos = n.pos, links = links }
	end
	return out
end

function Registry.phoneData(player: Player)
	local placeNames, types, stops = {}, {}, {}
	for i, place in places do
		placeNames[i] = place.name
	end
	for i, k in Config.PoliceCallTypes do
		types[i] = { name = k.Name, icon = k.Icon }
	end
	for i, stop in busStops do
		stops[i] = stop.name
	end
	return {
		places = placeNames,
		policeTypes = types,
		tickets = ticketList(player),
		taxiPrice = Config.TaxiPrice,
		busStops = stops,
	}
end

function Registry.phoneReport(player: Player, typeIndex: any, placeIndex: any)
	local answer = createReport(player, typeIndex, placeIndex)
	if answer then
		phoneSend(player, "PoliceAnswer", answer)
	end
end

-- Такси по телефону: приезжает к игроку, ждёт, везёт, берёт плату
local phoneTaxiBusy = {}
function Registry.phoneTaxi(player: Player, placeIndex: any)
	local place = type(placeIndex) == "number" and places[placeIndex] or nil
	local wallet = coins(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local function status(text: string, done: boolean?)
		phoneSend(player, "Taxi", { text = text, done = done == true })
	end
	if not place or not root or phoneTaxiBusy[player] or playerTaxiBusy[player] then
		return
	end
	if not wallet or wallet.Value < Config.TaxiPrice then
		status("Не хватает монет 🪙 (нужно " .. Config.TaxiPrice .. ")", true)
		return
	end
	local taxi = freeTaxi()
	if not taxi then
		status("Все такси заняты, попробуйте позже", true)
		return
	end
	phoneTaxiBusy[player] = true
	taxi.state = "busy"
	taxi.model:SetAttribute("TaxiBusy", true)
	taxi.model:SetAttribute("CalledBy", player.UserId)
	if taxi.prompt then
		taxi.prompt.Enabled = false
	end
	status("🚕 Такси едет к вам...")
	local ok = drive(taxi, { node = nearestNode(root.Position), curb = 5 })
	local function finish()
		phoneTaxiBusy[player] = nil
		taxi.model:SetAttribute("CalledBy", nil)
		taxiReturn(taxi)
		if taxi.prompt then
			taxi.prompt.Enabled = true
		end
	end
	if not ok then
		status("Такси не смогло проехать 😕", true)
		finish()
		return
	end
	status("🚕 Такси ждёт вас! Подойдите к машине")
	honk(taxi)
	-- Ждём игрока минуту
	local deadline = os.clock() + 60
	local near = false
	while os.clock() < deadline and player.Parent do
		local c = player.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - taxi.pos).Magnitude < 12 then
			near = true
			break
		end
		task.wait(0.5)
	end
	if not near then
		status("Такси уехало: вы не пришли", true)
		finish()
		return
	end
	local seat = freeSeat(taxi)
	if not seat or not wallet.Parent or wallet.Value < Config.TaxiPrice then
		status("Не получилось сесть", true)
		finish()
		return
	end
	wallet.Value -= Config.TaxiPrice
	seatPlayer(player, taxi, seat)
	status("🚕 Едем: " .. place.name)
	task.wait(0.8)
	drive(taxi, { node = nearestNode(place.pos), curb = 5 })
	unseatPlayer(player, taxi, 1)
	status("Приехали! -" .. Config.TaxiPrice .. " 🪙", true)
	if Registry.playerEvent then
		Registry.playerEvent(player, "Taxi")
	end
	finish()
end

----------------------------------------------------------------------
-- 28. ServerScriptService > Script "WeatherServer"
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- 29. ServerScriptService > Script "PhoneServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > PhoneServer
-- Телефон игрока: принимает запросы приложений и передаёт их жителям и транспорту.
--   Open   — данные для приложений (места, виды заявлений, заявления, остановки, друзья)
--   Taxi   — вызвать такси к себе
--   Report — заявление в полицию
--   Reply  — ответить знакомому жителю в сообщениях
--   Job, Buy, Equip, Photo, City — работа курьером, магазин, фото, достижения (CityLifeServer)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local remote = ReplicatedStorage:FindFirstChild("PhoneRemote") or Instance.new("RemoteEvent")
remote.Name = "PhoneRemote"
remote.Parent = ReplicatedStorage

local last = {} -- защита от спама: [player] = время

remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	local now = os.clock()
	if now - (last[player] or 0) < 0.3 then
		return
	end
	last[player] = now

	if action == "Open" then
		local data = Registry.phoneData and Registry.phoneData(player) or {}
		data.friends = Registry.friendsOf and Registry.friendsOf(player) or {}
		data.city = Registry.cityData and Registry.cityData(player) or nil
		remote:FireClient(player, "Data", data)
	elseif action == "Taxi" and Registry.phoneTaxi then
		task.spawn(Registry.phoneTaxi, player, a)
	elseif action == "Report" and Registry.phoneReport then
		Registry.phoneReport(player, a, b)
	elseif action == "Reply" and Registry.phoneReply then
		Registry.phoneReply(player, a, b)
	elseif action == "Friends" and Registry.friendsOf then
		remote:FireClient(player, "Friends", Registry.friendsOf(player))
	elseif type(action) == "string" and Registry.cityAction then
		Registry.cityAction(player, action, a, b)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)

----------------------------------------------------------------------
-- 30. ServerScriptService > Script "CityLifeServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > CityLifeServer
-- Новые механики города (настройки — ReplicatedStorage > CityConfig):
--   📦 Курьер      — забрать посылку на «Почте» и отнести случайному жителю
--   🛍 Магазин     — аксессуары за монеты (собираются из деталей прямо на персонаже)
--   🏆 Достижения  — счётчики полёта, такси, друзей, доставок... с наградой
--   📷 Фоторежим   — жители рядом позируют, когда игрок фотографирует
--   💾 Сохранение  — монеты, покупки, достижения (DataStore)
-- Работает через телефон (PhoneRemote) и на уже расставленных метках. Новых меток не нужно.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CityConfig"))
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local rng = Random.new()
local remote = ReplicatedStorage:WaitForChild("PhoneRemote")

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function toast(player: Player, text: string)
	if Registry.toast then
		Registry.toast(player, text)
	end
end

local function wallet(player: Player): IntValue?
	if Registry.getCoins then
		return Registry.getCoins(player)
	end
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild(NPCConfig.CurrencyName) or nil
end

local function giveCoins(player: Player, amount: number)
	if Registry.addCoins then
		Registry.addCoins(player, amount)
	else
		local w = wallet(player)
		if w then
			w.Value += amount
		end
	end
end

local SHOP = {}
for _, item in Config.Shop do
	SHOP[item.Id] = item
end

---------------------------------------------------------------------
-- Данные игрока и сохранение
---------------------------------------------------------------------

local profiles = {} -- [player] = { stats, done, owned, equipped, loaded }
local store = nil
if Config.SaveEnabled then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	store = ok and result or nil
end

local function profileOf(player: Player)
	local p = profiles[player]
	if not p then
		p = { stats = {}, done = {}, owned = {}, equipped = {}, loaded = false }
		profiles[player] = p
	end
	return p
end

local function save(player: Player)
	local p = profiles[player]
	if not store or not p or not p.loaded then
		return
	end
	local w = wallet(player)
	local data = { coins = w and w.Value or 0, stats = p.stats, done = p.done, owned = p.owned, equipped = p.equipped }
	local ok, err = pcall(function()
		store:SetAsync("p_" .. player.UserId, data)
	end)
	if not ok then
		warn("[CityLife] Не удалось сохранить", player.Name, err)
	end
end

local function load(player: Player)
	local p = profileOf(player)
	if store then
		local ok, data = pcall(function()
			return store:GetAsync("p_" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			p.stats = data.stats or {}
			p.done = data.done or {}
			p.owned = data.owned or {}
			p.equipped = data.equipped or {}
			local w = wallet(player)
			if w and type(data.coins) == "number" then
				w.Value = data.coins
			end
		elseif not ok then
			warn("[CityLife] Сохранения недоступны (в Studio включи API Services):", data)
		end
	end
	p.loaded = true
end

---------------------------------------------------------------------
-- Данные для телефона
---------------------------------------------------------------------

local function cityData(player: Player)
	local p = profileOf(player)
	local done = {}
	for id in pairs(p.done) do
		table.insert(done, id)
	end
	local owned = {}
	for id in pairs(p.owned) do
		table.insert(owned, id)
	end
	local equipped = {}
	for _, id in pairs(p.equipped) do
		table.insert(equipped, id)
	end
	return { stats = p.stats, done = done, owned = owned, equipped = equipped }
end

local pushQueued = {}
local function push(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.delay(0.3, function()
		pushQueued[player] = nil
		if player.Parent then
			remote:FireClient(player, "City", cityData(player))
		end
	end)
end

---------------------------------------------------------------------
-- 🏆 Достижения
---------------------------------------------------------------------

local function addStat(player: Player, stat: string, amount: number?)
	local p = profileOf(player)
	local before = p.stats[stat] or 0
	local after = before + (amount or 1)
	p.stats[stat] = after
	local changed = math.floor(before) ~= math.floor(after)
	for _, a in Config.Achievements do
		if a.Stat == stat and not p.done[a.Id] and after >= a.Goal then
			p.done[a.Id] = true
			changed = true
			giveCoins(player, a.Reward)
			remote:FireClient(player, "Achievement", { icon = a.Icon, name = a.Name, reward = a.Reward })
			if Registry.debugEvent then
				Registry.debugEvent(string.format("🏆 %s: достижение «%s»", player.Name, a.Name))
			end
		end
	end
	if changed then
		push(player)
	end
end

-- События от жителей и транспорта: Taxi, Bus, Report, Arrest, Friend, Quest
Registry.playerEvent = function(player: Player, name: string)
	if player and player.Parent then
		addStat(player, name, 1)
	end
end

-- Способности, прогулки и ночь — проверяем по атрибутам персонажа
local ABILITY_FLAGS = { Invisible = "Invisible", LaserActive = "Laser", CubeForm = "Cube" }
local tracking = {} -- [player] = { flags = {}, lastPos }

task.spawn(function()
	local STEP = 0.5
	while true do
		task.wait(STEP)
		local night = workspace:GetAttribute("Period") == "Ночь"
		for _, player in Players:GetPlayers() do
			local t = tracking[player]
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if t and humanoid and root and humanoid.Health > 0 then
				if character:GetAttribute("Flying") == true then
					addStat(player, "Fly", STEP)
				end
				for attribute, stat in pairs(ABILITY_FLAGS) do
					local on = character:GetAttribute(attribute) == true
					if on and not t.flags[attribute] then
						addStat(player, stat, 1)
					end
					t.flags[attribute] = on
				end
				local pos = root.Position
				if t.lastPos then
					local moved = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(t.lastPos.X, 0, t.lastPos.Z)).Magnitude
					local walking = humanoid.SeatPart == nil and humanoid.FloorMaterial ~= Enum.Material.Air
						and character:GetAttribute("Flying") ~= true and character:GetAttribute("CubeForm") ~= true
					if walking and moved > 0.5 and moved < 25 then
						addStat(player, "Walk", moved)
					end
				end
				t.lastPos = pos
				if night then
					addStat(player, "Night", STEP / 60)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- 🛍 Аксессуары
---------------------------------------------------------------------

local function decor(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	p:SetAttribute("BaseTransparency", p.Transparency)
	p.Parent = parent
	return p
end

local function weldTo(part: BasePart, to: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- цилиндр стоя

-- Видимая ширина головы: у R6 деталь 2×1×1, но выглядит как ~1.25
local function headSize(head: BasePart): Vector3
	local w = math.min(head.Size.X, head.Size.Z * 1.25)
	return Vector3.new(w, head.Size.Y, w)
end

local BUILDERS = {}

function BUILDERS.Hat(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local top = head.CFrame * CFrame.new(0, hs.Y / 2, 0)
	weldTo(decor(folder, Vector3.new(hs.X * 1.08, 0.42, hs.Z * 1.08), top * CFrame.new(0, 0.08, 0), item.Color), head)
	weldTo(decor(folder, Vector3.new(hs.X * 0.95, 0.08, 0.75), top * CFrame.new(0, -0.08, -hs.Z / 2 - 0.3), item.Color:Lerp(Color3.new(1, 1, 1), 0.1)), head)
	weldTo(decor(folder, Vector3.new(0.22, 0.22, 0.22), top * CFrame.new(0, 0.32, 0), Color3.new(1, 1, 1), nil, Enum.PartType.Ball), head)
end

function BUILDERS.TopHat(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local top = head.CFrame * CFrame.new(0, hs.Y / 2, 0)
	local w = hs.X
	weldTo(decor(folder, Vector3.new(0.08, w * 1.6, w * 1.6), top * UPRIGHT, item.Color, nil, Enum.PartType.Cylinder), head)
	weldTo(decor(folder, Vector3.new(1.1, w * 0.95, w * 0.95), top * CFrame.new(0, 0.58, 0) * UPRIGHT, item.Color, nil, Enum.PartType.Cylinder), head)
	weldTo(decor(folder, Vector3.new(0.2, w * 0.97, w * 0.97), top * CFrame.new(0, 0.18, 0) * UPRIGHT, Color3.fromRGB(170, 30, 40), nil, Enum.PartType.Cylinder), head)
end

function BUILDERS.Crown(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local top = head.CFrame * CFrame.new(0, hs.Y / 2 + 0.12, 0)
	local r = hs.X * 0.5
	weldTo(decor(folder, Vector3.new(0.28, r * 2.1, r * 2.1), top * UPRIGHT, item.Color, Enum.Material.Metal, Enum.PartType.Cylinder), head)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local spike = top * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, -r * 0.92)
		weldTo(decor(folder, Vector3.new(0.18, 0.36, 0.08), spike, item.Color, Enum.Material.Metal), head)
		local gem = decor(folder, Vector3.new(0.13, 0.13, 0.13), spike * CFrame.new(0, -0.18, -0.06), i % 2 == 0 and Color3.fromRGB(220, 30, 60) or Color3.fromRGB(40, 120, 255), Enum.Material.Neon, Enum.PartType.Ball)
		weldTo(gem, head)
	end
end

function BUILDERS.Face(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local front = head.CFrame * CFrame.new(0, hs.Y * 0.08, -hs.Z / 2 - 0.04)
	local lensW = hs.X * 0.32
	for _, side in { -1, 1 } do
		local lens = decor(folder, Vector3.new(lensW, 0.26, 0.05), front * CFrame.new(side * lensW * 0.62, 0, 0), item.Color, Enum.Material.Glass)
		lens.Reflectance = 0.3
		weldTo(lens, head)
	end
	weldTo(decor(folder, Vector3.new(lensW * 0.4, 0.06, 0.05), front * CFrame.new(0, 0.06, 0), item.Color), head)
end

function BUILDERS.Halo(folder, character, item)
	local head = character:FindFirstChild("Head") :: BasePart
	local hs = headSize(head)
	local center = head.CFrame * CFrame.new(0, hs.Y / 2 + 0.7, 0)
	local r = hs.X * 0.55
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		local seg = decor(folder, Vector3.new(0.12, 0.08, r * 0.5), center * CFrame.Angles(0, a, 0) * CFrame.new(r, 0, 0), item.Color, Enum.Material.Neon)
		weldTo(seg, head)
	end
	local glow = Instance.new("PointLight")
	glow.Color = item.Color
	glow.Brightness = 1.5
	glow.Range = 8
	glow.Parent = folder:FindFirstChildWhichIsA("BasePart")
end

function BUILDERS.Balloon(folder, character, item)
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart
	if not hand then
		return
	end
	local ball = decor(folder, Vector3.new(1.7, 1.9, 1.7), hand.CFrame * CFrame.new(0, 6, 0), item.Color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	ball.Massless = false
	ball.Reflectance = 0.15
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.05, 0, 0, 1, 1)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = ball
	folder:SetAttribute("HandAttachment", true)
	a0.Name = "BalloonAttachment"
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = a0
	rope.Attachment1 = a1
	rope.Length = 5
	rope.Visible = true
	rope.Thickness = 0.04
	rope.Color = BrickColor.new("Institutional white")
	rope.Parent = ball
	-- Подъёмная сила чуть больше веса
	local lift = Instance.new("VectorForce")
	lift.Attachment0 = a1
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.Force = Vector3.new(0, ball:GetMass() * workspace.Gravity * 1.6, 0)
	lift.Parent = ball
	-- Немного сопротивления воздуха, чтобы шарик не болтался
	local drag = Instance.new("LinearVelocity")
	drag.Attachment0 = a1
	drag.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drag.VectorVelocity = Vector3.zero
	drag.MaxForce = ball:GetMass() * workspace.Gravity * 0.6
	drag.Parent = ball
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		pcall(function()
			ball:SetNetworkOwner(player)
		end)
	end
end

function BUILDERS.Trail(folder, character)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local a0 = Instance.new("Attachment")
	a0.Name = "CosmeticTrailTop"
	a0.Position = Vector3.new(0, 0.9, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "CosmeticTrailBottom"
	a1.Position = Vector3.new(0, -1.6, 0.4)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.7
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 60)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 220, 90)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(60, 140, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 80, 255)),
	})
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = folder
end

function BUILDERS.Aura(folder, character, item)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local a = Instance.new("Attachment")
	a.Name = "CosmeticAura"
	a.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(item.Color)
	e.LightEmission = 0.7
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate = 14
	e.Speed = NumberRange.new(1, 2.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 2, 0)
	e.Parent = a
	-- Эмиттер живёт в папке, чтобы его можно было найти и выключить
	local ref = Instance.new("ObjectValue")
	ref.Name = "AuraRef"
	ref.Value = e
	ref.Parent = folder
end

-- Спрятать аксессуары, пока персонаж невидим или в форме куба
local function hiddenNow(character: Model): boolean
	return character:GetAttribute("Invisible") == true or character:GetAttribute("CubeForm") == true
end

local function refreshVisibility(character: Model)
	local folder = character:FindFirstChild("Cosmetics")
	if not folder then
		return
	end
	local hide = hiddenNow(character)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = hide and 1 or (d:GetAttribute("BaseTransparency") or 0)
		elseif d:IsA("Trail") or d:IsA("RopeConstraint") or d:IsA("PointLight") then
			if d:IsA("RopeConstraint") then
				d.Visible = not hide
			else
				d.Enabled = not hide
			end
		elseif d:IsA("ObjectValue") and d.Value and d.Value:IsA("ParticleEmitter") then
			(d.Value :: ParticleEmitter).Enabled = not hide
		end
	end
end

local function clearCosmetics(character: Model)
	local old = character:FindFirstChild("Cosmetics")
	if old then
		for _, d in old:GetDescendants() do
			if d:IsA("ObjectValue") and d.Value then
				local att = d.Value.Parent
				d.Value:Destroy()
				if att and att:IsA("Attachment") then
					att:Destroy()
				end
			end
		end
		old:Destroy()
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, name in { "CosmeticTrailTop", "CosmeticTrailBottom", "CosmeticAura" } do
			local a = root:FindFirstChild(name)
			if a then
				a:Destroy()
			end
		end
	end
	for _, d in character:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "BalloonAttachment" then
			d:Destroy()
		end
	end
end

local function applyCosmetics(player: Player)
	local character = player.Character
	if not character or not character:FindFirstChild("Head") or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	clearCosmetics(character)
	local folder = Instance.new("Folder")
	folder.Name = "Cosmetics"
	folder.Parent = character
	for _, id in pairs(profileOf(player).equipped) do
		local item = SHOP[id]
		local build = item and BUILDERS[item.Kind]
		if build then
			local ok, err = pcall(build, folder, character, item)
			if not ok then
				warn("[CityLife] Не удалось надеть", id, err)
			end
		end
	end
	refreshVisibility(character)
end

local function equip(player: Player, id: string)
	local p = profileOf(player)
	local item = SHOP[id]
	if not item or not p.owned[id] then
		return
	end
	if p.equipped[item.Slot] == id then
		p.equipped[item.Slot] = nil
	else
		p.equipped[item.Slot] = id
	end
	applyCosmetics(player)
	push(player)
end

local function buy(player: Player, id: string)
	local p = profileOf(player)
	local item = SHOP[id]
	if not item then
		return
	end
	if p.owned[id] then
		equip(player, id)
		return
	end
	local w = wallet(player)
	if not w or w.Value < item.Price then
		toast(player, "Не хватает монет 🪙")
		remote:FireClient(player, "ShopResult", { ok = false })
		return
	end
	w.Value -= item.Price
	p.owned[id] = true
	p.equipped[item.Slot] = id
	toast(player, string.format("%s %s куплено! -%d 🪙", item.Icon, item.Name, item.Price))
	remote:FireClient(player, "ShopResult", { ok = true, id = id })
	applyCosmetics(player)
	addStat(player, "Buy", 1)
	push(player)
end

---------------------------------------------------------------------
-- 📦 Курьер
---------------------------------------------------------------------

local jobs = {} -- [player] = { stage, crate, target, item, started }

local function jobTargetValue(player: Player): ObjectValue
	local v = player:FindFirstChild("JobTarget")
	if not v then
		v = Instance.new("ObjectValue")
		v.Name = "JobTarget"
		v.Parent = player
	end
	return v :: ObjectValue
end

local function setJobInfo(player: Player, stage: string?, text: string?, target: Instance?)
	player:SetAttribute("JobStage", stage)
	player:SetAttribute("JobText", text)
	jobTargetValue(player).Value = target
	local job = jobs[player]
	player:SetAttribute("JobEnds", job and stage and (workspace:GetServerTimeNow() + Config.Job.TimeLimit - (os.clock() - job.started)) or nil)
end

local function removeBox(player: Player)
	local character = player.Character
	if character then
		character:SetAttribute("CarryBox", nil)
		local box = character:FindFirstChild("CourierBox")
		if box then
			box:Destroy()
		end
	end
end

local function giveBox(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or character:FindFirstChild("CourierBox") then
		return
	end
	local box = decor(character, Vector3.new(1.7, 1.2, 1.3), root.CFrame * CFrame.new(0, 0.1, -1.25), Color3.fromRGB(190, 140, 85), Enum.Material.Cardboard)
	box.Name = "CourierBox"
	local tape = decor(box, Vector3.new(0.3, 1.22, 1.32), box.CFrame, Color3.fromRGB(150, 105, 60), Enum.Material.SmoothPlastic)
	weldTo(tape, box)
	weldTo(box, root)
	character:SetAttribute("CarryBox", true)
	refreshVisibility(character)
end

local function endJob(player: Player, message: string?)
	local job = jobs[player]
	if job and job.crate then
		job.crate:Destroy()
	end
	jobs[player] = nil
	removeBox(player)
	setJobInfo(player, nil, nil, nil)
	if message then
		toast(player, message)
	end
	remote:FireClient(player, "Job", { active = false, text = message })
end

local function residentOk(npc): boolean
	return npc.alive and not npc.officer and not npc.controlled and npc.model and npc.model.Parent ~= nil
end

local function chooseRecipient(player: Player, except)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local options = {}
	for _, npc in pairs(Registry.npcs) do
		if residentOk(npc) and npc ~= except then
			local far = root and (npc.hrp.Position - root.Position).Magnitude or 100
			table.insert(options, { npc = npc, weight = far > 40 and 3 or 1 })
		end
	end
	if #options == 0 then
		return nil
	end
	local total = 0
	for _, o in options do
		total += o.weight
	end
	local roll = rng:NextNumber() * total
	for _, o in options do
		roll -= o.weight
		if roll <= 0 then
			return o.npc
		end
	end
	return options[1].npc
end

local function startDelivery(player: Player)
	local job = jobs[player]
	if not job then
		return
	end
	local target = chooseRecipient(player, nil)
	if not target then
		endJob(player, "В городе пока никого нет — заказ отменён")
		return
	end
	job.stage = "deliver"
	job.target = target
	giveBox(player)
	setJobInfo(player, "deliver", string.format("Отнеси %s → %s", job.item, target.name), target.model)
	toast(player, string.format("📦 Посылка для: %s", target.name))
	remote:FireClient(player, "Job", { active = true, stage = "deliver", text = player:GetAttribute("JobText") })
end

local function placesList()
	local root = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local folder = root and root:FindFirstChild("Places")
	local list = {}
	if folder then
		for _, p in folder:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(list, p)
			end
		end
	end
	return list
end

local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	return hit and hit.Position or position
end

local function startJob(player: Player)
	if jobs[player] then
		endJob(player, "Заказ отменён")
		return
	end
	local job = { stage = "pickup", item = pick(Config.Job.Items), started = os.clock() }
	jobs[player] = job
	-- Где забрать
	local list = placesList()
	local depot = nil
	for _, p in list do
		if (p:GetAttribute("PlaceName") or p.Name) == Config.Job.DepotName then
			depot = p
		end
	end
	depot = depot or (#list > 0 and list[rng:NextInteger(1, #list)] or nil)
	if not depot then
		startDelivery(player)
		return
	end
	local floor = groundAt(depot.Position)
	local crate = Instance.new("Part")
	crate.Name = "CourierPickup"
	crate.Size = Vector3.new(2, 1.4, 1.6)
	crate.CFrame = CFrame.new(floor + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
	crate.Anchored = true
	crate.CanCollide = false
	crate.Color = Color3.fromRGB(190, 140, 85)
	crate.Material = Enum.Material.Cardboard
	crate.Parent = workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Взять посылку"
	prompt.ObjectText = job.item
	prompt.HoldDuration = 0.4
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = crate
	prompt.Triggered:Connect(function(who)
		if who == player and jobs[player] == job and job.stage == "pickup" then
			crate:Destroy()
			job.crate = nil
			startDelivery(player)
		end
	end)
	job.crate = crate
	local placeName = depot:GetAttribute("PlaceName") or depot.Name
	setJobInfo(player, "pickup", string.format("Забери посылку: %s", placeName), crate)
	toast(player, "📦 Новый заказ! Забери посылку: " .. placeName)
	remote:FireClient(player, "Job", { active = true, stage = "pickup", text = player:GetAttribute("JobText") })
end

local function deliver(player: Player, job)
	local npc = job.target
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and Registry.face then
		task.spawn(Registry.face, npc, root.Position - npc.hrp.Position, 2)
	end
	if Registry.say then
		Registry.say(npc, pick(Config.Job.Thanks))
	end
	if Registry.emote then
		Registry.emote(npc, "Cheer")
	end
	if Registry.sfx then
		Registry.sfx(npc, "Cheer")
	end
	if Registry.setMood then
		Registry.setMood(npc, "Happy", 4)
	end
	local took = os.clock() - job.started
	local reward = rng:NextInteger(Config.Job.Reward.Min, Config.Job.Reward.Max)
	local fast = took <= Config.Job.FastTime
	if fast then
		reward += Config.Job.FastBonus
	end
	giveCoins(player, reward)
	if Registry.addFriendship then
		Registry.addFriendship(npc, player, Config.Job.FriendPoints)
	end
	endJob(player, string.format("✅ Доставлено за %d с%s", math.floor(took), fast and " — быстро! ⚡" or ""))
	addStat(player, "Delivery", 1)
	task.delay(Config.Job.Cooldown, function()
		if player.Parent then
			remote:FireClient(player, "Job", { active = false, ready = true })
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(0.3)
		for player, job in pairs(jobs) do
			if not player.Parent then
				jobs[player] = nil
				continue
			end
			if os.clock() - job.started > Config.Job.TimeLimit then
				endJob(player, "⌛ Время вышло — заказ отменён")
				continue
			end
			if job.stage == "deliver" then
				local npc = job.target
				if not npc or not residentOk(npc) then
					-- Получатель пропал — посылку ждёт другой
					local nextOne = chooseRecipient(player, npc)
					if nextOne then
						job.target = nextOne
						setJobInfo(player, "deliver", string.format("Отнеси %s → %s", job.item, nextOne.name), nextOne.model)
						toast(player, "📦 Новый получатель: " .. nextOne.name)
					else
						endJob(player, "Получатель пропал — заказ отменён")
					end
					continue
				end
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then
					if not character:FindFirstChild("CourierBox") then
						giveBox(player) -- после возрождения
					end
					if (root.Position - npc.hrp.Position).Magnitude <= Config.Job.DeliverDistance and not npc.inVehicle then
						deliver(player, job)
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- 📷 Фото: жители позируют
---------------------------------------------------------------------

local lastPhoto = {}
local POSES = { "Wave", "Cheer", "Point", "Laugh" }

local function photo(player: Player)
	local now = os.clock()
	if now - (lastPhoto[player] or 0) < 1 then
		return
	end
	lastPhoto[player] = now
	addStat(player, "Photo", 1)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local posed = 0
	for _, npc in pairs(Registry.npcs) do
		if posed >= 4 then
			break
		end
		if residentOk(npc) and not npc.inVehicle and not npc.talkingTo and npc.lock == nil
			and (npc.hrp.Position - root.Position).Magnitude <= Config.Photo.PoseRadius and rng:NextNumber() < Config.Photo.PoseChance then
			posed += 1
			task.spawn(function()
				task.wait(rng:NextNumber(0, 0.4))
				if Registry.face then
					Registry.face(npc, root.Position - npc.hrp.Position, 1.5)
				end
				if Registry.emote then
					Registry.emote(npc, pick(POSES))
				end
				if Registry.say and rng:NextNumber() < 0.6 then
					Registry.say(npc, pick(Config.Photo.Lines), 2.5)
				end
			end)
		end
	end
end

---------------------------------------------------------------------
-- Запросы телефона
---------------------------------------------------------------------

Registry.cityData = cityData

-- Меню отладки: сбросить прогресс игрока (вещи, достижения, счётчики)
Registry.cityReset = function(player: Player)
	local p = profileOf(player)
	p.stats, p.done, p.owned, p.equipped = {}, {}, {}, {}
	applyCosmetics(player)
	push(player)
end
-- Меню отладки: добавить к счётчику (проверка достижений)
Registry.cityAddStat = addStat
Registry.cityAction = function(player: Player, action: string, a: any)
	if action == "Job" then
		startJob(player)
	elseif action == "Buy" and type(a) == "string" then
		buy(player, a)
	elseif action == "Equip" and type(a) == "string" then
		equip(player, a)
	elseif action == "Photo" then
		photo(player)
	elseif action == "City" then
		push(player)
	end
end

---------------------------------------------------------------------
-- Игроки
---------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Head", 10)
	task.wait(0.5)
	if player.Character ~= character then
		return
	end
	applyCosmetics(player)
	for _, attribute in { "Invisible", "CubeForm" } do
		character:GetAttributeChangedSignal(attribute):Connect(function()
			task.defer(refreshVisibility, character)
		end)
	end
	local tracker = tracking[player]
	if tracker then
		tracker.lastPos = nil
	end
end

local function onPlayer(player: Player)
	tracking[player] = { flags = {}, lastPos = nil }
	task.spawn(function()
		-- Ждём, пока жители создадут кошелёк, иначе загруженные монеты перезапишутся
		local t = os.clock()
		while not Registry.getCoins and os.clock() - t < 10 do
			task.wait(0.2)
		end
		load(player)
		if player.Character then
			onCharacter(player, player.Character)
		end
		push(player)
	end)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
Players.PlayerAdded:Connect(onPlayer)

Players.PlayerRemoving:Connect(function(player)
	local job = jobs[player]
	if job and job.crate then
		job.crate:Destroy()
	end
	jobs[player] = nil
	save(player)
	profiles[player] = nil
	tracking[player] = nil
	lastPhoto[player] = nil
	pushQueued[player] = nil
end)

-- Автосохранение и сохранение при выключении сервера
task.spawn(function()
	while true do
		task.wait(120)
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
	end
end)
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(save, player)
	end
	task.wait(2)
end)

----------------------------------------------------------------------
-- 31. ServerScriptService > Script "DebugServer"
----------------------------------------------------------------------

-- Script: ServerScriptService > DebugServer
-- Меню отладки (клавиша F2) — серверная часть. Доступ только у админов (DebugConfig).
--   * Output: собирает все сообщения сервера (print, warn, ошибки скриптов) и события игры;
--   * Мир: время (час, ускорение, пауза), погода, вызов полиции, монеты, кулдауны, телепорт;
--   * Жители и машины: что делает каждый и куда идёт/едет;
--   * Проверка: ищет ошибки разметки карты и установки скриптов.
-- Каждое действие сервер проверяет сам: обычный игрок ничего не сможет вызвать.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DebugConfig"))
if not Config.Enabled then
	return
end
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local SoundConfig = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local remote = Instance.new("RemoteEvent")
remote.Name = "DebugRemote"
remote.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- Кто админ
---------------------------------------------------------------------

local admins = {} -- [player] = true

local function checkAdmin(player: Player): boolean
	if RunService:IsStudio() and Config.AllInStudio then
		return true
	end
	if table.find(Config.Admins, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		if ok and rank >= Config.GroupMinRank then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- Output сервера и события игры
---------------------------------------------------------------------

local logs = {} -- { t, kind, text }
local outbox = {} -- новые строки, которые ещё не отправлены
local KIND = {
	[Enum.MessageType.MessageOutput] = "info",
	[Enum.MessageType.MessageInfo] = "info",
	[Enum.MessageType.MessageWarning] = "warn",
	[Enum.MessageType.MessageError] = "error",
}

local function addLog(kind: string, text: string)
	local entry = { t = workspace:GetServerTimeNow(), kind = kind, text = text, src = "S" }
	table.insert(logs, entry)
	if #logs > Config.LogLimit then
		table.remove(logs, 1)
	end
	table.insert(outbox, entry)
end

for _, m in LogService:GetLogHistory() do
	addLog(KIND[m.messageType] or "info", m.message)
end
LogService.MessageOut:Connect(function(message, messageType)
	addLog(KIND[messageType] or "info", message)
end)

-- События игры (полиция, достижения, погода, время) — отдельным цветом
Registry.debugEvent = function(text: string)
	addLog("event", text)
end
workspace:GetAttributeChangedSignal("Period"):Connect(function()
	addLog("event", string.format("🕗 Период: %s (%s)", tostring(workspace:GetAttribute("Period")), tostring(workspace:GetAttribute("Hour"))))
end)
workspace:GetAttributeChangedSignal("Weather"):Connect(function()
	addLog("event", "🌦 Погода: " .. tostring(workspace:GetAttribute("WeatherName")))
end)
workspace:GetAttributeChangedSignal("Day"):Connect(function()
	addLog("event", "📅 Новый день: " .. tostring(workspace:GetAttribute("Day")))
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		if #outbox > 0 then
			local batch = outbox
			outbox = {}
			for player in pairs(admins) do
				if player.Parent then
					remote:FireClient(player, "Logs", batch)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Производительность
---------------------------------------------------------------------

local fps, frames, frameTimer = 60, 0, 0
RunService.Heartbeat:Connect(function(dt)
	frames += 1
	frameTimer += dt
	if frameTimer >= 1 then
		fps = math.floor(frames / frameTimer)
		frames, frameTimer = 0, 0
	end
end)

local function perf()
	local npcCount = 0
	for _ in pairs(Registry.npcs) do
		npcCount += 1
	end
	local root = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local vehicles = root and root:FindFirstChild(VehicleConfig.VehiclesFolder)
	return {
		fps = fps,
		memory = math.floor(game:GetService("Stats"):GetTotalMemoryUsageMb()),
		npcs = npcCount,
		cars = vehicles and #vehicles:GetChildren() or 0,
		players = #Players:GetPlayers(),
		hour = workspace:GetAttribute("Hour"),
		period = workspace:GetAttribute("Period"),
		weather = workspace:GetAttribute("WeatherName"),
		timeScale = workspace:GetAttribute("TimeScale") or 1,
		day = workspace:GetAttribute("Day"),
	}
end

---------------------------------------------------------------------
-- Проверка карты и установки
---------------------------------------------------------------------

local function partsIn(folder: Instance?): { BasePart }
	local out = {}
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	return out
end

local EXPECTED = {
	{ ReplicatedStorage, { "PoseConfig", "InvisibilityConfig", "LaserConfig", "FlightConfig", "CubeConfig", "NPCConfig", "VehicleConfig", "SoundConfig", "WeatherConfig", "CityConfig", "DebugConfig", "AbilityButton", "RigAnimator", "AbilityFx" } },
	{ ServerScriptService, { "AbilityRegistry", "NPCRegistry", "VehicleDefaults", "PoseServer", "InvisibilityServer", "LaserServer", "FlightServer", "CubeServer", "NPCDemo", "NPCServer", "NPCDoors", "DayNightServer", "TrafficServer", "WeatherServer", "PhoneServer", "CityLifeServer", "DebugServer" } },
	{ StarterPlayer:FindFirstChild("StarterPlayerScripts"), { "PoseClient", "InvisibilityClient", "LaserClient", "FlightClient", "CubeClient", "NPCClient", "VehicleClient", "PoliceDeskClient", "WeatherClient", "PhoneClient", "CityLifeClient", "DebugClient" } },
}

local function runChecks()
	local out = {}
	local function add(level: string, group: string, text: string)
		table.insert(out, { level = level, group = group, text = text })
	end

	-- Скрипты
	local missing, dupes = {}, {}
	for _, entry in EXPECTED do
		local container, names = entry[1], entry[2]
		for _, name in names do
			local count = 0
			if container then
				for _, c in container:GetChildren() do
					if c.Name == name then
						count += 1
					end
				end
			end
			if count == 0 then
				table.insert(missing, name)
			elseif count > 1 then
				table.insert(dupes, name)
			end
		end
	end
	if #missing == 0 then
		add("ok", "Скрипты", "Все скрипты на месте")
	else
		add("error", "Скрипты", "Нет скриптов: " .. table.concat(missing, ", "))
	end
	if #dupes > 0 then
		add("error", "Скрипты", "Двойные копии: " .. table.concat(dupes, ", "))
	end
	local errors = 0
	for _, l in logs do
		if l.kind == "error" then
			errors += 1
		end
	end
	add(errors == 0 and "ok" or "error", "Скрипты", errors == 0 and "Ошибок скриптов в Output нет" or ("Ошибок в Output: " .. errors .. " — открой вкладку Output"))

	-- Жители
	local npcRoot = workspace:FindFirstChild(NPCConfig.FolderName)
	if not npcRoot then
		add("warn", "Жители", "Нет папки " .. NPCConfig.FolderName .. " — работает демо-городок")
	else
		local spawns = partsIn(npcRoot:FindFirstChild("Spawns"))
		local points = partsIn(npcRoot:FindFirstChild("Points"))
		local doors = npcRoot:FindFirstChild("Doors")
		add(#spawns > 0 and "ok" or "error", "Жители", "Точек появления: " .. #spawns)
		local byActivity, homes, lieZones, zones, seats = {}, {}, {}, {}, 0
		for _, s in spawns do
			local z = s:GetAttribute("Zone")
			if z and z ~= NPCConfig.OutdoorZone then
				homes[z] = true
			end
		end
		for _, p in points do
			local z = p:GetAttribute("Zone") or NPCConfig.OutdoorZone
			zones[z] = true
			if p:IsA("Seat") then
				seats += 1
			else
				local a = p:GetAttribute("Activity")
				if type(a) ~= "string" then
					add("error", "Жители", "У точки " .. p:GetFullName() .. " нет Activity")
				else
					byActivity[a] = (byActivity[a] or 0) + 1
					if a == "Lie" then
						lieZones[z] = true
					end
				end
			end
		end
		local parts = {}
		for a, n in pairs(byActivity) do
			table.insert(parts, a .. " " .. n)
		end
		table.insert(parts, "стулья " .. seats)
		add(#points > 0 and "ok" or "error", "Жители", "Точек: " .. #points .. " (" .. table.concat(parts, ", ") .. ")")
		for home in pairs(homes) do
			if not lieZones[home] then
				add("error", "Жители", "В доме «" .. home .. "» нет точки Lie — жителям негде спать")
			end
		end
		local other = 0
		for z in pairs(zones) do
			if not homes[z] and z ~= NPCConfig.OutdoorZone then
				other += 1
			end
		end
		add(other > 0 and "ok" or "warn", "Расписание", other > 0 and ("Зон для дня (кафе, магазины...): " .. other) or "Нет зон кафе/магазинов — днём жителям некуда ходить")
		add((doors and #doors:GetChildren() > 0) and "ok" or "warn", "Жители", "Дверей: " .. (doors and #doors:GetChildren() or 0))
	end

	-- Дороги
	local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
	if not map then
		add("warn", "Дороги", "Нет папки " .. VehicleConfig.MapFolder .. " — работают демо-дороги")
	else
		local nodes = Registry.debugNodes and Registry.debugNodes() or {}
		local count, lonely, dead, turn = 0, {}, 0, 0
		for name, n in pairs(nodes) do
			count += 1
			if #n.links == 0 then
				table.insert(lonely, name)
			end
		end
		-- Связность (без учёта направления)
		local adj = {}
		for name, n in pairs(nodes) do
			adj[name] = adj[name] or {}
			for _, o in n.links do
				adj[name][o] = true
				adj[o] = adj[o] or {}
				adj[o][name] = true
			end
		end
		for name in pairs(adj) do
			local k = 0
			for _ in pairs(adj[name]) do
				k += 1
			end
			if k == 1 then
				dead += 1
			end
		end
		local first = next(adj)
		local seen, queue = {}, { first }
		if first then
			seen[first] = true
		end
		while #queue > 0 do
			local cur = table.remove(queue)
			for o in pairs(adj[cur] or {}) do
				if not seen[o] then
					seen[o] = true
					table.insert(queue, o)
				end
			end
		end
		local reached = 0
		for _ in pairs(seen) do
			reached += 1
		end
		local oneWay = 0
		for _, p in partsIn(map:FindFirstChild("Roads")) do
			if p:GetAttribute("Turnaround") == true then
				turn += 1
			end
			if p:GetAttribute("OneWay") == true then
				oneWay += 1
			end
		end
		add(count > 1 and "ok" or "error", "Дороги", "Точек дорог: " .. count)
		if #lonely > 0 then
			add("error", "Дороги", "Точки без связей: " .. table.concat(lonely, ", "))
		end
		add(reached == count and "ok" or "error", "Дороги", reached == count and "Все дороги связаны между собой" or string.format("Дороги разорваны: связано %d из %d точек", reached, count))
		add((turn + dead + oneWay) > 0 and "ok" or "warn", "Развороты", string.format("Кольцо (OneWay): %d точек, Turnaround: %d, тупиков: %d", oneWay, turn, dead))
		local uturn = 0
		for _, l in logs do
			if string.find(l.text, "Без разворота не доехать", 1, true) then
				uturn += 1
			end
		end
		add(uturn == 0 and "ok" or "error", "Развороты", uturn == 0 and "Никто не разворачивался посреди дороги" or ("Машины разворачивались посреди дороги: " .. uturn .. " раз — добавь кольцо или Turnaround"))

		-- Парковки
		local byType = {}
		for _, p in partsIn(map:FindFirstChild("Parking")) do
			local t = p:GetAttribute("Type") or "?"
			byType[t] = (byType[t] or 0) + 1
		end
		for _, t in { "Civilian", "Taxi", "Police", "Bus" } do
			local need = (VehicleConfig.Count[t] or 0) > 0
			local n = byType[t] or 0
			add((n > 0 or not need) and "ok" or "error", "Парковки", t .. ": " .. n)
		end
		local stops = partsIn(map:FindFirstChild("BusStops"))
		add(#stops >= 2 and "ok" or "error", "Автобус", "Остановок: " .. #stops .. (#stops < 2 and " (нужно минимум 2)" or ""))
		for _, s in stops do
			local node = s:GetAttribute("Node")
			if type(node) == "string" and not nodes[node] then
				add("error", "Автобус", "Остановка " .. s.Name .. ": точки дороги «" .. node .. "» нет")
			end
		end
		local calls = partsIn(map:FindFirstChild("PoliceCalls"))
		add(#calls > 0 and "ok" or "warn", "Полиция", "Вызовов (PoliceCalls): " .. #calls)
		local places = partsIn(map:FindFirstChild("Places"))
		local post = false
		for _, p in places do
			if (p:GetAttribute("PlaceName") or p.Name) == "Почта" then
				post = true
			end
		end
		add(#places > 0 and "ok" or "warn", "Места", "Мест (Places): " .. #places)
		add(post and "ok" or "warn", "Курьер", post and "Есть место «Почта»" or "Нет места «Почта» — посылки будут в случайном месте")
		local station = map:FindFirstChild("PoliceStation")
		local desk, cell, idle = 0, 0, 0
		for _, p in partsIn(station) do
			if string.find(p.Name, "^Desk") then
				desk += 1
			elseif string.find(p.Name, "^Cell") then
				cell += 1
			elseif string.find(p.Name, "^Idle") then
				idle += 1
			end
		end
		add(desk == 1 and "ok" or "error", "Полиция", "Desk (дежурный): " .. desk)
		add(cell >= 1 and "ok" or "error", "Полиция", "Cell (камера): " .. cell)
		add(idle >= 2 and "ok" or "warn", "Полиция", "Idle (кабинеты): " .. idle)
	end

	-- Шаблоны машин
	local templates = ServerStorage:FindFirstChild(VehicleConfig.TemplatesFolder)
	if not templates then
		add("warn", "Машины", "Нет ServerStorage > " .. VehicleConfig.TemplatesFolder .. " — машины-заглушки")
	else
		local byKind = {}
		for _, m in templates:GetChildren() do
			if m:IsA("Model") then
				local k = m:GetAttribute("VehicleType") or "?"
				byKind[k] = (byKind[k] or 0) + 1
				if not (m.PrimaryPart or m:FindFirstChild("Body")) then
					add("error", "Машины", m.Name .. ": нет Body")
				end
				if not m:FindFirstChild("Seat_Driver", true) then
					add("error", "Машины", m.Name .. ": нет Seat_Driver")
				end
			end
		end
		for _, k in { "Civilian", "Taxi", "Police", "Bus" } do
			add((byKind[k] or 0) > 0 and "ok" or "warn", "Машины", "Шаблонов " .. k .. ": " .. (byKind[k] or 0))
		end
	end

	-- Звуки
	for groupName, group in pairs(SoundConfig) do
		if type(group) == "table" and not group.Min then
			local empty = {}
			for key, def in pairs(group) do
				if type(def) == "table" and def.Id == "" then
					table.insert(empty, key)
				end
			end
			if #empty > 0 then
				add("warn", "Звуки", groupName .. ": без звука — " .. table.concat(empty, ", "))
			end
		end
	end

	-- Сохранение
	local ok = pcall(function()
		DataStoreService:GetDataStore("CityDebugCheck"):GetAsync("ping")
	end)
	add(ok and "ok" or "warn", "Сохранение", ok and "DataStore работает" or "DataStore недоступен (в Studio: Game Settings → Security → API Services)")

	return out
end

---------------------------------------------------------------------
-- Действия
---------------------------------------------------------------------

local function teleport(player: Player, position: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root then
		if humanoid and humanoid.SeatPart then
			humanoid.Sit = false
			task.wait(0.1)
		end
		character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	end
end

local function findTeleport(arg: string): (Vector3?, string?)
	local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local kind, name = string.match(arg, "^(%a+):?(.*)$")
	if not map then
		return nil, "Нет папки " .. VehicleConfig.MapFolder
	end
	if kind == "Desk" or kind == "Cell" then
		for _, p in partsIn(map:FindFirstChild("PoliceStation")) do
			if string.find(p.Name, "^" .. kind) then
				-- К дежурному — со стороны посетителей
				return kind == "Desk" and (p.Position + p.CFrame.LookVector * 5) or p.Position
			end
		end
		return nil, "Нет метки " .. kind
	elseif kind == "Place" then
		for _, p in partsIn(map:FindFirstChild("Places")) do
			if (p:GetAttribute("PlaceName") or p.Name) == name then
				return p.Position
			end
		end
		return nil, "Нет места " .. name
	elseif kind == "Stop" then
		local order = tonumber(name)
		for _, p in partsIn(map:FindFirstChild("BusStops")) do
			if p:GetAttribute("Order") == order or p.Name == name then
				return p.Position
			end
		end
		return nil, "Нет остановки " .. name
	elseif kind == "Node" then
		local nodes = Registry.debugNodes and Registry.debugNodes() or {}
		return nodes[name] and nodes[name].pos or nil, "Нет точки " .. name
	end
	return nil, "Не знаю, куда: " .. arg
end

local COOLDOWNS = { "InvisibilityConfig", "LaserConfig", "FlightConfig", "CubeConfig" }

local ACTIONS = {}

function ACTIONS.SetHour(player, arg)
	local h = tonumber(arg)
	if not h then
		return "Нужен час"
	end
	Lighting.ClockTime = h % 24
	return string.format("Время: %02d:%02d", math.floor(h), math.floor((h % 1) * 60))
end
function ACTIONS.TimeScale(player, arg)
	local x = tonumber(arg) or 1
	workspace:SetAttribute("TimeScale", x)
	return x == 0 and "Время на паузе" or ("Скорость времени ×" .. x)
end
function ACTIONS.Weather(player, arg)
	workspace:SetAttribute("ForceWeather", tostring(arg))
	return "Погода: " .. tostring(arg)
end
function ACTIONS.PoliceCall(player, arg)
	if not Registry.debugPoliceCall then
		return "Транспорт не запущен"
	end
	return Registry.debugPoliceCall(player, tonumber(arg) or 1)
end
function ACTIONS.Coins(player, arg)
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild(NPCConfig.CurrencyName)
	if not coins then
		return "Нет монет"
	end
	coins.Value += tonumber(arg) or 100
	return "Монет: " .. coins.Value
end
function ACTIONS.ResetCooldowns(player)
	for _, name in COOLDOWNS do
		local module = ReplicatedStorage:FindFirstChild(name)
		if module then
			player:SetAttribute(require(module).CooldownAttribute, 0)
		end
	end
	return "Кулдауны сброшены"
end
function ACTIONS.ResetCity(player)
	if Registry.cityReset then
		Registry.cityReset(player)
		return "Прогресс сброшен"
	end
	return "CityLifeServer не запущен"
end
function ACTIONS.AddStat(player, arg)
	local stat, n = string.match(tostring(arg), "^(%a+):?(%d*%.?%d*)$")
	if Registry.cityAddStat and stat then
		Registry.cityAddStat(player, stat, tonumber(n) or 1)
		return "+" .. (tonumber(n) or 1) .. " к " .. stat
	end
	return "Не получилось"
end
function ACTIONS.StartJob(player)
	if Registry.cityAction then
		Registry.cityAction(player, "Job")
		return "Заказ курьера"
	end
	return "CityLifeServer не запущен"
end
function ACTIONS.Heal(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	return "Здоровье восстановлено"
end
function ACTIONS.Teleport(player, arg)
	local pos, err = findTeleport(tostring(arg))
	if pos then
		teleport(player, pos)
		return "Телепорт: " .. tostring(arg)
	end
	return err
end
function ACTIONS.TeleportTo(player, arg)
	if typeof(arg) == "Instance" and arg:IsDescendantOf(workspace) then
		local pivot = arg:IsA("Model") and arg:GetPivot() or (arg :: BasePart).CFrame
		teleport(player, pivot.Position + pivot.LookVector * 5)
		return "Телепорт к " .. arg.Name
	end
	return "Объект не найден"
end

---------------------------------------------------------------------
-- Отметки «проверено» (сохраняются)
---------------------------------------------------------------------

local testStore = nil
pcall(function()
	testStore = DataStoreService:GetDataStore("CityDebug_v1")
end)
local tested = {} -- [player] = { [key] = "ok"/"bug" }

local function loadTested(player: Player)
	local data = {}
	if testStore then
		local ok, result = pcall(function()
			return testStore:GetAsync("tests_" .. player.UserId)
		end)
		if ok and type(result) == "table" then
			data = result
		end
	end
	tested[player] = data
	return data
end

local function saveTested(player: Player)
	if testStore and tested[player] then
		pcall(function()
			testStore:SetAsync("tests_" .. player.UserId, tested[player])
		end)
	end
end

---------------------------------------------------------------------
-- Запросы клиента
---------------------------------------------------------------------

local lastAction = {}

remote.OnServerEvent:Connect(function(player: Player, request: any, a: any, b: any)
	if not admins[player] then
		return
	end
	if request == "Hello" then
		remote:FireClient(player, "Hello", {
			logs = logs,
			tested = tested[player] or loadTested(player),
			placeNames = (function()
				local names = {}
				local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
				for _, p in partsIn(map and map:FindFirstChild("Places")) do
					table.insert(names, p:GetAttribute("PlaceName") or p.Name)
				end
				return names
			end)(),
		})
	elseif request == "Snapshot" then
		remote:FireClient(player, "Snapshot", {
			npcs = Registry.debugNPCs and Registry.debugNPCs() or {},
			cars = Registry.debugCars and Registry.debugCars() or {},
			perf = perf(),
		})
	elseif request == "Nodes" then
		remote:FireClient(player, "Nodes", Registry.debugNodes and Registry.debugNodes() or {})
	elseif request == "Check" then
		remote:FireClient(player, "Check", runChecks())
	elseif request == "Action" and type(a) == "string" and ACTIONS[a] then
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.2 then
			return
		end
		lastAction[player] = now
		local ok, result = pcall(ACTIONS[a], player, b)
		local text = ok and tostring(result) or ("Ошибка: " .. tostring(result))
		addLog("debug", "[Debug] " .. player.Name .. ": " .. a .. " → " .. text)
		remote:FireClient(player, "Result", text)
	elseif request == "Tested" and type(a) == "string" and #a < 120 then
		local t = tested[player] or loadTested(player)
		t[a] = (b == "ok" or b == "bug") and b or nil
		task.spawn(saveTested, player)
	end
end)

local function onPlayer(player: Player)
	if checkAdmin(player) then
		admins[player] = true
		player:SetAttribute("DebugAdmin", true)
	end
end
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	admins[player] = nil
	tested[player] = nil
	lastAction[player] = nil
end)

----------------------------------------------------------------------
-- 32. StarterPlayer → StarterPlayerScripts > LocalScript "PoseClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > PoseClient
-- Клиент:
--   1) ловит кнопки (клавиатура, геймпад, кнопки на телефоне) и шлёт запрос серверу;
--   2) проигрывает процедурные анимации поз для ВСЕХ персонажей на сервере
--      (поза берётся из атрибута персонажа, поэтому все видят, кто сидит/лежит).
--
-- Анимации сделаны кодом (через Motor6D.Transform), поэтому их не нужно
-- загружать на Roblox и вставлять ID — работают сразу, для R15 и R6.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PoseConfig = require(ReplicatedStorage:WaitForChild("PoseConfig"))
local remote = ReplicatedStorage:WaitForChild(PoseConfig.RemoteName)

local player = Players.LocalPlayer
local ATTR = PoseConfig.AttributeName
local IDENTITY = CFrame.identity

-- Логические суставы -> {часть тела, имя Motor6D}
local JOINTS = {
	R15 = {
		Root = { "LowerTorso", "Root" },
		Waist = { "UpperTorso", "Waist" },
		Neck = { "Head", "Neck" },
		LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
		RightShoulder = { "RightUpperArm", "RightShoulder" },
		LeftElbow = { "LeftLowerArm", "LeftElbow" },
		RightElbow = { "RightLowerArm", "RightElbow" },
		LeftHip = { "LeftUpperLeg", "LeftHip" },
		RightHip = { "RightUpperLeg", "RightHip" },
		LeftKnee = { "LeftLowerLeg", "LeftKnee" },
		RightKnee = { "RightLowerLeg", "RightKnee" },
		LeftAnkle = { "LeftFoot", "LeftAnkle" },
		RightAnkle = { "RightFoot", "RightAnkle" },
	},
	R6 = {
		Root = { "HumanoidRootPart", "RootJoint" },
		Neck = { "Torso", "Neck" },
		LeftShoulder = { "Torso", "Left Shoulder" },
		RightShoulder = { "Torso", "Right Shoulder" },
		LeftHip = { "Torso", "Left Hip" },
		RightHip = { "Torso", "Right Hip" },
	},
}

-- Состояния Humanoid, в которых позу принять нельзя / нужно сразу встать
local BLOCKING_STATES = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

local controllers = {} -- [character] = controller
local warnedRig = {} -- [character] = true, чтобы не спамить в Output

-- Сустав: старый Motor6D или новый AnimationConstraint (Avatar Joint Upgrade).
-- У обоих есть C0 и Transform, поэтому математика одинаковая.
local function isJoint(obj: Instance): boolean
	return obj:IsA("Motor6D") or obj:IsA("AnimationConstraint")
end

local function debugPrint(...)
	if PoseConfig.Debug then
		print("[Pose]", ...)
	end
end
local updateLabels -- объявлена ниже (подписи кнопок и подсказка)

---------------------------------------------------------------------
-- Математика поз
---------------------------------------------------------------------

local function angles(v: Vector3): CFrame
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

local function buildRig(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		return nil
	end

	local rigType = humanoid.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"
	local motors = {}
	for name, path in pairs(JOINTS[rigType]) do
		local part = character:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		if motor and isJoint(motor) then
			motors[name] = motor
		end
	end
	if not motors.Root then
		if not warnedRig[character] then
			warnedRig[character] = true
			local found = {}
			for _, d in character:GetDescendants() do
				if d:IsA("JointInstance") or d:IsA("Constraint") then
					table.insert(found, d.ClassName .. " " .. d:GetFullName())
				end
			end
			warn("[Pose] Не найден корневой сустав у", character.Name, rigType, "\nНайдены суставы:\n" .. table.concat(found, "\n"))
		end
		return nil
	end
	local count = 0
	for _ in pairs(motors) do
		count += 1
	end
	debugPrint(character.Name, rigType, "суставов найдено:", count, "тип:", motors.Root.ClassName)

	local legLength
	if rigType == "R15" then
		legLength = humanoid.HipHeight
	else
		local leg = character:FindFirstChild("Left Leg")
		legLength = leg and leg.Size.Y or 2
	end
	if legLength <= 0 then
		legLength = 2
	end

	return {
		rigType = rigType,
		motors = motors,
		hrpHalf = hrp.Size.Y / 2,
		legLength = legLength,
		scale = legLength / 2,
	}
end

-- Кадры позы. Для обычных суставов — поворот (в пространстве родительской части),
-- для Root — полное смещение тела в пространстве HumanoidRootPart.
local function buildFrames(rig, state: string)
	local frames = {}
	local pose = PoseConfig.Poses[state]
	if not pose then
		return frames -- «Стоя» = все суставы в нуле, дальше работает обычный Animate
	end

	local overrides = pose[rig.rigType] or {}
	local joints = pose.Joints or {}
	for name in pairs(rig.motors) do
		if name ~= "Root" then
			local a = overrides[name] or joints[name]
			if a then
				frames[name] = angles(a)
			end
		end
	end

	local hipHeight = overrides.HipHeight or pose.HipHeight or 1
	local rootAngles = overrides.Root or pose.Root or Vector3.zero
	local shift = (overrides.Shift or pose.Shift or Vector3.zero) * rig.scale
	local drop = Vector3.new(0, (hipHeight - 1) * rig.legLength, 0)
	local pivot = Vector3.new(0, -rig.hrpHalf, 0) -- примерно уровень таза

	frames.Root = CFrame.new(shift + drop) * CFrame.new(pivot) * angles(rootAngles) * CFrame.new(-pivot)
	return frames
end

local function applyFrame(name: string, motor: any, frame: CFrame)
	-- Переводим желаемый поворот в систему координат сустава (учитывает C0 у R6)
	if name == "Root" then
		local c0 = motor.C0
		motor.Transform = c0:Inverse() * frame * c0
	else
		local q = motor.C0.Rotation
		motor.Transform = q:Inverse() * frame * q
	end
end

---------------------------------------------------------------------
-- Контроллер одного персонажа
---------------------------------------------------------------------

local function ensureRig(ctrl)
	local rig = ctrl.rig
	if rig then
		for _, motor in pairs(rig.motors) do
			if not motor:IsDescendantOf(ctrl.character) then
				rig = nil
				break
			end
		end
	end
	if not rig then
		rig = buildRig(ctrl.character)
		ctrl.rig = rig
		if rig then
			ctrl.toFrames = buildFrames(rig, ctrl.state)
		end
	end
	return rig
end

local function attributeState(ctrl): string
	local s = ctrl.character:GetAttribute(ATTR)
	return PoseConfig.IsValidState(s) and s or "Stand"
end

-- Для своего персонажа поза меняется мгновенно (предсказание),
-- не дожидаясь ответа сервера.
local function effectiveState(ctrl): string
	local attr = attributeState(ctrl)
	if ctrl.predicted then
		if os.clock() < ctrl.predictExpire and attr ~= ctrl.predicted then
			return ctrl.predicted
		end
		ctrl.predicted = nil
	end
	return attr
end

local function setState(ctrl, state: string)
	if ctrl.state == state then
		return
	end
	ctrl.fromState = ctrl.state
	ctrl.state = state
	ctrl.fromFrames = ctrl.active and table.clone(ctrl.current) or {}
	ctrl.alpha = 0
	ctrl.active = true
	local rig = ensureRig(ctrl)
	ctrl.toFrames = rig and buildFrames(rig, state) or {}
	debugPrint(ctrl.character.Name, ctrl.fromState, "->", state, rig and "" or "(суставы не найдены!)")
end

local function breathOf(state: string): number
	local pose = PoseConfig.Poses[state]
	return pose and pose.Breath or 0
end

local function step(ctrl, dt: number, now: number)
	local state = effectiveState(ctrl)
	if state ~= ctrl.state then
		setState(ctrl, state)
		if ctrl.isLocal then
			updateLabels()
		end
	end
	if not ctrl.active then
		return
	end

	local rig = ensureRig(ctrl)
	if not rig then
		return
	end

	ctrl.alpha = math.min(1, ctrl.alpha + dt / PoseConfig.TransitionTime)
	local a = smoothstep(ctrl.alpha)

	-- Лёгкое «дыхание», чтобы поза не выглядела замороженной
	local breath = breathOf(ctrl.state) * a + breathOf(ctrl.fromState) * (1 - a)
	local breathJoint = rig.motors.Waist and "Waist" or "Neck"
	local breathCF = CFrame.Angles(math.rad(math.sin(now * 2.2 + ctrl.phase) * breath), 0, 0)

	for name, motor in pairs(rig.motors) do
		local frame = (ctrl.fromFrames[name] or IDENTITY):Lerp(ctrl.toFrames[name] or IDENTITY, a)
		ctrl.current[name] = frame
		if name == breathJoint and breath > 0 then
			frame = frame * breathCF
		end
		applyFrame(name, motor, frame)
	end

	-- Камера опускается вместе с головой
	if ctrl.isLocal then
		local headRest = Vector3.new(0, 1.5 * rig.scale, 0)
		local rootFrame = ctrl.current.Root or IDENTITY
		ctrl.humanoid.CameraOffset = rootFrame * headRest - headRest
	end

	if ctrl.alpha >= 1 and ctrl.state == "Stand" then
		-- Полностью встали — отдаём суставы обратно стандартным анимациям
		ctrl.active = false
		ctrl.current = {}
		if ctrl.isLocal then
			ctrl.humanoid.CameraOffset = Vector3.zero
		end
	end
end

local function removeController(character: Model)
	local ctrl = controllers[character]
	if not ctrl then
		return
	end
	controllers[character] = nil
	for _, conn in ctrl.connections do
		conn:Disconnect()
	end
end

local function addController(character: Model)
	if controllers[character] then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local ctrl = {
		character = character,
		humanoid = humanoid,
		isLocal = Players:GetPlayerFromCharacter(character) == player,
		rig = nil,
		state = "Stand",
		fromState = "Stand",
		fromFrames = {},
		toFrames = {},
		current = {},
		alpha = 1,
		active = false,
		phase = math.random() * math.pi * 2,
		predicted = nil,
		predictExpire = 0,
		connections = {},
	}
	controllers[character] = ctrl

	local function invalidateRig()
		ctrl.rig = nil
	end
	table.insert(ctrl.connections, character.DescendantAdded:Connect(function(d)
		if isJoint(d) then
			invalidateRig()
		end
	end))
	table.insert(ctrl.connections, humanoid:GetPropertyChangedSignal("HipHeight"):Connect(invalidateRig))
	table.insert(ctrl.connections, humanoid.Died:Connect(function()
		removeController(character)
	end))
	table.insert(ctrl.connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			removeController(character)
		end
	end))
end

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(function(character)
		task.spawn(addController, character)
	end)
	if p.Character then
		task.spawn(addController, p.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end

-- Жители города (NPC) тоже умеют сидеть и лежать: их поза — тот же атрибут Pose
local CollectionService = game:GetService("CollectionService")
local NPC_TAG = "NPC"
for _, npc in CollectionService:GetTagged(NPC_TAG) do
	task.spawn(addController, npc)
end
CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(function(npc)
	task.spawn(addController, npc)
end)

RunService.PreSimulation:Connect(function(dt)
	-- PreSimulation идёт ПОСЛЕ стандартных анимаций, поэтому наша поза их перекрывает
	local now = os.clock()
	for _, ctrl in pairs(controllers) do
		step(ctrl, dt, now)
	end
end)

---------------------------------------------------------------------
-- Управление (только свой персонаж)
---------------------------------------------------------------------

local lastRequest = 0
local hintLabel: TextLabel? = nil

local function localController()
	local character = player.Character
	return character and controllers[character]
end

local function canStartPose(humanoid: Humanoid): boolean
	return humanoid.Health > 0
		and not humanoid.Sit
		and humanoid.FloorMaterial ~= Enum.Material.Air
		and not BLOCKING_STATES[humanoid:GetState()]
end

function updateLabels()
	local ctrl = localController()
	local state = ctrl and effectiveState(ctrl) or "Stand"
	local down = PoseConfig.GetNextState(state, "Down")
	local up = PoseConfig.GetNextState(state, "Up")
	ContextActionService:SetTitle("PoseDown", down ~= state and PoseConfig.ActionNames[down] or "—")
	ContextActionService:SetTitle("PoseUp", up ~= state and PoseConfig.ActionNames[up] or "—")

	if hintLabel then
		local downKey = PoseConfig.Keys.Down[1].Name
		local upKey = PoseConfig.Keys.Up[1].Name
		local parts = { PoseConfig.StateNames[state] or state }
		if down ~= state then
			table.insert(parts, string.format("[%s] %s", downKey, PoseConfig.ActionNames[down]))
		end
		if up ~= state then
			table.insert(parts, string.format("[%s] %s", upKey, PoseConfig.ActionNames[up]))
		end
		hintLabel.Text = table.concat(parts, "   •   ")
	end
end

local function request(direction: string, force: boolean?)
	local ctrl = localController()
	if not ctrl then
		return
	end
	local now = os.clock()
	if not force and now - lastRequest < PoseConfig.ClientCooldown then
		return
	end

	local current = effectiveState(ctrl)
	local nextState = PoseConfig.GetNextState(current, direction)
	if nextState == current then
		return
	end
	if current == "Stand" and not canStartPose(ctrl.humanoid) then
		return
	end
	-- Во время полёта и в форме куба позы недоступны
	if ctrl.character:GetAttribute("Flying") == true or ctrl.character:GetAttribute("CubeForm") == true then
		return
	end

	lastRequest = now
	ctrl.predicted = nextState
	ctrl.predictExpire = now + PoseConfig.PredictionTimeout
	remote:FireServer(direction)
	updateLabels()
end

local function onAction(actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	request(actionName == "PoseDown" and "Down" or "Up")
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("PoseDown", onAction, true, table.unpack(PoseConfig.Keys.Down))
ContextActionService:BindAction("PoseUp", onAction, true, table.unpack(PoseConfig.Keys.Up))
ContextActionService:SetPosition("PoseDown", UDim2.new(1, -170, 1, -150))
ContextActionService:SetPosition("PoseUp", UDim2.new(1, -170, 1, -210))

-- Пробел в позе = встать
UserInputService.JumpRequest:Connect(function()
	if not PoseConfig.JumpToStand then
		return
	end
	local ctrl = localController()
	if ctrl and effectiveState(ctrl) ~= "Stand" then
		request("Stand", true)
	end
end)

-- Если персонажа столкнули / он упал / сел на Seat — выходим из позы
local function hookLocalCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Dead then
			return
		end
		local ctrl = controllers[character]
		if ctrl and BLOCKING_STATES[newState] and effectiveState(ctrl) ~= "Stand" then
			request("Stand", true)
		end
	end)
	character:GetAttributeChangedSignal(ATTR):Connect(updateLabels)
	updateLabels()
end

player.CharacterAdded:Connect(hookLocalCharacter)
if player.Character then
	task.spawn(hookLocalCharacter, player.Character)
end

-- Подсказка внизу экрана (только для клавиатуры)
if PoseConfig.ShowHint and UserInputService.KeyboardEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "PoseHint"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -12)
	label.Size = UDim2.fromOffset(0, 30)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.45
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	hintLabel = label
	updateLabels()
end

----------------------------------------------------------------------
-- 33. StarterPlayer → StarterPlayerScripts > LocalScript "InvisibilityClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > InvisibilityClient
-- Клиент способности «Невидимость»:
--   * себя видишь полупрозрачным «стеклом» с голубым оттенком и лёгкой синевой на экране;
--   * другие невидимые игроки скрыты полностью (тело, ник, полоска здоровья, звуки);
--   * при выходе из невидимости персонажа на 1,5 сек обводит красный контур;
--   * анимации: исчезновение (руки крест-накрест и резкий взмах) и появление (силовая стойка),
--     вспышки частиц;
--   * кнопка с таймером кулдауна и полоской оставшейся невидимости.
-- Этот же скрипт прячет тело персонажа, когда он превращается в куб (CubeConfig).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("InvisibilityConfig"))
local CubeConfig = require(ReplicatedStorage:WaitForChild("CubeConfig"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))
local AbilityFx = require(ReplicatedStorage:WaitForChild("AbilityFx"))
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName)

local CUBE_FADE_TIME = 0.15

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------
-- Эффекты на персонажах
---------------------------------------------------------------------

local visuals = {} -- [character] = состояние эффекта

local screenTint = Instance.new("ColorCorrectionEffect")
screenTint.Name = "InvisibilityTint"
screenTint.Enabled = false
screenTint.Parent = Lighting

local function isFadeable(inst: Instance): boolean
	-- Сам куб и его лицо не трогаем
	if inst.Name == CubeConfig.PartName or (inst.Parent and inst.Parent.Name == CubeConfig.PartName) then
		return false
	end
	if inst:IsA("BasePart") then
		return inst.Name ~= "HumanoidRootPart"
	end
	return inst:IsA("Decal") -- Texture тоже наследуется от Decal
end

local function capture(v, inst: Instance)
	if v.saved[inst] or v.sounds[inst] then
		return
	end
	if isFadeable(inst) then
		local orig = { Transparency = (inst :: any).Transparency }
		if inst:IsA("BasePart") then
			orig.Material = inst.Material
			orig.Color = inst.Color
		end
		v.saved[inst] = orig
	elseif inst:IsA("Sound") and not v.isLocal and Config.HideSounds then
		v.sounds[inst] = inst.Volume
	end
end

local function restoreOne(v, inst: Instance)
	local orig = v.saved[inst]
	if orig then
		v.saved[inst] = nil
		local any = inst :: any
		any.Transparency = orig.Transparency
		if orig.Material then
			any.Material = orig.Material
			any.Color = orig.Color
		end
	end
	local volume = v.sounds[inst]
	if volume then
		v.sounds[inst] = nil
		local sound = inst :: Sound
		sound.Volume = volume
	end
end

-- a: 0 = обычный вид, 1 = полностью применён эффект.
-- Куб: тело скрыто у всех. Невидимость: себе — стекло, другим — пусто.
local function applyAlpha(v, a: number)
	local glass = v.isLocal and v.invisible and not v.cube
	for inst, orig in pairs(v.saved) do
		local any = inst :: any
		local goal = glass and math.max(orig.Transparency, Config.SelfTransparency) or 1
		any.Transparency = orig.Transparency + (goal - orig.Transparency) * a
		if orig.Material then
			if glass and a > 0 then
				any.Material = Config.SelfMaterial
				any.Color = orig.Color:Lerp(Config.SelfTint, Config.SelfTintStrength * a)
			else
				any.Material = orig.Material
				any.Color = orig.Color
			end
		end
	end
	local muted = v.invisible and not v.isLocal
	for sound, volume in pairs(v.sounds) do
		sound.Volume = muted and volume * (1 - a) or volume
	end
	if not v.isLocal and Config.HideName then
		if v.invisible and a > 0 and v.savedDisplay == nil then
			v.savedDisplay = v.humanoid.DisplayDistanceType
			v.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		elseif not v.invisible and v.savedDisplay ~= nil then
			v.humanoid.DisplayDistanceType = v.savedDisplay
			v.savedDisplay = nil
		end
	end
	if v.isLocal then
		local tint = glass and a or 0
		screenTint.Enabled = tint > 0
		screenTint.TintColor = WHITE:Lerp(Config.ScreenTint, tint)
		screenTint.Saturation = Config.ScreenSaturation * tint
	end
end

local function begin(v)
	if v.begun then
		return
	end
	v.begun = true
	for _, d in v.character:GetDescendants() do
		capture(v, d)
	end
end

local function restoreAll(v)
	for inst in pairs(v.saved) do
		restoreOne(v, inst)
	end
	for sound in pairs(v.sounds) do
		restoreOne(v, sound)
	end
	if v.savedDisplay then
		v.humanoid.DisplayDistanceType = v.savedDisplay
		v.savedDisplay = nil
	end
	if v.isLocal then
		screenTint.Enabled = false
	end
	v.begun = false
end

---------------------------------------------------------------------
-- Анимации исчезновения и появления
---------------------------------------------------------------------

-- Исчезновение, фаза 1: руки крест-накрест, лёгкое приседание
local VANISH_CROSS = {
	Waist = Vector3.new(-12, 0, 0),
	Neck = Vector3.new(-12, 0, 0),
	LeftShoulder = Vector3.new(75, 0, 38),
	RightShoulder = Vector3.new(75, 0, -38),
	LeftElbow = Vector3.new(95, 0, 0),
	RightElbow = Vector3.new(95, 0, 0),
	LeftHip = Vector3.new(15, 0, -4),
	RightHip = Vector3.new(15, 0, 4),
	LeftKnee = Vector3.new(-25, 0, 0),
	RightKnee = Vector3.new(-25, 0, 0),
}
-- Фаза 2: резкий взмах руками в стороны
local VANISH_FLING = {
	Waist = Vector3.new(10, 0, 0),
	Neck = Vector3.new(12, 0, 0),
	LeftShoulder = Vector3.new(25, 0, -75),
	RightShoulder = Vector3.new(25, 0, 75),
	LeftElbow = Vector3.new(10, 0, 0),
	RightElbow = Vector3.new(10, 0, 0),
}
-- Появление: силовая стойка, грудь вперёд, кулаки сжаты
local APPEAR = {
	Waist = Vector3.new(12, 0, 0),
	Neck = Vector3.new(10, 0, 0),
	LeftShoulder = Vector3.new(-10, 0, -30),
	RightShoulder = Vector3.new(-10, 0, 30),
	LeftElbow = Vector3.new(35, 0, 0),
	RightElbow = Vector3.new(35, 0, 0),
	LeftHip = Vector3.new(0, 0, -7),
	RightHip = Vector3.new(0, 0, 7),
}

local VANISH_TIME = 0.65
local APPEAR_TIME = 0.75

local function vanishLayer()
	local start = os.clock()
	return {
		Priority = 30,
		Update = function(rig, _, now)
			local elapsed = now - start
			if elapsed >= VANISH_TIME then
				return nil, 0, true
			end
			local p = elapsed / VANISH_TIME
			local pose = RigAnimator.Blend(VANISH_CROSS, VANISH_FLING, RigAnimator.Smooth((p - 0.35) / 0.2))
			local frames = RigAnimator.Frames(rig, pose)
			local crouch = 1 - 0.08 * (1 - RigAnimator.Smooth((p - 0.35) / 0.2))
			frames.Root = RigAnimator.RootFrame(rig, crouch)
			return frames, RigAnimator.Envelope(elapsed, VANISH_TIME, 0.1, 0.2)
		end,
	}
end

local function appearLayer()
	local start = os.clock()
	return {
		Priority = 30,
		Update = function(rig, _, now)
			local elapsed = now - start
			if elapsed >= APPEAR_TIME then
				return nil, 0, true
			end
			return RigAnimator.Frames(rig, APPEAR), RigAnimator.Envelope(elapsed, APPEAR_TIME, 0.12, 0.3)
		end,
	}
end

local function burstAt(character: Model, color: Color3)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		AbilityFx.Burst(hrp.Position, {
			Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
			Count = 35,
			Speed = NumberRange.new(6, 14),
			Size = 0.6,
			Lifetime = NumberRange.new(0.4, 0.9),
			Drag = 4,
			Acceleration = Vector3.new(0, 6, 0),
			Light = 12,
		})
	end
end

local function flash(character: Model)
	local h = Instance.new("Highlight")
	h.Name = "InvisibilityFlash"
	h.Adornee = character
	h.FillColor = Config.FlashColor
	h.OutlineColor = Config.FlashColor
	h.FillTransparency = Config.FlashFillTransparency
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = character

	-- Сначала держится, потом плавно гаснет
	local info = TweenInfo.new(
		Config.FlashTime * 0.6,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		0,
		false,
		Config.FlashTime * 0.4
	)
	TweenService:Create(h, info, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(h, Config.FlashTime + 0.1)
end

local function onAttributeChanged(v)
	local invisible = v.character:GetAttribute(Config.ActiveAttribute) == true
	local cube = v.character:GetAttribute(CubeConfig.ActiveAttribute) == true
	local wasInvisible = v.invisible

	v.invisible = invisible
	v.cube = cube
	v.fadeTime = cube and CUBE_FADE_TIME or Config.FadeTime

	if invisible and not wasInvisible then
		RigAnimator.SetLayer(v.character, "InvisibilityVanish", vanishLayer())
		burstAt(v.character, Config.SelfTint)
		if v.isLocal then
			AbilityFx.Shake(0.015, 0.3)
		end
	elseif not invisible and wasInvisible and not cube then
		flash(v.character)
		RigAnimator.SetLayer(v.character, "InvisibilityAppear", appearLayer())
		burstAt(v.character, Config.FlashColor)
	end

	local wanted = (invisible or cube) and 1 or 0
	if wanted == 1 then
		begin(v)
	end
	v.target = wanted
	if v.begun then
		applyAlpha(v, v.alpha)
	end
end

local function removeVisual(character: Model)
	local v = visuals[character]
	if not v then
		return
	end
	visuals[character] = nil
	for _, conn in v.connections do
		conn:Disconnect()
	end
	restoreAll(v)
end

local function addVisual(character: Model)
	if visuals[character] then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local v = {
		character = character,
		humanoid = humanoid,
		isLocal = Players:GetPlayerFromCharacter(character) == player,
		alpha = 0,
		target = 0,
		fadeTime = Config.FadeTime,
		invisible = false,
		cube = false,
		begun = false,
		saved = {},
		sounds = {},
		savedDisplay = nil,
		connections = {},
	}
	visuals[character] = v

	-- Новые части (аксессуары, взятый в руки инструмент) тоже прячем
	table.insert(v.connections, character.DescendantAdded:Connect(function(d)
		if v.begun then
			capture(v, d)
			applyAlpha(v, v.alpha)
		end
	end))
	-- Убранный инструмент возвращаем в нормальный вид
	table.insert(v.connections, character.DescendantRemoving:Connect(function(d)
		restoreOne(v, d)
	end))
	table.insert(v.connections, character:GetAttributeChangedSignal(Config.ActiveAttribute):Connect(function()
		onAttributeChanged(v)
	end))
	table.insert(v.connections, character:GetAttributeChangedSignal(CubeConfig.ActiveAttribute):Connect(function()
		onAttributeChanged(v)
	end))
	table.insert(v.connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			removeVisual(character)
		end
	end))

	onAttributeChanged(v)
end

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(function(character)
		task.spawn(addVisual, character)
	end)
	if p.Character then
		task.spawn(addVisual, p.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end

---------------------------------------------------------------------
-- Кнопка и таймеры
---------------------------------------------------------------------

local AbilityButton = require(ReplicatedStorage:WaitForChild("AbilityButton"))

local lastRequest = 0

local function request()
	local t = os.clock()
	if t - lastRequest < 0.25 then
		return
	end
	lastRequest = t
	remote:FireServer()
end

local button = AbilityButton.new({
	Name = Config.ButtonText,
	Icon = "👻",
	KeyName = Config.Keys[1].Name,
	Slot = Config.ButtonSlot,
	Duration = Config.Duration,
	Cooldown = Config.Cooldown,
	ActiveColor = Config.ActiveColor,
	OnActivate = request,
})

ContextActionService:BindAction("Invisibility", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		request()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, table.unpack(Config.Keys))

---------------------------------------------------------------------
-- Кадровый цикл: плавность эффектов и таймеры
---------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	for _, v in pairs(visuals) do
		local step = dt / v.fadeTime
		if v.alpha ~= v.target then
			if v.target > v.alpha then
				v.alpha = math.min(v.target, v.alpha + step)
			else
				v.alpha = math.max(v.target, v.alpha - step)
			end
			applyAlpha(v, v.alpha)
			if v.alpha == 0 and v.target == 0 then
				restoreAll(v)
			end
		end
	end

	local now = serverNow()
	local character = player.Character
	local active = character ~= nil and character:GetAttribute(Config.ActiveAttribute) == true
	local activeLeft = active and math.max(0, (character:GetAttribute(Config.UntilAttribute) or 0) - now) or nil
	local cooldownLeft = math.max(0, (player:GetAttribute(Config.CooldownAttribute) or 0) - now)
	button:Update(activeLeft, cooldownLeft)
end)

----------------------------------------------------------------------
-- 34. StarterPlayer → StarterPlayerScripts > LocalScript "LaserClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > LaserClient
-- Клиент способности «Лазеры из глаз»:
--   * рисует лучи из глаз у ВСЕХ стреляющих игроков (их видят все);
--   * светящиеся глаза, искры и свет в точке попадания, «мерцание» луча;
--   * свой прицел — мышка (на телефоне — центр экрана), персонаж разворачивается к цели;
--   * анимация «силовой стойки», голова следит за целью, лёгкая отдача;
--   * тряска камеры и раскалённые следы на поверхностях;
--   * в форме куба лазеры бьют из глаз куба;
--   * кнопка с таймером кулдауна и полоской оставшегося времени.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LaserConfig"))
local CubeConfig = require(ReplicatedStorage:WaitForChild("CubeConfig"))
local AbilityButton = require(ReplicatedStorage:WaitForChild("AbilityButton"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))
local AbilityFx = require(ReplicatedStorage:WaitForChild("AbilityFx"))
local Debris = game:GetService("Debris")
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName)
local aimRemote = ReplicatedStorage:WaitForChild(Config.AimRemoteName)

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------
-- Эффекты лучей
---------------------------------------------------------------------

local effects = {} -- [character] = эффект

local function makeBeam(a0: Attachment, a1: Attachment, color: Color3, parent: Instance): Beam
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = 0
	beam.Width1 = 0
	beam.Transparency = NumberSequence.new(0)
	beam.Parent = parent
	return beam
end

local function createEffect(character: Model)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end

	local instances = {}
	local function track(inst)
		table.insert(instances, inst)
		return inst
	end

	-- Глаза: чуть выше центра головы, на передней поверхности.
	-- В форме куба — глаза на лице куба.
	local cube = character:FindFirstChild(CubeConfig.PartName)
	local host = head
	local eyeX, eyeY, eyeZ
	if cube and cube:IsA("BasePart") and character:GetAttribute(CubeConfig.ActiveAttribute) == true then
		host = cube
		local size = cube:GetAttribute("BaseSize") or cube.Size.Y
		eyeX, eyeY, eyeZ = size * 0.18, size * 0.1, -size * 0.5
	else
		local size = head.Size
		eyeX, eyeY, eyeZ = size.Y * 0.2, size.Y * 0.1, -size.Z * 0.5
	end
	local eyes = {}
	for i, side in { -1, 1 } do
		local eye = track(Instance.new("Attachment"))
		eye.Name = "LaserEye" .. i
		eye.Position = Vector3.new(eyeX * side, eyeY, eyeZ)
		eye.Parent = host
		local light = Instance.new("PointLight")
		light.Color = Config.Color
		light.Range = Config.EyeLightRange
		light.Brightness = 0
		light.Parent = eye
		eyes[i] = { attachment = eye, light = light }
	end

	-- Точка попадания: невидимая локальная деталь со светом и искрами
	local target = track(Instance.new("Part"))
	target.Name = "LaserImpact"
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Transparency = 1
	target.Size = Vector3.new(0.2, 0.2, 0.2)
	target.CFrame = head.CFrame
	target.Parent = workspace

	local hit = Instance.new("Attachment")
	hit.Parent = target

	local impactLight = Instance.new("PointLight")
	impactLight.Color = Config.Color
	impactLight.Range = Config.ImpactLightRange
	impactLight.Brightness = 0
	impactLight.Parent = hit

	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Config.SparkColor, Config.Color)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Lifetime = NumberRange.new(0.15, 0.4)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Rate = 80
	sparks.Drag = 2
	sparks.Enabled = false
	sparks.Parent = hit

	local beams = {}
	for _, eye in eyes do
		table.insert(beams, { beam = track(makeBeam(eye.attachment, hit, Config.Color, head)), width = Config.OuterWidth })
		table.insert(beams, { beam = track(makeBeam(eye.attachment, hit, Config.CoreColor, head)), width = Config.CoreWidth })
	end

	local sound
	if Config.SoundId ~= "" then
		sound = track(Instance.new("Sound"))
		sound.SoundId = Config.SoundId
		sound.Volume = Config.SoundVolume
		sound.Looped = true
		sound.Parent = head
		sound:Play()
	end

	return {
		character = character,
		head = head,
		eyes = eyes,
		beams = beams,
		target = target,
		impactLight = impactLight,
		sparks = sparks,
		sound = sound,
		instances = instances,
		power = 0,
		aim = character:GetAttribute(Config.AimAttribute),
		seed = math.random() * 100,
	}
end

local function destroyEffect(character: Model)
	local fx = effects[character]
	if not fx then
		return
	end
	effects[character] = nil
	for _, inst in fx.instances do
		inst:Destroy()
	end
end

---------------------------------------------------------------------
-- Анимация стрельбы
---------------------------------------------------------------------

-- Силовая стойка: кулаки у пояса, ноги шире, корпус слегка назад от отдачи
local STANCE = {
	Waist = Vector3.new(8, 0, 0),
	LeftShoulder = Vector3.new(-15, 0, -25),
	RightShoulder = Vector3.new(-15, 0, 25),
	LeftElbow = Vector3.new(75, 0, 0),
	RightElbow = Vector3.new(75, 0, 0),
	LeftHip = Vector3.new(0, 0, -9),
	RightHip = Vector3.new(0, 0, 9),
}

local function laserLayer(character: Model, fx)
	return {
		Priority = 20,
		Update = function(rig, _, now)
			if effects[character] ~= fx then
				return nil, 0, true
			end
			local power = fx.power
			if power <= 0 then
				return nil, 0
			end
			local flying = character:GetAttribute("Flying") == true
			local pose = flying and {} or table.clone(STANCE)

			-- Голова смотрит на цель (по высоте), лёгкая дрожь от мощности луча
			local pitch = 0
			if fx.aim and not flying then
				local dir = fx.aim - fx.head.Position
				if dir.Magnitude > 0.1 then
					pitch = math.clamp(math.deg(math.asin(math.clamp(dir.Unit.Y, -1, 1))), -40, 50)
				end
			end
			local jitter = math.noise(now * 30, fx.seed) * 3
			pose.Neck = Vector3.new(pitch + jitter, math.noise(now * 30, fx.seed + 5) * 2, 0)
			pose.Waist = (pose.Waist or Vector3.zero) + Vector3.new(math.noise(now * 22, fx.seed + 9) * 2, 0, 0)
			return RigAnimator.Frames(rig, pose), power * 0.9
		end,
	}
end

-- Раскалённые следы в месте попадания: светятся и остывают
local scorches = {}
local MAX_SCORCHES = 60

local function addScorch(position: Vector3, normal: Vector3)
	local mark = Instance.new("Part")
	mark.Name = "LaserScorch"
	mark.Shape = Enum.PartType.Cylinder
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Material = Enum.Material.Neon
	mark.Color = Config.SparkColor
	local d = 0.5 + math.random() * 0.4
	mark.Size = Vector3.new(0.05, d, d)
	-- Ось цилиндра — X, разворачиваем её по нормали поверхности
	mark.CFrame = CFrame.lookAt(position + normal * 0.03, position + normal * 2) * CFrame.Angles(0, math.rad(90), 0)
	mark.Parent = workspace
	table.insert(scorches, { part = mark, born = os.clock() })
	if #scorches > MAX_SCORCHES then
		table.remove(scorches, 1).part:Destroy()
	end
	Debris:AddItem(mark, 4)
end

local function updateScorches(now: number)
	for i = #scorches, 1, -1 do
		local s = scorches[i]
		local age = now - s.born
		if not s.part.Parent or age > 4 then
			table.remove(scorches, i)
		else
			-- Остывает: оранжевый → тёмный → исчезает
			local cool = math.clamp(age / 1.2, 0, 1)
			s.part.Color = Config.SparkColor:Lerp(Color3.fromRGB(25, 15, 10), cool)
			if cool >= 1 then
				s.part.Material = Enum.Material.SmoothPlastic
			end
			s.part.Transparency = math.clamp((age - 2.5) / 1.5, 0, 1)
		end
	end
end

---------------------------------------------------------------------
-- Прицел своего персонажа
---------------------------------------------------------------------

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function getLocalAim(character: Model): Vector3
	local camera = workspace.CurrentCamera
	local screenPoint
	if isTouch then
		screenPoint = camera.ViewportSize / 2
	else
		screenPoint = UserInputService:GetMouseLocation()
	end
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	aimParams.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, aimParams)
	return result and result.Position or ray.Origin + ray.Direction * 1000
end

local savedAutoRotate: boolean? = nil
local sendTimer = 0

local function turnToward(character: Model, aim: Vector3, dt: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or humanoid.Sit or character:GetAttribute("Flying") == true then
		return
	end
	if savedAutoRotate == nil then
		savedAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
	end
	local pos = hrp.Position
	local flat = Vector3.new(aim.X - pos.X, 0, aim.Z - pos.Z)
	if flat.Magnitude < 0.5 then
		return
	end
	local goal = CFrame.lookAt(pos, pos + flat)
	local t = math.min(1, dt * 14)
	hrp.CFrame = CFrame.new(pos) * hrp.CFrame.Rotation:Lerp(goal.Rotation, t)
end

local function releaseTurn(character: Model?)
	if savedAutoRotate == nil then
		return
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = savedAutoRotate
	end
	savedAutoRotate = nil
end

---------------------------------------------------------------------
-- Кнопка и управление
---------------------------------------------------------------------

local lastRequest = 0

local function request()
	local t = os.clock()
	if t - lastRequest < 0.25 then
		return
	end
	lastRequest = t
	remote:FireServer()
end

local button = AbilityButton.new({
	Name = Config.ButtonText,
	Icon = Config.ButtonIcon,
	KeyName = Config.Keys[1].Name,
	Slot = Config.ButtonSlot,
	Duration = Config.Duration,
	Cooldown = Config.Cooldown,
	ActiveColor = Config.ActiveColor,
	OnActivate = request,
})

ContextActionService:BindAction("LaserEyes", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		request()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, table.unpack(Config.Keys))

---------------------------------------------------------------------
-- Кадровый цикл
---------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local myCharacter = player.Character
	local myActive = myCharacter ~= nil and myCharacter:GetAttribute(Config.ActiveAttribute) == true
	local myAim = myActive and getLocalAim(myCharacter) or nil

	-- Свой персонаж: шлём прицел и разворачиваемся к цели
	if myActive and myAim then
		sendTimer -= dt
		if sendTimer <= 0 then
			sendTimer = 1 / Config.AimSendRate
			aimRemote:FireServer(myAim)
		end
		if Config.TurnToAim then
			turnToward(myCharacter, myAim, dt)
		end
	else
		sendTimer = 0
		releaseTurn(myCharacter)
	end

	-- Появились новые стреляющие — создаём им эффект
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if character and not effects[character] and character:GetAttribute(Config.ActiveAttribute) == true then
			local fx = createEffect(character)
			effects[character] = fx
			if fx then
				RigAnimator.SetLayer(character, "Laser", laserLayer(character, fx))
				local eyes = (fx.eyes[1].attachment.WorldPosition + fx.eyes[2].attachment.WorldPosition) / 2
				AbilityFx.Burst(eyes, {
					Color = Config.Color,
					Count = 16,
					Speed = NumberRange.new(4, 9),
					Size = 0.4,
					Lifetime = NumberRange.new(0.15, 0.3),
					Light = 8,
				})
			end
		end
	end

	for character, fx in pairs(effects) do
		if not character.Parent or not fx.head.Parent then
			destroyEffect(character)
			continue
		end

		local active = character:GetAttribute(Config.ActiveAttribute) == true
		local step = dt / Config.ChargeTime
		fx.power = active and math.min(1, fx.power + step) or math.max(0, fx.power - step)
		if fx.power <= 0 and not active then
			destroyEffect(character)
			continue
		end

		-- Цель: своя — сразу из мышки, чужая — плавно догоняет данные сервера
		local aim
		if character == myCharacter and myAim then
			aim = myAim
			fx.aim = myAim
		else
			local serverAim = character:GetAttribute(Config.AimAttribute)
			if typeof(serverAim) == "Vector3" then
				fx.aim = fx.aim and fx.aim:Lerp(serverAim, 1 - math.exp(-15 * dt)) or serverAim
			end
			aim = fx.aim
		end
		if not aim then
			continue
		end

		local origin = (fx.eyes[1].attachment.WorldPosition + fx.eyes[2].attachment.WorldPosition) / 2
		local direction = aim - origin
		if direction.Magnitude < 0.01 then
			continue
		end
		rayParams.FilterDescendantsInstances = { character, fx.target }
		local result = workspace:Raycast(origin, direction.Unit * Config.Range, rayParams)
		local endPoint = result and result.Position or origin + direction.Unit * Config.Range

		fx.target.CFrame = CFrame.new(endPoint)

		-- Следы на поверхностях (не на персонажах)
		if result and fx.power > 0.5 and t >= (fx.nextScorch or 0) then
			fx.nextScorch = t + 0.07
			local model = result.Instance:FindFirstAncestorWhichIsA("Model")
			if not (model and model:FindFirstChildOfClass("Humanoid")) then
				addScorch(result.Position, result.Normal)
			end
		end
		if character == myCharacter and fx.power > 0.5 then
			AbilityFx.Shake(0.006, 0.08)
		end
		fx.sparks.Enabled = result ~= nil and fx.power > 0.5
		fx.impactLight.Brightness = result and 4 * fx.power or 0

		-- Мерцание толщины луча
		local flicker = 1 + 0.25 * math.noise(t * 25, fx.seed)
		for _, b in fx.beams do
			local w = b.width * fx.power * flicker
			b.beam.Width0 = w
			b.beam.Width1 = w
		end
		for _, eye in fx.eyes do
			eye.light.Brightness = 3 * fx.power
		end
	end

	updateScorches(t)

	-- Таймеры на кнопке
	local now = serverNow()
	local activeLeft = myActive and math.max(0, (myCharacter:GetAttribute(Config.UntilAttribute) or 0) - now) or nil
	local cooldownLeft = math.max(0, (player:GetAttribute(Config.CooldownAttribute) or 0) - now)
	button:Update(activeLeft, cooldownLeft)
end)

----------------------------------------------------------------------
-- 35. StarterPlayer → StarterPlayerScripts > LocalScript "FlightClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > FlightClient
-- Клиент способности «Полёт»:
--   * физика полёта своего персонажа: инерция, разгон, наклон по направлению,
--     крен в поворотах, рывок при взлёте;
--   * анимации для всех летящих: зависание с покачиванием ↔ «супергеройский» полёт,
--     следы от рук и ног на скорости, пыль при взлёте;
--   * «звуковой удар» при выходе на максимальную скорость, расширение обзора;
--   * супергеройское приземление (на одно колено) после полёта.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FlightConfig"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))
local AbilityFx = require(ReplicatedStorage:WaitForChild("AbilityFx"))
local AbilityButton = require(ReplicatedStorage:WaitForChild("AbilityButton"))
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName)

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- Позы полёта (градусы, как в PoseConfig)
---------------------------------------------------------------------

-- Зависание: ноги свободно свисают, руки чуть в стороны
local HOVER = {
	Waist = Vector3.new(0, 0, 0),
	Neck = Vector3.new(0, 0, 0),
	LeftShoulder = Vector3.new(5, 0, -22),
	RightShoulder = Vector3.new(5, 0, 22),
	LeftElbow = Vector3.new(18, 0, 0),
	RightElbow = Vector3.new(18, 0, 0),
	LeftHip = Vector3.new(12, 0, -4),
	RightHip = Vector3.new(-6, 0, 4),
	LeftKnee = Vector3.new(-30, 0, 0),
	RightKnee = Vector3.new(-14, 0, 0),
	LeftAnkle = Vector3.new(-25, 0, 0),
	RightAnkle = Vector3.new(-25, 0, 0),
}

-- Полёт: тело горизонтально (наклоняет физика), правая рука вперёд, ноги вытянуты
local FLY = {
	Waist = Vector3.new(10, 0, 0),
	Neck = Vector3.new(55, 0, 0), -- голова смотрит вперёд, а не в землю
	LeftShoulder = Vector3.new(-12, 0, -8),
	RightShoulder = Vector3.new(172, 0, 6),
	LeftElbow = Vector3.new(12, 0, 0),
	RightElbow = Vector3.new(0, 0, 0),
	LeftHip = Vector3.new(-4, 0, -3),
	RightHip = Vector3.new(-10, 0, 3),
	LeftKnee = Vector3.new(-6, 0, 0),
	RightKnee = Vector3.new(-28, 0, 0),
	LeftAnkle = Vector3.new(-45, 0, 0),
	RightAnkle = Vector3.new(-45, 0, 0),
}

-- Супергеройское приземление: на одно колено, кулак в землю
local LANDING = {
	HipHeight = 0.5,
	Root = Vector3.new(-15, 0, 0),
	Waist = Vector3.new(-15, 0, 0),
	Neck = Vector3.new(12, 0, 0),
	RightHip = Vector3.new(95, 0, 8),
	RightKnee = Vector3.new(-95, 0, 0),
	LeftHip = Vector3.new(-15, 0, -8),
	LeftKnee = Vector3.new(-110, 0, 0),
	LeftAnkle = Vector3.new(-30, 0, 0),
	RightShoulder = Vector3.new(55, 0, 12),
	RightElbow = Vector3.new(10, 0, 0),
	LeftShoulder = Vector3.new(-35, 0, -30),
	LeftElbow = Vector3.new(25, 0, 0),
	R6 = {
		HipHeight = 0.6,
		RightHip = Vector3.new(80, 0, 8),
		LeftHip = Vector3.new(-30, 0, -8),
	},
}
local LANDING_TIME = 0.8

local function flightLayer(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local weight = 0
	return {
		Priority = 10,
		Update = function(rig, dt, now)
			local flying = character:GetAttribute(Config.ActiveAttribute) == true
			weight = AbilityFx.Approach(weight, flying and 1 or 0, dt / 0.3)
			if not flying and weight <= 0 then
				return nil, 0, true
			end
			local vel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
			local s = RigAnimator.Smooth(vel.Magnitude / Config.Speed)
			local pose = RigAnimator.Blend(HOVER, FLY, s)

			-- Живость: на месте ноги покачиваются, на скорости дрожат от ветра
			local calm = 1 - s
			local sway = math.sin(now * 1.6)
			pose.LeftHip += Vector3.new(sway * 7 * calm + math.sin(now * 17) * 2.5 * s, 0, 0)
			pose.RightHip += Vector3.new(-sway * 7 * calm + math.sin(now * 15 + 1) * 2.5 * s, 0, 0)
			pose.LeftShoulder += Vector3.new(0, 0, math.sin(now * 1.3) * 5 * calm)
			pose.RightShoulder += Vector3.new(math.sin(now * 13) * 2 * s, 0, -math.sin(now * 1.3) * 5 * calm)

			local frames = RigAnimator.Frames(rig, pose)
			frames.Root = CFrame.new(0, math.sin(now * 2.2) * 0.25 * rig.scale * calm, 0)
			return frames, weight
		end,
	}
end

local function landingLayer(character: Model)
	local start = os.clock()
	return {
		Priority = 15,
		Update = function(rig, _, now)
			local elapsed = now - start
			if elapsed >= LANDING_TIME then
				return nil, 0, true
			end
			local frames = RigAnimator.Frames(rig, LANDING)
			local overrides = rig.rigType == "R6" and LANDING.R6 or {}
			frames.Root = RigAnimator.RootFrame(rig, overrides.HipHeight or LANDING.HipHeight, LANDING.Root)
			return frames, RigAnimator.Envelope(elapsed, LANDING_TIME, 0.06, 0.3)
		end,
	}
end

---------------------------------------------------------------------
-- Следы (trails) от рук и ног
---------------------------------------------------------------------

local TRAIL_PARTS = {
	R15 = { "LeftHand", "RightHand", "LeftFoot", "RightFoot" },
	R6 = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" },
}

local function createTrails(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return {}
	end
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local trails = {}
	for _, partName in TRAIL_PARTS[isR15 and "R15" or "R6"] do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			local y = isR15 and 0 or -part.Size.Y / 2
			local a0 = Instance.new("Attachment")
			a0.Name = "FlightTrail0"
			a0.Position = Vector3.new(0.12, y, 0)
			a0.Parent = part
			local a1 = Instance.new("Attachment")
			a1.Name = "FlightTrail1"
			a1.Position = Vector3.new(-0.12, y, 0)
			a1.Parent = part

			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(Config.TrailColor)
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			})
			trail.Lifetime = 0.35
			trail.LightEmission = 0.6
			trail.FaceCamera = true
			trail.MinLength = 0.05
			trail.Enabled = false
			trail.Parent = part
			table.insert(trails, { trail = trail, a0 = a0, a1 = a1 })
		end
	end
	return trails
end

local function destroyTrails(trails)
	for _, t in trails do
		t.trail.Enabled = false
		Debris:AddItem(t.trail, 0.5)
		Debris:AddItem(t.a0, 0.5)
		Debris:AddItem(t.a1, 0.5)
	end
end

---------------------------------------------------------------------
-- Физика своего полёта
---------------------------------------------------------------------

local controls = nil
local function getMoveVector(humanoid: Humanoid): Vector3
	if controls == nil then
		local ok, module = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5))
		end)
		controls = (ok and module) and module:GetControls() or false
	end
	if controls then
		return controls:GetMoveVector()
	end
	-- Запасной вариант: направление ходьбы в мире переводим в пространство камеры
	local camera = workspace.CurrentCamera
	return camera.CFrame:VectorToObjectSpace(humanoid.MoveDirection)
end

local function anyKeyDown(keys): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local flight = nil -- состояние своего полёта

local function startLocalFlight(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = hrp

	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)

	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.new(0, Config.LaunchSpeed, 0)
	velocity.Parent = hrp

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = Config.TurnResponsiveness
	align.CFrame = CFrame.lookAt(Vector3.zero, look)
	align.Parent = hrp

	humanoid.PlatformStand = true

	flight = {
		character = character,
		humanoid = humanoid,
		hrp = hrp,
		attachment = attachment,
		velocity = velocity,
		align = align,
		vel = Vector3.new(0, Config.LaunchSpeed, 0),
		momentum = 0,
		roll = 0,
		lastLook = look,
		baseFov = workspace.CurrentCamera.FieldOfView,
		boomed = false,
	}
	AbilityFx.Shake(0.025, 0.4)
end

local function stopLocalFlight()
	local f = flight
	if not f then
		return
	end
	flight = nil
	f.velocity:Destroy()
	f.align:Destroy()
	f.attachment:Destroy()
	if f.humanoid.Parent then
		f.humanoid.PlatformStand = false
		f.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
		FieldOfView = f.baseFov,
	}):Play()
end

local function sonicBoom(f)
	local camera = workspace.CurrentCamera
	AbilityFx.Burst(f.hrp.Position, {
		Color = Config.BoomColor,
		Count = 50,
		Speed = NumberRange.new(30, 45),
		Size = 1.6,
		Lifetime = NumberRange.new(0.25, 0.45),
		LightEmission = 0.7,
		Drag = 6,
		Light = 16,
	})
	AbilityFx.Shake(0.04, 0.45)
	camera.FieldOfView = math.min(110, camera.FieldOfView + 10) -- резкий «удар» обзора
end

local function updateLocalFlight(dt: number)
	local f = flight
	local camera = workspace.CurrentCamera
	local move = getMoveVector(f.humanoid)

	-- Направление: туда, куда смотрит камера, плюс вверх/вниз
	local direction = Vector3.zero
	if move.Magnitude > 0.05 then
		direction = camera.CFrame.RightVector * move.X + camera.CFrame.LookVector * -move.Z
	end
	local vertical = 0
	if anyKeyDown(Config.UpKeys) or f.humanoid.Jump then
		vertical += 1
	end
	if anyKeyDown(Config.DownKeys) then
		vertical -= 1
	end
	direction += Vector3.new(0, vertical, 0)
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end

	-- Разгон, если долго лететь вперёд
	if move.Magnitude > 0.5 then
		f.momentum = math.min(1, f.momentum + dt / Config.BoostTime)
	else
		f.momentum = math.max(0, f.momentum - dt * 1.5)
	end
	local speed = Config.Speed + (Config.MaxSpeed - Config.Speed) * f.momentum
	f.vel = f.vel:Lerp(direction * speed, 1 - math.exp(-Config.Acceleration * dt))
	f.velocity.VectorVelocity = f.vel

	-- Звуковой удар при выходе на максимум
	if f.momentum >= 0.98 and not f.boomed then
		f.boomed = true
		sonicBoom(f)
	elseif f.momentum < 0.5 then
		f.boomed = false
	end

	-- Поворот тела: куда летим, наклон по скорости, крен в поворотах
	local flat = Vector3.new(f.vel.X, 0, f.vel.Z)
	local look
	if flat.Magnitude > 3 then
		look = flat.Unit
	else
		local cl = camera.CFrame.LookVector
		local camFlat = Vector3.new(cl.X, 0, cl.Z)
		look = camFlat.Magnitude > 0.01 and camFlat.Unit or f.lastLook
	end
	local yawRate = math.atan2(f.lastLook:Cross(look).Y, f.lastLook:Dot(look)) / math.max(dt, 1 / 240)
	f.lastLook = look

	local speedFrac = math.clamp(f.vel.Magnitude / Config.Speed, 0, 1)
	local targetRoll = math.clamp(yawRate * Config.BankStrength, -math.rad(50), math.rad(50)) * speedFrac
	f.roll += (targetRoll - f.roll) * (1 - math.exp(-6 * dt))

	local elevation = 0
	if f.vel.Magnitude > 1 then
		elevation = math.asin(math.clamp(f.vel.Y / f.vel.Magnitude, -1, 1))
	end
	local pitch = math.clamp(-(math.pi / 2 - elevation) * speedFrac, -math.rad(Config.MaxPitch), 0)
	f.align.CFrame = CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(0, 0, f.roll) * CFrame.Angles(pitch, 0, 0)

	-- Обзор шире на скорости, лёгкая тряска на максимуме
	local fovTarget = f.baseFov + Config.FovBoost * math.clamp(f.vel.Magnitude / Config.MaxSpeed, 0, 1)
	camera.FieldOfView += (fovTarget - camera.FieldOfView) * (1 - math.exp(-5 * dt))
	if f.momentum > 0.9 then
		AbilityFx.Shake(0.004, 0.05)
	end
end

---------------------------------------------------------------------
-- Все персонажи: анимации, следы, приземление
---------------------------------------------------------------------

local tracked = {} -- [character] = { flying, trails, landUntil, prevVy }

RunService.RenderStepped:Connect(function(dt)
	-- Свой полёт
	local myCharacter = player.Character
	local myFlying = myCharacter ~= nil and myCharacter:GetAttribute(Config.ActiveAttribute) == true
	if myFlying and (not flight or flight.character ~= myCharacter) then
		stopLocalFlight()
		startLocalFlight(myCharacter)
	elseif not myFlying and flight then
		stopLocalFlight()
	end
	if flight then
		if flight.hrp.Parent and flight.humanoid.Health > 0 then
			updateLocalFlight(dt)
		else
			stopLocalFlight()
		end
	end

	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end
		local state = tracked[character]
		if not state then
			state = { flying = false, trails = nil, landUntil = 0, prevVy = 0 }
			tracked[character] = state
		end

		local flying = character:GetAttribute(Config.ActiveAttribute) == true
		local vel = hrp.AssemblyLinearVelocity

		if flying and not state.flying then
			-- Взлёт
			state.flying = true
			state.trails = createTrails(character)
			RigAnimator.SetLayer(character, "Flight", flightLayer(character))
			AbilityFx.Dust(character, 30)
		elseif not flying and state.flying then
			-- Конец полёта: ждём приземления
			state.flying = false
			destroyTrails(state.trails or {})
			state.trails = nil
			state.landUntil = now + 5
		end

		if state.trails then
			local enabled = vel.Magnitude > Config.Speed * 0.6
			for _, t in state.trails do
				t.trail.Enabled = enabled
			end
		end

		-- Супергеройское приземление: резко падали и остановились
		if now < state.landUntil and state.prevVy < -Config.LandingMinFallSpeed and vel.Y > -4 then
			state.landUntil = 0
			RigAnimator.SetLayer(character, "FlightLanding", landingLayer(character))
			AbilityFx.Dust(character, 40)
			AbilityFx.Burst(hrp.Position - Vector3.new(0, 2.5, 0), {
				Color = Config.BoomColor,
				Count = 20,
				Speed = NumberRange.new(18, 26),
				Size = 0.8,
				Lifetime = NumberRange.new(0.2, 0.35),
				Spread = Vector2.new(90, 90),
			})
			if character == myCharacter then
				AbilityFx.Shake(0.06, 0.5)
			end
		end
		state.prevVy = vel.Y
	end

	for character in pairs(tracked) do
		if not character.Parent then
			tracked[character] = nil
		end
	end
end)

---------------------------------------------------------------------
-- Кнопка
---------------------------------------------------------------------

AbilityButton.Create({
	Name = Config.ButtonText,
	Icon = Config.ButtonIcon,
	Slot = Config.ButtonSlot,
	Duration = Config.Duration,
	Cooldown = Config.Cooldown,
	ActiveColor = Config.ActiveColor,
	Remote = remote,
	Keys = Config.Keys,
	ActionName = "Flight",
	ActiveAttribute = Config.ActiveAttribute,
	UntilAttribute = Config.UntilAttribute,
	CooldownAttribute = Config.CooldownAttribute,
})

----------------------------------------------------------------------
-- 36. StarterPlayer → StarterPlayerScripts > LocalScript "CubeClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > CubeClient
-- Анимации куба (у всех игроков на экране):
--   * куб «выпрыгивает» с пружинкой и облаком частиц, при выходе сжимается;
--   * при ходьбе подскакивает, при касании земли сплющивается, наклоняется вперёд;
--   * в прыжке вытягивается и делает сальто, при приземлении — «шлёп» и пыль;
--   * на месте «дышит», глаза моргают.
-- Тело персонажа в форме куба прячет InvisibilityClient.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CubeConfig"))
local AbilityFx = require(ReplicatedStorage:WaitForChild("AbilityFx"))
local AbilityButton = require(ReplicatedStorage:WaitForChild("AbilityButton"))
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName)

local player = Players.LocalPlayer
local cubes = {} -- [cube part] = состояние

local function poof(position: Vector3, color: Color3)
	AbilityFx.Burst(position, {
		Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
		Count = 45,
		Speed = NumberRange.new(10, 22),
		Size = 1.1,
		Lifetime = NumberRange.new(0.35, 0.7),
		LightEmission = 0.4,
		Drag = 5,
		Light = 14,
	})
end

local function newState(character: Model, cube: BasePart)
	local now = os.clock()
	return {
		character = character,
		cube = cube,
		weld = cube:FindFirstChild("CubeWeld"),
		hrp = character:FindFirstChild("HumanoidRootPart"),
		base = cube:GetAttribute("BaseSize") or cube.Size.Y,
		offsetY = cube:GetAttribute("OffsetY") or 0,
		start = now,
		endedAt = nil,
		hopPhase = 0,
		impact = 0,
		prevVy = 0,
		flipStart = nil,
		blinkAt = now + 1 + math.random() * 2,
		blinkUntil = 0,
		eyes = {},
	}
end

local function findEyes(state)
	local face = state.cube:FindFirstChild("Face")
	if face then
		for _, name in { "Eye1", "Eye2" } do
			local eye = face:FindFirstChild(name)
			if eye then
				table.insert(state.eyes, eye)
			end
		end
	end
end

local function updateCube(state, dt: number, now: number)
	local cube, weld, hrp = state.cube, state.weld, state.hrp
	if not weld or not hrp then
		return
	end
	local active = state.character:GetAttribute(Config.ActiveAttribute) == true

	-- Появление / исчезновение
	if not active and not state.endedAt then
		state.endedAt = now
		poof(cube.Position, cube.Color)
		if state.character == player.Character then
			AbilityFx.Shake(0.03, 0.3)
		end
	end
	local pop
	if state.endedAt then
		pop = math.max(0, 1 - AbilityFx.BackIn((now - state.endedAt) / Config.PopOutTime))
	else
		pop = AbilityFx.ElasticOut((now - state.start) / Config.PopTime)
	end

	local vel = hrp.AssemblyLinearVelocity
	local vy = vel.Y
	local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local moving = math.clamp(flatSpeed / 16, 0, 1)
	local grounded = math.abs(vy) < 3

	-- Подскоки при ходьбе
	local hop, contact = 0, 0
	if grounded and moving > 0.1 then
		state.hopPhase += dt * Config.HopRate * (0.6 + 0.4 * moving)
		local s = math.abs(math.sin(state.hopPhase * math.pi))
		hop = s * Config.HopHeight * moving * (state.base / Config.Size)
		contact = (1 - s) ^ 6 * moving
	else
		state.hopPhase = 0
	end

	-- Приземление: сплющивание и пыль
	if state.prevVy < -15 and vy > -3 then
		state.impact = math.clamp(-state.prevVy / 60, 0.15, 0.4)
		AbilityFx.Dust(state.character, 18)
	end
	state.impact *= math.exp(-9 * dt)

	-- Прыжок: сальто вперёд
	if state.prevVy < 5 and vy > 25 and not state.flipStart then
		state.flipStart = now
	end
	local flip = 0
	if state.flipStart then
		local t = (now - state.flipStart) / 0.55
		if t >= 1 then
			state.flipStart = nil
		else
			flip = -2 * math.pi * (t * t * (3 - 2 * t))
		end
	end
	state.prevVy = vy

	-- Растяжение в воздухе, «дыхание» на месте
	local stretch = grounded and 0 or math.clamp(math.abs(vy) / 90, 0, 0.22)
	local breath = math.sin(now * 3) * 0.03 * (1 - moving)
	local scaleY = math.max(0.4, 1 - 0.16 * contact - state.impact + stretch + breath)
	local scaleXZ = 1 + 0.5 * (1 - scaleY)

	local size = math.max(0.05, state.base * pop)
	local height = size * scaleY
	cube.Size = Vector3.new(size * scaleXZ, height, size * scaleXZ)

	-- Нижняя грань остаётся на земле
	local groundY = state.offsetY - state.base / 2
	local tilt = -math.rad(12) * moving
	weld.C0 = CFrame.new(0, groundY + height / 2 + hop, 0) * CFrame.Angles(tilt + flip, 0, 0)

	-- Моргание
	if now > state.blinkAt then
		state.blinkUntil = now + 0.12
		state.blinkAt = now + 2 + math.random() * 3
	end
	local eyeHeight = now < state.blinkUntil and 0.03 or 0.2
	for _, eye in state.eyes do
		eye.Size = UDim2.fromScale(0.13, eyeHeight)
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local cube = character and character:FindFirstChild(Config.PartName)
		if cube and cube:IsA("BasePart") and not cubes[cube] then
			local state = newState(character, cube)
			findEyes(state)
			cubes[cube] = state
			if character:GetAttribute(Config.ActiveAttribute) == true then
				poof(cube.Position, cube.Color)
				if character == player.Character then
					AbilityFx.Shake(0.035, 0.35)
				end
			end
		end
	end

	for cube, state in pairs(cubes) do
		if not cube.Parent then
			cubes[cube] = nil
		else
			updateCube(state, dt, now)
		end
	end
end)

AbilityButton.Create({
	Name = Config.ButtonText,
	Icon = Config.ButtonIcon,
	Slot = Config.ButtonSlot,
	Duration = Config.Duration,
	Cooldown = Config.Cooldown,
	ActiveColor = Config.ActiveColor,
	Remote = remote,
	Keys = Config.Keys,
	ActionName = "CubeForm",
	ActiveAttribute = Config.ActiveAttribute,
	UntilAttribute = Config.UntilAttribute,
	CooldownAttribute = Config.CooldownAttribute,
})

----------------------------------------------------------------------
-- 37. StarterPlayer → StarterPlayerScripts > LocalScript "NPCClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > NPCClient
-- Клиент жителей:
--   * облачка с репликами над головой: «выпрыгивают», текст печатается по буквам, потом тают;
--   * значок настроения над головой (💤 💬 🎵 😊 😱 ...), покачивается;
--   * окно разговора с жителем: имя, уровень дружбы, ответ и кнопки тем;
--   * задания: вещь видна только тебе, отмечена значком сквозь стены, трекер сверху экрана;
--   * всплывающие уведомления (+монеты, новый друг);
--   * собаки на поводке у жителей: бегают рядом, виляют хвостом, садятся, гавкают;
--   * звуки жителей: шаги, «бормотание» голосом при репликах (у каждого своя высота),
--     смех, крик, храп, лай, скрип дверей (ID звуков — в SoundConfig).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))

-- Руки за спиной (задержанный в наручниках): только руки, ноги шагают как обычно
local CUFFED_POSE = {
	LeftShoulder = Vector3.new(-32, 0, 26),
	RightShoulder = Vector3.new(-32, 0, -26),
	LeftElbow = Vector3.new(38, 0, 0),
	RightElbow = Vector3.new(38, 0, 0),
}

-- Рука держит зонт над головой
local UMBRELLA_POSE = {
	RightShoulder = Vector3.new(62, 0, 14),
	RightElbow = Vector3.new(62, 0, 0),
}

local function armLayer(model: Model, attribute: string, pose, priority: number)
	local weight = 0
	return {
		Priority = priority,
		Update = function(rig, dt)
			local on = model:GetAttribute(attribute) == true
			weight = math.clamp(weight + (on and dt or -dt) * 4, 0, 1)
			if not on and weight <= 0 then
				return nil, 0, true
			end
			return RigAnimator.Frames(rig, pose), weight
		end,
	}
end

local function cuffedLayer(model: Model)
	local weight = 0
	return {
		Priority = 40,
		Update = function(rig, dt)
			local on = model:GetAttribute("Cuffed") == true
			weight = math.clamp(weight + (on and dt or -dt) * 4, 0, 1)
			if not on and weight <= 0 then
				return nil, 0, true
			end
			return RigAnimator.Frames(rig, CUFFED_POSE), weight
		end,
	}
end
local dialogRemote = ReplicatedStorage:WaitForChild("NPCDialog")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BUBBLE_FONT = Enum.Font.GothamMedium
local BUBBLE_TEXT_SIZE = 18
local BUBBLE_MAX_WIDTH = 240
local TYPE_SPEED = 45 -- букв в секунду

-- Звук в детали (3D: громче рядом, тише вдали)
local function playAt(parent: Instance?, def, pitch: number?)
	if not parent or not def or def.Id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = 70
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local bubbleGui = Instance.new("ScreenGui")
bubbleGui.Name = "NPCBubbles"
bubbleGui.ResetOnSpawn = false
bubbleGui.Parent = playerGui

---------------------------------------------------------------------
-- Облачка
---------------------------------------------------------------------

local bubbles = {} -- [npc model] = { billboard, token }

-- target — житель (облачко над головой) или любая деталь (например, голова собаки)
local function showBubble(model: Instance, text: string, duration: number)
	local head = model:IsA("BasePart") and model or model:FindFirstChild("Head")
	if not head then
		return
	end
	local old = bubbles[model]
	if old then
		old.billboard:Destroy()
	end

	local bounds = TextService:GetTextSize(text, BUBBLE_TEXT_SIZE, BUBBLE_FONT, Vector2.new(BUBBLE_MAX_WIDTH, 1000))
	local width, height = bounds.X + 28, bounds.Y + 20

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Bubble"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(width, height + 12)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Parent = bubbleGui

	local group = Instance.new("CanvasGroup")
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.GroupTransparency = 0
	group.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = group

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, -12)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BorderSizePixel = 0
	frame.Parent = group
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

	-- «Хвостик» облачка
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, -12)
	tail.Size = UDim2.fromOffset(14, 14)
	tail.Rotation = 45
	tail.BackgroundColor3 = frame.BackgroundColor3
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = group

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = BUBBLE_FONT
	label.TextSize = BUBBLE_TEXT_SIZE
	label.TextColor3 = Color3.fromRGB(30, 30, 40)
	label.TextWrapped = true
	label.Text = text
	label.MaxVisibleGraphemes = 0
	label.Parent = frame

	local entry = { billboard = billboard }
	bubbles[model] = entry

	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.spawn(function()
		-- Печатаем по буквам
		local length = utf8.len(text) or #text
		local start = os.clock()
		-- Голос: живое «бормотание» с высотой этого жителя; длинная реплика — пара слогов
		local pitch = (not model:IsA("BasePart")) and model:GetAttribute("VoicePitch") or nil
		local syllables = pitch and math.clamp(math.ceil(length / 12), 1, 3) or 0
		local nextBlip = 0
		while billboard.Parent do
			local shown = math.floor((os.clock() - start) * TYPE_SPEED)
			label.MaxVisibleGraphemes = math.min(shown, length)
			if syllables > 0 and os.clock() >= nextBlip then
				syllables -= 1
				nextBlip = os.clock() + 1 / Sounds.VoiceSpeed
				playAt(head, Sounds.NPC.Voice, pitch * (0.95 + math.random() * 0.1))
			end
			if shown >= length then
				break
			end
			task.wait()
		end
		label.MaxVisibleGraphemes = -1

		task.wait(duration)
		if bubbles[model] ~= entry then
			return
		end
		local fade = TweenService:Create(group, TweenInfo.new(0.4), { GroupTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if bubbles[model] == entry then
			bubbles[model] = nil
		end
		billboard:Destroy()
	end)
end

---------------------------------------------------------------------
-- Значок настроения
---------------------------------------------------------------------

local moods = {} -- [npc model] = billboard

local function showMood(model: Model)
	local emoji = model:GetAttribute("Mood")
	local old = moods[model]
	if old then
		moods[model] = nil
		local label = old:FindFirstChildOfClass("TextLabel")
		if label then
			local fade = TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 1 })
			fade:Play()
			fade.Completed:Once(function()
				old:Destroy()
			end)
		else
			old:Destroy()
		end
	end
	local head = model:FindFirstChild("Head")
	if type(emoji) ~= "string" or emoji == "" or not head then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Mood"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(38, 38)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.MaxDistance = 60
	billboard.LightInfluence = 0
	billboard.Parent = bubbleGui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = emoji
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- Плавно покачивается вверх-вниз
	TweenService:Create(billboard, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		StudsOffset = Vector3.new(0, 4.35, 0),
	}):Play()
	moods[model] = billboard
end

local function watchNpc(model: Instance)
	if not model:IsA("Model") then
		return
	end
	-- Наручники
	local function onCuffed()
		if model:GetAttribute("Cuffed") == true and not RigAnimator.HasLayer(model, "Cuffed") then
			RigAnimator.SetLayer(model, "Cuffed", cuffedLayer(model))
		end
	end
	model:GetAttributeChangedSignal("Cuffed"):Connect(onCuffed)
	onCuffed()

	-- Зонт
	local function onUmbrella()
		if model:GetAttribute("Umbrella") == true and not RigAnimator.HasLayer(model, "Umbrella") then
			RigAnimator.SetLayer(model, "Umbrella", armLayer(model, "Umbrella", UMBRELLA_POSE, 35))
		end
	end
	model:GetAttributeChangedSignal("Umbrella"):Connect(onUmbrella)
	onUmbrella()

	-- Звуковые события с сервера: смех, крик, храп...
	model:GetAttributeChangedSignal("SoundEventId"):Connect(function()
		local name = model:GetAttribute("SoundEvent")
		local def = type(name) == "string" and Sounds.NPC[name] or nil
		local pitch = model:GetAttribute("VoicePitch") or 1
		playAt(model:FindFirstChild("Head"), def, name == "Hurt" and pitch * 0.9 + 0.1 or pitch)
	end)
	model:GetAttributeChangedSignal("Mood"):Connect(function()
		showMood(model)
	end)
	if model:GetAttribute("Mood") then
		showMood(model)
	end
	model:GetAttributeChangedSignal("SayId"):Connect(function()
		local text = model:GetAttribute("SayText")
		if type(text) == "string" and text ~= "" then
			showBubble(model, text, model:GetAttribute("SayDuration") or Config.BubbleTime)
		end
	end)
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			if bubbles[model] then
				bubbles[model].billboard:Destroy()
				bubbles[model] = nil
			end
			if moods[model] then
				moods[model]:Destroy()
				moods[model] = nil
			end
		end
	end)
end

for _, model in CollectionService:GetTagged(Config.Tag) do
	watchNpc(model)
end
CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(watchNpc)

---------------------------------------------------------------------
-- Окно разговора
---------------------------------------------------------------------

local dialogGui = Instance.new("ScreenGui")
dialogGui.Name = "NPCDialog"
dialogGui.ResetOnSpawn = false
dialogGui.Enabled = false
dialogGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -110)
panel.Size = UDim2.new(1, -32, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = dialogGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(520, math.huge)
sizeLimit.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(90, 110, 150)
panelStroke.Thickness = 1.5
panelStroke.Parent = panel
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 14)
padding.PaddingBottom = UDim.new(0, 14)
padding.PaddingLeft = UDim.new(0, 16)
padding.PaddingRight = UDim.new(0, 16)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.Parent = panel

local nameLabel = Instance.new("TextLabel")
nameLabel.LayoutOrder = 1
nameLabel.BackgroundTransparency = 1
nameLabel.Size = UDim2.new(1, 0, 0, 22)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextSize = 18
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextColor3 = Color3.fromRGB(255, 205, 110)
nameLabel.Parent = panel

local speechLabel = Instance.new("TextLabel")
speechLabel.LayoutOrder = 2
speechLabel.BackgroundTransparency = 1
speechLabel.Size = UDim2.new(1, 0, 0, 0)
speechLabel.AutomaticSize = Enum.AutomaticSize.Y
speechLabel.Font = Enum.Font.GothamMedium
speechLabel.TextSize = 17
speechLabel.TextWrapped = true
speechLabel.TextXAlignment = Enum.TextXAlignment.Left
speechLabel.TextColor3 = Color3.fromRGB(235, 238, 245)
speechLabel.Parent = panel

local buttons = Instance.new("Frame")
buttons.LayoutOrder = 3
buttons.BackgroundTransparency = 1
buttons.Size = UDim2.new(1, 0, 0, 0)
buttons.AutomaticSize = Enum.AutomaticSize.Y
buttons.Parent = panel
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -5, 0, 38)
grid.CellPadding = UDim2.fromOffset(10, 8)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = buttons

local currentNpc: Model? = nil
local typingToken = 0
local busyUntil = 0

local function typeText(text: string)
	typingToken += 1
	local token = typingToken
	speechLabel.Text = text
	speechLabel.MaxVisibleGraphemes = 0
	local length = utf8.len(text) or #text
	task.spawn(function()
		local start = os.clock()
		while token == typingToken do
			local shown = math.floor((os.clock() - start) * TYPE_SPEED)
			speechLabel.MaxVisibleGraphemes = math.min(shown, length)
			if shown >= length then
				speechLabel.MaxVisibleGraphemes = -1
				break
			end
			task.wait()
		end
	end)
end

local function makeButton(text: string, order: number, accent: boolean, onClick)
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.BackgroundColor3 = accent and Color3.fromRGB(70, 50, 55) or Color3.fromRGB(45, 55, 75)
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(240, 242, 250)
	button.Text = text
	button.TextWrapped = true
	button.Parent = buttons
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
	button.Activated:Connect(function()
		if os.clock() < busyUntil then
			return
		end
		onClick()
	end)
	return button
end

local function closeDialog()
	currentNpc = nil
	typingToken += 1
	dialogGui.Enabled = false
end

local function setTopics(model: Model, topics: { string })
	for _, child in buttons:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for i, text in topics do
		makeButton(text, i, false, function()
			busyUntil = os.clock() + 0.7
			dialogRemote:FireServer("Ask", model, i)
		end)
	end
	makeButton("Пока 👋", #topics + 1, true, function()
		dialogRemote:FireServer("Bye", model)
		closeDialog()
	end)
end

local function openDialog(model: Model, name: string, greeting: string, topics: { string })
	currentNpc = model
	nameLabel.Text = name
	typeText(greeting)
	setTopics(model, topics)

	dialogGui.Enabled = true
	panelScale.Scale = 0.85
	TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------------
-- Всплывающие уведомления
---------------------------------------------------------------------

local toastGui = Instance.new("ScreenGui")
toastGui.Name = "NPCToasts"
toastGui.ResetOnSpawn = false
toastGui.Parent = playerGui

local toastList = Instance.new("Frame")
toastList.AnchorPoint = Vector2.new(0.5, 0)
toastList.Position = UDim2.new(0.5, 0, 0, 110)
toastList.Size = UDim2.fromOffset(360, 200)
toastList.BackgroundTransparency = 1
toastList.Parent = toastGui
local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.Parent = toastList

local function showToast(text: string)
	local holder = Instance.new("CanvasGroup")
	holder.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	holder.BackgroundTransparency = 0.1
	holder.Size = UDim2.fromOffset(0, 36)
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.Parent = toastList
	Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 18)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = holder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 225, 120)
	label.Text = text
	label.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = holder
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.8, function()
		local fade = TweenService:Create(holder, TweenInfo.new(0.4), { GroupTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		holder:Destroy()
	end)
end

---------------------------------------------------------------------
-- Трекер задания (сверху экрана)
---------------------------------------------------------------------

local tracker = Instance.new("Frame")
tracker.AnchorPoint = Vector2.new(0.5, 0)
tracker.Position = UDim2.new(0.5, 0, 0, 62)
tracker.Size = UDim2.fromOffset(0, 38)
tracker.AutomaticSize = Enum.AutomaticSize.X
tracker.BackgroundColor3 = Color3.fromRGB(40, 32, 20)
tracker.BackgroundTransparency = 0.15
tracker.Visible = false
tracker.Parent = toastGui
Instance.new("UICorner", tracker).CornerRadius = UDim.new(0, 12)
local trackerStroke = Instance.new("UIStroke")
trackerStroke.Color = Color3.fromRGB(255, 200, 80)
trackerStroke.Thickness = 1.5
trackerStroke.Parent = tracker
local trackerPad = Instance.new("UIPadding")
trackerPad.PaddingLeft = UDim.new(0, 14)
trackerPad.PaddingRight = UDim.new(0, 14)
trackerPad.Parent = tracker
local trackerLabel = Instance.new("TextLabel")
trackerLabel.BackgroundTransparency = 1
trackerLabel.Size = UDim2.fromScale(0, 1)
trackerLabel.AutomaticSize = Enum.AutomaticSize.X
trackerLabel.Font = Enum.Font.GothamBold
trackerLabel.TextSize = 16
trackerLabel.TextColor3 = Color3.fromRGB(255, 235, 190)
trackerLabel.Parent = tracker
local trackerScale = Instance.new("UIScale")
trackerScale.Parent = tracker

local function updateTracker()
	local text = player:GetAttribute("QuestText")
	if type(text) == "string" and text ~= "" then
		trackerLabel.Text = "❗ " .. text
		if not tracker.Visible then
			tracker.Visible = true
			trackerScale.Scale = 0.6
			TweenService:Create(trackerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	else
		tracker.Visible = false
	end
end
player:GetAttributeChangedSignal("QuestText"):Connect(updateTracker)
updateTracker()

---------------------------------------------------------------------
-- Вещи для заданий: видны только тому, кто ищет
---------------------------------------------------------------------

local questItems = {} -- [part] = { marker, distanceLabel }

local function watchQuestItem(item: Instance)
	if not item:IsA("BasePart") then
		return
	end
	local mine = item:GetAttribute("QuestOwner") == player.UserId
	if not mine then
		item.LocalTransparencyModifier = 1
		for _, d in item:GetDescendants() do
			if d:IsA("ProximityPrompt") or d:IsA("Sparkles") then
				d.Enabled = false
			end
		end
		return
	end
	local marker = Instance.new("BillboardGui")
	marker.Adornee = item
	marker.AlwaysOnTop = true
	marker.Size = UDim2.fromOffset(70, 60)
	marker.StudsOffset = Vector3.new(0, 2, 0)
	marker.LightInfluence = 0
	marker.Parent = bubbleGui
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 0, 36)
	icon.Text = item:GetAttribute("QuestIcon") or "❗"
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBold
	icon.Parent = marker
	local distance = Instance.new("TextLabel")
	distance.BackgroundTransparency = 1
	distance.Position = UDim2.fromOffset(0, 38)
	distance.Size = UDim2.new(1, 0, 0, 20)
	distance.Font = Enum.Font.GothamBold
	distance.TextSize = 15
	distance.TextColor3 = Color3.fromRGB(255, 230, 120)
	distance.TextStrokeTransparency = 0.4
	distance.Parent = marker
	TweenService:Create(marker, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		StudsOffset = Vector3.new(0, 2.6, 0),
	}):Play()
	questItems[item] = { marker = marker, distance = distance, base = item.CFrame }
	item.AncestryChanged:Connect(function()
		if not item.Parent and questItems[item] then
			questItems[item].marker:Destroy()
			questItems[item] = nil
		end
	end)
end

for _, item in CollectionService:GetTagged("QuestItem") do
	watchQuestItem(item)
end
CollectionService:GetInstanceAddedSignal("QuestItem"):Connect(watchQuestItem)

---------------------------------------------------------------------
-- Собаки на поводке
---------------------------------------------------------------------

local dogs = {} -- [npc model] = собака
local dogParams = RaycastParams.new()
dogParams.FilterType = Enum.RaycastFilterType.Exclude

local function dogPart(folder: Instance, size: Vector3, color: Color3, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Parent = folder
	return p
end

local function createDog(model: Model)
	local color = model:GetAttribute("DogColor")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hand = model:FindFirstChild("LeftHand")
	if typeof(color) ~= "Color3" or not hrp then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "Dog_" .. model.Name
	folder.Parent = workspace
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local dog = {
		folder = folder,
		body = dogPart(folder, Vector3.new(1.1, 0.9, 2), color),
		head = dogPart(folder, Vector3.new(0.9, 0.85, 0.9), color),
		snout = dogPart(folder, Vector3.new(0.5, 0.35, 0.45), dark),
		nose = dogPart(folder, Vector3.new(0.2, 0.15, 0.1), Color3.fromRGB(20, 20, 20)),
		earL = dogPart(folder, Vector3.new(0.22, 0.5, 0.12), dark),
		earR = dogPart(folder, Vector3.new(0.22, 0.5, 0.12), dark),
		tail = dogPart(folder, Vector3.new(0.18, 0.18, 0.9), color),
		legs = {},
		pos = hrp.Position - hrp.CFrame.LookVector * 3,
		look = hrp.CFrame.LookVector,
		phase = 0,
		still = 0,
		nextBark = os.clock() + math.random(8, 25),
	}
	for i = 1, 4 do
		dog.legs[i] = dogPart(folder, Vector3.new(0.28, 0.7, 0.28), color)
	end
	for _, eyeX in { -0.22, 0.22 } do
		dog["eye" .. (eyeX < 0 and "L" or "R")] = dogPart(folder, Vector3.new(0.14, 0.14, 0.05), Color3.fromRGB(15, 15, 15))
	end

	-- Поводок
	if hand then
		local a0 = Instance.new("Attachment")
		a0.Name = "LeashHand"
		a0.Position = Vector3.new(0, -0.3, 0)
		a0.Parent = hand
		local a1 = Instance.new("Attachment")
		a1.Name = "LeashCollar"
		a1.Parent = dog.head
		local leash = Instance.new("Beam")
		leash.Attachment0 = a0
		leash.Attachment1 = a1
		leash.Color = ColorSequence.new(Color3.fromRGB(170, 40, 40))
		leash.Width0 = 0.08
		leash.Width1 = 0.08
		leash.FaceCamera = true
		leash.Segments = 12
		leash.CurveSize0 = -1
		leash.CurveSize1 = 1
		leash.Parent = dog.head
		dog.handAttachment = a0
	end
	dogs[model] = dog
end

local function destroyDog(model: Model)
	local dog = dogs[model]
	if dog then
		dogs[model] = nil
		dog.folder:Destroy()
		if dog.handAttachment then
			dog.handAttachment:Destroy()
		end
	end
end

local function updateDog(model: Model, dog, dt: number, now: number)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	-- Место рядом с хозяином: сбоку и чуть сзади
	local goal = hrp.Position + hrp.CFrame.RightVector * 2.2 - hrp.CFrame.LookVector * 1.2
	local toGoal = Vector3.new(goal.X - dog.pos.X, 0, goal.Z - dog.pos.Z)
	local dist = toGoal.Magnitude
	local speed = 0
	if dist > 0.4 then
		local maxStep = math.max(10, dist * 3) * dt
		local step = math.min(dist, maxStep)
		dog.pos += toGoal.Unit * step
		speed = step / dt
		dog.look = dog.look:Lerp(toGoal.Unit, math.min(1, dt * 8))
	else
		local ownerLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		dog.look = dog.look:Lerp(ownerLook.Unit, math.min(1, dt * 3))
	end
	-- Пол под собакой
	dogParams.FilterDescendantsInstances = { model, dog.folder }
	local hit = workspace:Raycast(Vector3.new(dog.pos.X, hrp.Position.Y + 2, dog.pos.Z), Vector3.new(0, -12, 0), dogParams)
	local ground = hit and hit.Position.Y or (hrp.Position.Y - 3)
	dog.pos = Vector3.new(dog.pos.X, ground, dog.pos.Z)

	local moving = speed > 1
	dog.still = moving and 0 or dog.still + dt
	local sitting = dog.still > 2.5
	dog.phase += dt * (moving and math.clamp(speed, 4, 20) * 1.1 or 0)

	local look = Vector3.new(dog.look.X, 0, dog.look.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local bob = moving and math.abs(math.sin(dog.phase)) * 0.15 or 0
	local root = CFrame.lookAt(dog.pos, dog.pos + look.Unit) * CFrame.new(0, 1.15 + bob, 0)
	-- Сидит: корпус наклонён назад
	local bodyCF = sitting and (root * CFrame.new(0, -0.25, 0.2) * CFrame.Angles(math.rad(25), 0, 0)) or root
	dog.body.CFrame = bodyCF
	local headCF = bodyCF * CFrame.new(0, 0.55, -1.15) * CFrame.Angles(math.rad(sitting and -20 or 0) + math.sin(now * 2) * 0.05, math.sin(now * 0.7) * 0.25, 0)
	dog.head.CFrame = headCF
	dog.snout.CFrame = headCF * CFrame.new(0, -0.15, -0.6)
	dog.nose.CFrame = headCF * CFrame.new(0, -0.05, -0.85)
	dog.eyeL.CFrame = headCF * CFrame.new(-0.22, 0.15, -0.46)
	dog.eyeR.CFrame = headCF * CFrame.new(0.22, 0.15, -0.46)
	local earFlap = math.sin(dog.phase * 2) * (moving and 0.25 or 0.05)
	dog.earL.CFrame = headCF * CFrame.new(-0.4, 0.2, 0.05) * CFrame.Angles(0, 0, math.rad(20) + earFlap)
	dog.earR.CFrame = headCF * CFrame.new(0.4, 0.2, 0.05) * CFrame.Angles(0, 0, -math.rad(20) - earFlap)
	-- Хвост виляет, на ходу быстрее
	local wag = math.sin(now * (moving and 18 or 10)) * 0.6
	dog.tail.CFrame = bodyCF * CFrame.new(0, 0.35, 1.05) * CFrame.Angles(math.rad(35), wag, 0) * CFrame.new(0, 0, 0.4)
	-- Лапы шагают
	local legOffsets = { Vector3.new(-0.35, -0.55, -0.7), Vector3.new(0.35, -0.55, -0.7), Vector3.new(-0.35, -0.55, 0.7), Vector3.new(0.35, -0.55, 0.7) }
	for i = 1, 4 do
		local swing = moving and math.sin(dog.phase + (i % 2 == 0 and math.pi or 0) + (i > 2 and math.pi or 0)) * 0.6 or 0
		local legRoot = (sitting and i > 2) and root or bodyCF
		dog.legs[i].CFrame = legRoot * CFrame.new(legOffsets[i] + Vector3.new(0, 0.2, 0)) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.35, 0)
	end
	-- Гав!
	if now > dog.nextBark then
		dog.nextBark = now + math.random(12, 35)
		showBubble(dog.head, "Гав!", 1.2)
		playAt(dog.head, Sounds.NPC.DogBark, 0.9 + math.random() * 0.3)
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, model in CollectionService:GetTagged(Config.Tag) do
		if model:GetAttribute("DogColor") and not dogs[model] and model:FindFirstChild("HumanoidRootPart") then
			createDog(model)
		end
	end
	for model, dog in pairs(dogs) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not model.Parent or not humanoid or humanoid.Health <= 0 then
			destroyDog(model)
		else
			updateDog(model, dog, dt, now)
		end
	end
	-- Вещи для заданий вращаются, показываем расстояние
	local character = player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	for item, entry in pairs(questItems) do
		item.CFrame = entry.base * CFrame.new(0, math.sin(now * 3) * 0.2, 0) * CFrame.Angles(0, now * 2, 0)
		if myRoot then
			entry.distance.Text = string.format("%d м", math.floor((item.Position - myRoot.Position).Magnitude))
		end
	end
end)

dialogRemote.OnClientEvent:Connect(function(action, model, a, b, c)
	if action == "Toast" then
		showToast(model)
		return
	elseif action == "Title" and model == currentNpc then
		nameLabel.Text = a
		return
	end
	if action == "Open" then
		openDialog(model, a, b, c)
	elseif action == "Answer" and model == currentNpc then
		typeText(a)
		if type(b) == "table" then
			setTopics(model, b)
		end
	elseif action == "Close" and model == currentNpc then
		closeDialog()
	end
end)

---------------------------------------------------------------------
-- Шаги жителей
---------------------------------------------------------------------

local steps = {} -- [npc] = пройденное расстояние
local STEP_LENGTH = 2.6

RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	for _, model in CollectionService:GetTagged(Config.Tag) do
		local hrp = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if hrp and humanoid and humanoid.Health > 0 and (hrp.Position - camera.CFrame.Position).Magnitude < 60 then
			local v = hrp.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local grounded = math.abs(v.Y) < 2
			if speed > 2 and grounded and not humanoid.PlatformStand then
				steps[model] = (steps[model] or 0) + speed * dt
				if steps[model] >= STEP_LENGTH then
					steps[model] = 0
					playAt(hrp, Sounds.NPC.Footstep, 0.9 + math.random() * 0.25 + (speed > 15 and 0.15 or 0))
				end
			end
		else
			steps[model] = nil
		end
	end
end)

---------------------------------------------------------------------
-- Скрип дверей домов
---------------------------------------------------------------------

task.spawn(function()
	local system = workspace:WaitForChild(Config.FolderName, 60)
	local doors = system and system:WaitForChild("Doors", 30)
	if not doors then
		return
	end
	local function watchDoor(door: Instance)
		door:GetAttributeChangedSignal("DoorOpen"):Connect(function()
			local part = door:IsA("BasePart") and door or door:FindFirstChildWhichIsA("BasePart", true)
			playAt(part, door:GetAttribute("DoorOpen") and Sounds.NPC.HouseDoorOpen or Sounds.NPC.HouseDoorClose)
		end)
	end
	for _, d in doors:GetChildren() do
		watchDoor(d)
	end
	doors.ChildAdded:Connect(watchDoor)
end)

----------------------------------------------------------------------
-- 38. StarterPlayer → StarterPlayerScripts > LocalScript "VehicleClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > VehicleClient
-- Внешний вид и звуки машин (у каждого игрока на экране, плавно):
--   * двери и багажник открываются/закрываются, автобусные двери отъезжают;
--   * колёса крутятся по скорости;
--   * фары, стоп-сигналы, поворотники (с тиканьем), мигалки полиции, шашечки такси;
--   * звуки: двигатель, гудок, сирена, двери, багажник, щелчок фар;
--   * меню такси для игрока (куда ехать).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

RunService.RenderStepped:Connect(function(dt)
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

----------------------------------------------------------------------
-- 39. StarterPlayer → StarterPlayerScripts > LocalScript "PoliceDeskClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > PoliceDeskClient
-- Меню дежурного в полицейском участке:
--   * живой портрет дежурного, его реплики печатаются в облачке;
--   * «Заявление»: что случилось → где → отправить (по заявлению реально выезжает наряд);
--   * «Вопросы»: спросить дежурного о городе;
--   * «Мои заявления»: статус каждого заявления обновляется в реальном времени.
-- Фон размывается, окно плавно появляется, кнопки откликаются на наведение.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("PoliceRemote")
local player = Players.LocalPlayer

local W, H = 700, 450
local C = {
	bg = Color3.fromRGB(16, 22, 38),
	panel = Color3.fromRGB(24, 32, 54),
	card = Color3.fromRGB(34, 45, 74),
	cardHover = Color3.fromRGB(48, 64, 104),
	accent = Color3.fromRGB(70, 140, 255),
	accent2 = Color3.fromRGB(40, 90, 210),
	text = Color3.fromRGB(235, 240, 250),
	dim = Color3.fromRGB(150, 165, 195),
	gold = Color3.fromRGB(255, 205, 90),
	green = Color3.fromRGB(80, 210, 120),
	orange = Color3.fromRGB(255, 160, 60),
	yellow = Color3.fromRGB(250, 220, 80),
	red = Color3.fromRGB(240, 90, 90),
}
local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local function corner(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end
local function pad(parent: Instance, p: number)
	new("UIPadding", { PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p) }, parent)
end
local function label(parent: Instance, text: string, size: number, color: Color3?, font: Enum.Font?, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color or C.text,
		Font = font or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 6),
	}, parent)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end

-- Кнопка с откликом на наведение и нажатие
local function button(parent: Instance, text: string, props, onClick)
	local b = new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = C.card,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
	}, parent)
	for k, v in pairs(props or {}) do
		(b :: any)[k] = v
	end
	corner(b, 10)
	local base = b.BackgroundColor3
	local scale = new("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, FAST, { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) }):Play()
		TweenService:Create(scale, FAST, { Scale = 1.03 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, FAST, { BackgroundColor3 = base }):Play()
		TweenService:Create(scale, FAST, { Scale = 1 }):Play()
	end)
	b.Activated:Connect(function()
		scale.Scale = 0.94
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
		onClick()
	end)
	return b
end

---------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "PoliceDesk", ResetOnSpawn = false, Enabled = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
local shade = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)

-- Обычный Frame (не CanvasGroup): внутри ViewportFrame с портретом
local card = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = C.bg,
	ClipsDescendants = true,
}, gui)
corner(card, 18)
new("UIStroke", { Color = C.accent, Thickness = 2, Transparency = 0.3 }, card)
local cardScale = new("UIScale", {}, card)

-- Шапка с градиентом
local header = new("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.accent2, BorderSizePixel = 0 }, card)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(40, 90, 210), Color3.fromRGB(20, 40, 110)), Rotation = 10 }, header)
local badge = new("TextLabel", { BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.85, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(14, 9), Text = "🚔", TextSize = 26, Font = Enum.Font.GothamBold }, header)
corner(badge, 23)
label(header, "Дежурная часть", 22, C.text, Enum.Font.GothamBold, { Position = UDim2.fromOffset(72, 10), Size = UDim2.new(1, -140, 0, 26) })
local subtitle = label(header, "", 15, Color3.fromRGB(200, 215, 255), Enum.Font.Gotham, { Position = UDim2.fromOffset(72, 36), Size = UDim2.new(1, -140, 0, 20) })

-- Левая колонка: портрет и реплика
local left = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 80), Size = UDim2.fromOffset(220, H - 96) }, card)
local portrait = new("ViewportFrame", {
	Size = UDim2.fromOffset(220, 200),
	BackgroundColor3 = C.panel,
	Ambient = Color3.fromRGB(170, 175, 190),
	LightColor = Color3.fromRGB(255, 245, 230),
	LightDirection = Vector3.new(-1, -1, -1),
}, left)
corner(portrait, 14)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(60, 80, 130), Color3.fromRGB(25, 32, 55)), Rotation = 90 }, portrait)
local world = new("WorldModel", {}, portrait)
local camera = new("Camera", { FieldOfView = 30 }, portrait)
portrait.CurrentCamera = camera

local bubble = new("Frame", { Position = UDim2.fromOffset(0, 212), Size = UDim2.fromOffset(220, H - 96 - 212), BackgroundColor3 = Color3.fromRGB(245, 247, 252) }, left)
corner(bubble, 14)
pad(bubble, 12)
local speech = label(bubble, "", 15, Color3.fromRGB(30, 35, 50), Enum.Font.GothamMedium, { Size = UDim2.fromScale(1, 1), TextYAlignment = Enum.TextYAlignment.Top })
new("Frame", { BackgroundColor3 = bubble.BackgroundColor3, Size = UDim2.fromOffset(16, 16), Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 212), ZIndex = 0 }, left)

-- Правая колонка: вкладки и содержимое
local right = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(252, 80), Size = UDim2.new(1, -268, 1, -96) }, card)
local tabsRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38) }, right)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabsRow)
local content = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 48),
	Size = UDim2.new(1, 0, 1, -48),
	BackgroundColor3 = C.panel,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = C.accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, right)
corner(content, 14)
pad(content, 12)

local closeButton = button(header, "✕", { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -52, 0, 12), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.85, TextSize = 20, Font = Enum.Font.GothamBold }, function() end)

---------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------

local data = nil
local officerModel: Model? = nil
local currentTab = "report"
local step, chosenType, chosenPlace = 1, nil, nil
local typingToken = 0
local blur: BlurEffect? = nil
local tabButtons = {}
local render -- объявлена ниже

local function typeText(text: string)
	typingToken += 1
	local token = typingToken
	speech.Text = text
	speech.MaxVisibleGraphemes = 0
	local length = utf8.len(text) or #text
	task.spawn(function()
		local start = os.clock()
		while token == typingToken do
			local shown = math.floor((os.clock() - start) * 50)
			speech.MaxVisibleGraphemes = math.min(shown, length)
			if shown >= length then
				speech.MaxVisibleGraphemes = -1
				break
			end
			task.wait()
		end
	end)
end

local function clearContent()
	for _, c in content:GetChildren() do
		if not c:IsA("UICorner") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function list(parent: Instance, gap: number)
	return new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end

local function statusColor(status: string, done: boolean): Color3
	if done then
		return C.green
	elseif string.find(status, "пути") or string.find(status, "выезжает") then
		return C.orange
	elseif string.find(status, "месте") or string.find(status, "доставлен") then
		return C.yellow
	end
	return C.accent
end

-- Шаги заявления: 1 Что → 2 Где → 3 Отправить
local function stepper(parent: Instance)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0 }, parent)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center }, row)
	for i, name in { "Что случилось", "Где", "Отправить" } do
		local active, passed = i == step, i < step
		local dot = new("TextLabel", {
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = (active or passed) and C.accent or C.card,
			Text = passed and "✓" or tostring(i),
			TextColor3 = C.text,
			TextSize = 13,
			Font = Enum.Font.GothamBold,
		}, row)
		corner(dot, 12)
		new("TextLabel", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24),
			Text = name,
			TextSize = 13,
			Font = active and Enum.Font.GothamBold or Enum.Font.Gotham,
			TextColor3 = active and C.text or C.dim,
		}, row)
		if i < 3 then
			new("Frame", { Size = UDim2.fromOffset(14, 2), BackgroundColor3 = passed and C.accent or C.card, BorderSizePixel = 0 }, row)
		end
	end
end

local function renderReport()
	list(content, 10)
	stepper(content)
	if step == 1 then
		label(content, "Что случилось?", 17, C.text, Enum.Font.GothamBold, { LayoutOrder = 1 })
		local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, content)
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 70), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for i, t in data.types do
			local b = button(grid, "", { LayoutOrder = i }, function()
				chosenType = i
				step = 2
				render()
			end)
			label(b, t.icon, 26, nil, Enum.Font.GothamBold, { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(40, 40), TextXAlignment = Enum.TextXAlignment.Center })
			label(b, t.name, 15, nil, Enum.Font.GothamMedium, { Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -64, 1, 0), TextYAlignment = Enum.TextYAlignment.Center })
		end
	elseif step == 2 then
		local t = data.types[chosenType]
		label(content, string.format("%s %s — где это случилось?", t.icon, t.name), 17, C.text, Enum.Font.GothamBold, { LayoutOrder = 1 })
		for i, name in data.places do
			button(content, "📍  " .. name, { LayoutOrder = 1 + i, TextXAlignment = Enum.TextXAlignment.Left }, function()
				chosenPlace = i
				step = 3
				render()
			end)
		end
		button(content, "← Назад", { LayoutOrder = 100, BackgroundColor3 = C.panel, TextColor3 = C.dim, Size = UDim2.new(0, 120, 0, 32) }, function()
			step = 1
			render()
		end)
	else
		local t = data.types[chosenType]
		local summary = new("Frame", { BackgroundColor3 = C.card, Size = UDim2.new(1, 0, 0, 96), LayoutOrder = 1 }, content)
		corner(summary, 12)
		new("UIStroke", { Color = C.accent, Transparency = 0.5 }, summary)
		label(summary, t.icon, 40, nil, Enum.Font.GothamBold, { Position = UDim2.fromOffset(14, 20), Size = UDim2.fromOffset(56, 56), TextXAlignment = Enum.TextXAlignment.Center })
		label(summary, t.name, 19, C.text, Enum.Font.GothamBold, { Position = UDim2.fromOffset(84, 18), Size = UDim2.new(1, -96, 0, 26) })
		label(summary, "📍 " .. data.places[chosenPlace], 16, C.dim, Enum.Font.Gotham, { Position = UDim2.fromOffset(84, 50), Size = UDim2.new(1, -96, 0, 22) })
		local send = button(content, "Подать заявление", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 18 }, function()
			remote:FireServer("Report", chosenType, chosenPlace)
			step, chosenType, chosenPlace = 1, nil, nil
			currentTab = "tickets"
			render()
		end)
		-- Кнопка «дышит», чтобы притягивать взгляд
		local glow = new("UIStroke", { Color = Color3.fromRGB(150, 200, 255), Thickness = 2 }, send)
		TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.9 }):Play()
		button(content, "← Изменить", { LayoutOrder = 3, BackgroundColor3 = C.panel, TextColor3 = C.dim, Size = UDim2.new(0, 140, 0, 32) }, function()
			step = 2
			render()
		end)
	end
end

local function renderQuestions()
	list(content, 8)
	label(content, "Спросить дежурного", 17, C.text, Enum.Font.GothamBold, { LayoutOrder = 0 })
	for i, q in data.questions do
		button(content, "❓  " .. q, { LayoutOrder = i, TextXAlignment = Enum.TextXAlignment.Left }, function()
			remote:FireServer("Ask", i)
		end)
	end
end

local function renderTickets()
	list(content, 8)
	label(content, "Мои заявления", 17, C.text, Enum.Font.GothamBold, { LayoutOrder = 0 })
	if #data.tickets == 0 then
		label(content, "Пока нет заявлений. Если что-то случилось — подайте заявление.", 15, C.dim, Enum.Font.Gotham, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 44) })
	end
	for i, t in data.tickets do
		local row = new("Frame", { BackgroundColor3 = C.card, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = i }, content)
		corner(row, 12)
		label(row, t.icon, 26, nil, Enum.Font.GothamBold, { Position = UDim2.fromOffset(10, 14), Size = UDim2.fromOffset(36, 36), TextXAlignment = Enum.TextXAlignment.Center })
		label(row, string.format("№%d · %s", t.id, t.kind), 15, C.text, Enum.Font.GothamBold, { Position = UDim2.fromOffset(54, 8), Size = UDim2.new(1, -64, 0, 20) })
		label(row, "📍 " .. t.place, 13, C.dim, Enum.Font.Gotham, { Position = UDim2.fromOffset(54, 26), Size = UDim2.new(1, -64, 0, 16) })
		local color = statusColor(t.status, t.done)
		local chip = new("TextLabel", {
			Position = UDim2.fromOffset(54, 43),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.75,
			TextColor3 = color,
			Text = "  " .. t.status .. "  ",
			TextSize = 12,
			Font = Enum.Font.GothamBold,
		}, row)
		corner(chip, 8)
		if not t.done then
			-- Активное заявление мигает статусом
			TweenService:Create(chip, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.55 }):Play()
		end
	end
end

local TABS = {
	{ id = "report", text = "📝 Заявление" },
	{ id = "questions", text = "❓ Вопросы" },
	{ id = "tickets", text = "📋 Мои заявления" },
}

function render()
	if not data then
		return
	end
	for _, t in TABS do
		local b = tabButtons[t.id]
		if b then
			local active = currentTab == t.id
			TweenService:Create(b, FAST, { BackgroundColor3 = active and C.accent or C.card, TextColor3 = active and C.text or C.dim }):Play()
		end
	end
	clearContent()
	if currentTab == "report" then
		renderReport()
	elseif currentTab == "questions" then
		renderQuestions()
	else
		renderTickets()
	end
	content.CanvasPosition = Vector2.zero
end

for i, t in TABS do
	local b = button(tabsRow, t.text, { Size = UDim2.new(1 / 3, -6, 1, 0), TextSize = 14, LayoutOrder = i }, function()
		currentTab = t.id
		render()
	end)
	tabButtons[t.id] = b
end

---------------------------------------------------------------------
-- Портрет дежурного
---------------------------------------------------------------------

local function setPortrait(model: Model?)
	world:ClearAllChildren()
	if not model then
		return
	end
	local ok, clone = pcall(function()
		model.Archivable = true
		return model:Clone()
	end)
	if not ok or not clone then
		return
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	clone:PivotTo(CFrame.new())
	clone.Parent = world
	local head = clone:FindFirstChild("Head")
	if head then
		local focus = head.Position - Vector3.new(0, 0.6, 0)
		camera.CFrame = CFrame.lookAt(focus + head.CFrame.LookVector * 7 + Vector3.new(0, 0.3, 0), focus)
	end
end

---------------------------------------------------------------------
-- Открыть / закрыть
---------------------------------------------------------------------

local function fitScale()
	local view = workspace.CurrentCamera.ViewportSize
	return math.min(1, (view.X - 24) / W, (view.Y - 24) / H)
end

local function close()
	if not gui.Enabled then
		return
	end
	TweenService:Create(cardScale, FAST, { Scale = 0.6 * fitScale() }):Play()
	TweenService:Create(shade, FAST, { BackgroundTransparency = 1 }):Play()
	if blur then
		local b = blur
		blur = nil
		local fade = TweenService:Create(b, FAST, { Size = 0 })
		fade:Play()
		fade.Completed:Once(function()
			b:Destroy()
		end)
	end
	task.delay(0.16, function()
		gui.Enabled = false
		world:ClearAllChildren()
	end)
	data = nil
end
closeButton.Activated:Connect(close)

local function open(payload)
	data = payload
	officerModel = payload.officer
	subtitle.Text = (payload.name or "Дежурный") .. " · на связи"
	currentTab, step, chosenType, chosenPlace = "report", 1, nil, nil
	setPortrait(officerModel)
	typeText(payload.greeting or "")
	render()

	gui.Enabled = true
	if not blur then
		blur = new("BlurEffect", { Size = 0, Name = "PoliceDeskBlur" }, Lighting)
		TweenService:Create(blur, TweenInfo.new(0.3), { Size = 14 }):Play()
	end
	shade.BackgroundTransparency = 1
	TweenService:Create(shade, TweenInfo.new(0.3), { BackgroundTransparency = 0.55 }):Play()
	cardScale.Scale = 0.75 * fitScale()
	TweenService:Create(cardScale, POP, { Scale = fitScale() }):Play()
end

remote.OnClientEvent:Connect(function(action, payload)
	if action == "Open" then
		open(payload)
	elseif action == "Say" and data then
		typeText(payload)
	elseif action == "Tickets" and data then
		data.tickets = payload
		if currentTab == "tickets" then
			render()
		end
	end
end)

-- Отошёл от стойки — окно закрывается; портрет чуть «дышит»
RunService.RenderStepped:Connect(function()
	if not gui.Enabled or not data then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local officerRoot = officerModel and officerModel:FindFirstChild("HumanoidRootPart")
	if not root or not officerRoot or (root.Position - officerRoot.Position).Magnitude > 18 then
		close()
		return
	end
	local head = world:FindFirstChildWhichIsA("Model") and world:FindFirstChildWhichIsA("Model"):FindFirstChild("Head")
	if head then
		local t = os.clock()
		local focus = head.Position - Vector3.new(0, 0.6, 0)
		local offset = Vector3.new(math.sin(t * 0.6) * 0.25, 0.3 + math.sin(t * 0.9) * 0.08, 0)
		camera.CFrame = CFrame.lookAt(focus + head.CFrame.LookVector * 7 + offset, focus)
	end
end)

----------------------------------------------------------------------
-- 40. StarterPlayer → StarterPlayerScripts > LocalScript "WeatherClient"
----------------------------------------------------------------------

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
	-- Капли можно выключить в телефоне (⚙️ Настройки → «Капли дождя»)
	local effects = player:GetAttribute("RainEffects") ~= false
	rain.Rate = (indoors or not effects) and 0 or Config.RainDrops * intensity

	local ignore = { camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	skyParams.FilterDescendantsInstances = ignore
	local ground = workspace:Raycast(camPos, Vector3.new(0, -60, 0), skyParams)
	if ground then
		splashPart.CFrame = CFrame.new(ground.Position + Vector3.new(0, 0.1, 0))
	end
	splash.Rate = (indoors or not ground or not effects) and 0 or 160 * intensity

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

----------------------------------------------------------------------
-- 41. StarterPlayer → StarterPlayerScripts > LocalScript "PhoneClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > PhoneClient
-- Телефон игрока: клавиша P или кнопка 📱.
--   Экран блокировки (время, дата, погода, уведомления) → рабочий стол с приложениями:
--   🗺 Карта (дороги, ты, автобус, такси, полиция), 🚕 Такси (вызвать к себе),
--   🚔 Полиция 102 (заявления), 🚌 Автобус (маршрут), 💬 Сообщения (знакомые жители),
--   ☀️ Погода, 📋 Задания, ⚙️ Настройки (обои, часы, капли дождя).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local CityConfig = require(ReplicatedStorage:WaitForChild("CityConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local remote = ReplicatedStorage:WaitForChild("PhoneRemote")

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local W, H = 300, 620
local SW, SH = W - 20, H - 20 -- экран внутри рамки
local FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local WHITE = Color3.new(1, 1, 1)

local WALLPAPERS = {
	{ Color3.fromRGB(60, 40, 140), Color3.fromRGB(20, 120, 200) },
	{ Color3.fromRGB(240, 110, 80), Color3.fromRGB(120, 40, 140) },
	{ Color3.fromRGB(20, 140, 110), Color3.fromRGB(10, 40, 70) },
	{ Color3.fromRGB(30, 30, 40), Color3.fromRGB(80, 80, 100) },
}

local APPS = {
	{ id = "map", name = "Карта", icon = "🗺️", colors = { Color3.fromRGB(70, 200, 120), Color3.fromRGB(20, 120, 80) } },
	{ id = "taxi", name = "Такси", icon = "🚕", colors = { Color3.fromRGB(255, 210, 60), Color3.fromRGB(230, 150, 20) } },
	{ id = "police", name = "Полиция", icon = "🚔", colors = { Color3.fromRGB(80, 140, 255), Color3.fromRGB(30, 60, 170) } },
	{ id = "bus", name = "Автобус", icon = "🚌", colors = { Color3.fromRGB(255, 140, 60), Color3.fromRGB(210, 70, 40) } },
	{ id = "messages", name = "Сообщения", icon = "💬", colors = { Color3.fromRGB(90, 220, 110), Color3.fromRGB(30, 160, 70) } },
	{ id = "weather", name = "Погода", icon = "☀️", colors = { Color3.fromRGB(110, 190, 255), Color3.fromRGB(40, 110, 220) } },
	{ id = "quests", name = "Задания", icon = "📋", colors = { Color3.fromRGB(250, 120, 160), Color3.fromRGB(190, 60, 120) } },
	{ id = "work", name = "Работа", icon = "📦", colors = { Color3.fromRGB(210, 150, 90), Color3.fromRGB(140, 85, 40) } },
	{ id = "shop", name = "Магазин", icon = "🛍️", colors = { Color3.fromRGB(200, 110, 255), Color3.fromRGB(120, 50, 190) } },
	{ id = "awards", name = "Награды", icon = "🏆", colors = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(210, 140, 20) } },
	{ id = "camera", name = "Камера", icon = "📷", colors = { Color3.fromRGB(90, 95, 110), Color3.fromRGB(30, 32, 40) } },
	{ id = "settings", name = "Настройки", icon = "⚙️", colors = { Color3.fromRGB(160, 165, 180), Color3.fromRGB(90, 95, 110) } },
}

---------------------------------------------------------------------
-- Помощники
---------------------------------------------------------------------

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local function corner(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end
local function pad(parent: Instance, p: number)
	new("UIPadding", { PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p) }, parent)
end
local function text(parent: Instance, value: string, size: number, color: Color3?, bold: boolean?, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextSize = size,
		TextColor3 = color or WHITE,
		Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 6),
	}, parent)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end

local function playSound(def)
	if not def or def.Id == "" then
		return
	end
	local s = new("Sound", { SoundId = def.Id, Volume = def.Volume or 0.4 }, workspace)
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local soundsOn = true
local function tap()
	if soundsOn then
		playSound(Sounds.Phone and Sounds.Phone.Tap)
	end
end

local function button(parent: Instance, label: string, props, onClick)
	local b = new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.85,
		Text = label,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
	}, parent)
	for k, v in pairs(props or {}) do
		(b :: any)[k] = v
	end
	corner(b, 12)
	local scale = new("UIScale", {}, b)
	local baseT = b.BackgroundTransparency
	b.MouseEnter:Connect(function()
		TweenService:Create(b, FAST, { BackgroundTransparency = math.max(0, baseT - 0.1) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, FAST, { BackgroundTransparency = baseT }):Play()
	end)
	b.Activated:Connect(function()
		scale.Scale = 0.92
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
		tap()
		onClick()
	end)
	return b
end

local function list(parent: Instance, gap: number)
	return new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, parent)
end

local function card(parent: Instance, height: number?, order: number?)
	local c = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.88,
		Size = UDim2.new(1, 0, 0, height or 0),
		AutomaticSize = height and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
		LayoutOrder = order or 0,
	}, parent)
	corner(c, 14)
	pad(c, 12)
	return c
end

local function clockText(): (string, string)
	local hour = workspace:GetAttribute("Hour") or Lighting.ClockTime
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60)
	local weekDay = workspace:GetAttribute("WeekDay") or 1
	local names = { "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье" }
	local period = workspace:GetAttribute("Period") or ""
	return string.format("%02d:%02d", h, m), string.format("%s · %s", names[weekDay] or "", period)
end

---------------------------------------------------------------------
-- Каркас телефона
---------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "Phone", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

-- Кнопка 📱 с красным значком непрочитанного
local toggle = new("TextButton", {
	AnchorPoint = isTouch and Vector2.new(0, 0.5) or Vector2.new(0, 1),
	Position = isTouch and UDim2.new(0, 12, 0.42, 0) or UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(56, 56),
	BackgroundColor3 = Color3.fromRGB(25, 28, 40),
	BackgroundTransparency = 0.1,
	Text = "📱",
	TextSize = 28,
	Font = Enum.Font.GothamBold,
	AutoButtonColor = true,
}, gui)
corner(toggle, 16)
new("UIStroke", { Color = Color3.fromRGB(110, 130, 190), Thickness = 1.5, Transparency = 0.3 }, toggle)
local toggleScale = new("UIScale", {}, toggle)
local badge = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -4, 0, 4),
	Size = UDim2.fromOffset(22, 22),
	BackgroundColor3 = Color3.fromRGB(240, 60, 60),
	TextColor3 = WHITE,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	Text = "",
	Visible = false,
	ZIndex = 3,
}, toggle)
corner(badge, 11)
if not isTouch then
	text(toggle, "P", 11, Color3.fromRGB(180, 190, 220), true, { Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(12, 12), TextXAlignment = Enum.TextXAlignment.Center })
end

-- Подсказка рядом с кнопкой, когда телефон закрыт
local peek = new("TextLabel", {
	AnchorPoint = toggle.AnchorPoint,
	Position = toggle.Position + UDim2.fromOffset(66, 0),
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(25, 28, 40),
	BackgroundTransparency = 0.1,
	TextColor3 = WHITE,
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	Text = "",
	Visible = false,
}, gui)
corner(peek, 12)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, peek)

local phone = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, W + 60, 0.5, 0),
	Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = Color3.fromRGB(12, 12, 16),
	Visible = false,
}, gui)
corner(phone, 44)
new("UIStroke", { Color = Color3.fromRGB(70, 72, 85), Thickness = 3 }, phone)
local phoneScale = new("UIScale", {}, phone)

local screen = new("Frame", {
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.fromOffset(SW, SH),
	BackgroundColor3 = WHITE,
	ClipsDescendants = true,
}, phone)
corner(screen, 36)
local wallpaper = new("UIGradient", { Rotation = 120 }, screen)

-- Статус-бар и «островок»
local statusBar = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), ZIndex = 20 }, screen)
local statusTime = text(statusBar, "", 14, WHITE, true, { Position = UDim2.fromOffset(26, 8), Size = UDim2.fromOffset(60, 20), ZIndex = 20 })
local statusIcons = text(statusBar, "", 12, WHITE, true, { Position = UDim2.new(1, -110, 0, 9), Size = UDim2.fromOffset(90, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 20 })
local island = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(84, 24), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 21 }, screen)
corner(island, 12)

-- Полоска «домой»
local homeBar = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(110, 5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, Text = "", ZIndex = 30 }, screen)
corner(homeBar, 3)

-- Уведомление сверху экрана
local banner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -80), Size = UDim2.new(1, -20, 0, 62), BackgroundColor3 = Color3.fromRGB(30, 32, 44), BackgroundTransparency = 0.05, ZIndex = 40 }, screen)
corner(banner, 18)
pad(banner, 10)
local bannerIcon = text(banner, "", 26, WHITE, true, { Size = UDim2.fromOffset(34, 40), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
local bannerTitle = text(banner, "", 13, Color3.fromRGB(180, 190, 215), true, { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -42, 0, 16), ZIndex = 41 })
local bannerText = text(banner, "", 14, WHITE, false, { Position = UDim2.fromOffset(42, 17), Size = UDim2.new(1, -42, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 41 })

-- Слои: блокировка, рабочий стол, приложение
local lockLayer = new("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 5, AutoButtonColor = false }, screen)
local homeLayer = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Visible = false }, screen)
local appLayer = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 20, 30), ZIndex = 10, Visible = false }, screen)
corner(appLayer, 36)
local appScale = new("UIScale", {}, appLayer)

---------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------

local isOpen, locked = false, true
local currentApp = nil
local data = { places = {}, policeTypes = {}, tickets = {}, busStops = {}, friends = {}, taxiPrice = VehicleConfig.TaxiPrice }
local city = { stats = {}, done = {}, owned = {}, equipped = {} } -- работа, магазин, достижения
local chats = {} -- [имя] = { messages = { {mine, text} }, unread = 0, typingUntil = 0 }
local openChat = nil
local notifications = {}
local taxiStatus = nil
local policeStep, policeType = 1, nil
local policeAnswer = nil
local wallpaperIndex = 1
local renderApp, renderLock, renderHomeBadges, closePhone -- объявлены ниже

local function applyWallpaper()
	local w = WALLPAPERS[wallpaperIndex]
	wallpaper.Color = ColorSequence.new(w[1], w[2])
end
applyWallpaper()

local function unreadTotal(): number
	local n = 0
	for _, chat in pairs(chats) do
		n += chat.unread
	end
	return n
end

local function updateBadges()
	local n = unreadTotal()
	badge.Visible = n > 0
	badge.Text = tostring(math.min(n, 99))
	renderHomeBadges()
end

---------------------------------------------------------------------
-- Уведомления
---------------------------------------------------------------------

local bannerToken = 0
local function notify(icon: string, title: string, body: string)
	table.insert(notifications, 1, { icon = icon, title = title, body = body })
	if #notifications > 5 then
		table.remove(notifications)
	end
	if soundsOn then
		playSound(Sounds.Phone and Sounds.Phone.Notify)
	end
	if isOpen then
		bannerToken += 1
		local token = bannerToken
		bannerIcon.Text, bannerTitle.Text, bannerText.Text = icon, title, body
		TweenService:Create(banner, POP, { Position = UDim2.new(0.5, 0, 0, 40) }):Play()
		task.delay(2.8, function()
			if token == bannerToken then
				TweenService:Create(banner, FAST, { Position = UDim2.new(0.5, 0, 0, -80) }):Play()
			end
		end)
	else
		peek.Text = icon .. "  " .. title .. ": " .. body
		peek.Visible = true
		toggleScale.Scale = 1.2
		TweenService:Create(toggleScale, POP, { Scale = 1 }):Play()
		bannerToken += 1
		local token = bannerToken
		task.delay(3.5, function()
			if token == bannerToken then
				peek.Visible = false
			end
		end)
	end
	if locked then
		renderLock()
	end
end

---------------------------------------------------------------------
-- Экран блокировки
---------------------------------------------------------------------

local lockTime = text(lockLayer, "", 64, WHITE, true, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 72), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
local lockDate = text(lockLayer, "", 15, Color3.fromRGB(230, 235, 255), false, { Position = UDim2.fromOffset(0, 148), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
local lockWeather = text(lockLayer, "", 15, Color3.fromRGB(230, 235, 255), false, { Position = UDim2.fromOffset(0, 170), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
local lockList = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 210), Size = UDim2.new(1, -24, 0, 280), ZIndex = 6 }, lockLayer)
list(lockList, 8)
local lockHint = text(lockLayer, "Нажмите, чтобы открыть", 14, WHITE, true, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
TweenService:Create(lockHint, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.6 }):Play()

function renderLock()
	for _, c in lockList:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, n in notifications do
		if i > 3 then
			break
		end
		local c = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = i, ZIndex = 6 }, lockList)
		corner(c, 16)
		pad(c, 10)
		text(c, n.icon, 22, WHITE, true, { Size = UDim2.fromOffset(30, 36), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		text(c, n.title, 13, Color3.fromRGB(240, 240, 255), true, { Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -38, 0, 16), ZIndex = 7 })
		text(c, n.body, 13, WHITE, false, { Position = UDim2.fromOffset(38, 17), Size = UDim2.new(1, -38, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 })
	end
end

local function updateClock()
	local t, d = clockText()
	statusTime.Text = t
	lockTime.Text = t
	lockDate.Text = d
	local icon = workspace:GetAttribute("WeatherIcon") or ""
	local name = workspace:GetAttribute("WeatherName") or ""
	lockWeather.Text = icon .. " " .. name
	statusIcons.Text = icon .. "  📶 🔋"
end

---------------------------------------------------------------------
-- Рабочий стол
---------------------------------------------------------------------

local grid = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 1, -120), ZIndex = 4 }, homeLayer)
new("UIGridLayout", { CellSize = UDim2.fromOffset(72, 92), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, grid)
local homeBadges = {}
local openApp -- объявлена ниже

for i, app in APPS do
	local cell = new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 4 }, grid)
	local icon = new("TextButton", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(4, 0), BackgroundColor3 = WHITE, Text = app.icon, TextSize = 32, Font = Enum.Font.GothamBold, AutoButtonColor = false, ZIndex = 4 }, cell)
	corner(icon, 18)
	new("UIGradient", { Color = ColorSequence.new(app.colors[1], app.colors[2]), Rotation = 90 }, icon)
	local scale = new("UIScale", {}, icon)
	icon.MouseEnter:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 1.08 }):Play()
	end)
	icon.MouseLeave:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 1 }):Play()
	end)
	icon.Activated:Connect(function()
		scale.Scale = 0.85
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
		tap()
		openApp(app.id)
	end)
	text(cell, app.name, 12, WHITE, true, { Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.7, ZIndex = 4 })
	local b = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(64, 4), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromRGB(240, 60, 60), TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 12, Visible = false, ZIndex = 6 }, cell)
	corner(b, 11)
	homeBadges[app.id] = b
end

function renderHomeBadges()
	local unread = unreadTotal()
	homeBadges.messages.Visible = unread > 0
	homeBadges.messages.Text = tostring(unread)
	local active = 0
	for _, t in data.tickets do
		if not t.done then
			active += 1
		end
	end
	homeBadges.police.Visible = active > 0
	homeBadges.police.Text = tostring(active)
	homeBadges.taxi.Visible = taxiStatus ~= nil and not taxiStatus.done
	homeBadges.taxi.Text = "!"
	homeBadges.work.Visible = player:GetAttribute("JobStage") ~= nil
	homeBadges.work.Text = "!"
end

---------------------------------------------------------------------
-- Приложение: шапка и содержимое
---------------------------------------------------------------------

local appHeader = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 44), ZIndex = 11 }, appLayer)
local backButton = new("TextButton", { Position = UDim2.fromOffset(10, 4), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, Text = "‹", TextSize = 34, TextColor3 = Color3.fromRGB(110, 170, 255), Font = Enum.Font.GothamBold, ZIndex = 11 }, appHeader)
local appTitle = text(appHeader, "", 20, WHITE, true, { Position = UDim2.fromOffset(50, 8), Size = UDim2.new(1, -60, 0, 28), ZIndex = 11 })
local content = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 84),
	Size = UDim2.new(1, 0, 1, -100),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 11,
}, appLayer)
pad(content, 12)

local function clearContent()
	for _, c in content:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function goHome()
	if not currentApp then
		return
	end
	currentApp = nil
	openChat = nil
	TweenService:Create(appScale, FAST, { Scale = 0.4 }):Play()
	task.delay(0.15, function()
		if not currentApp then
			appLayer.Visible = false
		end
	end)
end
backButton.Activated:Connect(function()
	tap()
	if currentApp == "messages" and openChat then
		openChat = nil
		renderApp()
	else
		goHome()
	end
end)
homeBar.Activated:Connect(goHome)

function openApp(id: string)
	if id == "camera" then
		-- Камера — это фоторежим на весь экран (CityLifeClient)
		closePhone()
		task.delay(0.25, function()
			player:SetAttribute("PhotoMode", true)
		end)
		return
	end
	currentApp = id
	openChat = nil
	for _, app in APPS do
		if app.id == id then
			appTitle.Text = app.icon .. "  " .. app.name
		end
	end
	if id == "messages" then
		remote:FireServer("Friends")
	elseif id == "shop" or id == "awards" or id == "work" then
		remote:FireServer("City")
	end
	appLayer.Visible = true
	appScale.Scale = 0.4
	TweenService:Create(appScale, POP, { Scale = 1 }):Play()
	renderApp()
end

---------------------------------------------------------------------
-- 🗺 Карта
---------------------------------------------------------------------

local map = { frame = nil, markers = {}, bounds = nil }
local MAP_W, MAP_H = SW - 24, 360

local function trafficFolder(name: string): Instance?
	local root = workspace:FindFirstChild(VehicleConfig.MapFolder)
	return root and root:FindFirstChild(name)
end

local function toMap(pos: Vector3): UDim2
	local b = map.bounds
	local x = (pos.X - b.minX) / math.max(1, b.maxX - b.minX)
	local y = (pos.Z - b.minZ) / math.max(1, b.maxZ - b.minZ)
	return UDim2.fromOffset(10 + x * (MAP_W - 20), 10 + y * (MAP_H - 20))
end

local function renderMap()
	local roads = trafficFolder("Roads")
	local frame = new("Frame", { BackgroundColor3 = Color3.fromRGB(28, 40, 34), Size = UDim2.fromOffset(MAP_W, MAP_H), ClipsDescendants = true, LayoutOrder = 1, ZIndex = 11 }, content)
	corner(frame, 16)
	map.frame = frame
	map.markers = {}
	if not roads then
		text(frame, "Карта недоступна: нет дорог", 14, WHITE, false, { Position = UDim2.fromOffset(12, 12), ZIndex = 12 })
		return
	end
	local nodes = {}
	local b = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
	for _, p in roads:GetDescendants() do
		if p:IsA("BasePart") then
			nodes[p.Name] = p
			b.minX, b.maxX = math.min(b.minX, p.Position.X), math.max(b.maxX, p.Position.X)
			b.minZ, b.maxZ = math.min(b.minZ, p.Position.Z), math.max(b.maxZ, p.Position.Z)
		end
	end
	-- Сохраняем пропорции
	local spanX, spanZ = b.maxX - b.minX, b.maxZ - b.minZ
	local aspect = (MAP_W - 20) / (MAP_H - 20)
	if spanX / math.max(1, spanZ) > aspect then
		local extra = spanX / aspect - spanZ
		b.minZ -= extra / 2
		b.maxZ += extra / 2
	else
		local extra = spanZ * aspect - spanX
		b.minX -= extra / 2
		b.maxX += extra / 2
	end
	b.minX -= 15
	b.maxX += 15
	b.minZ -= 15
	b.maxZ += 15
	map.bounds = b

	-- Дороги
	local drawn = {}
	for name, p in pairs(nodes) do
		local links = p:GetAttribute("Links")
		if type(links) == "string" then
			for item in string.gmatch(links, "[^,;]+") do
				local other = string.match(item, "^%s*(.-)%s*$")
				local q = nodes[other]
				local key = name < other and name .. "|" .. other or other .. "|" .. name
				if q and not drawn[key] then
					drawn[key] = true
					local a, c = toMap(p.Position), toMap(q.Position)
					local ax, ay, cx, cy = a.X.Offset, a.Y.Offset, c.X.Offset, c.Y.Offset
					local len = math.sqrt((cx - ax) ^ 2 + (cy - ay) ^ 2)
					local road = new("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset((ax + cx) / 2, (ay + cy) / 2),
						Size = UDim2.fromOffset(len + 6, 6),
						Rotation = math.deg(math.atan2(cy - ay, cx - ax)),
						BackgroundColor3 = Color3.fromRGB(120, 125, 135),
						BorderSizePixel = 0,
						ZIndex = 12,
					}, frame)
					corner(road, 3)
				end
			end
		end
	end

	local function marker(icon: string, pos: Vector3, size: number, z: number)
		return new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(pos), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Text = icon, TextSize = size - 4, Font = Enum.Font.GothamBold, ZIndex = z }, frame)
	end
	-- Места, остановки, участок
	local places = trafficFolder("Places")
	if places then
		for _, p in places:GetDescendants() do
			if p:IsA("BasePart") then
				marker("📍", p.Position, 18, 13)
				text(frame, p:GetAttribute("PlaceName") or p.Name, 10, Color3.fromRGB(230, 235, 245), true, {
					AnchorPoint = Vector2.new(0.5, 0), Position = toMap(p.Position) + UDim2.fromOffset(0, 8),
					Size = UDim2.fromOffset(90, 14), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, ZIndex = 13,
				})
			end
		end
	end
	local stops = trafficFolder("BusStops")
	if stops then
		for _, p in stops:GetDescendants() do
			if p:IsA("BasePart") then
				marker("🚏", p.Position, 16, 13)
			end
		end
	end
	local station = trafficFolder("PoliceStation")
	local desk = station and station:FindFirstChild("Desk", true)
	if desk then
		marker("🏢", desk.Position, 20, 13)
	end

	-- Живые метки: машины и ты
	map.vehicleIcons = {}
	map.me = marker("🔵", Vector3.zero, 18, 16)
	map.arrow = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Text = "▲", TextSize = 16, TextColor3 = Color3.fromRGB(120, 190, 255), Font = Enum.Font.GothamBold, ZIndex = 15 }, frame)

	local legend = card(content, nil, 2)
	text(legend, "🔵 Ты   🚌 Автобус   🚕 Такси   🚓 Полиция   🚗 Машины   🚏 Остановка   🏢 Участок", 12, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 34) })
end

local VEHICLE_ICONS = { Bus = "🚌", Taxi = "🚕", Police = "🚓", Civilian = "🚗" }

local function updateMap(now: number)
	if not map.frame or not map.bounds or not map.frame.Parent then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		map.me.Position = toMap(root.Position)
		map.me.TextSize = 14 + math.sin(now * 5) * 2
		local look = root.CFrame.LookVector
		map.arrow.Position = toMap(root.Position + look * 9)
		map.arrow.Rotation = math.deg(math.atan2(look.Z, look.X)) + 90
	end
	local vehicles = trafficFolder(VehicleConfig.VehiclesFolder)
	local seen = {}
	if vehicles then
		for _, m in vehicles:GetChildren() do
			local body = m:IsA("Model") and m.PrimaryPart
			if body then
				seen[m] = true
				local icon = map.vehicleIcons[m]
				if not icon then
					icon = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, TextSize = 16, Font = Enum.Font.GothamBold, ZIndex = 14 }, map.frame)
					map.vehicleIcons[m] = icon
				end
				icon.Text = VEHICLE_ICONS[m:GetAttribute("VehicleType")] or "🚗"
				icon.Position = toMap(body.Position)
				-- Мигалки полиции на карте
				icon.TextTransparency = (m:GetAttribute("Siren") and (now * 4) % 1 < 0.5) and 0.5 or 0
			end
		end
	end
	for m, icon in pairs(map.vehicleIcons) do
		if not seen[m] then
			icon:Destroy()
			map.vehicleIcons[m] = nil
		end
	end
end

---------------------------------------------------------------------
-- Остальные приложения
---------------------------------------------------------------------

local function statusChip(parent: Instance, value: string, color: Color3, order: number?)
	local chip = new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.7,
		TextColor3 = color:Lerp(WHITE, 0.4),
		Text = "  " .. value .. "  ",
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		LayoutOrder = order or 0,
	}, parent)
	corner(chip, 10)
	return chip
end

local function renderTaxi()
	list(content, 8)
	local top = card(content, nil, 0)
	list(top, 4)
	text(top, "🚕 Такси к вашему месту", 16, WHITE, true)
	text(top, string.format("Цена поездки: %d 🪙", data.taxiPrice or 5), 14, Color3.fromRGB(255, 220, 120), false)
	if taxiStatus then
		local s = card(content, nil, 1)
		list(s, 6)
		text(s, taxiStatus.text, 15, WHITE, true, { Size = UDim2.new(1, 0, 0, 40) })
		if not taxiStatus.done then
			statusChip(s, "В процессе", Color3.fromRGB(255, 190, 60))
		end
	end
	local busy = taxiStatus and not taxiStatus.done
	text(content, busy and "Дождитесь окончания поездки" or "Куда едем?", 14, Color3.fromRGB(180, 190, 215), true, { LayoutOrder = 2 })
	if not busy then
		for i, name in data.places do
			button(content, "📍  " .. name, { LayoutOrder = 2 + i, TextXAlignment = Enum.TextXAlignment.Left }, function()
				taxiStatus = { text = "Ищем свободное такси...", done = false }
				remote:FireServer("Taxi", i)
				renderApp()
			end)
		end
	end
end

local function ticketColor(t): Color3
	if t.done then
		return Color3.fromRGB(80, 210, 120)
	elseif string.find(t.status, "пути") or string.find(t.status, "выезжает") then
		return Color3.fromRGB(255, 160, 60)
	elseif string.find(t.status, "месте") or string.find(t.status, "доставлен") then
		return Color3.fromRGB(250, 220, 80)
	end
	return Color3.fromRGB(90, 150, 255)
end

local function renderPolice()
	list(content, 8)
	if policeAnswer then
		local a = card(content, nil, 0)
		text(a, "👮 " .. policeAnswer, 14, WHITE, false, { Size = UDim2.new(1, 0, 0, 40) })
	end
	if policeStep == 1 then
		text(content, "Что случилось?", 15, WHITE, true, { LayoutOrder = 1 })
		local g = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, content)
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 58), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, g)
		for i, t in data.policeTypes do
			button(g, t.icon .. "\n" .. t.name, { LayoutOrder = i, TextSize = 13 }, function()
				policeType = i
				policeStep = 2
				renderApp()
			end)
		end
	else
		local t = data.policeTypes[policeType]
		text(content, (t and t.icon .. " " .. t.name or "") .. " — где?", 15, WHITE, true, { LayoutOrder = 1 })
		for i, name in data.places do
			button(content, "📍  " .. name, { LayoutOrder = 1 + i, TextXAlignment = Enum.TextXAlignment.Left }, function()
				remote:FireServer("Report", policeType, i)
				policeStep, policeType = 1, nil
				policeAnswer = "Отправляем заявление..."
				renderApp()
			end)
		end
		button(content, "← Назад", { LayoutOrder = 99, Size = UDim2.new(0, 110, 0, 32), BackgroundTransparency = 0.92 }, function()
			policeStep = 1
			renderApp()
		end)
	end
	if #data.tickets > 0 then
		text(content, "Мои заявления", 15, WHITE, true, { LayoutOrder = 100 })
		for i, t in data.tickets do
			local row = card(content, nil, 100 + i)
			list(row, 4)
			text(row, string.format("%s №%d · %s", t.icon, t.id, t.kind), 14, WHITE, true)
			text(row, "📍 " .. t.place, 12, Color3.fromRGB(180, 190, 215), false)
			statusChip(row, t.status, ticketColor(t))
		end
	end
end

local function findBus(): Model?
	local vehicles = trafficFolder(VehicleConfig.VehiclesFolder)
	if vehicles then
		for _, m in vehicles:GetChildren() do
			if m:GetAttribute("VehicleType") == "Bus" then
				return m
			end
		end
	end
	return nil
end

local function renderBus()
	list(content, 8)
	local bus = findBus()
	local top = card(content, nil, 0)
	list(top, 4)
	if not bus then
		text(top, "Автобус сейчас не ходит", 15, WHITE, true)
		return
	end
	local at = bus:GetAttribute("AtStop") or ""
	local nextStop = bus:GetAttribute("NextStop") or ""
	text(top, at ~= "" and ("🚌 Стоит: " .. at) or ("🚌 Едет к: " .. nextStop), 16, WHITE, true)
	local speed = math.floor((bus:GetAttribute("Speed") or 0) * 10) / 10
	text(top, at ~= "" and "Двери открыты — успейте сесть!" or string.format("Скорость: %s", tostring(speed)), 13, Color3.fromRGB(180, 190, 215), false)
	text(content, "Маршрут", 15, WHITE, true, { LayoutOrder = 1 })
	for i, name in data.busStops do
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1 + i }, content)
		local here = name == at
		local nextOne = at == "" and name == nextStop
		local dotColor = here and Color3.fromRGB(80, 210, 120) or nextOne and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(110, 115, 135)
		local dot = new("Frame", { Position = UDim2.fromOffset(10, 12), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = dotColor }, row)
		corner(dot, 9)
		if i < #data.busStops then
			new("Frame", { Position = UDim2.fromOffset(17, 30), Size = UDim2.fromOffset(4, 16), BackgroundColor3 = Color3.fromRGB(80, 85, 100), BorderSizePixel = 0 }, row)
		end
		text(row, name .. (here and "  🚌" or nextOne and "  ← едет сюда" or ""), 15, WHITE, here or nextOne, { Position = UDim2.fromOffset(40, 10), Size = UDim2.new(1, -40, 0, 22) })
	end
end

local function chatOf(name: string)
	chats[name] = chats[name] or { messages = {}, unread = 0, typingUntil = 0 }
	return chats[name]
end

local function renderMessages()
	list(content, 8)
	if not openChat then
		local names, seen = {}, {}
		for _, f in data.friends do
			table.insert(names, f)
			seen[f.name] = true
		end
		for name in pairs(chats) do
			if not seen[name] then
				table.insert(names, { name = name, level = "", icon = "" })
			end
		end
		if #names == 0 then
			local c = card(content, nil, 0)
			text(c, "Пока никто не пишет. Поговори с жителями — знакомые будут писать сюда!", 14, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 56) })
			return
		end
		for i, f in names do
			local chat = chatOf(f.name)
			local last = chat.messages[#chat.messages]
			local row = button(content, "", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 0.9 }, function()
				openChat = f.name
				chat.unread = 0
				updateBadges()
				renderApp()
			end)
			local hue = (string.byte(f.name, 1) or 0) % 6
			local avatar = new("TextLabel", { Position = UDim2.fromOffset(8, 9), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = Color3.fromHSV(hue / 6, 0.55, 0.85), Text = string.sub(f.name, 1, utf8.offset(f.name, 2) and utf8.offset(f.name, 2) - 1 or 1), TextSize = 20, Font = Enum.Font.GothamBold, TextColor3 = WHITE }, row)
			corner(avatar, 22)
			text(row, f.name .. (f.icon ~= "" and " " .. f.icon or ""), 15, WHITE, true, { Position = UDim2.fromOffset(62, 10), Size = UDim2.new(1, -100, 0, 20) })
			local preview = os.clock() < chat.typingUntil and "печатает…" or (last and ((last.mine and "Вы: " or "") .. last.text) or f.level)
			text(row, preview, 13, Color3.fromRGB(180, 190, 215), false, { Position = UDim2.fromOffset(62, 32), Size = UDim2.new(1, -100, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
			if chat.unread > 0 then
				local b = new("TextLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromRGB(60, 200, 100), Text = tostring(chat.unread), TextColor3 = WHITE, TextSize = 12, Font = Enum.Font.GothamBold }, row)
				corner(b, 11)
			end
		end
		return
	end

	-- Переписка
	appTitle.Text = "💬  " .. openChat
	local chat = chatOf(openChat)
	for i, m in chat.messages do
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i }, content)
		local bubble = new("TextLabel", {
			AnchorPoint = Vector2.new(m.mine and 1 or 0, 0),
			Position = m.mine and UDim2.fromScale(1, 0) or UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = m.mine and Color3.fromRGB(60, 130, 255) or Color3.fromRGB(55, 58, 75),
			Text = m.text,
			TextColor3 = WHITE,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		new("UISizeConstraint", { MaxSize = Vector2.new(190, math.huge) }, bubble)
		corner(bubble, 14)
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, bubble)
	end
	if os.clock() < chat.typingUntil then
		text(content, "  " .. openChat .. " печатает…", 13, Color3.fromRGB(160, 170, 195), false, { LayoutOrder = #chat.messages + 1 })
	end
	text(content, "Ответить:", 13, Color3.fromRGB(160, 170, 195), true, { LayoutOrder = 1000 })
	local replies = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1001 }, content)
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 34), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }, replies)
	for i, r in NPCConfig.Phone.Replies do
		button(replies, r.Text, { LayoutOrder = i, TextSize = 13, BackgroundColor3 = Color3.fromRGB(60, 130, 255), BackgroundTransparency = 0.3 }, function()
			table.insert(chat.messages, { mine = true, text = r.Text })
			if soundsOn then
				playSound(Sounds.Phone and Sounds.Phone.Send)
			end
			remote:FireServer("Reply", openChat, i)
			renderApp()
		end)
	end
	task.defer(function()
		content.CanvasPosition = Vector2.new(0, math.max(0, content.AbsoluteCanvasSize.Y - content.AbsoluteSize.Y))
	end)
end

local function bar(parent: Instance, label: string, value: number, color: Color3, order: number)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order }, parent)
	text(row, label, 13, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 16) })
	local back = new("Frame", { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Color3.fromRGB(60, 65, 80) }, row)
	corner(back, 4)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color }, back)
	corner(fill, 4)
	TweenService:Create(fill, SLIDE, { Size = UDim2.fromScale(math.clamp(value, 0, 1), 1) }):Play()
end

local function renderWeather()
	list(content, 10)
	local key = workspace:GetAttribute("Weather") or "Clear"
	local top = card(content, 150, 0)
	text(top, workspace:GetAttribute("WeatherIcon") or "☀️", 64, WHITE, true, { Size = UDim2.new(1, 0, 0, 76), TextXAlignment = Enum.TextXAlignment.Center })
	text(top, workspace:GetAttribute("WeatherName") or "", 22, WHITE, true, { Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	local t, d = clockText()
	text(top, t .. " · " .. d, 13, Color3.fromRGB(200, 210, 230), false, { Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	local details = card(content, nil, 1)
	list(details, 6)
	bar(details, "🌧 Дождь", workspace:GetAttribute("Rain") or 0, Color3.fromRGB(90, 160, 255), 1)
	bar(details, "☁️ Облачность", workspace:GetAttribute("Clouds") or 0, Color3.fromRGB(190, 195, 210), 2)
	bar(details, "🌫 Туман", workspace:GetAttribute("Fog") or 0, Color3.fromRGB(170, 175, 190), 3)
	local tips = {
		Clear = "Отличный день для прогулки! 😎",
		Cloudy = "Пасмурно, но без дождя.",
		Rain = "Возьми зонт ☂️ — жители прячутся по домам.",
		Storm = "Гроза! Лучше переждать под крышей ⚡",
		Fog = "Туман: на дорогах осторожнее 🚗",
	}
	local tip = card(content, nil, 2)
	text(tip, "💡 " .. (tips[key] or ""), 14, WHITE, false, { Size = UDim2.new(1, 0, 0, 40) })
end

local function renderQuests()
	list(content, 10)
	local quest = player:GetAttribute("QuestText")
	local q = card(content, nil, 0)
	list(q, 6)
	text(q, "Текущее задание", 15, WHITE, true)
	text(q, (type(quest) == "string" and quest ~= "") and ("❗ " .. quest) or "Нет активных заданий. Ищи жителей с ❗ над головой!", 14, Color3.fromRGB(220, 225, 240), false, { Size = UDim2.new(1, 0, 0, 40) })
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild(NPCConfig.CurrencyName)
	local c = card(content, nil, 1)
	list(c, 4)
	text(c, "🪙 " .. (coins and tostring(coins.Value) or "0") .. " " .. NPCConfig.CurrencyName, 20, Color3.fromRGB(255, 215, 90), true)
	text(c, "👥 Знакомых жителей: " .. #data.friends, 14, Color3.fromRGB(200, 210, 230), false)
	if #data.friends > 0 then
		local f = card(content, nil, 2)
		list(f, 4)
		text(f, "Друзья", 15, WHITE, true)
		for i, friend in data.friends do
			if i > 8 then
				break
			end
			text(f, string.format("%s — %s %s", friend.name, friend.level, friend.icon), 13, Color3.fromRGB(210, 215, 235), false)
		end
	end
end

local function toggleRow(parent: Instance, label: string, value: boolean, order: number, onChange)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order }, parent)
	text(row, label, 15, WHITE, false, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, -60, 0, 20) })
	local sw = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(48, 28), BackgroundColor3 = value and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(80, 85, 100), Text = "", AutoButtonColor = false }, row)
	corner(sw, 14)
	local knob = new("Frame", { Position = value and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = WHITE }, sw)
	corner(knob, 12)
	local state = value
	sw.Activated:Connect(function()
		state = not state
		tap()
		TweenService:Create(knob, FAST, { Position = state and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2) }):Play()
		TweenService:Create(sw, FAST, { BackgroundColor3 = state and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(80, 85, 100) }):Play()
		onChange(state)
	end)
end

local function renderSettings()
	list(content, 10)
	local c = card(content, nil, 0)
	list(c, 4)
	local clock = player.PlayerGui:FindFirstChild("ClockHud")
	toggleRow(c, "🕗 Часы на экране", clock == nil or clock.Enabled, 1, function(v)
		local hud = player.PlayerGui:FindFirstChild("ClockHud")
		if hud then
			hud.Enabled = v
		end
	end)
	toggleRow(c, "🌧 Капли дождя", player:GetAttribute("RainEffects") ~= false, 2, function(v)
		player:SetAttribute("RainEffects", v)
	end)
	toggleRow(c, "🔔 Звуки телефона", soundsOn, 3, function(v)
		soundsOn = v
	end)
	local w = card(content, nil, 1)
	list(w, 8)
	text(w, "🖼 Обои", 15, WHITE, true)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70) }, w)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }, row)
	for i, colors in WALLPAPERS do
		local sw = new("TextButton", { Size = UDim2.fromOffset(48, 70), BackgroundColor3 = WHITE, Text = i == wallpaperIndex and "✓" or "", TextColor3 = WHITE, TextSize = 20, Font = Enum.Font.GothamBold, AutoButtonColor = false }, row)
		corner(sw, 10)
		new("UIGradient", { Color = ColorSequence.new(colors[1], colors[2]), Rotation = 120 }, sw)
		if i == wallpaperIndex then
			new("UIStroke", { Color = WHITE, Thickness = 2 }, sw)
		end
		sw.Activated:Connect(function()
			wallpaperIndex = i
			tap()
			applyWallpaper()
			renderApp()
		end)
	end
end

---------------------------------------------------------------------
-- 📦 Работа, 🛍 Магазин, 🏆 Награды
---------------------------------------------------------------------

local function coinsText(): string
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild(NPCConfig.CurrencyName)
	return coins and tostring(coins.Value) or "0"
end

local function renderWork()
	list(content, 10)
	local stage = player:GetAttribute("JobStage")
	local top = card(content, nil, 0)
	list(top, 6)
	text(top, "📦 Курьер города", 17, WHITE, true)
	if not stage then
		text(top, "Забери посылку и отнеси её жителю. Получатель подсвечен, к нему ведёт золотой луч.", 13, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 52) })
		text(top, string.format("Награда: %d–%d 🪙, за %d с — ещё +%d ⚡", CityConfig.Job.Reward.Min, CityConfig.Job.Reward.Max, CityConfig.Job.FastTime, CityConfig.Job.FastBonus), 13, Color3.fromRGB(255, 220, 120), false, { Size = UDim2.new(1, 0, 0, 36) })
		button(content, "Взять заказ", { LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(60, 200, 100), BackgroundTransparency = 0.2, Font = Enum.Font.GothamBold }, function()
			remote:FireServer("Job")
		end)
	else
		text(top, player:GetAttribute("JobText") or "", 15, WHITE, true, { Size = UDim2.new(1, 0, 0, 40) })
		local ends = player:GetAttribute("JobEnds")
		local left = ends and math.max(0, ends - workspace:GetServerTimeNow()) or 0
		statusChip(top, string.format("⏱ %d:%02d", math.floor(left / 60), math.floor(left % 60)), left < 30 and Color3.fromRGB(255, 100, 90) or Color3.fromRGB(255, 190, 60))
		text(top, stage == "pickup" and "Шаг 1 из 2: забери посылку (кнопка у коробки)" or "Шаг 2 из 2: подойди к получателю", 13, Color3.fromRGB(200, 210, 230), false, { Size = UDim2.new(1, 0, 0, 34) })
		button(content, "Отменить заказ", { LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(240, 80, 80), BackgroundTransparency = 0.4 }, function()
			remote:FireServer("Job")
		end)
	end
	local stats = card(content, nil, 2)
	list(stats, 4)
	text(stats, "📊 Статистика", 15, WHITE, true)
	text(stats, "Доставлено посылок: " .. math.floor(city.stats.Delivery or 0), 14, Color3.fromRGB(210, 215, 235), false)
	text(stats, "🪙 " .. coinsText() .. " " .. NPCConfig.CurrencyName, 14, Color3.fromRGB(255, 215, 90), true)
end

local function contains(list: { string }, value: string): boolean
	for _, v in list do
		if v == value then
			return true
		end
	end
	return false
end

local function renderShop()
	list(content, 10)
	local top = card(content, nil, 0)
	text(top, "🪙 " .. coinsText() .. " " .. NPCConfig.CurrencyName, 20, Color3.fromRGB(255, 215, 90), true)
	local g = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 }, content)
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 132), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, g)
	for i, item in CityConfig.Shop do
		local owned = contains(city.owned, item.Id)
		local worn = contains(city.equipped, item.Id)
		local cell = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = worn and 0.75 or 0.88, LayoutOrder = i }, g)
		corner(cell, 14)
		if worn then
			new("UIStroke", { Color = Color3.fromRGB(120, 230, 140), Thickness = 2 }, cell)
		end
		text(cell, item.Icon, 34, WHITE, true, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
		text(cell, item.Name, 13, WHITE, true, { Position = UDim2.fromOffset(4, 52), Size = UDim2.new(1, -8, 0, 32), TextXAlignment = Enum.TextXAlignment.Center })
		local label = worn and "Снять" or owned and "Надеть" or (item.Price .. " 🪙")
		local color = worn and Color3.fromRGB(240, 90, 90) or owned and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(255, 190, 50)
		button(cell, label, { Position = UDim2.new(0, 8, 1, -40), Size = UDim2.new(1, -16, 0, 32), BackgroundColor3 = color, BackgroundTransparency = 0.25, TextSize = 13, Font = Enum.Font.GothamBold }, function()
			remote:FireServer(owned and "Equip" or "Buy", item.Id)
		end)
	end
	text(content, "Вещи остаются у тебя навсегда. В одном месте (голова, лицо...) — одна вещь.", 12, Color3.fromRGB(160, 170, 195), false, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 34) })
end

local function renderAwards()
	list(content, 8)
	local doneCount = 0
	for _, a in CityConfig.Achievements do
		if contains(city.done, a.Id) then
			doneCount += 1
		end
	end
	local top = card(content, nil, 0)
	list(top, 6)
	text(top, string.format("🏆 Получено: %d из %d", doneCount, #CityConfig.Achievements), 17, WHITE, true)
	bar(top, "", doneCount / math.max(1, #CityConfig.Achievements), Color3.fromRGB(255, 200, 60), 2)
	-- Сначала незавершённые, ближайшие к цели
	local order = {}
	for i, a in CityConfig.Achievements do
		local done = contains(city.done, a.Id)
		local progress = math.clamp((city.stats[a.Stat] or 0) / a.Goal, 0, 1)
		table.insert(order, { a = a, done = done, progress = progress, i = i })
	end
	table.sort(order, function(x, y)
		if x.done ~= y.done then
			return not x.done
		end
		if x.progress ~= y.progress then
			return x.progress > y.progress
		end
		return x.i < y.i
	end)
	for n, o in order do
		local a = o.a
		local row = card(content, 74, n)
		row.BackgroundTransparency = o.done and 0.8 or 0.9
		text(row, a.Icon, 30, WHITE, true, { Size = UDim2.fromOffset(40, 50), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = o.done and 0 or 0.35 })
		text(row, a.Name .. (o.done and "  ✓" or ""), 14, o.done and Color3.fromRGB(255, 215, 90) or WHITE, true, { Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -100, 0, 18) })
		text(row, a.Desc, 12, Color3.fromRGB(180, 190, 215), false, { Position = UDim2.fromOffset(48, 18), Size = UDim2.new(1, -48, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		text(row, "+" .. a.Reward .. " 🪙", 12, Color3.fromRGB(255, 215, 90), true, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(60, 18), TextXAlignment = Enum.TextXAlignment.Right })
		if not o.done then
			local back = new("Frame", { Position = UDim2.fromOffset(48, 40), Size = UDim2.new(1, -48, 0, 6), BackgroundColor3 = Color3.fromRGB(60, 65, 80) }, row)
			corner(back, 3)
			local fill = new("Frame", { Size = UDim2.fromScale(o.progress, 1), BackgroundColor3 = Color3.fromRGB(255, 190, 60) }, back)
			corner(fill, 3)
		end
	end
end

local RENDERERS = {
	map = renderMap,
	taxi = renderTaxi,
	police = renderPolice,
	bus = renderBus,
	messages = renderMessages,
	weather = renderWeather,
	quests = renderQuests,
	settings = renderSettings,
	work = renderWork,
	shop = renderShop,
	awards = renderAwards,
}

function renderApp()
	if not currentApp then
		return
	end
	clearContent()
	map.frame = nil
	local r = RENDERERS[currentApp]
	if r then
		r()
	end
end

---------------------------------------------------------------------
-- Открыть / закрыть
---------------------------------------------------------------------

local function fitScale(): number
	local view = workspace.CurrentCamera.ViewportSize
	return math.min(1, (view.Y - 40) / H)
end

local function setLocked(value: boolean)
	locked = value
	if value then
		lockLayer.Visible = true
		lockLayer.Position = UDim2.fromScale(0, 0)
		homeLayer.Visible = false
		appLayer.Visible = false
		currentApp = nil
		renderLock()
	else
		homeLayer.Visible = true
		if soundsOn then
			playSound(Sounds.Phone and Sounds.Phone.Unlock)
		end
		local slide = TweenService:Create(lockLayer, SLIDE, { Position = UDim2.fromScale(0, -1) })
		slide:Play()
		slide.Completed:Once(function()
			if not locked then
				lockLayer.Visible = false
			end
		end)
		renderHomeBadges()
	end
end
lockLayer.Activated:Connect(function()
	tap()
	setLocked(false)
end)

local function openPhone()
	if isOpen then
		return
	end
	isOpen = true
	peek.Visible = false
	remote:FireServer("Open")
	setLocked(true)
	updateClock()
	phone.Visible = true
	phoneScale.Scale = fitScale()
	phone.Position = UDim2.new(1, W + 60, 0.5, 0)
	TweenService:Create(phone, SLIDE, { Position = UDim2.new(1, -24, 0.5, 0) }):Play()
end

function closePhone()
	if not isOpen then
		return
	end
	isOpen = false
	local slide = TweenService:Create(phone, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.new(1, W + 60, 0.5, 0) })
	slide:Play()
	slide.Completed:Once(function()
		if not isOpen then
			phone.Visible = false
		end
	end)
end

local function togglePhone()
	if isOpen then
		closePhone()
	else
		openPhone()
	end
end
toggle.Activated:Connect(togglePhone)
ContextActionService:BindAction("TogglePhone", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		togglePhone()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.P, Enum.KeyCode.ButtonSelect)

---------------------------------------------------------------------
-- Сообщения от сервера
---------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action, payload)
	if action == "Data" then
		for k, v in pairs(payload) do
			if k == "city" then
				city = v
			else
				data[k] = v
			end
		end
		renderHomeBadges()
		if currentApp and currentApp ~= "map" then
			renderApp()
		end
	elseif action == "City" then
		city = payload
		if currentApp == "shop" or currentApp == "awards" or currentApp == "work" then
			renderApp()
		end
	elseif action == "Job" then
		if payload.text then
			notify("📦", "Работа", payload.text)
		elseif payload.ready then
			notify("📦", "Работа", "Есть новые заказы!")
		end
		renderHomeBadges()
		if currentApp == "work" then
			renderApp()
		end
	elseif action == "Achievement" then
		notify(payload.icon, "Достижение", payload.name .. "  +" .. payload.reward .. " 🪙")
	elseif action == "Friends" then
		data.friends = payload
		if currentApp == "messages" or currentApp == "quests" then
			renderApp()
		end
	elseif action == "Tickets" then
		data.tickets = payload
		renderHomeBadges()
		if currentApp == "police" then
			renderApp()
		end
	elseif action == "PoliceAnswer" then
		policeAnswer = payload
		notify("🚔", "Полиция", payload)
		if currentApp == "police" then
			renderApp()
		end
	elseif action == "Taxi" then
		taxiStatus = payload
		notify("🚕", "Такси", payload.text)
		renderHomeBadges()
		if currentApp == "taxi" then
			renderApp()
		end
	elseif action == "Typing" then
		local chat = chatOf(payload)
		chat.typingUntil = os.clock() + 4
		if currentApp == "messages" then
			renderApp()
		end
	elseif action == "Message" then
		local chat = chatOf(payload.from)
		chat.typingUntil = 0
		table.insert(chat.messages, { mine = false, text = payload.text })
		if #chat.messages > 40 then
			table.remove(chat.messages, 1)
		end
		local viewing = isOpen and currentApp == "messages" and openChat == payload.from
		if not viewing then
			chat.unread += 1
			notify("💬", payload.from, payload.text)
		end
		updateBadges()
		if currentApp == "messages" then
			renderApp()
		end
	end
end)

---------------------------------------------------------------------
-- Живые обновления
---------------------------------------------------------------------

local clockTimer, slowTimer = 0, 0
RunService.RenderStepped:Connect(function(dt)
	if not isOpen then
		return
	end
	local now = os.clock()
	clockTimer -= dt
	if clockTimer <= 0 then
		clockTimer = 1
		updateClock()
	end
	if currentApp == "map" then
		updateMap(now)
	end
	slowTimer -= dt
	if slowTimer <= 0 then
		slowTimer = 1.5
		if currentApp == "bus" or currentApp == "weather" or currentApp == "work" then
			renderApp()
		end
	end
end)

workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	phoneScale.Scale = fitScale()
end)

----------------------------------------------------------------------
-- 42. StarterPlayer → StarterPlayerScripts > LocalScript "CityLifeClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > CityLifeClient
-- Экранная часть новых механик (настройки — ReplicatedStorage > CityConfig):
--   📦 курьер: подсветка цели, стрелка-луч, таймер; персонажи несут коробку двумя руками;
--   🏆 большое золотое окно при новом достижении;
--   📷 фоторежим (из телефона): видоискатель, фильтры, зум, селфи, вспышка — жители позируют.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CityConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))
local remote = ReplicatedStorage:WaitForChild("PhoneRemote")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 70)
local POP = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function playSound(def)
	if not def or def.Id == "" then
		return
	end
	local s = new("Sound", { SoundId = def.Id, Volume = def.Volume or 0.4 }, workspace)
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local gui = new("ScreenGui", { Name = "CityLife", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5 }, playerGui)

---------------------------------------------------------------------
-- 📦 Коробка в руках (у всех персонажей с атрибутом CarryBox)
---------------------------------------------------------------------

local CARRY_POSE = {
	LeftShoulder = Vector3.new(70, 0, 8),
	RightShoulder = Vector3.new(70, 0, -8),
	LeftElbow = Vector3.new(25, 0, 0),
	RightElbow = Vector3.new(25, 0, 0),
	R6 = {
		LeftShoulder = Vector3.new(0, 0, -75),
		RightShoulder = Vector3.new(0, 0, 75),
	},
}

local function carryLayer(model: Model)
	local weight = 0
	return {
		Priority = 30,
		Update = function(rig, dt)
			local on = model:GetAttribute("CarryBox") == true
			weight = math.clamp(weight + (on and dt or -dt) * 5, 0, 1)
			if not on and weight <= 0 then
				return nil, 0, true
			end
			return RigAnimator.Frames(rig, CARRY_POSE), weight
		end,
	}
end

local function watchCharacter(character: Model)
	local function check()
		if character:GetAttribute("CarryBox") == true and not RigAnimator.HasLayer(character, "CarryBox") then
			RigAnimator.SetLayer(character, "CarryBox", carryLayer(character))
		end
	end
	character:GetAttributeChangedSignal("CarryBox"):Connect(check)
	check()
end
local function watchPlayer(p: Player)
	if p.Character then
		watchCharacter(p.Character)
	end
	p.CharacterAdded:Connect(watchCharacter)
end
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)

---------------------------------------------------------------------
-- 📦 Цель заказа: подсветка, значок, луч и карточка с таймером
---------------------------------------------------------------------

local jobCard = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.fromOffset(300, 54),
	BackgroundColor3 = Color3.fromRGB(25, 28, 40),
	BackgroundTransparency = 0.1,
	Visible = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, jobCard)
new("UIStroke", { Color = GOLD, Thickness = 1.5, Transparency = 0.3 }, jobCard)
local jobText = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 22), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, jobCard)
local jobInfo = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 18), Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.fromRGB(190, 200, 225), TextXAlignment = Enum.TextXAlignment.Left }, jobCard)

local highlight = new("Highlight", { FillColor = GOLD, FillTransparency = 0.85, OutlineColor = GOLD, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false }, camera)
local marker = new("BillboardGui", { Size = UDim2.fromOffset(60, 60), StudsOffset = Vector3.new(0, 4.2, 0), AlwaysOnTop = true, Enabled = false }, gui)
local markerIcon = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "📦", TextSize = 34, Font = Enum.Font.GothamBold }, marker)
local beamFrom = new("Attachment", { Name = "JobBeamFrom" })
local beamTo = new("Attachment", { Name = "JobBeamTo" })
local beam = new("Beam", {
	Attachment0 = beamFrom,
	Attachment1 = beamTo,
	Color = ColorSequence.new(GOLD),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.15, 0.4), NumberSequenceKeypoint.new(0.85, 0.4), NumberSequenceKeypoint.new(1, 0.9) }),
	Width0 = 0.25,
	Width1 = 0.25,
	FaceCamera = true,
	LightEmission = 0.8,
	Segments = 20,
	CurveSize0 = 6,
	CurveSize1 = -2,
	Enabled = false,
}, workspace.Terrain)
beamTo.Parent = workspace.Terrain

local function jobTarget(): Instance?
	local v = player:FindFirstChild("JobTarget")
	return v and (v :: ObjectValue).Value or nil
end

local function targetPart(target: Instance?): BasePart?
	if not target then
		return nil
	end
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		return (target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart) :: BasePart?
	end
	return nil
end

---------------------------------------------------------------------
-- 🏆 Новое достижение
---------------------------------------------------------------------

local award = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -140),
	Size = UDim2.fromOffset(340, 96),
	BackgroundColor3 = Color3.fromRGB(40, 32, 12),
	ZIndex = 50,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 20) }, award)
new("UIStroke", { Color = GOLD, Thickness = 2.5 }, award)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 225, 140), Color3.fromRGB(200, 140, 30)), Rotation = 90, Transparency = NumberSequence.new(0.75) }, award)
local awardIcon = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(72, 72), TextSize = 48, Font = Enum.Font.GothamBold, ZIndex = 51 }, award)
local awardIconScale = new("UIScale", {}, awardIcon)
new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(92, 14), Size = UDim2.new(1, -104, 0, 18), Text = "🏆 НОВОЕ ДОСТИЖЕНИЕ", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51 }, award)
local awardName = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(92, 34), Size = UDim2.new(1, -104, 0, 26), TextSize = 22, Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 51 }, award)
local awardReward = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(92, 62), Size = UDim2.new(1, -104, 0, 18), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(255, 225, 150), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51 }, award)

local awardQueue, showingAward = {}, false
local function showNextAward()
	if showingAward or #awardQueue == 0 then
		return
	end
	showingAward = true
	local a = table.remove(awardQueue, 1)
	awardIcon.Text, awardName.Text = a.icon, a.name
	awardReward.Text = string.format("+%d 🪙", a.reward)
	playSound(Sounds.Phone and Sounds.Phone.Notify)
	TweenService:Create(award, POP, { Position = UDim2.new(0.5, 0, 0, 20) }):Play()
	awardIconScale.Scale = 0.3
	TweenService:Create(awardIconScale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- Конфетти
	for _ = 1, 18 do
		local c = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.15, 0.5),
			Size = UDim2.fromOffset(7, 7),
			Rotation = math.random(0, 90),
			BackgroundColor3 = Color3.fromHSV(math.random(), 0.7, 1),
			BorderSizePixel = 0,
			ZIndex = 52,
		}, award)
		local angle = math.random() * math.pi * 2
		local dist = math.random(40, 110)
		local tween = TweenService:Create(c, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.15, math.cos(angle) * dist, 0.5, math.sin(angle) * dist),
			Rotation = c.Rotation + 180,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			c:Destroy()
		end)
	end
	task.delay(3.6, function()
		local hide = TweenService:Create(award, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -140) })
		hide:Play()
		hide.Completed:Wait()
		showingAward = false
		showNextAward()
	end)
end

remote.OnClientEvent:Connect(function(action, payload)
	if action == "Achievement" then
		table.insert(awardQueue, payload)
		showNextAward()
	end
end)

---------------------------------------------------------------------
-- 📷 Фоторежим (включается из телефона: атрибут игрока PhotoMode = true)
---------------------------------------------------------------------

local photoGui = new("ScreenGui", { Name = "PhotoMode", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false, DisplayOrder = 20 }, playerGui)
local frameLines = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, photoGui)
-- Уголки видоискателя
for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
	local x, y = c[1], c[2]
	local holder = new("Frame", { AnchorPoint = Vector2.new(x, y), Position = UDim2.new(x, x == 0 and 30 or -30, y, y == 0 and 30 or -30), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1 }, frameLines)
	new("Frame", { AnchorPoint = Vector2.new(x, y), Position = UDim2.fromScale(x, y), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, holder)
	new("Frame", { AnchorPoint = Vector2.new(x, y), Position = UDim2.fromScale(x, y), Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, holder)
end
-- Сетка третей
for i = 1, 2 do
	new("Frame", { Position = UDim2.fromScale(i / 3, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, frameLines)
	new("Frame", { Position = UDim2.fromScale(0, i / 3), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, frameLines)
end
local rec = new("TextLabel", { Position = UDim2.fromOffset(44, 40), Size = UDim2.fromOffset(160, 24), BackgroundTransparency = 1, Text = "● ФОТО", TextColor3 = Color3.fromRGB(255, 80, 80), Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left }, frameLines)

local controls = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(560, 150), BackgroundTransparency = 1 }, photoGui)
new("UISizeConstraint", { MaxSize = Vector2.new(560, 150) }, controls)

local function pill(parent: Instance, label: string, size: UDim2, position: UDim2, onClick)
	local b = new("TextButton", { Size = size, Position = position, BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.3, Text = label, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 15, AutoButtonColor = true }, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	b.Activated:Connect(onClick)
	return b
end

local filterRow = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X }, controls)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }, filterRow)

local shutter = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(84, 84), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, controls)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, shutter)
new("UIStroke", { Color = Color3.fromRGB(200, 200, 210), Thickness = 5 }, shutter)
local shutterScale = new("UIScale", {}, shutter)

local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 100 }, photoGui)
local zoomLabel = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 40), Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 1, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right }, frameLines)

local photo = { on = false, fov = 70, baseFov = 70, filter = 1, selfie = false, selfieAngle = 0, hiddenGuis = {} }
local grade = nil -- ColorCorrectionEffect фильтра

local function applyFilter(index: number)
	photo.filter = index
	local f = Config.Photo.Filters[index]
	if not grade then
		grade = new("ColorCorrectionEffect", { Name = "PhotoFilter" }, Lighting)
	end
	grade.TintColor = f.Tint or WHITE
	grade.Saturation = f.Saturation or 0
	grade.Contrast = f.Contrast or 0
	grade.Brightness = f.Brightness or 0
	for _, b in filterRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = b.LayoutOrder == index and GOLD or Color3.fromRGB(20, 22, 30)
			b.TextColor3 = b.LayoutOrder == index and Color3.fromRGB(30, 25, 10) or WHITE
		end
	end
end

for i, f in Config.Photo.Filters do
	local b = pill(filterRow, f.Name, UDim2.fromOffset(0, 34), UDim2.new(), function()
		applyFilter(i)
	end)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.LayoutOrder = i
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, b)
end

local function setZoom(fov: number)
	photo.fov = math.clamp(fov, 20, 90)
	zoomLabel.Text = string.format("🔍 %.1f×", photo.baseFov / photo.fov)
end

local exitPhoto -- объявлена ниже

pill(controls, "✕", UDim2.fromOffset(52, 52), UDim2.new(0, 10, 1, -68), function()
	exitPhoto()
end)
local selfieButton = pill(controls, "🤳 Селфи", UDim2.fromOffset(120, 44), UDim2.new(0, 72, 1, -64), function()
	photo.selfie = not photo.selfie
	photo.selfieAngle = 0
end)
pill(controls, "−", UDim2.fromOffset(44, 44), UDim2.new(1, -164, 1, -64), function()
	setZoom(photo.fov + 10)
end)
pill(controls, "+", UDim2.fromOffset(44, 44), UDim2.new(1, -112, 1, -64), function()
	setZoom(photo.fov - 10)
end)
local hideButton = pill(controls, "👁", UDim2.fromOffset(44, 44), UDim2.new(1, -56, 1, -64), function() end)

local function takePhoto()
	if not photo.on then
		return
	end
	shutterScale.Scale = 0.85
	TweenService:Create(shutterScale, POP, { Scale = 1 }):Play()
	playSound(Sounds.Phone and (Sounds.Phone.Shutter and Sounds.Phone.Shutter.Id ~= "" and Sounds.Phone.Shutter or Sounds.Phone.Tap))
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	remote:FireServer("Photo")
end
shutter.Activated:Connect(takePhoto)

-- Спрятать интерфейс на 3 секунды — чтобы сделать чистый скриншот
hideButton.Activated:Connect(function()
	controls.Visible = false
	frameLines.Visible = false
	task.delay(3, function()
		if photo.on then
			controls.Visible = true
			frameLines.Visible = true
		end
	end)
end)

local function enterPhoto()
	if photo.on then
		return
	end
	photo.on = true
	photo.baseFov = camera.FieldOfView
	setZoom(photo.baseFov)
	photo.selfie = false
	photo.hiddenGuis = {}
	for _, g in playerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= photoGui and g.Enabled then
			g.Enabled = false
			table.insert(photo.hiddenGuis, g)
		end
	end
	photoGui.Enabled = true
	controls.Visible = true
	frameLines.Visible = true
	applyFilter(photo.filter)
	ContextActionService:BindActionAtPriority("PhotoShutter", function(_, state)
		if state == Enum.UserInputState.Begin then
			takePhoto()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Return, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority("PhotoExit", function(_, state)
		if state == Enum.UserInputState.Begin then
			exitPhoto()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.P, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
end

function exitPhoto()
	if not photo.on then
		return
	end
	photo.on = false
	player:SetAttribute("PhotoMode", false)
	ContextActionService:UnbindAction("PhotoShutter")
	ContextActionService:UnbindAction("PhotoExit")
	photoGui.Enabled = false
	for _, g in photo.hiddenGuis do
		if g.Parent then
			g.Enabled = true
		end
	end
	photo.hiddenGuis = {}
	if grade then
		grade:Destroy()
		grade = nil
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = photo.baseFov
end

player:GetAttributeChangedSignal("PhotoMode"):Connect(function()
	if player:GetAttribute("PhotoMode") == true then
		enterPhoto()
	else
		exitPhoto()
	end
end)
player.CharacterRemoving:Connect(exitPhoto)

-- Селфи: поворот камеры вокруг лица — перетаскиванием мыши/пальца
UserInputService.InputChanged:Connect(function(input, processed)
	if photo.on and photo.selfie and not processed then
		if input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			or input.UserInputType == Enum.UserInputType.Touch then
			photo.selfieAngle = math.clamp(photo.selfieAngle - input.Delta.X * 0.006, -1.4, 1.4)
		end
	end
	if photo.on and input.UserInputType == Enum.UserInputType.MouseWheel then
		setZoom(photo.fov - input.Position.Z * 4)
	end
end)

---------------------------------------------------------------------
-- Каждый кадр
---------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Заказ курьера
	local stage = player:GetAttribute("JobStage")
	local target = targetPart(jobTarget())
	local active = stage ~= nil and target ~= nil and root ~= nil and not photo.on
	jobCard.Visible = stage ~= nil and not photo.on
	highlight.Enabled = active
	marker.Enabled = active
	beam.Enabled = active
	if stage then
		jobText.Text = "📦 " .. (player:GetAttribute("JobText") or "")
		local ends = player:GetAttribute("JobEnds")
		local left = ends and math.max(0, ends - workspace:GetServerTimeNow()) or 0
		local dist = (target and root) and math.floor((target.Position - root.Position).Magnitude) or 0
		jobInfo.Text = string.format("⏱ %d:%02d   📍 %d стадов", math.floor(left / 60), math.floor(left % 60), dist)
		jobInfo.TextColor3 = left < 30 and Color3.fromRGB(255, 120, 100) or Color3.fromRGB(190, 200, 225)
	end
	if active and target and root then
		local model = target:FindFirstAncestorOfClass("Model")
		highlight.Adornee = (model and model ~= workspace and model:FindFirstChildOfClass("Humanoid")) and model or target
		marker.Adornee = target
		marker.StudsOffset = Vector3.new(0, 4.2 + math.sin(now * 4) * 0.3, 0)
		markerIcon.Text = stage == "pickup" and "📦" or "🎁"
		beamFrom.Parent = root
		beamFrom.Position = Vector3.new(0, -1.5, 0)
		beamTo.WorldPosition = target.Position + Vector3.new(0, -1, 0)
		beam.TextureSpeed = 1
	end

	-- Фоторежим
	if photo.on then
		rec.TextTransparency = (now % 1 < 0.5) and 0 or 0.6
		camera.FieldOfView += (photo.fov - camera.FieldOfView) * math.min(1, dt * 10)
		local head = character and character:FindFirstChild("Head") :: BasePart?
		selfieButton.Text = photo.selfie and "🎥 Обычная" or "🤳 Селфи"
		if photo.selfie and head and root then
			camera.CameraType = Enum.CameraType.Scriptable
			local look = root.CFrame.LookVector
			local dir = (CFrame.Angles(0, photo.selfieAngle, 0) * Vector3.new(look.X, 0, look.Z)).Unit
			local eye = head.Position + dir * 6 + Vector3.new(0, 0.8, 0)
			camera.CFrame = CFrame.lookAt(eye, head.Position + Vector3.new(0, 0.2, 0))
		elseif camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end)

----------------------------------------------------------------------
-- 43. StarterPlayer → StarterPlayerScripts > LocalScript "DebugClient"
----------------------------------------------------------------------

-- LocalScript: StarterPlayer > StarterPlayerScripts > DebugClient
-- Меню отладки: F2 или кнопка 🛠 (только у админов, см. DebugConfig).
-- Вкладки:
--   📋 Новое     — что добавлено в каждом обновлении + проверки с кнопкой «▶» и отметками ✓ / 🐞
--   🌍 Мир       — время, ускорение, погода, вызов полиции, монеты, кулдауны, телепорт
--   🧑 Жители    — что делает каждый житель, куда идёт; следить камерой, телепорт
--   🚗 Машины    — тип, состояние, скорость, куда едет; следить, телепорт
--   🗺 Метки     — показать на карте дороги, точки, двери, парковки, пути жителей, маршруты машин
--   🖥 Output    — сообщения сервера и клиента, фильтры, копирование
--   ✅ Проверка  — автопроверка разметки карты и установки скриптов

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DebugConfig"))
if not Config.Enabled then
	return
end
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local WeatherConfig = require(ReplicatedStorage:WaitForChild("WeatherConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- Меню только для админов: сервер ставит атрибут DebugAdmin
if player:GetAttribute("DebugAdmin") ~= true then
	player:GetAttributeChangedSignal("DebugAdmin"):Wait()
end
local remote = ReplicatedStorage:WaitForChild("DebugRemote")

local W, H = 480, 560
local C = {
	bg = Color3.fromRGB(16, 18, 26),
	panel = Color3.fromRGB(26, 29, 40),
	panel2 = Color3.fromRGB(34, 38, 52),
	text = Color3.fromRGB(235, 238, 248),
	dim = Color3.fromRGB(150, 158, 185),
	accent = Color3.fromRGB(90, 150, 255),
	ok = Color3.fromRGB(80, 210, 120),
	warn = Color3.fromRGB(255, 190, 60),
	error = Color3.fromRGB(255, 85, 85),
	event = Color3.fromRGB(190, 140, 255),
	debug = Color3.fromRGB(110, 200, 255),
}

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local function corner(p: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end
local function label(parent: Instance, text: string, size: number, color: Color3?, bold: boolean?, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color or C.text,
		Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end
local function btn(parent: Instance, text: string, props, onClick)
	local b = new("TextButton", {
		BackgroundColor3 = C.panel2,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
	}, parent)
	for k, v in pairs(props or {}) do
		(b :: any)[k] = v
	end
	corner(b, 8)
	if b.AutomaticSize == Enum.AutomaticSize.X then
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, b)
	end
	b.Activated:Connect(onClick)
	return b
end
local function vlist(parent: Instance, gap: number)
	return new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end
local function hflow(parent: Instance, order: number?)
	local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order or 0 }, parent)
	local layout = new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	pcall(function()
		layout.Wraps = true -- кнопки переносятся на новую строку
	end)
	return f
end
local function section(parent: Instance, title: string, order: number)
	local s = new("Frame", { BackgroundColor3 = C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, parent)
	corner(s, 10)
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, s)
	vlist(s, 6)
	label(s, title, 14, C.text, true, { LayoutOrder = 0 })
	return s
end

---------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "DebugMenu", ResetOnSpawn = false, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)

local toggle = new("TextButton", {
	Position = UDim2.new(0, 16, 0, 110),
	Size = UDim2.fromOffset(44, 44),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.1,
	Text = "🛠",
	TextSize = 22,
	Font = Enum.Font.GothamBold,
}, gui)
corner(toggle, 12)
new("UIStroke", { Color = C.accent, Thickness = 1.5, Transparency = 0.3 }, toggle)
local errBadge = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 0, 2), Size = UDim2.fromOffset(22, 18), BackgroundColor3 = C.error, TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = Enum.Font.GothamBold, Visible = false, ZIndex = 3 }, toggle)
corner(errBadge, 9)

local win = new("Frame", {
	Position = UDim2.new(0, 70, 0, 80),
	Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = C.bg,
	Visible = false,
}, gui)
corner(win, 14)
new("UIStroke", { Color = Color3.fromRGB(60, 70, 100), Thickness = 1.5 }, win)
local winScale = new("UIScale", {}, win)

local titleBar = new("TextButton", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, win)
label(titleBar, "🛠  Меню отладки", 15, C.text, true, { Position = UDim2.fromOffset(14, 9), Size = UDim2.new(1, -60, 0, 18), AutomaticSize = Enum.AutomaticSize.None })
btn(titleBar, "✕", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(28, 28), AutomaticSize = Enum.AutomaticSize.None, BackgroundTransparency = 1 }, function()
	win.Visible = false
end)

-- Перетаскивание за заголовок
do
	local dragging, start, startPos
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, start, startPos = true, input.Position, win.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - start
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local TABS = {
	{ id = "news", text = "📋 Новое" },
	{ id = "world", text = "🌍 Мир" },
	{ id = "npcs", text = "🧑 Жители" },
	{ id = "cars", text = "🚗 Машины" },
	{ id = "overlay", text = "🗺 Метки" },
	{ id = "output", text = "🖥 Output" },
	{ id = "check", text = "✅ Проверка" },
}
local tabBar = new("ScrollingFrame", { Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, -16, 0, 32), BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X }, win)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)

local body = new("ScrollingFrame", {
	Position = UDim2.fromOffset(8, 76),
	Size = UDim2.new(1, -16, 1, -112),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, win)

local footer = label(win, "", 11, C.dim, false, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -8), Size = UDim2.new(1, -24, 0, 26), AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Center })
local resultToast = label(win, "", 12, C.debug, true, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -34), Size = UDim2.new(1, -24, 0, 0), Visible = false })

---------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------

local currentTab = "news"
local logs = {} -- { t, kind, text, src }
local tested = {}
local placeNames = {}
local snapshot = { npcs = {}, cars = {}, perf = {} }
local checks = nil
local unseenErrors = 0
local outputFilter, outputPaused, outputSearch = "all", false, ""
local followTarget = nil
local overlays = {} -- [слой] = true
local npcSearch = ""
local render -- объявлена ниже

local function addLog(entry)
	table.insert(logs, entry)
	if #logs > Config.LogLimit then
		table.remove(logs, 1)
	end
	if entry.kind == "error" and not (win.Visible and currentTab == "output") then
		unseenErrors += 1
	end
end

local function updateBadge()
	errBadge.Visible = unseenErrors > 0
	errBadge.Text = tostring(math.min(unseenErrors, 99))
end

-- Output клиента
local CLIENT_KIND = {
	[Enum.MessageType.MessageOutput] = "info",
	[Enum.MessageType.MessageInfo] = "info",
	[Enum.MessageType.MessageWarning] = "warn",
	[Enum.MessageType.MessageError] = "error",
}
for _, m in LogService:GetLogHistory() do
	addLog({ t = workspace:GetServerTimeNow(), kind = CLIENT_KIND[m.messageType] or "info", text = m.message, src = "C" })
end
local outputDirty = false
LogService.MessageOut:Connect(function(message, messageType)
	addLog({ t = workspace:GetServerTimeNow(), kind = CLIENT_KIND[messageType] or "info", text = message, src = "C" })
	outputDirty = true
	updateBadge()
end)

local function showResult(text: string)
	resultToast.Text = "→ " .. text
	resultToast.Visible = true
	local token = os.clock()
	resultToast:SetAttribute("Token", token)
	task.delay(3, function()
		if resultToast:GetAttribute("Token") == token then
			resultToast.Visible = false
		end
	end)
end

local function action(name: string, arg: any)
	remote:FireServer("Action", name, arg)
end

---------------------------------------------------------------------
-- 🗺 Слои меток на карте (видны только тебе)
---------------------------------------------------------------------

local overlayRoot = new("Folder", { Name = "DebugOverlay" }, camera)
local layerFolders = {}
local LAYERS = {
	{ id = "Roads", name = "🛣 Дороги: точки, связи, имена", color = Color3.fromRGB(255, 220, 60) },
	{ id = "Points", name = "📍 Точки жителей (Activity / Zone)", color = Color3.fromRGB(80, 210, 255) },
	{ id = "Spawns", name = "🐣 Точки появления", color = Color3.fromRGB(120, 255, 120) },
	{ id = "Doors", name = "🚪 Двери", color = Color3.fromRGB(255, 150, 60) },
	{ id = "Parking", name = "🅿️ Парковки", color = Color3.fromRGB(110, 140, 255) },
	{ id = "BusStops", name = "🚏 Остановки", color = Color3.fromRGB(255, 120, 200) },
	{ id = "Police", name = "🚔 Участок и вызовы", color = Color3.fromRGB(60, 120, 255) },
	{ id = "Places", name = "📌 Места (Places)", color = Color3.fromRGB(255, 255, 255) },
	{ id = "NPCPaths", name = "🧭 Пути жителей (живые)", color = Color3.fromRGB(80, 255, 200) },
	{ id = "CarRoutes", name = "🚗 Маршруты машин (живые)", color = Color3.fromRGB(255, 90, 90) },
	{ id = "NPCLabels", name = "🏷 Ярлыки над жителями (живые)", color = Color3.fromRGB(255, 255, 255) },
}
local LAYER_COLOR = {}
for _, l in LAYERS do
	LAYER_COLOR[l.id] = l.color
end

local function layerFolder(id: string): Folder
	local f = layerFolders[id]
	if not f then
		f = new("Folder", { Name = id }, overlayRoot)
		layerFolders[id] = f
	end
	return f
end

local function line(parent: Instance, a: Vector3, b: Vector3, color: Color3, width: number?)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return
	end
	new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.25,
		Size = Vector3.new(width or 0.2, width or 0.2, len),
		CFrame = CFrame.lookAt((a + b) / 2, b),
	}, parent)
end

local function tag(parent: Instance, adornee: Instance?, position: Vector3?, text: string, color: Color3, offset: number?)
	local holder = adornee
	if not holder then
		holder = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1), Position = position }, parent)
	end
	local bb = new("BillboardGui", { Adornee = holder, Size = UDim2.fromOffset(220, 40), StudsOffset = Vector3.new(0, offset or 2, 0), AlwaysOnTop = true, MaxDistance = 180, LightInfluence = 0 }, parent)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextWrapped = true,
	}, bb)
	return bb
end

local function markPart(parent: Instance, part: BasePart, color: Color3, text: string?)
	new("BoxHandleAdornment", { Adornee = part, Size = part.Size + Vector3.new(0.05, 0.05, 0.05), Color3 = color, Transparency = 0.45, AlwaysOnTop = true, ZIndex = 1 }, parent)
	-- Стрелка «передняя грань»
	line(parent, part.Position, part.Position + part.CFrame.LookVector * math.max(2, part.Size.Z / 2 + 1), color, 0.15)
	if text then
		tag(parent, part, nil, text, color, 1.5)
	end
end

local function partsIn(folder: Instance?): { BasePart }
	local out = {}
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	return out
end

local function attrText(p: Instance, keys: { string }): string
	local bits = { p.Name }
	for _, k in keys do
		local v = p:GetAttribute(k)
		if v ~= nil then
			table.insert(bits, k .. "=" .. tostring(v))
		end
	end
	return table.concat(bits, "  ")
end

local function buildStatic(id: string)
	local f = layerFolder(id)
	f:ClearAllChildren()
	local npcRoot = workspace:FindFirstChild(NPCConfig.FolderName)
	local map = workspace:FindFirstChild(VehicleConfig.MapFolder)
	local color = LAYER_COLOR[id]
	if id == "Roads" then
		remote:FireServer("Nodes")
		return -- рисуем, когда придёт граф
	elseif id == "Points" and npcRoot then
		for _, p in partsIn(npcRoot:FindFirstChild("Points")) do
			markPart(f, p, color, p:IsA("Seat") and ("🪑 " .. tostring(p:GetAttribute("Zone"))) or attrText(p, { "Activity", "Zone", "Role", "Route", "Order" }))
		end
	elseif id == "Spawns" and npcRoot then
		for _, p in partsIn(npcRoot:FindFirstChild("Spawns")) do
			markPart(f, p, color, attrText(p, { "Count", "Zone" }))
		end
	elseif id == "Doors" and npcRoot then
		local doors = npcRoot:FindFirstChild("Doors")
		for _, d in doors and doors:GetChildren() or {} do
			local part = d:IsA("BasePart") and d or (d:IsA("Model") and (d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")))
			if part then
				markPart(f, part, color, attrText(d, { "Hinge", "Locked" }))
			end
		end
	elseif id == "Parking" and map then
		for _, p in partsIn(map:FindFirstChild("Parking")) do
			markPart(f, p, color, attrText(p, { "Type", "Zone" }))
		end
	elseif id == "BusStops" and map then
		for _, p in partsIn(map:FindFirstChild("BusStops")) do
			markPart(f, p, color, attrText(p, { "Order", "StopName", "Node" }))
		end
	elseif id == "Police" and map then
		for _, p in partsIn(map:FindFirstChild("PoliceStation")) do
			markPart(f, p, color, "🚔 " .. p.Name)
		end
		for _, p in partsIn(map:FindFirstChild("PoliceCalls")) do
			markPart(f, p, Color3.fromRGB(150, 180, 255), attrText(p, { "Zone" }))
		end
	elseif id == "Places" and map then
		for _, p in partsIn(map:FindFirstChild("Places")) do
			markPart(f, p, color, "📌 " .. tostring(p:GetAttribute("PlaceName") or p.Name))
		end
	end
end

local function drawRoads(nodes)
	local f = layerFolder("Roads")
	f:ClearAllChildren()
	local color = LAYER_COLOR.Roads
	for name, n in pairs(nodes) do
		local holder = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = n.pos + Vector3.new(0, 0.6, 0), Material = Enum.Material.Neon, Color = #n.links == 0 and C.error or color }, f)
		tag(f, holder, nil, name .. (#n.links <= 1 and "  (тупик)" or ""), #n.links == 0 and C.error or color, 1.6)
		for _, other in n.links do
			local o = nodes[other]
			if o then
				local a, b = n.pos + Vector3.new(0, 0.6, 0), o.pos + Vector3.new(0, 0.6, 0)
				line(f, a, b, color, 0.18)
				-- Стрелка направления в середине связи
				local mid = a:Lerp(b, 0.6)
				local dir = (b - a).Unit
				local side = dir:Cross(Vector3.yAxis)
				line(f, mid, mid - dir * 1.2 + side * 0.6, color, 0.14)
				line(f, mid, mid - dir * 1.2 - side * 0.6, color, 0.14)
			end
		end
	end
end

local function drawDynamic()
	if overlays.NPCPaths then
		local f = layerFolder("NPCPaths")
		f:ClearAllChildren()
		for _, n in snapshot.npcs do
			if n.goal then
				line(f, n.pos, n.goal, LAYER_COLOR.NPCPaths, 0.12)
				new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), Position = n.goal, Material = Enum.Material.Neon, Color = LAYER_COLOR.NPCPaths }, f)
			end
		end
	end
	if overlays.CarRoutes then
		local f = layerFolder("CarRoutes")
		f:ClearAllChildren()
		for _, car in snapshot.cars do
			local prev = car.pos
			for _, p in car.route or {} do
				line(f, prev + Vector3.new(0, 1, 0), p + Vector3.new(0, 1, 0), LAYER_COLOR.CarRoutes, 0.16)
				prev = p
			end
		end
	end
	if overlays.NPCLabels then
		local f = layerFolder("NPCLabels")
		f:ClearAllChildren()
		for _, n in snapshot.npcs do
			if n.model and n.model.Parent then
				local head = n.model:FindFirstChild("Head")
				if head then
					tag(f, head, nil, n.name .. "\n" .. n.action, n.officer and Color3.fromRGB(150, 180, 255) or Color3.new(1, 1, 1), 3.4)
				end
			end
		end
		for _, car in snapshot.cars do
			if car.model and car.model.Parent then
				tag(f, car.model.PrimaryPart, nil, string.format("%s · %s · %s → %s", car.kind, car.state, tostring(car.speed), tostring(car.to or "—")), LAYER_COLOR.CarRoutes, 4)
			end
		end
	end
end

local function setOverlay(id: string, on: boolean)
	overlays[id] = on or nil
	if on then
		if id == "NPCPaths" or id == "CarRoutes" or id == "NPCLabels" then
			remote:FireServer("Snapshot")
		else
			buildStatic(id)
		end
	elseif layerFolders[id] then
		layerFolders[id]:ClearAllChildren()
	end
end

---------------------------------------------------------------------
-- Слежение камерой
---------------------------------------------------------------------

local followBar = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(320, 36), BackgroundColor3 = C.bg, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 14, Visible = false }, gui)
corner(followBar, 12)
new("UIStroke", { Color = C.accent, Thickness = 1.5 }, followBar)

local function stopFollow()
	followTarget = nil
	followBar.Visible = false
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end
followBar.Activated:Connect(stopFollow)

local function follow(model: Instance?, name: string)
	if not model or not model.Parent then
		return
	end
	local subject = model:FindFirstChildOfClass("Humanoid") or (model:IsA("Model") and model.PrimaryPart) or model
	camera.CameraSubject = subject
	followTarget = model
	followBar.Text = "👁 Слежу за: " .. name .. "   (нажми, чтобы вернуться)"
	followBar.Visible = true
end

---------------------------------------------------------------------
-- Вкладки
---------------------------------------------------------------------

local function clearBody()
	for _, c in body:GetChildren() do
		c:Destroy()
	end
	vlist(body, 8)
end

local function testKey(entry, i: number): string
	return entry.Version .. "#" .. i
end

local function renderNews()
	local total, done, bugs = 0, 0, 0
	for _, e in Config.Changelog do
		for i in e.Tests or {} do
			total += 1
			local s = tested[testKey(e, i)]
			if s == "ok" then
				done += 1
			elseif s == "bug" then
				bugs += 1
			end
		end
	end
	local top = section(body, string.format("Проверено %d из %d   🐞 багов: %d", done, total, bugs), 0)
	label(top, "▶ — подготовить проверку (время, погода, телепорт...). ✓ — работает, 🐞 — баг. Отметки сохраняются.", 12, C.dim, false, { LayoutOrder = 1 })
	for order, e in Config.Changelog do
		local s = section(body, "v" .. e.Version .. " — " .. e.Title, order)
		for _, item in e.Items or {} do
			label(s, "• " .. item, 12, C.dim, false, { LayoutOrder = 1 })
		end
		for i, t in e.Tests or {} do
			local key = testKey(e, i)
			local state = tested[key]
			local row = new("Frame", { BackgroundColor3 = state == "ok" and Color3.fromRGB(28, 56, 38) or state == "bug" and Color3.fromRGB(64, 28, 30) or C.panel2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 10 + i }, s)
			corner(row, 8)
			new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 104) }, row)
			label(row, t.Text, 12, C.text, false)
			local buttons = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 100, 0.5, 0), Size = UDim2.fromOffset(96, 26), BackgroundTransparency = 1 }, row)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Right }, buttons)
			if t.Action then
				btn(buttons, "▶", { Size = UDim2.fromOffset(28, 26), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = C.accent }, function()
					if t.Action == "Overlay" then
						setOverlay(t.Arg, true)
						showResult("Слой включён: " .. tostring(t.Arg))
					elseif t.Action == "Tab" then
						currentTab = t.Arg
						render()
					else
						action(t.Action, t.Arg)
					end
				end)
			end
			for _, mark in { { "ok", "✓", C.ok }, { "bug", "🐞", C.error } } do
				btn(buttons, mark[2], { Size = UDim2.fromOffset(28, 26), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = state == mark[1] and mark[3] or C.panel }, function()
					local value = tested[key] ~= mark[1] and mark[1] or nil
					tested[key] = value
					remote:FireServer("Tested", key, value)
					render()
				end)
			end
		end
	end
end

local function renderWorld()
	local p = snapshot.perf or {}
	local time = section(body, string.format("🕗 Время: %s  %s  (день %s, ×%s)", tostring(p.hour or "?"), tostring(p.period or ""), tostring(p.day or "?"), tostring(p.timeScale or 1)), 1)
	local hours = hflow(time, 1)
	for _, h in { { 3, "3:00" }, { 7, "7:00" }, { 9.5, "9:30" }, { 13.5, "13:30" }, { 16, "16:00" }, { 19, "19:00" }, { 22, "22:00" } } do
		btn(hours, h[2], {}, function()
			action("SetHour", h[1])
		end)
	end
	local speed = hflow(time, 2)
	for _, x in { 0, 1, 5, 20, 60 } do
		btn(speed, x == 0 and "⏸ Пауза" or ("×" .. x), { BackgroundColor3 = (p.timeScale or 1) == x and C.accent or C.panel2 }, function()
			action("TimeScale", x)
		end)
	end

	local weather = section(body, "🌦 Погода: " .. tostring(p.weather or "?"), 2)
	local wf = hflow(weather, 1)
	for key, t in pairs(WeatherConfig.Types) do
		btn(wf, t.Icon .. " " .. t.Name, {}, function()
			action("Weather", key)
		end)
	end

	local police = section(body, "🚔 Вызов полиции (место — ближайшее к тебе)", 3)
	local pf = hflow(police, 1)
	for i, t in VehicleConfig.PoliceCallTypes do
		btn(pf, t.Icon .. " " .. t.Name, {}, function()
			action("PoliceCall", i)
		end)
	end

	local me = section(body, "🙋 Игрок", 4)
	local mf = hflow(me, 1)
	btn(mf, "+100 🪙", {}, function()
		action("Coins", 100)
	end)
	btn(mf, "⏱ Сбросить кулдауны", {}, function()
		action("ResetCooldowns")
	end)
	btn(mf, "❤️ Вылечить", {}, function()
		action("Heal")
	end)
	btn(mf, "📦 Заказ курьера", {}, function()
		action("StartJob")
	end)
	btn(mf, "🗑 Сбросить прогресс", { BackgroundColor3 = Color3.fromRGB(90, 40, 40) }, function()
		action("ResetCity")
	end)

	local tp = section(body, "📍 Телепорт", 5)
	local tf = hflow(tp, 1)
	btn(tf, "👮 Дежурный", {}, function()
		action("Teleport", "Desk")
	end)
	btn(tf, "🔒 Камера", {}, function()
		action("Teleport", "Cell")
	end)
	btn(tf, "🚏 Остановка 1", {}, function()
		action("Teleport", "Stop:1")
	end)
	for _, name in placeNames do
		btn(tf, "📌 " .. name, {}, function()
			action("Teleport", "Place:" .. name)
		end)
	end
end

local function renderNPCs()
	local list = snapshot.npcs or {}
	local top = section(body, string.format("🧑 Жителей: %d", #list), 0)
	local box = new("TextBox", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.panel2, TextColor3 = C.text, PlaceholderText = "🔍 Поиск по имени, зоне, действию…", PlaceholderColor3 = C.dim, Text = npcSearch, Font = Enum.Font.GothamMedium, TextSize = 13, ClearTextOnFocus = false, LayoutOrder = 1 }, top)
	corner(box, 8)
	box.FocusLost:Connect(function()
		npcSearch = box.Text
		render()
	end)
	local q = string.lower(npcSearch)
	for i, n in list do
		local hay = string.lower(n.name .. " " .. (n.title or "") .. " " .. n.action .. " " .. tostring(n.zone) .. " " .. tostring(n.home))
		if q == "" or string.find(hay, q, 1, true) then
			local row = new("Frame", { BackgroundColor3 = C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i + 1 }, body)
			corner(row, 8)
			new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 76) }, row)
			vlist(row, 2)
			label(row, string.format("%s%s%s  %s", n.officer and "👮 " or "", n.title or n.name, n.quest and " ❗" or "", tostring(n.mood or "")), 13, C.text, true)
			label(row, n.action, 12, C.debug, false)
			label(row, string.format("зона: %s · дом: %s · ❤ %s", tostring(n.zone or "Street"), tostring(n.home or "—"), tostring(n.health)), 11, C.dim, false)
			local bf = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 72, 0.5, 0), Size = UDim2.fromOffset(66, 26), BackgroundTransparency = 1 }, row)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, bf)
			btn(bf, "👁", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
				follow(n.model, n.name)
			end)
			btn(bf, "📍", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
				remote:FireServer("Action", "TeleportTo", n.model)
			end)
		end
	end
end

local CAR_ICON = { Civilian = "🚗", Taxi = "🚕", Bus = "🚌", Police = "🚓" }
local function renderCars()
	local list = snapshot.cars or {}
	section(body, string.format("🚗 Машин: %d", #list), 0)
	for i, car in list do
		local row = new("Frame", { BackgroundColor3 = C.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i }, body)
		corner(row, 8)
		new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 76) }, row)
		vlist(row, 2)
		local stuck = car.state == "busy" and car.speed < 0.1
		label(row, string.format("%s %s #%d %s", CAR_ICON[car.kind] or "🚗", tostring(car.kind), car.id, car.siren and "🚨" or ""), 13, C.text, true)
		label(row, string.format("состояние: %s · скорость: %s%s", tostring(car.state), tostring(car.speed), stuck and "  (стоит)" or ""), 12, stuck and C.warn or C.debug, false)
		label(row, string.format("едет к: %s · водитель: %s", tostring(car.to or "—"), tostring(car.driver or "—")), 11, C.dim, false)
		local bf = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 72, 0.5, 0), Size = UDim2.fromOffset(66, 26), BackgroundTransparency = 1 }, row)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, bf)
		btn(bf, "👁", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
			follow(car.model, tostring(car.kind) .. " #" .. car.id)
		end)
		btn(bf, "📍", { Size = UDim2.fromOffset(30, 26), AutomaticSize = Enum.AutomaticSize.None }, function()
			remote:FireServer("Action", "TeleportTo", car.model)
		end)
	end
end

local function renderOverlay()
	local s = section(body, "🗺 Метки на карте — видишь только ты", 0)
	label(s, "Невидимые метки становятся видны: цвет, имя, атрибуты и линия «куда смотрит передняя грань».", 12, C.dim, false, { LayoutOrder = 1 })
	for i, l in LAYERS do
		local on = overlays[l.id] == true
		btn(s, (on and "☑ " or "☐ ") .. l.name, { LayoutOrder = 1 + i, Size = UDim2.new(1, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = on and C.panel2:Lerp(l.color, 0.25) or C.panel2 }, function()
			setOverlay(l.id, not on)
			render()
		end)
	end
	btn(s, "Выключить все", { LayoutOrder = 100 }, function()
		for id in pairs(overlays) do
			setOverlay(id, false)
		end
		render()
	end)
end

local OUTPUT_FILTERS = {
	{ id = "all", text = "Все" },
	{ id = "error", text = "❌ Ошибки" },
	{ id = "warn", text = "⚠️ Предупр." },
	{ id = "event", text = "✨ События" },
	{ id = "C", text = "💻 Клиент" },
	{ id = "S", text = "🖥 Сервер" },
}
for _, t in Config.LogTags do
	table.insert(OUTPUT_FILTERS, { id = t, text = t })
end

local function logMatches(l): boolean
	local f = outputFilter
	local ok
	if f == "all" then
		ok = true
	elseif f == "error" or f == "warn" or f == "event" then
		ok = l.kind == f
	elseif f == "C" or f == "S" then
		ok = l.src == f
	else
		ok = string.find(l.text, f, 1, true) ~= nil
	end
	if ok and outputSearch ~= "" then
		ok = string.find(string.lower(l.text), string.lower(outputSearch), 1, true) ~= nil
	end
	return ok
end

local function filteredLogs(limit: number)
	local out = {}
	for i = #logs, 1, -1 do
		if logMatches(logs[i]) then
			table.insert(out, 1, logs[i])
			if #out >= limit then
				break
			end
		end
	end
	return out
end

local function timeOf(t: number): string
	local d = os.date("!*t", math.floor(t))
	return string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
end

local copyMode = false
local function renderOutput()
	unseenErrors = 0
	updateBadge()
	local top = section(body, "🖥 Output — сервер (S) и клиент (C)", 0)
	local ff = hflow(top, 1)
	for _, f in OUTPUT_FILTERS do
		btn(ff, f.text, { BackgroundColor3 = outputFilter == f.id and C.accent or C.panel2, TextSize = 12 }, function()
			outputFilter = f.id
			render()
		end)
	end
	local tools = hflow(top, 2)
	btn(tools, outputPaused and "▶ Продолжить" or "⏸ Пауза", {}, function()
		outputPaused = not outputPaused
		render()
	end)
	btn(tools, "🗑 Очистить", {}, function()
		table.clear(logs)
		render()
	end)
	btn(tools, copyMode and "📄 Списком" or "📋 Текстом (скопировать)", {}, function()
		copyMode = not copyMode
		render()
	end)
	local box = new("TextBox", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.panel2, TextColor3 = C.text, PlaceholderText = "🔍 Поиск в Output…", PlaceholderColor3 = C.dim, Text = outputSearch, Font = Enum.Font.GothamMedium, TextSize = 13, ClearTextOnFocus = false, LayoutOrder = 3 }, top)
	corner(box, 8)
	box.FocusLost:Connect(function()
		outputSearch = box.Text
		render()
	end)

	local list = filteredLogs(copyMode and 300 or 120)
	if copyMode then
		local lines = {}
		for _, l in list do
			table.insert(lines, string.format("%s [%s] %s %s", timeOf(l.t), l.src or "S", string.upper(l.kind), l.text))
		end
		local area = new("TextBox", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.panel,
			TextColor3 = C.text,
			Font = Enum.Font.Code,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ClearTextOnFocus = false,
			TextEditable = false,
			MultiLine = true,
			Text = #lines > 0 and table.concat(lines, "\n") or "(пусто)",
			LayoutOrder = 1,
		}, body)
		corner(area, 8)
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, area)
		label(body, "Выдели текст (Ctrl+A внутри поля) и скопируй (Ctrl+C) — так удобно прислать ошибки Claude.", 11, C.dim, false, { LayoutOrder = 2 })
		return
	end
	if #list == 0 then
		label(body, "Пусто", 12, C.dim, false, { LayoutOrder = 1 })
	end
	for i, l in list do
		local color = C[l.kind] or C.text
		local row = label(body, string.format("%s  %s  %s", timeOf(l.t), l.src or "S", l.text), 12, l.kind == "info" and C.dim:Lerp(C.text, 0.5) or color, l.kind == "error", { LayoutOrder = i, Font = Enum.Font.Code })
		if l.kind == "error" then
			row.BackgroundTransparency = 0.85
			row.BackgroundColor3 = C.error
		end
	end
	task.defer(function()
		body.CanvasPosition = Vector2.new(0, math.max(0, body.AbsoluteCanvasSize.Y - body.AbsoluteSize.Y))
	end)
end

local LEVEL = { ok = { "✅", C.ok }, warn = { "⚠️", C.warn }, error = { "❌", C.error } }
local function renderCheck()
	local top = section(body, "✅ Проверка карты и установки", 0)
	label(top, "Ищет пропущенные скрипты, ошибки разметки (точки без связей, дом без кровати, нет дежурного...) и ошибки в Output.", 12, C.dim, false, { LayoutOrder = 1 })
	btn(top, checks and "🔄 Проверить ещё раз" or "▶ Запустить проверку", { LayoutOrder = 2, BackgroundColor3 = C.accent }, function()
		remote:FireServer("Check")
	end)
	if not checks then
		return
	end
	local counts = { ok = 0, warn = 0, error = 0 }
	for _, c in checks do
		counts[c.level] += 1
	end
	label(top, string.format("✅ %d   ⚠️ %d   ❌ %d", counts.ok, counts.warn, counts.error), 15, C.text, true, { LayoutOrder = 3 })
	-- Сначала ошибки, потом предупреждения
	local order = { error = 1, warn = 2, ok = 3 }
	local sorted = table.clone(checks)
	table.sort(sorted, function(a, b)
		if order[a.level] ~= order[b.level] then
			return order[a.level] < order[b.level]
		end
		return a.group < b.group
	end)
	for i, c in sorted do
		local lv = LEVEL[c.level]
		label(body, string.format("%s  %s: %s", lv[1], c.group, c.text), 12, c.level == "ok" and C.dim or lv[2], c.level == "error", { LayoutOrder = i })
	end
end

local RENDER = { news = renderNews, world = renderWorld, npcs = renderNPCs, cars = renderCars, overlay = renderOverlay, output = renderOutput, check = renderCheck }
local tabButtons = {}
for i, t in TABS do
	tabButtons[t.id] = btn(tabBar, t.text, { LayoutOrder = i, Size = UDim2.fromOffset(0, 30), TextSize = 12 }, function()
		currentTab = t.id
		render()
	end)
end

function render()
	for id, b in pairs(tabButtons) do
		b.BackgroundColor3 = id == currentTab and C.accent or C.panel2
	end
	local keepScroll = body.CanvasPosition
	clearBody()
	RENDER[currentTab]()
	if currentTab ~= "output" then
		task.defer(function()
			body.CanvasPosition = keepScroll
		end)
	end
end

---------------------------------------------------------------------
-- Сервер
---------------------------------------------------------------------

remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "Hello" then
		for _, l in payload.logs do
			addLog(l)
		end
		table.sort(logs, function(a, b)
			return a.t < b.t
		end)
		tested = payload.tested or {}
		placeNames = payload.placeNames or {}
		updateBadge()
		if win.Visible then
			render()
		end
	elseif kind == "Logs" then
		for _, l in payload do
			addLog(l)
		end
		updateBadge()
		outputDirty = true
	elseif kind == "Snapshot" then
		snapshot = payload
		drawDynamic()
		if win.Visible and (currentTab == "npcs" or currentTab == "cars") and not UserInputService:GetFocusedTextBox() then
			render()
		end
	elseif kind == "Nodes" then
		if overlays.Roads then
			drawRoads(payload)
		end
	elseif kind == "Check" then
		checks = payload
		if currentTab == "check" then
			render()
		end
	elseif kind == "Result" then
		showResult(payload)
		if win.Visible and currentTab == "world" then
			remote:FireServer("Snapshot")
			task.delay(0.4, function()
				if currentTab == "world" then
					render()
				end
			end)
		end
	end
end)
remote:FireServer("Hello")

---------------------------------------------------------------------
-- Открыть / закрыть, обновления
---------------------------------------------------------------------

local function fit()
	local view = camera.ViewportSize
	winScale.Scale = math.min(1, (view.Y - 100) / H, (view.X - 90) / W)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
fit()

local function toggleMenu()
	win.Visible = not win.Visible
	if win.Visible then
		remote:FireServer("Snapshot")
		render()
	end
end
toggle.Activated:Connect(toggleMenu)
ContextActionService:BindAction("DebugMenu", function(_, state)
	if state == Enum.UserInputState.Begin then
		toggleMenu()
	end
	return Enum.ContextActionResult.Sink
end, false, Config.Key)

local fpsFrames, fpsTimer, clientFps = 0, 0, 60
local snapTimer, outputTimer = 0, 0
RunService.RenderStepped:Connect(function(dt)
	fpsFrames += 1
	fpsTimer += dt
	if fpsTimer >= 1 then
		clientFps = math.floor(fpsFrames / fpsTimer)
		fpsFrames, fpsTimer = 0, 0
		local p = snapshot.perf or {}
		footer.Text = string.format("FPS: клиент %d · сервер %s   💾 %s МБ   🧑 %s   🚗 %s   🕗 %s ×%s   📶 %d мс",
			clientFps, tostring(p.fps or "?"), tostring(p.memory or "?"), tostring(p.npcs or "?"), tostring(p.cars or "?"),
			tostring(p.hour or "?"), tostring(p.timeScale or 1), math.floor(player:GetNetworkPing() * 1000))
	end
	-- Живые данные: только когда они на экране
	local live = overlays.NPCPaths or overlays.CarRoutes or overlays.NPCLabels or (win.Visible and (currentTab == "npcs" or currentTab == "cars"))
	snapTimer -= dt
	if (live or win.Visible) and snapTimer <= 0 then
		snapTimer = live and 1 or 2 -- строке внизу хватает раза в 2 секунды
		remote:FireServer("Snapshot")
	end
	outputTimer -= dt
	if outputDirty and outputTimer <= 0 and win.Visible and currentTab == "output" and not outputPaused and not copyMode and not UserInputService:GetFocusedTextBox() then
		outputTimer = 0.6
		outputDirty = false
		render()
	end
	if followTarget and not followTarget.Parent then
		stopFollow()
	end
end)

player.CharacterAdded:Connect(function()
	if followTarget then
		task.defer(stopFollow)
	end
end)
