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
