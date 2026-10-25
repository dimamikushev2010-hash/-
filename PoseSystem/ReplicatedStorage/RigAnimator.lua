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
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки

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
DebugTimer.connect(RunService.PreSimulation, "RigAnimator", function(dt)
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
