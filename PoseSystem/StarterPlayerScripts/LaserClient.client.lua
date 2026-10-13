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
