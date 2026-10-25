-- Script: ServerScriptService > LaserServer
-- Сервер ведёт таймеры лазеров, принимает прицел от игрока и наносит урон.
-- Лучи и искры рисует каждый клиент по атрибутам персонажа.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DebugTimer = require(game:GetService("ReplicatedStorage"):WaitForChild("DebugConfig")) -- секундомер для меню отладки
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LaserConfig"))

local function getRemote(name: string, className: string)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local remote = getRemote(Config.RemoteName, "RemoteEvent")
local aimRemote = getRemote(Config.AimRemoteName, "UnreliableRemoteEvent")

local lastRequest: { [Player]: number } = {}
local tokens: { [Player]: number } = {}
local firing: { [Player]: Model } = {} -- кто сейчас стреляет

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stopLaser(player: Player, character: Model)
	firing[player] = nil
	if character:GetAttribute(Config.ActiveAttribute) ~= true then
		return
	end
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	player:SetAttribute(Config.CooldownAttribute, now() + Config.Cooldown)
end

local function startLaser(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local token = (tokens[player] or 0) + 1
	tokens[player] = token

	character:SetAttribute(Config.AimAttribute, head.Position + head.CFrame.LookVector * Config.Range)
	character:SetAttribute(Config.UntilAttribute, now() + Config.Duration)
	character:SetAttribute(Config.ActiveAttribute, true)
	firing[player] = character

	task.delay(Config.Duration, function()
		if tokens[player] == token and character.Parent then
			stopLaser(player, character)
		end
	end)
end

remote.OnServerEvent:Connect(function(player: Player)
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < 0.25 then
		return
	end
	lastRequest[player] = t

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if character:GetAttribute(Config.ActiveAttribute) == true then
		if Config.CanCancelEarly then
			stopLaser(player, character)
		end
		return
	end

	if now() < (player:GetAttribute(Config.CooldownAttribute) or 0) then
		return
	end

	startLaser(player, character)
end)

aimRemote.OnServerEvent:Connect(function(player: Player, point: any)
	local character = firing[player]
	if not character or typeof(point) ~= "Vector3" or point ~= point then
		return -- не стреляет, мусор или NaN
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	-- Ограничиваем дальность, чтобы нельзя было «бить» через всю карту
	local offset = point - head.Position
	if offset.Magnitude > Config.Range then
		point = head.Position + offset.Unit * Config.Range
	end
	character:SetAttribute(Config.AimAttribute, point)
end)

local function isFriendly(attacker: Player, victimModel: Model): boolean
	if Config.FriendlyFire then
		return false
	end
	local victim = Players:GetPlayerFromCharacter(victimModel)
	return victim ~= nil
		and not attacker.Neutral
		and not victim.Neutral
		and attacker.Team ~= nil
		and attacker.Team == victim.Team
end

local accumulator = 0
DebugTimer.connect(RunService.Heartbeat, "LaserServer", function(dt)
	accumulator += dt
	if accumulator < Config.DamageInterval then
		return
	end
	local interval = accumulator
	accumulator = 0

	for player, character in pairs(firing) do
		local head = character:FindFirstChild("Head")
		local aim = character:GetAttribute(Config.AimAttribute)
		if head and typeof(aim) == "Vector3" then
			local direction = aim - head.Position
			if direction.Magnitude > 0.01 then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { character }
				local result = workspace:Raycast(head.Position, direction.Unit * Config.Range, params)
				if result then
					local model = result.Instance:FindFirstAncestorWhichIsA("Model")
					local humanoid = model and model:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 and not isFriendly(player, model) then
						humanoid:TakeDamage(Config.DamagePerSecond * interval)
					end
				end
			end
		end
	end
end)

local function onCharacterAdded(player: Player, character: Model)
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			stopLaser(player, character)
		end)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Config.CooldownAttribute, 0)
	player.CharacterAdded:Connect(function(character)
		firing[player] = nil
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	tokens[player] = nil
	firing[player] = nil
end)
