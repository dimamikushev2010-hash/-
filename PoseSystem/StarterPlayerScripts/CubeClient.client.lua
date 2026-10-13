-- LocalScript: StarterPlayer > StarterPlayerScripts > CubeClient
-- Анимации куба (у всех игроков на экране):
--   * куб «выпрыгивает» с пружинкой и облаком частиц, при выходе сжимается;
--   * при ходьбе подскакивает, при касании земли сплющивается, наклоняется вперёд;
--   * в прыжке вытягивается и делает сальто, при приземлении — «шлёп» и пыль;
--   * на месте «дышит», глаза моргают.
-- Тело персонажа в форме куба прячет InvisibilityClient.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CubeConfig"))
local AbilityFx = require(ReplicatedStorage:WaitForChild("AbilityFx"))
local AbilityButton = require(ReplicatedStorage:WaitForChild("AbilityButton"))
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName)

local player = Players.LocalPlayer
local cubes = {} -- [cube part] = состояние

local function poof(position: Vector3, color: Color3)
	AbilityFx.Burst(position, {
		Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
		Count = 45,
		Speed = NumberRange.new(10, 22),
		Size = 1.1,
		Lifetime = NumberRange.new(0.35, 0.7),
		LightEmission = 0.4,
		Drag = 5,
		Light = 14,
	})
end

local function newState(character: Model, cube: BasePart)
	local now = os.clock()
	return {
		character = character,
		cube = cube,
		weld = cube:FindFirstChild("CubeWeld"),
		hrp = character:FindFirstChild("HumanoidRootPart"),
		base = cube:GetAttribute("BaseSize") or cube.Size.Y,
		offsetY = cube:GetAttribute("OffsetY") or 0,
		start = now,
		endedAt = nil,
		hopPhase = 0,
		impact = 0,
		prevVy = 0,
		flipStart = nil,
		blinkAt = now + 1 + math.random() * 2,
		blinkUntil = 0,
		eyes = {},
	}
end

local function findEyes(state)
	local face = state.cube:FindFirstChild("Face")
	if face then
		for _, name in { "Eye1", "Eye2" } do
			local eye = face:FindFirstChild(name)
			if eye then
				table.insert(state.eyes, eye)
			end
		end
	end
end

local function updateCube(state, dt: number, now: number)
	local cube, weld, hrp = state.cube, state.weld, state.hrp
	if not weld or not hrp then
		return
	end
	local active = state.character:GetAttribute(Config.ActiveAttribute) == true

	-- Появление / исчезновение
	if not active and not state.endedAt then
		state.endedAt = now
		poof(cube.Position, cube.Color)
		if state.character == player.Character then
			AbilityFx.Shake(0.03, 0.3)
		end
	end
	local pop
	if state.endedAt then
		pop = math.max(0, 1 - AbilityFx.BackIn((now - state.endedAt) / Config.PopOutTime))
	else
		pop = AbilityFx.ElasticOut((now - state.start) / Config.PopTime)
	end

	local vel = hrp.AssemblyLinearVelocity
	local vy = vel.Y
	local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local moving = math.clamp(flatSpeed / 16, 0, 1)
	local grounded = math.abs(vy) < 3

	-- Подскоки при ходьбе
	local hop, contact = 0, 0
	if grounded and moving > 0.1 then
		state.hopPhase += dt * Config.HopRate * (0.6 + 0.4 * moving)
		local s = math.abs(math.sin(state.hopPhase * math.pi))
		hop = s * Config.HopHeight * moving * (state.base / Config.Size)
		contact = (1 - s) ^ 6 * moving
	else
		state.hopPhase = 0
	end

	-- Приземление: сплющивание и пыль
	if state.prevVy < -15 and vy > -3 then
		state.impact = math.clamp(-state.prevVy / 60, 0.15, 0.4)
		AbilityFx.Dust(state.character, 18)
	end
	state.impact *= math.exp(-9 * dt)

	-- Прыжок: сальто вперёд
	if state.prevVy < 5 and vy > 25 and not state.flipStart then
		state.flipStart = now
	end
	local flip = 0
	if state.flipStart then
		local t = (now - state.flipStart) / 0.55
		if t >= 1 then
			state.flipStart = nil
		else
			flip = -2 * math.pi * (t * t * (3 - 2 * t))
		end
	end
	state.prevVy = vy

	-- Растяжение в воздухе, «дыхание» на месте
	local stretch = grounded and 0 or math.clamp(math.abs(vy) / 90, 0, 0.22)
	local breath = math.sin(now * 3) * 0.03 * (1 - moving)
	local scaleY = math.max(0.4, 1 - 0.16 * contact - state.impact + stretch + breath)
	local scaleXZ = 1 + 0.5 * (1 - scaleY)

	local size = math.max(0.05, state.base * pop)
	local height = size * scaleY
	cube.Size = Vector3.new(size * scaleXZ, height, size * scaleXZ)

	-- Нижняя грань остаётся на земле
	local groundY = state.offsetY - state.base / 2
	local tilt = -math.rad(12) * moving
	weld.C0 = CFrame.new(0, groundY + height / 2 + hop, 0) * CFrame.Angles(tilt + flip, 0, 0)

	-- Моргание
	if now > state.blinkAt then
		state.blinkUntil = now + 0.12
		state.blinkAt = now + 2 + math.random() * 3
	end
	local eyeHeight = now < state.blinkUntil and 0.03 or 0.2
	for _, eye in state.eyes do
		eye.Size = UDim2.fromScale(0.13, eyeHeight)
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local cube = character and character:FindFirstChild(Config.PartName)
		if cube and cube:IsA("BasePart") and not cubes[cube] then
			local state = newState(character, cube)
			findEyes(state)
			cubes[cube] = state
			if character:GetAttribute(Config.ActiveAttribute) == true then
				poof(cube.Position, cube.Color)
				if character == player.Character then
					AbilityFx.Shake(0.035, 0.35)
				end
			end
		end
	end

	for cube, state in pairs(cubes) do
		if not cube.Parent then
			cubes[cube] = nil
		else
			updateCube(state, dt, now)
		end
	end
end)

AbilityButton.Create({
	Name = Config.ButtonText,
	Icon = Config.ButtonIcon,
	Slot = Config.ButtonSlot,
	Duration = Config.Duration,
	Cooldown = Config.Cooldown,
	ActiveColor = Config.ActiveColor,
	Remote = remote,
	Keys = Config.Keys,
	ActionName = "CubeForm",
	ActiveAttribute = Config.ActiveAttribute,
	UntilAttribute = Config.UntilAttribute,
	CooldownAttribute = Config.CooldownAttribute,
})
