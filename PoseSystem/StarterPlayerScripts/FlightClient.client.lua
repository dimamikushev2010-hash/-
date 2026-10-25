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
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки
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

DebugTimer.connect(RunService.RenderStepped, "FlightClient", function(dt)
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
