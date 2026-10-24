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
