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
NPCConfig.AgentRadius = 1.2 -- «ширина» жителя для поиска пути: 1.2 проходит в двери шириной 4
NPCConfig.AgentHeight = 5
-- «Стоимость» материалов для поиска пути: чем больше, тем реже жители по нему ходят.
-- Например, { Asphalt = 8 } — жители не ходят по дорогам без нужды (если дороги из Asphalt).
NPCConfig.PathCosts = {}
-- Дорога: жители ходят по тротуарам и переходят только по переходам (зоны строит TrafficServer)
NPCConfig.RoadCost = 30 -- насколько жителям «дорого» идти по проезжей части (больше — реже)
NPCConfig.CrossLookDistance = 30 -- перед переходом ждут, если машина ближе
NPCConfig.CrossMaxWait = 10 -- но не дольше стольких секунд

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

-- Свои модели жителей: ServerStorage > NPCTemplates (Model с Humanoid, R15).
-- Атрибут Gender = "M" или "F" — тогда имя берётся из MaleNames / FemaleNames.
-- Если папки нет — жители собираются сами (цвета одежды ниже).
NPCConfig.TemplatesFolder = "NPCTemplates"
NPCConfig.MaleNames = { "Миша", "Дима", "Саша", "Ваня", "Костя", "Артём", "Егор", "Никита", "Паша", "Рома", "Илья", "Лёша" }
NPCConfig.FemaleNames = { "Аня", "Катя", "Оля", "Лена", "Маша", "Юля", "Настя", "Света", "Вика", "Даша", "Полина", "Ира" }
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
