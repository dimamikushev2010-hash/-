-- Script: ServerScriptService > InvisibilityServer
-- Сервер ведёт таймеры невидимости и кулдауна. Сами эффекты рисует
-- каждый клиент по атрибутам: себе — «стекло», другим — полная невидимость.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("InvisibilityConfig"))

local remote = ReplicatedStorage:FindFirstChild(Config.RemoteName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = Config.RemoteName
	remote.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}
local tokens: { [Player]: number } = {} -- чтобы старый таймер не выключил новую невидимость

local function now(): number
	return workspace:GetServerTimeNow()
end

local function endInvisibility(player: Player, character: Model)
	if character:GetAttribute(Config.ActiveAttribute) ~= true then
		return
	end
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	player:SetAttribute(Config.CooldownAttribute, now() + Config.Cooldown)
end

local function startInvisibility(player: Player, character: Model)
	local token = (tokens[player] or 0) + 1
	tokens[player] = token
	character:SetAttribute(Config.ActiveAttribute, true)
	character:SetAttribute(Config.UntilAttribute, now() + Config.Duration)

	task.delay(Config.Duration, function()
		if tokens[player] == token and character.Parent then
			endInvisibility(player, character)
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
			endInvisibility(player, character)
		end
		return
	end

	if now() < (player:GetAttribute(Config.CooldownAttribute) or 0) then
		return
	end

	startInvisibility(player, character)
end)

local function onCharacterAdded(player: Player, character: Model)
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			endInvisibility(player, character)
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
