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
NPCConfig.PlayerGreeting = { "Привет! Чем могу помочь?", "О, здравствуй!", "Да-да?", "Привет-привет!" }
NPCConfig.PlayerBye = { "Пока!", "Удачи!", "Заходи ещё!", "До встречи!" }
NPCConfig.TalkPromptText = "Поговорить"
NPCConfig.TalkDistance = 10

-- Смена дня и ночи
NPCConfig.DayNight = true
NPCConfig.DayLengthMinutes = 12 -- сколько реальных минут длятся одни игровые сутки
NPCConfig.StartTime = 9 -- со скольки часов начинается сервер
NPCConfig.NightStart = 21 -- с этого часа жители идут домой спать
NPCConfig.NightEnd = 6.5 -- в это время просыпаются
-- Детали с этим атрибутом (true) светятся только ночью: фонари, окна, вывески
NPCConfig.NightLightAttribute = "NightLight"

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
}

-- Двери
NPCConfig.DoorOpenDistance = 6 -- на каком расстоянии житель открывает дверь
NPCConfig.DoorCloseDelay = 2.5 -- через сколько секунд после ухода дверь закрывается
NPCConfig.DoorOpenAngle = 95 -- на сколько градусов открывается
NPCConfig.DoorSpeed = 4 -- скорость открывания (больше = быстрее)

return NPCConfig
