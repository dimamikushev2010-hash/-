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
		if motor and motor:IsA("Motor6D") then
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

local function applyFrame(name: string, motor: Motor6D, frame: CFrame)
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
		if d:IsA("Motor6D") then
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
