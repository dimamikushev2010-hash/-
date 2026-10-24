-- Script: ServerScriptService > PhoneServer
-- Телефон игрока: принимает запросы приложений и передаёт их жителям и транспорту.
--   Open   — данные для приложений (места, виды заявлений, заявления, остановки, друзья)
--   Taxi   — вызвать такси к себе
--   Report — заявление в полицию
--   Reply  — ответить знакомому жителю в сообщениях
--   Job, Buy, Equip, Photo, City — работа курьером, магазин, фото, достижения (CityLifeServer)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local remote = ReplicatedStorage:FindFirstChild("PhoneRemote") or Instance.new("RemoteEvent")
remote.Name = "PhoneRemote"
remote.Parent = ReplicatedStorage

local last = {} -- защита от спама: [player] = время

remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	local now = os.clock()
	if now - (last[player] or 0) < 0.3 then
		return
	end
	last[player] = now

	if action == "Open" then
		local data = Registry.phoneData and Registry.phoneData(player) or {}
		data.friends = Registry.friendsOf and Registry.friendsOf(player) or {}
		data.city = Registry.cityData and Registry.cityData(player) or nil
		remote:FireClient(player, "Data", data)
	elseif action == "Taxi" and Registry.phoneTaxi then
		task.spawn(Registry.phoneTaxi, player, a)
	elseif action == "Report" and Registry.phoneReport then
		Registry.phoneReport(player, a, b)
	elseif action == "Reply" and Registry.phoneReply then
		Registry.phoneReply(player, a, b)
	elseif action == "Friends" and Registry.friendsOf then
		remote:FireClient(player, "Friends", Registry.friendsOf(player))
	elseif type(action) == "string" and Registry.cityAction then
		Registry.cityAction(player, action, a, b)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)
