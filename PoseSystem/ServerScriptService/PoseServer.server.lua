-- Script: ServerScriptService > PoseServer
-- Сервер: принимает запросы «вниз/вверх/встать», проверяет их,
-- выставляет атрибут позы персонажу (его видят все игроки) и блокирует ходьбу.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PoseConfig = require(ReplicatedStorage:WaitForChild("PoseConfig"))
local ATTR = PoseConfig.AttributeName

local remote = ReplicatedStorage:FindFirstChild(PoseConfig.RemoteName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = PoseConfig.RemoteName
	remote.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}

local SAVED = {
	WalkSpeed = "PoseSavedWalkSpeed",
	JumpPower = "PoseSavedJumpPower",
	JumpHeight = "PoseSavedJumpHeight",
	AutoRotate = "PoseSavedAutoRotate",
}

local function applyMovement(humanoid: Humanoid, state: string)
	local pose = PoseConfig.Poses[state]
	if pose then
		-- Запоминаем исходные значения только при выходе из положения «стоя»
		if humanoid:GetAttribute(SAVED.WalkSpeed) == nil then
			humanoid:SetAttribute(SAVED.WalkSpeed, humanoid.WalkSpeed)
			humanoid:SetAttribute(SAVED.JumpPower, humanoid.JumpPower)
			humanoid:SetAttribute(SAVED.JumpHeight, humanoid.JumpHeight)
			humanoid:SetAttribute(SAVED.AutoRotate, humanoid.AutoRotate)
		end
		humanoid.WalkSpeed = pose.WalkSpeed or 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = (pose.WalkSpeed or 0) > 0
	else
		local walkSpeed = humanoid:GetAttribute(SAVED.WalkSpeed)
		if walkSpeed ~= nil then
			humanoid.WalkSpeed = walkSpeed
			humanoid.JumpPower = humanoid:GetAttribute(SAVED.JumpPower)
			humanoid.JumpHeight = humanoid:GetAttribute(SAVED.JumpHeight)
			humanoid.AutoRotate = humanoid:GetAttribute(SAVED.AutoRotate)
			for _, name in pairs(SAVED) do
				humanoid:SetAttribute(name, nil)
			end
		end
	end
end

local function setPose(character: Model, state: string)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	character:SetAttribute(ATTR, state)
	applyMovement(humanoid, state)
end

remote.OnServerEvent:Connect(function(player: Player, direction: any)
	if direction ~= "Down" and direction ~= "Up" and direction ~= "Stand" then
		return
	end

	local now = os.clock()
	-- «Встать» пропускаем без кулдауна, чтобы игрок не застревал в позе
	if direction ~= "Stand" then
		if lastRequest[player] and now - lastRequest[player] < PoseConfig.ServerCooldown then
			return
		end
		lastRequest[player] = now
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local current = character:GetAttribute(ATTR)
	if not PoseConfig.IsValidState(current) then
		current = "Stand"
	end

	local nextState = PoseConfig.GetNextState(current, direction)
	if nextState == current or not PoseConfig.IsValidState(nextState) then
		return
	end

	-- Нельзя садиться, если персонаж уже сидит на сиденье (Seat)
	if current == "Stand" and humanoid.Sit then
		return
	end

	setPose(character, nextState)
end)

local function onCharacterAdded(character: Model)
	character:SetAttribute(ATTR, "Stand")
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	-- Сел на настоящее сиденье — выходим из позы
	humanoid.Seated:Connect(function(active)
		if active and character:GetAttribute(ATTR) ~= "Stand" then
			setPose(character, "Stand")
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)
