-- ModuleScript: ReplicatedStorage > SoundConfig
-- ВСЕ ЗВУКИ ИГРЫ В ОДНОМ МЕСТЕ.
-- Вставь сюда ID звуков из Creator Store (Toolbox → Audio): "rbxassetid://123456789".
-- Пустая строка "" — звука нет (всё остальное работает).
-- Звуки "rbxasset://sounds/..." встроены в Roblox и работают сразу.

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
	Indicator = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.15 }, -- тиканье поворотника
	LightSwitch = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.3 }, -- щелчок фар
	Brake = { Id = "", Volume = 0.3 }, -- скрип тормозов при резкой остановке
}

-- Жители
SoundConfig.NPC = {
	Footstep = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0.25 },
	Voice = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25 }, -- «бормотание» при репликах
	Laugh = { Id = "", Volume = 0.5 },
	Hurt = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.6 },
	Scream = { Id = "", Volume = 0.6 }, -- крик при бегстве
	Snore = { Id = "", Volume = 0.3 }, -- храп ночью
	Cheer = { Id = "", Volume = 0.5 }, -- радость (задание выполнено, утро)
	Wave = { Id = "", Volume = 0.4 }, -- «приве-ет!»
	DogBark = { Id = "", Volume = 0.5 },
	HouseDoorOpen = { Id = "", Volume = 0.5 }, -- скрип двери дома
	HouseDoorClose = { Id = "", Volume = 0.6 },
}

-- Голоса жителей: у каждого своя высота (случайная в этом диапазоне)
SoundConfig.VoicePitch = NumberRange.new(0.8, 1.5)
SoundConfig.VoiceSpeed = 14 -- «слогов» в секунду при печати реплики

return SoundConfig
