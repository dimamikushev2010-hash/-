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
