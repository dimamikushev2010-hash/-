-- ModuleScript: ReplicatedStorage > AbilityFx
-- Общие эффекты для способностей (только на клиенте):
-- вспышки частиц, тряска камеры, плавные функции.

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local AbilityFx = {}

---------------------------------------------------------------------
-- Вспышка частиц в точке
---------------------------------------------------------------------
--[[
	opts = {
		Color = Color3 или ColorSequence,
		Count = 30,
		Speed = NumberRange.new(6, 14),
		Size = 0.5,               -- начальный размер, к концу уменьшается до 0
		Lifetime = NumberRange.new(0.3, 0.7),
		LightEmission = 1,
		Drag = 3,
		Acceleration = Vector3.zero,
		Spread = Vector2.new(180, 180),
		Direction = Enum.NormalId.Top,
	}
]]
function AbilityFx.Burst(position: Vector3, opts)
	opts = opts or {}
	local part = Instance.new("Part")
	part.Name = "AbilityBurst"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	part.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local lifetime = opts.Lifetime or NumberRange.new(0.3, 0.7)
	local color = opts.Color or Color3.new(1, 1, 1)
	local size = opts.Size or 0.5

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = typeof(color) == "ColorSequence" and color or ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = lifetime
	emitter.Speed = opts.Speed or NumberRange.new(6, 14)
	emitter.SpreadAngle = opts.Spread or Vector2.new(180, 180)
	emitter.EmissionDirection = opts.Direction or Enum.NormalId.Top
	emitter.LightEmission = opts.LightEmission or 1
	emitter.Drag = opts.Drag or 3
	emitter.Acceleration = opts.Acceleration or Vector3.zero
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(opts.Count or 30)

	if opts.Light then
		local light = Instance.new("PointLight")
		light.Color = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
		light.Range = opts.Light
		light.Brightness = 3
		light.Parent = attachment
		task.spawn(function()
			local start = os.clock()
			while light.Parent and os.clock() - start < 0.35 do
				light.Brightness = 3 * (1 - (os.clock() - start) / 0.35)
				RunService.Heartbeat:Wait()
			end
			light:Destroy()
		end)
	end

	Debris:AddItem(part, lifetime.Max + 0.3)
	return part
end

-- Пыль у ног персонажа
function AbilityFx.Dust(character: Model, count: number?, color: Color3?)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return
	end
	local legLength = humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.HipHeight or 2
	local feet = hrp.Position - Vector3.new(0, hrp.Size.Y / 2 + legLength - 0.2, 0)
	AbilityFx.Burst(feet, {
		Color = color or Color3.fromRGB(200, 190, 175),
		Count = count or 24,
		Speed = NumberRange.new(10, 18),
		Size = 1.2,
		Lifetime = NumberRange.new(0.4, 0.8),
		LightEmission = 0,
		Drag = 5,
		Spread = Vector2.new(85, 85),
		Acceleration = Vector3.new(0, 4, 0),
	})
end

---------------------------------------------------------------------
-- Тряска камеры
---------------------------------------------------------------------

local shakes = {}

function AbilityFx.Shake(intensity: number, duration: number)
	table.insert(shakes, { intensity = intensity, duration = duration, start = os.clock() })
end

RunService:BindToRenderStep("AbilityCameraShake", Enum.RenderPriority.Camera.Value + 1, function()
	if #shakes == 0 then
		return
	end
	local now = os.clock()
	local amount = 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local k = 1 - (now - s.start) / s.duration
		if k <= 0 then
			table.remove(shakes, i)
		else
			amount += s.intensity * k
		end
	end
	if amount > 0 then
		local camera = workspace.CurrentCamera
		local x = math.noise(now * 25, 1.3) * amount
		local y = math.noise(now * 25, 7.1) * amount
		local z = math.noise(now * 25, 3.7) * amount * 0.5
		camera.CFrame = camera.CFrame * CFrame.Angles(x, y, z)
	end
end)

---------------------------------------------------------------------
-- Плавные функции
---------------------------------------------------------------------

function AbilityFx.ElasticOut(t: number): number
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

function AbilityFx.BackIn(t: number): number
	t = math.clamp(t, 0, 1)
	local c1 = 1.70158
	return (c1 + 1) * t * t * t - c1 * t * t
end

function AbilityFx.Approach(current: number, target: number, step: number): number
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

return AbilityFx
