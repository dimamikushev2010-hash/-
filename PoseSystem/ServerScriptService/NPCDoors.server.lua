-- Script: ServerScriptService > NPCDoors
-- Двери из Workspace > NPCSystem > Doors:
--   * жители открывают их сами, когда подходят, и закрывают за собой;
--   * игроки открывают и закрывают кнопкой E;
--   * дверь всегда открывается «от себя» — в сторону от того, кто открыл;
--   * поиск пути у жителей проходит сквозь закрытые двери (PathfindingModifier).
--
-- Дверь — это Part или Model (несколько деталей, например полотно + ручка).
-- Атрибуты двери (необязательно):
--   Hinge  = "Left" / "Right" — с какой стороны петли (по умолчанию "Left")
--   Locked = true            — заперта: жители не ходят через неё, игроки не открывают

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))

local folder = workspace:WaitForChild(Config.FolderName, 30)
if not folder then
	return
end
local doorsFolder = folder:WaitForChild("Doors", 10)
if not doorsFolder then
	return
end

local doors = {} -- [instance] = состояние двери

local function getParts(door: Instance): { BasePart }
	if door:IsA("BasePart") then
		return { door }
	end
	local parts = {}
	for _, d in door:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function setupDoor(door: Instance)
	if doors[door] or not (door:IsA("BasePart") or door:IsA("Model")) then
		return
	end
	local parts = getParts(door)
	if #parts == 0 then
		return
	end

	local boxCF, boxSize
	if door:IsA("BasePart") then
		boxCF, boxSize = door.CFrame, door.Size
	else
		boxCF, boxSize = (door :: Model):GetBoundingBox()
	end

	-- Ширина двери — по большей горизонтальной оси
	local widthAxis, width
	if boxSize.X >= boxSize.Z then
		widthAxis, width = boxCF.RightVector, boxSize.X
	else
		widthAxis, width = boxCF.LookVector, boxSize.Z
	end
	local side = door:GetAttribute("Hinge") == "Right" and 1 or -1
	local hinge = boxCF.Position + widthAxis * (width / 2) * side
	local freeEnd = boxCF.Position - hinge
	local locked = door:GetAttribute("Locked") == true

	local collide = {}
	for _, part in parts do
		part.Anchored = true
		collide[part] = part.CanCollide
		-- Поиск пути считает дверь проходимой (если она не заперта)
		local modifier = part:FindFirstChildOfClass("PathfindingModifier") or Instance.new("PathfindingModifier")
		modifier.Label = "Door"
		modifier.PassThrough = not locked
		modifier.Parent = part
	end

	-- Кнопка для игроков — на самой большой детали
	local main = parts[1]
	for _, part in parts do
		if part.Size.Magnitude > main.Size.Magnitude then
			main = part
		end
	end
	local prompt
	if not locked then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DoorPrompt"
		prompt.ActionText = "Открыть"
		prompt.ObjectText = "Дверь"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = main
	end

	local state = {
		door = door,
		parts = parts,
		collide = collide,
		closedPivot = door:GetPivot(),
		hingeCF = CFrame.new(hinge),
		center = boxCF.Position,
		swingDir = Vector3.yAxis:Cross(freeEnd), -- куда идёт край двери при повороте на +угол
		angle = 0,
		target = 0,
		openedByPlayer = false,
		lastNpcNear = 0,
		locked = locked,
		prompt = prompt,
	}
	doors[door] = state

	if prompt then
		prompt.Triggered:Connect(function(player)
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if state.target ~= 0 then
				state.target = 0
				state.openedByPlayer = false
			elseif hrp then
				state.openedByPlayer = true
				state.target = math.rad(Config.DoorOpenAngle) * (state.swingDir:Dot(hrp.Position - state.center) > 0 and -1 or 1)
			end
		end)
	end
end

for _, door in doorsFolder:GetChildren() do
	setupDoor(door)
end
doorsFolder.ChildAdded:Connect(function(door)
	task.wait(0.1) -- даём детали модели догрузиться
	setupDoor(door)
end)
doorsFolder.ChildRemoved:Connect(function(door)
	doors[door] = nil
end)

-- Кто из жителей рядом с дверью
local function nearestNpc(state): Vector3?
	for _, npc in CollectionService:GetTagged(Config.Tag) do
		local hrp = npc:FindFirstChild("HumanoidRootPart")
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		if hrp and humanoid and humanoid.Health > 0 then
			if (hrp.Position - state.center).Magnitude < Config.DoorOpenDistance then
				return hrp.Position
			end
		end
	end
	return nil
end

local scanTimer = 0
DebugTimer.connect(RunService.Heartbeat, "NPCDoors", function(dt)
	scanTimer += dt
	local scan = scanTimer >= 0.15
	if scan then
		scanTimer = 0
	end
	local now = os.clock()

	for door, state in pairs(doors) do
		if not door.Parent then
			doors[door] = nil
			continue
		end

		-- Жители открывают и закрывают сами
		if scan and not state.locked and not state.openedByPlayer then
			local npcPos = nearestNpc(state)
			if npcPos then
				state.lastNpcNear = now
				if state.target == 0 then
					state.target = math.rad(Config.DoorOpenAngle) * (state.swingDir:Dot(npcPos - state.center) > 0 and -1 or 1)
				end
			elseif state.target ~= 0 and now - state.lastNpcNear > Config.DoorCloseDelay then
				state.target = 0
			end
		end

		-- Плавное движение створки
		if state.angle ~= state.target then
			local diff = state.target - state.angle
			local step = diff * math.min(1, dt * Config.DoorSpeed)
			if math.abs(diff) < 0.01 then
				state.angle = state.target
			else
				state.angle += step
			end
			door:PivotTo(state.hingeCF * CFrame.Angles(0, state.angle, 0) * state.hingeCF:Inverse() * state.closedPivot)

			local open = math.abs(state.angle) > math.rad(5)
			for _, part in state.parts do
				part.CanCollide = (not open) and state.collide[part]
			end
			if state.prompt then
				state.prompt.ActionText = state.target ~= 0 and "Закрыть" or "Открыть"
			end
			-- Для звука скрипа (NPCClient)
			local opening = state.target ~= 0
			if door:GetAttribute("DoorOpen") ~= opening then
				door:SetAttribute("DoorOpen", opening)
			end
		end
	end
end)
