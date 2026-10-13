-- Script: ServerScriptService > FlightServer
-- Сервер ведёт таймеры полёта. Саму физику полёта считает клиент игрока
-- (персонаж принадлежит ему), анимации рисует каждый клиент.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FlightConfig"))
local AbilityRegistry = require(script.Parent:WaitForChild("AbilityRegistry"))

local remote = ReplicatedStorage:FindFirstChild(Config.RemoteName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = Config.RemoteName
	remote.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}
local tokens: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stopFlight(player: Player, character: Model)
	if character:GetAttribute(Config.ActiveAttribute) ~= true then
		return
	end
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	player:SetAttribute(Config.CooldownAttribute, now() + Config.Cooldown)
end

local function startFlight(player: Player, character: Model)
	AbilityRegistry.Stop("Cube", player, character)
	AbilityRegistry.ForcePoseStand(character)

	local token = (tokens[player] or 0) + 1
	tokens[player] = token
	character:SetAttribute(Config.UntilAttribute, now() + Config.Duration)
	character:SetAttribute(Config.ActiveAttribute, true)

	task.delay(Config.Duration, function()
		if tokens[player] == token and character.Parent then
			stopFlight(player, character)
		end
	end)
end

AbilityRegistry.RegisterStopper("Flight", stopFlight)

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
			stopFlight(player, character)
		end
		return
	end

	if humanoid.Sit or now() < (player:GetAttribute(Config.CooldownAttribute) or 0) then
		return
	end

	startFlight(player, character)
end)

local function onCharacterAdded(player: Player, character: Model)
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			stopFlight(player, character)
		end)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Config.CooldownAttribute, 0)
	player.CharacterAdded:Connect(function(character)
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
end)
