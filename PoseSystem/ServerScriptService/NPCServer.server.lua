-- Script: ServerScriptService > NPCServer
-- Жители города (NPC):
--   * появляются на точках Spawns, «просыпаются» (лёжа → на колени → встают);
--   * ходят по точкам Points с поиском пути: по дому, потом на улицу, в другие дома;
--   * в точках занимаются делами: стоят, смотрят в окно, сидят, лежат, танцуют, ждут собеседника;
--   * болтают друг с другом (облачка с текстом и жесты), машут проходящим игрокам;
--   * с ними можно поговорить (кнопка E) и выбрать тему;
--   * получив урон, вскрикивают и убегают; погибнув — возрождаются на своей точке;
--   * ночью идут домой спать (💤), утром просыпаются (DayNightServer);
--   * реагируют на суперспособности: показывают на летящего, смеются над кубом,
--     оглядываются на невидимку, разбегаются от лазеров;
--   * помнят игроков по имени и могут пойти следом («Пойдём со мной!»);
--   * над головой значок настроения;
--   * живут по расписанию: утро, день, обед, вечер, ночь; в выходные отдыхают
--     (NPCConfig.Schedule), продавцы работают по часам с обедом;
--   * погода: в дождь раскрывают зонты, прячутся по домам и ускоряют шаг, пугаются грома;
--   * дают задания (❗): найти потерянную вещь за монеты;
--   * дружат с игроками (Знакомый → Приятель → Друг ❤️), друзьям дарят подарок;
--   * работают: продавцы стоят за прилавком (Activity = "Work"), охранники обходят маршрут ("Patrol");
--   * гуляют с собаками и носят вещи в руках (кофе, телефон, мороженое, сумка).
-- Анимации — стандартные анимации Roblox (их видят все), сидение/лежание на полу —
-- через систему поз (PoseClient).

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local SoundConfig = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))

local folder = workspace:WaitForChild(Config.FolderName, 30)
if not folder then
	warn("[NPC] Нет папки Workspace >", Config.FolderName, "— жители не появятся. См. NPC_SETUP.md")
	return
end
local spawnsFolder = folder:WaitForChild("Spawns", 10)
local pointsFolder = folder:WaitForChild("Points", 10)
if not spawnsFolder or not pointsFolder then
	warn("[NPC] В папке", Config.FolderName, "нужны папки Spawns и Points")
	return
end

local liveFolder = folder:FindFirstChild("Live") or Instance.new("Folder")
liveFolder.Name = "Live"
liveFolder.Parent = folder

local dialogRemote = ReplicatedStorage:FindFirstChild("NPCDialog") or Instance.new("RemoteEvent")
dialogRemote.Name = "NPCDialog"
dialogRemote.Parent = ReplicatedStorage

-- Жители не толкают друг друга в дверях
local COLLISION_GROUP = "NPCs"
pcall(function()
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
end)

-- Атрибуты суперспособностей (если таких скриптов нет — берём стандартные имена)
local function abilityAttribute(moduleName: string, default: string): string
	local module = ReplicatedStorage:FindFirstChild(moduleName)
	if module then
		local ok, cfg = pcall(require, module)
		if ok and type(cfg) == "table" and cfg.ActiveAttribute then
			return cfg.ActiveAttribute
		end
	end
	return default
end
local ATTR_FLYING = abilityAttribute("FlightConfig", "Flying")
local ATTR_CUBE = abilityAttribute("CubeConfig", "CubeForm")
local ATTR_INVISIBLE = abilityAttribute("InvisibilityConfig", "Invisible")
local ATTR_LASER = abilityAttribute("LaserConfig", "LaserActive")

local memory = {} -- [имя жителя] = { [UserId] = true } — с кем уже знакомы

local rng = Random.new()
local function pick(list)
	return list[rng:NextInteger(1, #list)]
end
local function randomIn(range: NumberRange): number
	return rng:NextNumber(range.Min, range.Max)
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

---------------------------------------------------------------------
-- Маркеры на карте
---------------------------------------------------------------------

local function hideMarker(part: BasePart)
	if Config.HideMarkersInGame and not part:IsA("Seat") then
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		for _, d in part:GetDescendants() do
			if d:IsA("Decal") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
	end
end

local points = {} -- [part] = { part, activity, zone, occupants }
local routes = {} -- [имя маршрута] = { points = {...по Order}, guard = npc }

local function registerPoint(part: Instance)
	if not part:IsA("BasePart") or points[part] then
		return
	end
	hideMarker(part)
	local activity = part:GetAttribute("Activity") or (part:IsA("Seat") and "Sit") or "Idle"
	local info = {
		part = part,
		activity = activity,
		zone = part:GetAttribute("Zone"),
		occupants = 0,
		capacity = activity == "Talk" and 2 or 1,
		role = part:GetAttribute("Role"),
		route = part:GetAttribute("Route"),
		order = part:GetAttribute("Order") or 0,
		worker = nil,
	}
	points[part] = info
	if activity == "Patrol" then
		local name = info.route or "Patrol"
		local route = routes[name] or { points = {}, guard = nil }
		routes[name] = route
		info.route = name
		table.insert(route.points, info)
		table.sort(route.points, function(a, b)
			return a.order < b.order
		end)
	end
end

for _, d in pointsFolder:GetDescendants() do
	registerPoint(d)
end
pointsFolder.DescendantAdded:Connect(registerPoint)
pointsFolder.DescendantRemoving:Connect(function(d)
	local info = points[d]
	points[d] = nil
	if info and info.route and routes[info.route] then
		local list = routes[info.route].points
		local i = table.find(list, info)
		if i then
			table.remove(list, i)
		end
	end
end)

for _, d in spawnsFolder:GetDescendants() do
	if d:IsA("BasePart") then
		hideMarker(d)
	end
end

---------------------------------------------------------------------
-- Внешность
---------------------------------------------------------------------

local function makeDescription(opts): HumanoidDescription
	if opts and opts.shirt then
		-- Форма (например, полиция)
		local desc = Instance.new("HumanoidDescription")
		local skin = pick(Config.SkinColors)
		desc.HeadColor = skin
		desc.TorsoColor = opts.shirt
		desc.LeftArmColor = opts.shirt
		desc.RightArmColor = opts.shirt
		desc.LeftLegColor = opts.pants or opts.shirt
		desc.RightLegColor = opts.pants or opts.shirt
		return desc
	end
	if #Config.AvatarUserIds > 0 then
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(pick(Config.AvatarUserIds))
		end)
		if ok and desc then
			return desc
		end
	end
	local desc = Instance.new("HumanoidDescription")
	local skin = pick(Config.SkinColors)
	local shirt = pick(Config.ShirtColors)
	local pants = pick(Config.PantsColors)
	local longSleeves = rng:NextNumber() < 0.5
	desc.HeadColor = skin
	desc.TorsoColor = shirt
	desc.LeftArmColor = longSleeves and shirt or skin
	desc.RightArmColor = longSleeves and shirt or skin
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	desc.HeightScale = rng:NextNumber(0.92, 1.05)
	desc.WidthScale = rng:NextNumber(0.9, 1.05)
	return desc
end

---------------------------------------------------------------------
-- Анимации (на сервере — видны всем)
---------------------------------------------------------------------

local function newAnimator(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks = {}

	local function track(name: string, priority: Enum.AnimationPriority, looped: boolean)
		if tracks[name] == nil then
			local animation = Instance.new("Animation")
			animation.AnimationId = Config.Animations[name]
			local ok, t = pcall(animator.LoadAnimation, animator, animation)
			if ok and t then
				t.Priority = priority
				t.Looped = looped
				tracks[name] = t
			else
				tracks[name] = false
			end
		end
		return tracks[name] or nil
	end

	local self = { current = nil }

	local function setLocomotion(name: string, speed: number)
		local t = track(name, name == "Idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement, true)
		if self.current ~= t then
			if self.current then
				self.current:Stop(0.25)
			end
			if t then
				t:Play(0.25)
			end
			self.current = t
		end
		if t then
			t:AdjustSpeed(speed)
		end
	end

	humanoid.Running:Connect(function(speed)
		if speed < 0.5 then
			setLocomotion("Idle", 1)
		elseif speed < 15 then
			setLocomotion("Walk", speed / 14)
		else
			setLocomotion("Run", speed / 20)
		end
	end)

	humanoid.StateChanged:Connect(function(_, new)
		local fall = track("Fall", Enum.AnimationPriority.Movement, true)
		if new == Enum.HumanoidStateType.Freefall then
			if fall then
				fall:Play(0.2)
			end
		elseif fall and fall.IsPlaying then
			fall:Stop(0.2)
		end
		if new == Enum.HumanoidStateType.Jumping then
			local jump = track("Jump", Enum.AnimationPriority.Movement, false)
			if jump then
				jump:Play(0.1)
			end
		end
	end)

	humanoid.Seated:Connect(function(active)
		local sit = track("SitChair", Enum.AnimationPriority.Action, true)
		if sit then
			if active then
				sit:Play(0.3)
			else
				sit:Stop(0.3)
			end
		end
	end)

	-- Жест/эмоция: проигрывается поверх, duration — для зацикленных (танец)
	function self.emote(name: string, duration: number?)
		local looped = duration ~= nil
		local t = track(name, Enum.AnimationPriority.Action, looped)
		if t then
			t:Play(0.2)
			if duration then
				task.delay(duration, function()
					t:Stop(0.4)
				end)
			end
		end
		return t
	end

	function self.stopAll()
		for _, t in pairs(tracks) do
			if t then
				t:Stop(0.2)
			end
		end
	end

	setLocomotion("Idle", 1)
	return self
end

---------------------------------------------------------------------
-- Жители
---------------------------------------------------------------------

local npcs = Registry.npcs -- [model] = npc (общая таблица с транспортом)
local total = 0

local function say(npc, text: string, duration: number?)
	if not npc.alive then
		return
	end
	npc.model:SetAttribute("SayDuration", duration or Config.BubbleTime)
	npc.model:SetAttribute("SayText", text)
	npc.model:SetAttribute("SayId", (npc.model:GetAttribute("SayId") or 0) + 1)
end

-- Звук жителя (имя из SoundConfig.NPC), играют клиенты
local function sfx(npc, name: string)
	if npc.alive and SoundConfig.NPC[name] then
		npc.model:SetAttribute("SoundEvent", name)
		npc.model:SetAttribute("SoundEventId", (npc.model:GetAttribute("SoundEventId") or 0) + 1)
	end
end

-- Значок настроения над головой (ключ из NPCConfig.Moods, nil — убрать)
-- Если временного настроения нет — показываем «постоянное» (например, ❗ задание)
local function moodValue(npc, mood: string?)
	local key = mood or npc.baseMood
	return key and Config.Moods[key] or nil
end

local function setMood(npc, mood: string?, duration: number?)
	npc.moodToken = (npc.moodToken or 0) + 1
	npc.activeMood = mood
	local token = npc.moodToken
	npc.model:SetAttribute("Mood", moodValue(npc, mood))
	if duration then
		task.delay(duration, function()
			if npc.moodToken == token and npc.model.Parent then
				npc.activeMood = nil
				npc.model:SetAttribute("Mood", moodValue(npc, nil))
			end
		end)
	end
end

local function setBaseMood(npc, mood: string?)
	npc.baseMood = mood
	if npc.activeMood == nil then
		npc.model:SetAttribute("Mood", moodValue(npc, nil))
	end
end

local function isNight(): boolean
	return workspace:GetAttribute("IsNight") == true
end

---------------------------------------------------------------------
-- Расписание и погода
---------------------------------------------------------------------

local Lighting = game:GetService("Lighting")

local function hourNow(): number
	return workspace:GetAttribute("Hour") or Lighting.ClockTime
end

local function isWeekend(): boolean
	return workspace:GetAttribute("Weekend") == true
end

local function rainNow(): number
	return workspace:GetAttribute("Rain") or 0
end

local function currentPeriod()
	local hour = hourNow()
	for _, p in Config.Schedule or {} do
		if hour >= p.From and hour < p.To then
			return p
		end
	end
	return nil
end

-- Продавцы работают в рабочие часы, кроме обеда (и выходных, если так настроено)
local function isWorkTime(): boolean
	local h, w = hourNow(), Config.WorkHours
	if not w then
		return true
	end
	if Config.WorkersRestOnWeekend and isWeekend() then
		return false
	end
	return h >= w.Start and h < w.End and not (h >= w.LunchStart and h < w.LunchEnd)
end

local function walkSpeedOf(npc): number
	return npc.speed * (npc.speedMul or 1)
end

---------------------------------------------------------------------
-- Монеты и дружба
---------------------------------------------------------------------

local function getCoins(player: Player): IntValue
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local coins = stats:FindFirstChild(Config.CurrencyName)
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = Config.CurrencyName
		coins.Parent = stats
	end
	return coins
end
Players.PlayerAdded:Connect(getCoins)
for _, player in Players:GetPlayers() do
	getCoins(player)
end

local function toast(player: Player, text: string)
	if player.Parent then
		dialogRemote:FireClient(player, "Toast", text)
	end
end

local function addCoins(player: Player, amount: number)
	getCoins(player).Value += amount
	toast(player, string.format("+%d 🪙 %s", amount, Config.CurrencyName))
end

local FRIEND_POINTS = Config.FriendLevels[#Config.FriendLevels].Points

local function friendPoints(npc, player: Player): number
	local m = memory[npc.name]
	return m and m[player.UserId] or 0
end

local function friendLevel(amount: number)
	local level = Config.FriendLevels[1]
	for _, l in Config.FriendLevels do
		if amount >= l.Points then
			level = l
		end
	end
	return level
end

local function addFriendship(npc, player: Player, amount: number)
	memory[npc.name] = memory[npc.name] or {}
	local before = memory[npc.name][player.UserId] or 0
	local after = before + amount
	memory[npc.name][player.UserId] = after
	-- Стали друзьями — подарок
	if before < FRIEND_POINTS and after >= FRIEND_POINTS then
		task.delay(2.5, function()
			if npc.alive then
				say(npc, pick(Config.Phrases.Gift))
				npc.anim.emote("Cheer")
				setMood(npc, "Happy", 4)
			end
			if player.Parent then
				addCoins(player, Config.FriendGift)
				toast(player, "❤️ " .. npc.name .. " теперь твой друг!")
				if Registry.playerEvent then
					Registry.playerEvent(player, "Friend")
				end
			end
		end)
	end
end

---------------------------------------------------------------------
-- Задания: найти потерянную вещь
---------------------------------------------------------------------

local playerQuests = {} -- [player] = задание

local function clearQuest(quest, reason: string?)
	if quest.done then
		return
	end
	quest.done = true
	local player = quest.player
	if playerQuests[player] == quest then
		playerQuests[player] = nil
	end
	if quest.item and quest.item.Parent then
		quest.item:Destroy()
	end
	if quest.npc.activeQuest == quest then
		quest.npc.activeQuest = nil
	end
	if player.Parent then
		player:SetAttribute("QuestText", nil)
		if reason then
			toast(player, reason)
		end
	end
end

local function offerQuestLater(npc, delay: number)
	task.delay(delay, function()
		if npc.alive and not npc.activeQuest and not npc.route and rng:NextNumber() < math.min(1, Config.QuestChance * 1.5) then
			npc.hasQuest = true
			setBaseMood(npc, "Quest")
		end
	end)
end

local function questSpot(npc)
	local far, any = {}, {}
	for _, p in pairs(points) do
		if p.part.Parent and not p.part:IsA("Seat") then
			table.insert(any, p)
			if (p.part.Position - npc.hrp.Position).Magnitude >= Config.QuestMinDistance then
				table.insert(far, p)
			end
		end
	end
	local list = #far > 0 and far or any
	return #list > 0 and pick(list) or nil
end

local function startQuest(npc, player: Player)
	local spot = questSpot(npc)
	if not spot then
		return nil
	end
	local def = pick(Config.QuestItems)

	local item = Instance.new("Part")
	item.Name = "QuestItem"
	item.Shape = Enum.PartType.Ball
	item.Size = Vector3.new(1, 1, 1)
	item.Color = def.Color
	item.Material = Enum.Material.SmoothPlastic
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CFrame = CFrame.new(spot.part.Position + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.8, rng:NextNumber(-1.5, 1.5)))
	item:SetAttribute("QuestOwner", player.UserId)
	item:SetAttribute("QuestIcon", def.Icon)
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = def.Color
	sparkles.Parent = item
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Подобрать"
	prompt.ObjectText = def.Name
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = item
	CollectionService:AddTag(item, "QuestItem")
	item.Parent = liveFolder

	local quest = { npc = npc, player = player, def = def, item = item, carrying = false, done = false }
	prompt.Triggered:Connect(function(who)
		if who ~= player or quest.done or quest.carrying then
			return
		end
		quest.carrying = true
		item:Destroy()
		quest.item = nil
		player:SetAttribute("QuestText", string.format("Верни %s %s — %s", def.Icon, def.Name, npc.name))
		toast(player, string.format("%s Нашёл %s!", def.Icon, def.Name))
	end)

	npc.hasQuest = false
	setBaseMood(npc, nil)
	npc.activeQuest = quest
	playerQuests[player] = quest
	player:SetAttribute("QuestText", string.format("Найди %s %s для: %s", def.Icon, def.Name, npc.name))

	task.delay(Config.QuestTime, function()
		if not quest.done then
			clearQuest(quest, "⌛ Время вышло, задание отменено")
			offerQuestLater(npc, Config.QuestCooldown)
		end
	end)
	return quest
end

local function finishQuest(npc, player: Player, quest): number
	clearQuest(quest, nil)
	local reward = rng:NextInteger(Config.QuestReward.Min, Config.QuestReward.Max)
	addCoins(player, reward)
	addFriendship(npc, player, 5)
	setMood(npc, "Happy", 4)
	npc.anim.emote("Cheer")
	sfx(npc, "Cheer")
	offerQuestLater(npc, Config.QuestCooldown)
	if Registry.playerEvent then
		Registry.playerEvent(player, "Quest")
	end
	return reward
end

Players.PlayerRemoving:Connect(function(player)
	local quest = playerQuests[player]
	if quest then
		clearQuest(quest, nil)
		offerQuestLater(quest.npc, 5)
	end
end)

local function shouldStop(npc): boolean
	-- controlled — жителем управляет другой скрипт (например, полиция): свои дела он бросает
	return not npc.alive or npc.abort or npc.lock ~= nil or (npc.controlled ~= nil and not npc.externalWalking)
end

local function stopMoving(npc)
	if npc.alive then
		npc.humanoid:MoveTo(npc.hrp.Position)
	end
end

local function setPose(npc, pose: string)
	npc.model:SetAttribute("Pose", pose)
end

-- Плавный поворот лицом в сторону
local function face(npc, direction: Vector3, time: number?)
	direction = flat(direction)
	if direction.Magnitude < 0.05 or not npc.alive then
		return
	end
	local hrp = npc.hrp
	local from = hrp.CFrame
	local goal = CFrame.lookAt(hrp.Position, hrp.Position + direction.Unit)
	local duration = time or 0.3
	local start = os.clock()
	npc.humanoid.AutoRotate = false
	while npc.alive do
		local t = math.min(1, (os.clock() - start) / duration)
		hrp.CFrame = CFrame.new(hrp.Position) * from.Rotation:Lerp(goal.Rotation, t * t * (3 - 2 * t))
		if t >= 1 then
			break
		end
		task.wait()
	end
	npc.humanoid.AutoRotate = true
end

-- Подняться из позы (сидя на стуле, на полу или лёжа)
---------------------------------------------------------------------
-- Стулья, диваны, скамейки (Seat)
-- Жители садятся сами, без физики Seat: так они всегда смотрят от спинки,
-- сидят ровно на сиденье и не занимают одно место вдвоём.
---------------------------------------------------------------------

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Exclude

local function ignoreList(extra: Instance?)
	local list = { liveFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	if extra then
		table.insert(list, extra)
	end
	return list
end

-- Верх сиденья: если сам Seat невидимый (служебный), берём видимую подушку под ним
local function seatTop(seat: BasePart): Vector3
	local cf, size = seat.CFrame, seat.Size
	local halfY = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
	local top = seat.Position + Vector3.new(0, halfY, 0)
	if seat.Transparency >= 0.9 then
		surfaceParams.FilterDescendantsInstances = ignoreList(seat)
		local hit = workspace:Raycast(top + Vector3.new(0, 0.1, 0), Vector3.new(0, -3, 0), surfaceParams)
		if hit then
			top = Vector3.new(top.X, hit.Position.Y, top.Z)
		end
	end
	return top
end

-- Куда смотреть сидя: от спинки. Спинку ищем лучами на уровне спины,
-- если её нет — по передней грани Seat.
local function seatFacing(seat: BasePart, top: Vector3): Vector3
	local cf = seat.CFrame
	local dirs = { cf.LookVector, -cf.LookVector, cf.RightVector, -cf.RightVector }
	surfaceParams.FilterDescendantsInstances = ignoreList(seat)
	local origin = top + Vector3.new(0, 2.3, 0) -- выше столов, на уровне спинки
	local best, bestDist = nil, math.huge
	for _, d in dirs do
		local flatDir = Vector3.new(d.X, 0, d.Z)
		if flatDir.Magnitude > 0.1 then
			local hit = workspace:Raycast(origin, flatDir.Unit * 2.5, surfaceParams)
			if hit and hit.Distance < bestDist then
				best, bestDist = flatDir.Unit, hit.Distance
			end
		end
	end
	if best then
		return -best
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	return look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
end

local function floorBelow(position: Vector3, ignore: Instance?): number
	surfaceParams.FilterDescendantsInstances = ignoreList(ignore)
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), surfaceParams)
	return hit and hit.Position.Y or position.Y
end

-- Куда подойти, чтобы сесть: на пол перед сиденьем
local function seatApproach(seat: BasePart): Vector3
	local top = seatTop(seat)
	local facing = seatFacing(seat, top)
	local depth = math.max(seat.Size.X, seat.Size.Z) / 2
	local front = top + facing * math.min(depth, 1.2) + facing * 1.4
	return Vector3.new(front.X, floorBelow(front, seat), front.Z)
end

local function sitOnChair(npc, seat: BasePart): boolean
	if seat.Occupant or seat:GetAttribute("NPCSeated") then
		return false
	end
	local top = seatTop(seat)
	local facing = seatFacing(seat, top)
	local hrp = npc.hrp
	local hrpHalf = hrp.Size.Y / 2
	-- Таз ровно на сиденье, спиной к спинке
	local position = top + Vector3.new(0, hrpHalf + 0.3, 0) - facing * 0.15
	local target = CFrame.lookAt(position, position + facing)

	seat:SetAttribute("NPCSeated", true)
	seat.Disabled = true -- игрок не сядет «внутрь» жителя
	npc.humanoid.PlatformStand = true
	hrp.CFrame = target
	local weld = Instance.new("Weld")
	weld.Name = "NPCChairWeld"
	weld.Part0 = seat
	weld.Part1 = hrp
	weld.C0 = seat.CFrame:ToObjectSpace(target)
	weld.Parent = seat
	npc.chair = { seat = seat, weld = weld, facing = facing, top = top }
	setPose(npc, "Chair")
	return true
end

local function leaveChair(npc)
	local chair = npc.chair
	if not chair then
		return
	end
	npc.chair = nil
	chair.weld:Destroy()
	chair.seat:SetAttribute("NPCSeated", nil)
	chair.seat.Disabled = false
	if npc.alive then
		setPose(npc, "Stand")
		-- Встаём перед стулом
		local front = chair.top + chair.facing * 1.6
		local floorY = floorBelow(front, chair.seat)
		local height = npc.humanoid.HipHeight + npc.hrp.Size.Y / 2
		local position = Vector3.new(front.X, floorY + height, front.Z)
		npc.hrp.CFrame = CFrame.lookAt(position, position + chair.facing)
		npc.humanoid.PlatformStand = false
		task.wait(0.35)
	end
end

-- Точка (или место рядом) уже занята другим жителем или игроком?
local function spotTaken(point): boolean
	local part = point.part
	if part:IsA("Seat") and (part.Occupant or part:GetAttribute("NPCSeated")) then
		return true
	end
	for _, other in pairs(points) do
		if other ~= point and other.occupants > 0 and (other.part.Position - part.Position).Magnitude < 1.6 then
			return true
		end
	end
	return false
end

local function standUp(npc)
	if npc.inVehicle then
		return
	end
	if npc.chair then
		leaveChair(npc)
	end
	if npc.humanoid.Sit then
		npc.humanoid.Sit = false
		npc.humanoid.Jump = true
		task.wait(0.4)
	end
	local pose = npc.model:GetAttribute("Pose")
	if pose == "Lie" then
		setPose(npc, "Kneel")
		task.wait(0.7)
	end
	if pose and pose ~= "Stand" then
		setPose(npc, "Stand")
		task.wait(0.45)
	end
	npc.humanoid.WalkSpeed = walkSpeedOf(npc)
end

local function pause(npc, seconds: number): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if shouldStop(npc) then
			return false
		end
		task.wait(0.2)
	end
	return true
end

---------------------------------------------------------------------
-- Общение
---------------------------------------------------------------------

local react -- объявлена ниже

local snapToPoint -- объявлена ниже

local function freeForChat(npc, now: number): boolean
	return npc.alive
		and npc.lock == nil
		and now >= npc.chatCooldown
		and npc.model:GetAttribute("Pose") ~= "Lie"
		and not npc.humanoid.Sit
		and now >= npc.fleeUntil
		and not npc.sleeping
		and not npc.inVehicle
		and not npc.noSocial
		and not npc.controlled
end

local function runConversation(a, b, lines)
	a.lock, b.lock = "chat", "chat"
	setMood(a, "Talk")
	setMood(b, "Talk")
	stopMoving(a)
	stopMoving(b)
	task.spawn(face, a, b.hrp.Position - a.hrp.Position)
	face(b, a.hrp.Position - b.hrp.Position)

	for i, line in lines do
		local speaker = (i % 2 == 1) and a or b
		if not (a.alive and b.alive) or a.lock ~= "chat" or b.lock ~= "chat" then
			break
		end
		say(speaker, line)
		local r = rng:NextNumber()
		if r < 0.25 then
			speaker.anim.emote("Point")
		elseif r < 0.45 then
			speaker.anim.emote("Laugh")
		elseif i == 1 and r < 0.7 then
			speaker.anim.emote("Wave")
		end
		task.wait(Config.BubbleTime * 0.85)
	end

	local now = os.clock()
	for _, npc in { a, b } do
		if npc.lock == "chat" then
			npc.lock = nil
			setMood(npc, nil)
		end
		npc.chatCooldown = now + rng:NextNumber(30, 60)
		npc.abort = true -- после разговора выбираем новое дело
	end
end

-- Реакция на суперспособность игрока
function react(npc, kind: string, target: BasePart)
	if not npc.alive then
		return
	end
	say(npc, pick(Config.Phrases[kind]), 2.5)
	if kind == "Laser" then
		setMood(npc, "Scared", 6)
		npc.fleeUntil = os.clock() + 5
		npc.abort = true
		return
	end
	-- Остановиться и посмотреть
	npc.lock = "react"
	stopMoving(npc)
	if kind == "Invisible" then
		setMood(npc, "Wow", 3)
		for _ = 1, 2 do
			face(npc, (npc.hrp.CFrame * CFrame.Angles(0, rng:NextNumber(-2, 2), 0)).LookVector, 0.5)
			task.wait(0.4)
		end
	else
		setMood(npc, kind == "Cube" and "Laugh" or "Wow", 3)
		if kind == "Cube" then
			sfx(npc, "Laugh")
		end
		face(npc, target.Position - npc.hrp.Position, 0.3)
		npc.anim.emote(kind == "Cube" and "Laugh" or "Point")
		task.wait(2)
	end
	if npc.lock == "react" then
		npc.lock = nil
	end
	npc.abort = true
end

local function tryStartChat(npc, now: number)
	if now < npc.nextSocialCheck or npc.inVehicle or npc.noSocial or npc.controlled then
		return
	end
	npc.nextSocialCheck = now + 0.6

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or npc.sleeping then
			continue
		end
		local dist = (hrp.Position - npc.hrp.Position).Magnitude
		local invisible = character:GetAttribute(ATTR_INVISIBLE) == true

		-- Реакция на суперспособности
		if dist < Config.ReactDistance and now >= (npc.reacted[player] or 0) and npc.lock == nil then
			local kind
			if character:GetAttribute(ATTR_LASER) == true then
				kind = "Laser"
			elseif character:GetAttribute(ATTR_FLYING) == true then
				kind = "Flying"
			elseif character:GetAttribute(ATTR_CUBE) == true and dist < 18 then
				kind = "Cube"
			elseif invisible and dist < 8 then
				kind = "Invisible"
			end
			if kind then
				npc.reacted[player] = now + Config.ReactCooldown
				task.spawn(react, npc, kind, hrp)
				continue
			end
		end

		-- Помахать проходящему игроку (знакомого — назвать по имени)
		if not invisible and dist < Config.GreetDistance and now >= (npc.greeted[player] or 0) then
			npc.greeted[player] = now + 45
			if rng:NextNumber() < Config.GreetPlayerChance then
				local known = memory[npc.name] and memory[npc.name][player.UserId]
				local text = known and string.format(pick(Config.Phrases.KnownGreet) :: string, player.DisplayName)
					or pick(Config.Phrases.Greet)
				task.spawn(function()
					npc.anim.emote("Wave")
					sfx(npc, "Wave")
					say(npc, text, 2.5)
				end)
			end
		end
	end

	-- Заговорить с соседом
	if not freeForChat(npc, now) then
		return
	end
	for _, other in pairs(npcs) do
		if other ~= npc and freeForChat(other, now)
			and (other.hrp.Position - npc.hrp.Position).Magnitude < Config.ChatDistance then
			local key = other.model
			if now >= (npc.chatChecked[key] or 0) then
				npc.chatChecked[key] = now + 20
				other.chatChecked[npc.model] = now + 20
				if rng:NextNumber() < Config.ChatChance then
					task.spawn(runConversation, npc, other, pick(Config.Conversations))
					return
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Ходьба
---------------------------------------------------------------------

local function walkTo(npc, target: Vector3): boolean
	local humanoid, hrp = npc.humanoid, npc.hrp
	local path = PathfindingService:CreatePath({
		AgentRadius = Config.AgentRadius,
		AgentHeight = Config.AgentHeight,
		AgentCanJump = true,
		WaypointSpacing = 4,
		Costs = { Door = 1 },
	})

	for _ = 1, 3 do
		if shouldStop(npc) then
			return false
		end
		local ok = pcall(path.ComputeAsync, path, hrp.Position, target)
		local waypoints
		if ok and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
		elseif (flat(target - hrp.Position)).Magnitude < 14 then
			waypoints = { { Position = hrp.Position }, { Position = target, Action = Enum.PathWaypointAction.Walk } }
		else
			task.wait(1)
			continue
		end

		local blocked = false
		local conn
		if ok then
			conn = path.Blocked:Connect(function()
				blocked = true
			end)
		end

		local reachedAll = true
		for i = 2, #waypoints do
			local wp = waypoints[i]
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			humanoid:MoveTo(wp.Position)

			local start = os.clock()
			local lastPos, lastMove = hrp.Position, os.clock()
			local reached = false
			while true do
				if shouldStop(npc) then
					if conn then
						conn:Disconnect()
					end
					stopMoving(npc)
					return false
				end
				local now = os.clock()
				tryStartChat(npc, now)
				if (flat(wp.Position - hrp.Position)).Magnitude < 2.2 then
					reached = true
					break
				end
				-- Застрял: подпрыгнуть, потом пересчитать путь
				if (hrp.Position - lastPos).Magnitude > 0.5 then
					lastPos, lastMove = hrp.Position, now
				elseif now - lastMove > 1.2 then
					humanoid.Jump = true
					lastMove = now
				end
				if blocked or now - start > 4 then
					break
				end
				humanoid:MoveTo(wp.Position)
				task.wait(0.1)
			end
			if not reached then
				reachedAll = false
				break
			end
		end
		if conn then
			conn:Disconnect()
		end
		if reachedAll then
			return true
		end
		-- Почти дошли (точка на кровати/диване, куда не залезть) — считаем, что пришли
		if (flat(target - hrp.Position)).Magnitude < 4 then
			return true
		end
	end
	return (flat(target - hrp.Position)).Magnitude < 4
end

---------------------------------------------------------------------
-- Выбор дела
---------------------------------------------------------------------

-- Дойти — или доехать (своя машина, такси, автобус), если далеко
local function travelTo(npc, target: Vector3): boolean
	if Registry.tryTrip and not shouldStop(npc) then
		local ok, used = pcall(Registry.tryTrip, npc, target)
		if not ok then
			warn("[NPC] Ошибка поездки:", used)
		end
		if not npc.alive then
			return false
		end
	end
	return walkTo(npc, target)
end

local function pointCategory(npc, point): string
	if point.zone == nil or point.zone == Config.OutdoorZone then
		return "Street"
	elseif npc.homeZone and point.zone == npc.homeZone then
		return "Home"
	end
	return "Other"
end

-- Куда пойти: по расписанию (дом / улица / другие места), выходным и погоде
local function choosePoint(npc)
	local period = currentPeriod()
	local weights = {
		Home = period and period.Home or 0.4,
		Street = period and period.Street or 0.35,
		Other = period and period.Other or 0.25,
	}
	local prefer = {}
	for k, v in pairs(period and period.Prefer or {}) do
		prefer[k] = v
	end
	if isWeekend() and Config.Weekend then
		local w = Config.Weekend
		weights.Home *= w.Home or 1
		weights.Street *= w.Street or 1
		weights.Other *= w.Other or 1
		for k, v in pairs(w.Prefer or {}) do
			prefer[k] = (prefer[k] or 1) * v
		end
	end
	if rainNow() > 0.3 then
		weights.Street *= Config.RainStreetFactor or 0.25
		weights.Home *= 1.5
	end
	if not npc.homeZone then
		weights.Street += weights.Home
		weights.Home = 0
	end

	local buckets = { Home = {}, Street = {}, Other = {} }
	local sums = { Home = 0, Street = 0, Other = 0 }
	for _, point in pairs(points) do
		if point ~= npc.point and point.occupants < point.capacity and point.part.Parent
			and point.activity ~= "Work" and point.activity ~= "Patrol"
			and not spotTaken(point) then
			local cat = pointCategory(npc, point)
			-- Ближние точки чуть вероятнее, любимые занятия периода — тоже
			local dist = (point.part.Position - npc.hrp.Position).Magnitude
			local weight = (1 / (1 + dist / 80)) * (prefer[point.activity] or 1)
			table.insert(buckets[cat], { point = point, weight = weight })
			sums[cat] += weight
		end
	end

	local total = 0
	for cat, w in pairs(weights) do
		if #buckets[cat] > 0 then
			total += w
		end
	end
	local chosen
	if total > 0 then
		local roll = rng:NextNumber() * total
		for cat, w in pairs(weights) do
			if #buckets[cat] > 0 then
				roll -= w
				if roll <= 0 then
					chosen = cat
					break
				end
			end
		end
	end
	if not chosen then
		for cat, list in pairs(buckets) do
			if #list > 0 then
				chosen = cat
				break
			end
		end
	end
	if not chosen then
		return nil
	end

	local list = buckets[chosen]
	local roll = rng:NextNumber() * sums[chosen]
	for _, c in list do
		roll -= c.weight
		if roll <= 0 then
			return c.point
		end
	end
	return list[#list].point
end

-- Встать точно на точку (например, на кровать) и повернуться, как она смотрит
function snapToPoint(npc, part: BasePart)
	local hrp = npc.hrp
	local top = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
	if (flat(top - hrp.Position)).Magnitude > 4.5 then
		face(npc, part.CFrame.LookVector)
		return
	end
	local look = flat(part.CFrame.LookVector)
	local position = top + Vector3.new(0, npc.humanoid.HipHeight + hrp.Size.Y / 2 + 0.05, 0)
	hrp.CFrame = CFrame.lookAt(position, position + (look.Magnitude > 0.1 and look.Unit or hrp.CFrame.LookVector))
end

-- Куда идти к точке: к стулу — на пол перед ним
local function approachPosition(point): Vector3
	if point.part:IsA("Seat") then
		return seatApproach(point.part)
	end
	return point.part.Position
end

local function doActivity(npc, point)
	local part = point.part
	local activity = point.activity
	local range = Config.ActivityTime[activity] or Config.ActivityTime.Idle
	local duration = randomIn(range)

	if part:IsA("Seat") then
		if not sitOnChair(npc, part) then
			return
		end
		pause(npc, duration)
		standUp(npc)
	elseif activity == "Sit" or activity == "Lie" then
		snapToPoint(npc, part)
		npc.humanoid.WalkSpeed = 0
		setPose(npc, activity)
		pause(npc, duration)
		if npc.alive then
			standUp(npc)
		end
	elseif activity == "Look" then
		face(npc, part.CFrame.LookVector, 0.5)
		pause(npc, duration)
	elseif activity == "Dance" then
		face(npc, part.CFrame.LookVector)
		setMood(npc, "Dance", duration)
		local t = npc.anim.emote(rng:NextNumber() < 0.5 and "Dance" or "Dance2", duration)
		if not pause(npc, duration) and t then
			t:Stop(0.3)
		end
	elseif activity == "Talk" then
		-- Ждём собеседника: tryStartChat сам заведёт разговор
		face(npc, part.CFrame.LookVector)
		local deadline = os.clock() + duration
		while os.clock() < deadline and not shouldStop(npc) do
			npc.chatChecked = {} -- в точке для болтовни шанс встречи выше
			tryStartChat(npc, os.clock())
			task.wait(0.5)
		end
	else -- Idle: стоит, иногда осматривается и бормочет
		local elapsed = 0
		while elapsed < duration and not shouldStop(npc) do
			local step = rng:NextNumber(1.5, 3)
			if rng:NextNumber() < 0.5 then
				local angle = rng:NextNumber(-1.2, 1.2)
				face(npc, (npc.hrp.CFrame * CFrame.Angles(0, angle, 0)).LookVector, 0.6)
			end
			if rng:NextNumber() < 0.12 then
				say(npc, pick(Config.Phrases.Idle))
			end
			pause(npc, step)
			elapsed += step
		end
	end
end

local function fleePoint(npc)
	local best, bestDist = nil, 0
	for _, point in pairs(points) do
		local dist = (point.part.Position - npc.hrp.Position).Magnitude
		if dist > bestDist and dist < 250 then
			best, bestDist = point, dist
		end
	end
	return best
end

---------------------------------------------------------------------
-- Ночь: домой спать
---------------------------------------------------------------------

local function sleepPoint(npc)
	for _, wanted in { "Lie", "Sit", "Idle" } do
		for _, p in pairs(points) do
			if p.zone == npc.homeZone and p.activity == wanted and p.occupants < p.capacity
				and not spotTaken(p) then
				return p
			end
		end
	end
	return nil
end

local function goSleep(npc): boolean
	local point = sleepPoint(npc)
	if not point then
		return false
	end
	if not npc.saidNight then
		npc.saidNight = true
		say(npc, pick(Config.Phrases.Night))
	end
	point.occupants += 1
	npc.point = point
	local arrived = travelTo(npc, approachPosition(point))
	if arrived and not shouldStop(npc) then
		npc.zone = npc.homeZone
		npc.sleeping = true
		setMood(npc, "Sleep")
		if point.part:IsA("Seat") then
			if not sitOnChair(npc, point.part) then
				npc.sleeping = false
				setMood(npc, nil)
				point.occupants = math.max(0, point.occupants - 1)
				return false
			end
		else
			snapToPoint(npc, point.part)
			npc.humanoid.WalkSpeed = 0
			setPose(npc, point.activity == "Lie" and "Lie" or "Sit")
		end
		local nextSnore = os.clock() + rng:NextNumber(3, 8)
		while isNight() and not shouldStop(npc) do
			if os.clock() > nextSnore then
				say(npc, pick(Config.Phrases.Sleep), 2.5)
				sfx(npc, "Snore")
				nextSnore = os.clock() + rng:NextNumber(6, 14)
			end
			task.wait(0.5)
		end
		npc.sleeping = false
		setMood(npc, nil)
		if npc.alive then
			standUp(npc)
			if not isNight() then
				npc.saidNight = false
				say(npc, pick(Config.Phrases.Morning))
				npc.anim.emote("Cheer")
			end
		end
	end
	point.occupants = math.max(0, point.occupants - 1)
	return true
end

---------------------------------------------------------------------
-- Работа и патрули
---------------------------------------------------------------------

local function someoneNear(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local c = player.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - position).Magnitude < radius then
			return true
		end
	end
	return false
end

local function doWork(npc)
	local point = npc.job
	if not point.part.Parent then
		npc.job = nil
		return
	end
	if not travelTo(npc, point.part.Position) or shouldStop(npc) then
		npc.onBreak = not shouldStop(npc) -- не дошёл до прилавка — займётся чем-то другим
		return
	end
	face(npc, point.part.CFrame.LookVector)
	if not npc.atWork then
		npc.atWork = true
		say(npc, pick(Config.WorkPhrases.Start))
		setMood(npc, "Work", 4)
	end
	local shiftEnd = os.clock() + randomIn(Config.WorkShift)
	while os.clock() < shiftEnd and not shouldStop(npc) and not (isNight() and npc.homeZone) and isWorkTime() do
		if someoneNear(npc.hrp.Position, 16) and rng:NextNumber() < 0.5 then
			say(npc, pick(Config.Phrases.Work))
			npc.anim.emote(rng:NextNumber() < 0.5 and "Wave" or "Point")
		elseif rng:NextNumber() < 0.35 then
			face(npc, (point.part.CFrame * CFrame.Angles(0, rng:NextNumber(-0.7, 0.7), 0)).LookVector, 0.6)
		else
			face(npc, point.part.CFrame.LookVector, 0.5)
		end
		pause(npc, rng:NextNumber(4, 8))
	end
	if not isWorkTime() and npc.atWork then
		-- Обед или конец смены
		npc.atWork = false
		local h = hourNow()
		local lunch = Config.WorkHours and h >= Config.WorkHours.LunchStart and h < Config.WorkHours.LunchEnd
		say(npc, pick(lunch and Config.WorkPhrases.Lunch or Config.WorkPhrases.End))
		if lunch then
			setMood(npc, "Lunch", 10)
		end
	elseif not shouldStop(npc) then
		npc.onBreak = true -- перерыв: одно обычное дело, потом снова за работу
	end
end

local function doPatrol(npc)
	local route = routes[npc.route]
	if not route or #route.points == 0 then
		npc.route = nil
		return
	end
	for _, p in route.points do
		if shouldStop(npc) or (isNight() and npc.homeZone) then
			return
		end
		if p.part.Parent and walkTo(npc, p.part.Position) then
			face(npc, p.part.CFrame.LookVector, 0.4)
			if rng:NextNumber() < 0.25 then
				say(npc, pick(Config.Phrases.Patrol))
			end
			if not pause(npc, randomIn(Config.PatrolPause)) then
				return
			end
		end
	end
	if rng:NextNumber() < 0.3 then
		npc.onBreak = true
	end
end

local function assignJob(npc): string?
	local best
	for _, p in pairs(points) do
		if p.activity == "Work" and not p.worker and p.part.Parent then
			if not best or (p.zone == npc.homeZone and best.zone ~= npc.homeZone) then
				best = p
			end
		end
	end
	if best then
		best.worker = npc
		npc.job = best
		return best.role or Config.DefaultWorkRole
	end
	for name, route in pairs(routes) do
		if not route.guard and #route.points > 0 then
			route.guard = npc
			npc.route = name
			return route.points[1].role or Config.DefaultPatrolRole
		end
	end
	return nil
end

local function brain(npc)
	-- Просыпаемся: лёжа → на колени → встаём
	setPose(npc, "Lie")
	task.wait(1.4)
	if rng:NextNumber() < 0.35 then
		say(npc, pick(Config.Phrases.Wake))
	end
	setPose(npc, "Kneel")
	task.wait(0.9)
	setPose(npc, "Stand")
	task.wait(0.5)

	while npc.alive do
		while npc.alive and (npc.lock ~= nil or npc.controlled ~= nil) do
			task.wait(0.2)
		end
		if not npc.alive then
			break
		end
		npc.abort = false

		local now = os.clock()
		if now < npc.fleeUntil then
			-- Убегаем подальше
			standUp(npc)
			setMood(npc, "Scared", 5)
			sfx(npc, "Scream")
			npc.humanoid.WalkSpeed = Config.RunSpeed
			local target = fleePoint(npc)
			if target then
				walkTo(npc, target.part.Position)
			else
				task.wait(1)
			end
			npc.humanoid.WalkSpeed = walkSpeedOf(npc)
			continue
		end

		-- Ночью у кого есть дом — идут спать
		if isNight() and npc.homeZone and goSleep(npc) then
			continue
		end

		-- Работа или обход маршрута (между ними — перерывы)
		if not npc.onBreak then
			if npc.job and isWorkTime() then
				doWork(npc)
				continue
			elseif npc.route then
				doPatrol(npc)
				continue
			end
		end
		npc.onBreak = false

		local point = choosePoint(npc)
		if not point then
			task.wait(2)
			continue
		end
		point.occupants += 1
		npc.point = point
		local arrived = travelTo(npc, approachPosition(point))
		if arrived and not shouldStop(npc) then
			if point.zone ~= nil then
				npc.zone = point.zone
			end
			doActivity(npc, point)
		end
		point.occupants = math.max(0, point.occupants - 1)
		task.wait(rng:NextNumber(0.2, 1))
	end
end

---------------------------------------------------------------------
-- Разговор с игроком
---------------------------------------------------------------------

local dialogTitle, refreshTopics -- объявлены ниже

local function endPlayerTalk(npc, sayBye: boolean)
	local player = npc.talkingTo
	if not player then
		return
	end
	npc.talkingTo = nil
	if sayBye and npc.alive then
		say(npc, pick(Config.PlayerBye), 2.5)
		npc.anim.emote("Wave")
	end
	if npc.lock == "player" then
		npc.lock = nil
		setMood(npc, nil)
	end
	npc.abort = true
	npc.chatCooldown = os.clock() + 10
	if npc.prompt then
		npc.prompt.Enabled = true
	end
	if player.Parent then
		dialogRemote:FireClient(player, "Close", npc.model)
	end
end

-- Заголовок окна: имя, работа и уровень дружбы
function dialogTitle(npc, player: Player): string
	local level = friendLevel(friendPoints(npc, player))
	return string.format("%s  ·  %s %s", npc.title, level.Name, level.Icon)
end

-- Темы разговора: задание (если есть) + обычные темы
function refreshTopics(npc, player: Player): { string }
	local list = {}
	local quest = playerQuests[player]
	if quest and quest.npc == npc and quest.carrying then
		table.insert(list, { text = string.format(Config.QuestReturnTopic, quest.def.Name), kind = "QuestReturn" })
	elseif npc.hasQuest and not quest then
		table.insert(list, { text = Config.QuestTopic, kind = "QuestAsk" })
	end
	for _, topic in Config.PlayerTopics do
		table.insert(list, { text = topic.Text, kind = "Topic", topic = topic })
	end
	npc.topics = list
	local texts = {}
	for i, entry in list do
		texts[i] = entry.text
	end
	return texts
end

local function startPlayerTalk(npc, player: Player)
	if not npc.alive or npc.talkingTo or npc.inVehicle or npc.officer then
		return
	end
	if npc.controlled then
		say(npc, "Извините, не сейчас...", 2)
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	if npc.lock == "chat" then
		say(npc, "Секунду, я разговариваю!", 2)
		return
	end

	local wasSleeping = npc.sleeping
	npc.lock = "player"
	npc.talkingTo = player
	npc.lastTalk = os.clock()
	npc.prompt.Enabled = false
	stopMoving(npc)
	setMood(npc, "Talk")

	local points0 = friendPoints(npc, player)
	if os.clock() >= (npc.friendCooldown[player] or 0) then
		npc.friendCooldown[player] = os.clock() + 60
		addFriendship(npc, player, 1)
	end
	local quest = playerQuests[player]
	local greeting
	if wasSleeping then
		greeting = pick(Config.Phrases.Grumpy)
	elseif quest and quest.npc == npc and not quest.carrying then
		greeting = pick(Config.Phrases.QuestWaiting)
	elseif points0 >= FRIEND_POINTS then
		greeting = string.format(pick(Config.Phrases.Friend) :: string, player.DisplayName)
	elseif points0 > 0 then
		greeting = string.format(pick(Config.Phrases.KnownGreet) :: string, player.DisplayName)
	else
		greeting = pick(Config.PlayerGreeting)
	end
	dialogRemote:FireClient(player, "Open", npc.model, dialogTitle(npc, player), greeting, refreshTopics(npc, player))

	task.spawn(function()
		standUp(npc)
		face(npc, hrp.Position - npc.hrp.Position)
		npc.anim.emote("Wave")
		say(npc, greeting)

		-- Следим, не ушёл ли игрок
		while npc.talkingTo == player and npc.alive do
			local c = player.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if not r or (r.Position - npc.hrp.Position).Magnitude > Config.TalkDistance + 8
				or os.clock() - npc.lastTalk > 40 then
				endPlayerTalk(npc, true)
				break
			end
			if (flat(r.Position - npc.hrp.Position)).Magnitude > 1 then
				local look = flat(npc.hrp.CFrame.LookVector)
				local want = flat(r.Position - npc.hrp.Position).Unit
				if look:Dot(want) < 0.9 then
					face(npc, want, 0.25)
				end
			end
			task.wait(0.3)
		end
	end)
end

---------------------------------------------------------------------
-- «Пойдём со мной!»
---------------------------------------------------------------------

local function stopFollow(npc, sayBye: boolean)
	if not npc.following then
		return
	end
	npc.following = nil
	if npc.lock == "follow" then
		npc.lock = nil
	end
	setMood(npc, nil)
	if npc.alive then
		npc.humanoid.WalkSpeed = npc.speed
		npc.prompt.ActionText = Config.TalkPromptText
		npc.prompt.Enabled = true
		if sayBye then
			say(npc, pick(Config.Phrases.FollowEnd))
			npc.anim.emote("Wave")
		end
	end
	npc.abort = true
end

local function startFollow(npc, player: Player)
	npc.talkingTo = nil
	npc.lock = "follow"
	npc.following = player
	setMood(npc, "Follow")
	npc.prompt.ActionText = "Отпустить"
	npc.prompt.Enabled = true
	dialogRemote:FireClient(player, "Close", npc.model)

	task.spawn(function()
		local deadline = os.clock() + Config.FollowTime
		local lastPos, lastMove = npc.hrp.Position, os.clock()
		while npc.alive and npc.following == player and os.clock() < deadline do
			local c = player.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if not r or (r.Position - npc.hrp.Position).Magnitude > 90 or os.clock() < npc.fleeUntil then
				break
			end
			local offset = flat(r.Position - npc.hrp.Position)
			local dist = offset.Magnitude
			if dist > Config.FollowDistance then
				npc.humanoid.WalkSpeed = dist > 16 and Config.RunSpeed or math.max(npc.speed, 13)
				local goal = r.Position - offset.Unit * (Config.FollowDistance - 1)
				-- Застрял за стеной — идём по найденному пути
				if os.clock() - lastMove > 1.5 then
					local path = PathfindingService:CreatePath({ AgentRadius = Config.AgentRadius, AgentHeight = Config.AgentHeight, AgentCanJump = true })
					if pcall(path.ComputeAsync, path, npc.hrp.Position, r.Position) and path.Status == Enum.PathStatus.Success then
						local wps = path:GetWaypoints()
						goal = (wps[math.min(3, #wps)] or wps[#wps]).Position
					end
					npc.humanoid.Jump = true
					lastMove = os.clock()
				end
				npc.humanoid:MoveTo(goal)
			else
				stopMoving(npc)
				lastMove = os.clock()
			end
			if (npc.hrp.Position - lastPos).Magnitude > 0.5 then
				lastPos, lastMove = npc.hrp.Position, os.clock()
			end
			task.wait(0.25)
		end
		stopFollow(npc, npc.alive)
	end)
end

dialogRemote.OnServerEvent:Connect(function(player: Player, action: any, model: any, index: any)
	local npc = typeof(model) == "Instance" and npcs[model] or nil
	if not npc or npc.talkingTo ~= player then
		return
	end
	if action == "Bye" then
		endPlayerTalk(npc, true)
	elseif action == "Ask" and type(index) == "number" then
		local entry = npc.topics and npc.topics[index]
		if not entry or os.clock() - (npc.lastAsk or 0) < 0.6 then
			return
		end
		npc.lastAsk = os.clock()
		npc.lastTalk = os.clock()

		if entry.kind == "QuestAsk" then
			local answer
			local quest = npc.hasQuest and not playerQuests[player] and startQuest(npc, player)
			if quest then
				answer = string.format(pick(Config.Phrases.QuestAsk) :: string, quest.def.Name)
				npc.anim.emote("Point")
			else
				answer = "Уже не нужно, спасибо!"
			end
			say(npc, answer)
			dialogRemote:FireClient(player, "Answer", model, answer, refreshTopics(npc, player))
			return
		elseif entry.kind == "QuestReturn" then
			local quest = playerQuests[player]
			if quest and quest.npc == npc and quest.carrying then
				local reward = finishQuest(npc, player, quest)
				local answer = pick(Config.Phrases.QuestThanks) .. string.format(" (+%d)", reward)
				say(npc, answer)
				dialogRemote:FireClient(player, "Answer", model, answer, refreshTopics(npc, player))
				dialogRemote:FireClient(player, "Title", model, dialogTitle(npc, player))
			end
			return
		end

		local topic = entry.topic
		local answer = pick(topic.Answers)
		say(npc, answer)
		if topic.Emote == "Dance" then
			npc.anim.emote(rng:NextNumber() < 0.5 and "Dance" or "Dance2", 4)
		elseif topic.Emote then
			npc.anim.emote(topic.Emote)
		end
		dialogRemote:FireClient(player, "Answer", model, answer)
		if topic.Follow then
			task.delay(0.8, function()
				if npc.alive and npc.talkingTo == player then
					startFollow(npc, player)
				end
			end)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, npc in pairs(npcs) do
		if npc.talkingTo == player then
			endPlayerTalk(npc, false)
		end
		if npc.following == player then
			stopFollow(npc, false)
		end
		npc.greeted[player] = nil
		npc.reacted[player] = nil
	end
end)

---------------------------------------------------------------------
-- Появление и возрождение
---------------------------------------------------------------------

local spawnNPC

local function onDied(npc)
	if not npc.alive then
		return
	end
	npc.alive = false
	if npc.talkingTo then
		endPlayerTalk(npc, false)
	end
	if npc.point then
		npc.point.occupants = math.max(0, npc.point.occupants - 1)
	end
	if npc.following then
		stopFollow(npc, false)
	end
	if npc.chair then
		npc.chair.weld:Destroy()
		npc.chair.seat:SetAttribute("NPCSeated", nil)
		npc.chair.seat.Disabled = false
		npc.chair = nil
	end
	if npc.job then
		npc.job.worker = nil
	end
	if npc.route and routes[npc.route] and routes[npc.route].guard == npc then
		routes[npc.route].guard = nil
	end
	if npc.activeQuest then
		clearQuest(npc.activeQuest, "😢 " .. npc.name .. " пропал(а) — задание отменено")
	end
	npc.anim.stopAll()
	task.delay(Config.CorpseTime, function()
		npcs[npc.model] = nil
		total -= 1
		npc.model:Destroy()
	end)
	if npc.inVehicle then
		local car = npc.inVehicle
		if npc.vehicleWeld then
			npc.vehicleWeld:Destroy()
		end
		if car.occupants and npc.vehicleSeat then
			car.occupants[npc.vehicleSeat] = nil
		end
		npc.inVehicle = nil
	end
	if Registry.releaseCar then
		Registry.releaseCar(npc)
	end
	task.delay(Config.RespawnTime, function()
		if npc.spawn and npc.spawn.Parent then
			spawnNPC(npc.spawn)
		end
	end)
end

-- Вещи в руках (приварены к кисти и двигаются вместе с анимацией)
local PROP_KINDS = { "Cup", "Phone", "IceCream", "Bag" }

local function addProp(model: Model, kind: string)
	local hand = model:FindFirstChild(kind == "Bag" and "LeftHand" or "RightHand")
	if not hand then
		return
	end
	local function piece(size: Vector3, color: Color3, offset: CFrame, shape: Enum.PartType?, material: Enum.Material?)
		local p = Instance.new("Part")
		p.Name = "Prop"
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CollisionGroup = COLLISION_GROUP
		p.CFrame = hand.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- ось цилиндра — вертикально
	if kind == "Cup" then
		piece(Vector3.new(0.7, 0.45, 0.45), Color3.fromRGB(245, 245, 240), CFrame.new(0, -0.3, -0.2) * upright, Enum.PartType.Cylinder)
		piece(Vector3.new(0.1, 0.48, 0.48), Color3.fromRGB(120, 75, 45), CFrame.new(0, 0.07, -0.2) * upright, Enum.PartType.Cylinder)
	elseif kind == "Phone" then
		piece(Vector3.new(0.35, 0.7, 0.08), Color3.fromRGB(25, 25, 30), CFrame.new(0, -0.3, -0.25))
		piece(Vector3.new(0.3, 0.6, 0.02), Color3.fromRGB(120, 190, 255), CFrame.new(0, -0.3, -0.3), nil, Enum.Material.Neon)
	elseif kind == "IceCream" then
		piece(Vector3.new(0.7, 0.3, 0.3), Color3.fromRGB(210, 160, 90), CFrame.new(0, -0.3, -0.2) * upright, Enum.PartType.Cylinder)
		piece(Vector3.new(0.5, 0.5, 0.5), pick({ Color3.fromRGB(255, 170, 200), Color3.fromRGB(250, 240, 210), Color3.fromRGB(120, 80, 50) }), CFrame.new(0, 0.15, -0.2), Enum.PartType.Ball)
	elseif kind == "Bag" then
		piece(Vector3.new(1.1, 0.9, 0.4), pick(Config.ShirtColors), CFrame.new(0, -0.8, 0), nil, Enum.Material.Fabric)
	end
end

-- Создать жителя. spawnPart — точка появления (обычные жители),
-- opts.custom — без «мозга» (им управляет другой скрипт, например полиция)
local function createNPC(spawnPart: BasePart?, opts)
	opts = opts or {}
	if total >= Config.MaxNPCs + (opts.custom and 14 or 0) then
		return nil
	end
	total += 1

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(makeDescription(opts), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		total -= 1
		warn("[NPC] Не удалось создать модель жителя:", model)
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		total -= 1
		model:Destroy()
		return nil
	end
	local oldAnimate = model:FindFirstChild("Animate")
	if oldAnimate then
		oldAnimate:Destroy() -- анимации ведёт сервер
	end

	local name = pick(Config.FirstNames)
	if opts.prefix then
		name = opts.prefix .. " " .. name
	end
	model.Name = name
	model:SetAttribute("VoicePitch", rng:NextNumber(SoundConfig.VoicePitch.Min, SoundConfig.VoicePitch.Max))
	humanoid.DisplayName = name
	humanoid.NameDisplayDistance = 40
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	local speed = randomIn(Config.WalkSpeed)
	humanoid.WalkSpeed = speed
	-- Сиденья не «затягивают» проходящих мимо жителей: садятся они только сами
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = COLLISION_GROUP
		end
	end

	-- Ставим на точку появления
	if opts.cframe then
		model:PivotTo(opts.cframe)
	else
		local offset = (rng:NextNumber() - 0.5) * 2
		local top = spawnPart.Position + Vector3.new(offset, spawnPart.Size.Y / 2, offset)
		local look = flat(spawnPart.CFrame.LookVector)
		local height = humanoid.HipHeight + hrp.Size.Y / 2 + 0.1
		model:PivotTo(CFrame.lookAt(top + Vector3.new(0, height, 0), top + Vector3.new(0, height, 0) + (look.Magnitude > 0 and look or Vector3.new(0, 0, -1))))
	end
	model:SetAttribute("Pose", opts.custom and "Stand" or "Lie")
	if not opts.custom and rng:NextNumber() < Config.PropChance then
		addProp(model, pick(PROP_KINDS))
	end
	CollectionService:AddTag(model, Config.Tag)
	model.Parent = liveFolder
	pcall(function()
		hrp:SetNetworkOwner(nil)
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = Config.TalkPromptText
	prompt.ObjectText = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.TalkDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = hrp

	local npc = {
		model = model,
		humanoid = humanoid,
		hrp = hrp,
		name = name,
		spawn = spawnPart,
		zone = spawnPart and spawnPart:GetAttribute("Zone") or nil,
		homeZone = spawnPart and (spawnPart:GetAttribute("Zone") ~= Config.OutdoorZone) and spawnPart:GetAttribute("Zone") or nil,
		sleeping = false,
		saidNight = false,
		following = nil,
		reacted = {},
		friendCooldown = {},
		hasUmbrellaItem = rng:NextNumber() < (Config.UmbrellaChance or 0.6),
		title = name,
		job = nil,
		route = nil,
		onBreak = false,
		hasQuest = false,
		activeQuest = nil,
		baseMood = nil,
		speed = speed,
		anim = newAnimator(humanoid),
		prompt = prompt,
		alive = true,
		lock = nil, -- "chat" / "player"
		abort = false,
		point = nil,
		talkingTo = nil,
		lastTalk = 0,
		chatCooldown = os.clock() + rng:NextNumber(5, 15),
		chatChecked = {},
		greeted = {},
		nextSocialCheck = 0,
		fleeUntil = 0,
		lastHurt = 0,
	}
	npcs[model] = npc

	-- Работа, задание, собака
	local role = (not opts.custom) and assignJob(npc) or opts.role
	if opts.custom and role then
		npc.title = name
		humanoid.DisplayName = name .. " · " .. role
	elseif role then
		npc.title = name .. " · " .. role
		humanoid.DisplayName = npc.title
		prompt.ObjectText = npc.title
	elseif not opts.custom then
		if rng:NextNumber() < Config.DogChance then
			model:SetAttribute("DogColor", pick(Config.DogColors))
		end
	end
	if not opts.custom and not npc.route and rng:NextNumber() < Config.QuestChance then
		npc.hasQuest = true
		setBaseMood(npc, "Quest")
	end

	prompt.Triggered:Connect(function(player)
		if npc.following == player then
			stopFollow(npc, true)
		elseif not npc.following then
			startPlayerTalk(npc, player)
		end
	end)

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth and health > 0 then
			local now = os.clock()
			if now - npc.lastHurt > 2 then
				npc.lastHurt = now
				say(npc, pick(Config.Phrases.Hurt), 2)
				sfx(npc, "Hurt")
			end
			if npc.inVehicle or npc.officer or npc.controlled then
				lastHealth = health
				return -- в машине и под присмотром полиции не убегает
			end
			npc.fleeUntil = now + 6
			setMood(npc, "Scared", 6)
			if npc.talkingTo then
				endPlayerTalk(npc, false)
			end
			if npc.lock == "chat" then
				npc.lock = nil
			end
			npc.abort = true
		end
		lastHealth = health
	end)
	humanoid.Died:Connect(function()
		onDied(npc)
	end)

	if not opts.custom then
		task.spawn(brain, npc)
		if Registry.assignCar then
			task.spawn(Registry.assignCar, npc)
		end
	end
	return npc
end

function spawnNPC(spawnPart: BasePart)
	createNPC(spawnPart, nil)
end

---------------------------------------------------------------------
-- Зонты, скорость по расписанию, реакции на погоду
---------------------------------------------------------------------

local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Exclude

local function outdoors(npc): boolean
	local ignore = { liveFolder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	roofParams.FilterDescendantsInstances = ignore
	return workspace:Raycast(npc.hrp.Position + Vector3.new(0, 2, 0), Vector3.new(0, 50, 0), roofParams) == nil
end

local function addUmbrella(npc)
	local torso = npc.model:FindFirstChild("UpperTorso")
	if not torso or npc.umbrella then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Umbrella"
	local color = pick(Config.UmbrellaColors)
	local function piece(size: Vector3, offset: CFrame, c: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Size = size
		p.Color = c
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CollisionGroup = COLLISION_GROUP
		p.CFrame = torso.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = p
		w.Parent = p
		p.Parent = m
		return p
	end
	local upright = CFrame.Angles(0, 0, math.rad(90))
	piece(Vector3.new(3.2, 0.12, 0.12), CFrame.new(0.75, 1.3, -0.9) * upright, Color3.fromRGB(40, 40, 45), Enum.PartType.Cylinder) -- ручка
	piece(Vector3.new(0.25, 4.4, 4.4), CFrame.new(0.4, 3, -0.4) * upright, color, Enum.PartType.Cylinder) -- купол
	piece(Vector3.new(0.6, 0.6, 0.6), CFrame.new(0.4, 3.2, -0.4), color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.PartType.Ball)
	m.Parent = npc.model
	npc.umbrella = m
	npc.model:SetAttribute("Umbrella", true) -- клиент поднимает руку
end

local function removeUmbrella(npc)
	if npc.umbrella then
		npc.umbrella:Destroy()
		npc.umbrella = nil
		npc.model:SetAttribute("Umbrella", nil)
	end
end

task.spawn(function()
	local wasRaining = false
	while true do
		task.wait(1.5)
		local raining = rainNow() > 0.25
		local period = currentPeriod()
		local now = os.clock()
		for _, npc in pairs(npcs) do
			if npc.alive and not npc.officer then
				local out = not npc.inVehicle and outdoors(npc)
				-- Зонт
				local standing = (npc.model:GetAttribute("Pose") or "Stand") == "Stand" and not npc.chair and not npc.inVehicle
				if raining and out and standing and npc.hasUmbrellaItem and not npc.model:GetAttribute("Cuffed") then
					addUmbrella(npc)
				else
					removeUmbrella(npc)
				end
				-- Скорость: утром спешат, в дождь бегут
				npc.speedMul = (period and period.Speed or 1) * ((raining and out) and (Config.RainSpeed or 1) or 1)
				if npc.humanoid.WalkSpeed > 0 and now >= npc.fleeUntil and not npc.following then
					npc.humanoid.WalkSpeed = walkSpeedOf(npc)
				end
				-- Начался дождь — жалуются (особенно без зонта)
				if raining and not wasRaining and out and not npc.controlled and rng:NextNumber() < (npc.hasUmbrellaItem and 0.2 or 0.6) then
					say(npc, pick(Config.Phrases.Rain))
					setMood(npc, "Rain", 4)
				end
			end
		end
		if raining and not wasRaining then
			-- Под дождём бросают дела на улице и идут под крышу
			for _, npc in pairs(npcs) do
				local outsidePoint = npc.point and (npc.point.zone == nil or npc.point.zone == Config.OutdoorZone)
				if npc.alive and not npc.officer and outsidePoint then
					if not npc.hasUmbrellaItem and npc.lock == nil and not npc.controlled then
						npc.abort = true
					end
				end
			end
		end
		wasRaining = raining
	end
end)

-- Новый период дня — жители это замечают
workspace:GetAttributeChangedSignal("Period"):Connect(function()
	local period = currentPeriod()
	local phrases = period and period.Phrases
	if isWeekend() and period and period.Name == "Утро" and Config.Weekend then
		phrases = Config.Weekend.Phrases
	end
	if not phrases then
		return
	end
	for _, npc in pairs(npcs) do
		if npc.alive and not npc.officer and not npc.sleeping and not npc.controlled and not npc.inVehicle and rng:NextNumber() < 0.3 then
			task.delay(rng:NextNumber(0, 6), function()
				say(npc, pick(phrases))
			end)
		end
	end
end)

-- Гром: пугаются те, кто на улице
workspace:GetAttributeChangedSignal("ThunderId"):Connect(function()
	task.wait(0.8)
	for _, npc in pairs(npcs) do
		if npc.alive and not npc.officer and not npc.sleeping and not npc.inVehicle and rng:NextNumber() < 0.3 and outdoors(npc) then
			say(npc, pick(Config.Phrases.Thunder), 1.8)
			setMood(npc, "Scared", 2)
		end
	end
end)

workspace:GetAttributeChangedSignal("Weather"):Connect(function()
	if workspace:GetAttribute("Weather") == "Fog" then
		for _, npc in pairs(npcs) do
			if npc.alive and not npc.officer and not npc.sleeping and rng:NextNumber() < 0.2 then
				say(npc, pick(Config.Phrases.Fog))
			end
		end
	end
end)

---------------------------------------------------------------------
-- Телефон: знакомые жители пишут сообщения
---------------------------------------------------------------------

local function npcByName(name: string)
	for _, npc in pairs(npcs) do
		if npc.name == name and npc.alive then
			return npc
		end
	end
	return nil
end

-- Знакомые игрока (по памяти жителей)
Registry.friendsOf = function(player: Player)
	local list = {}
	for name, known in pairs(memory) do
		local pts = known[player.UserId]
		if pts and pts > 0 then
			local level = friendLevel(pts)
			table.insert(list, { name = name, level = level.Name, icon = level.Icon, points = pts, online = npcByName(name) ~= nil })
		end
	end
	table.sort(list, function(a, b)
		return a.points > b.points
	end)
	return list
end

local chatCooldown = {} -- [player][name] = время
Registry.phoneReply = function(player: Player, name: any, replyIndex: any)
	if type(name) ~= "string" or type(replyIndex) ~= "number" then
		return
	end
	local reply = Config.Phone.Replies[replyIndex]
	local known = memory[name] and memory[name][player.UserId]
	if not reply or not known then
		return
	end
	local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
	task.spawn(function()
		task.wait(rng:NextNumber(0.6, 1.2))
		if phone and player.Parent then
			phone:FireClient(player, "Typing", name)
		end
		task.wait(rng:NextNumber(1.2, 2.6))
		if phone and player.Parent then
			phone:FireClient(player, "Message", { from = name, text = pick(reply.Answers) })
		end
		local now = os.clock()
		chatCooldown[player] = chatCooldown[player] or {}
		if now >= (chatCooldown[player][name] or 0) then
			chatCooldown[player][name] = now + 120
			local npc = npcByName(name)
			if npc then
				addFriendship(npc, player, Config.Phone.FriendPointsPerChat or 1)
			end
		end
	end)
end

-- Иногда кто-то из знакомых пишет сам
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(Config.Phone.MessageEvery.Min, Config.Phone.MessageEvery.Max))
		local phone = ReplicatedStorage:FindFirstChild("PhoneRemote")
		for _, player in Players:GetPlayers() do
			local friends = Registry.friendsOf(player)
			if phone and #friends > 0 and rng:NextNumber() < 0.7 then
				local friend = friends[rng:NextInteger(1, math.min(#friends, 4))]
				phone:FireClient(player, "Typing", friend.name)
				task.delay(rng:NextNumber(1.5, 3), function()
					if player.Parent then
						phone:FireClient(player, "Message", { from = friend.name, text = pick(Config.Phone.Messages) })
					end
				end)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	chatCooldown[player] = nil
end)

-- API для транспорта
Registry.walkTo = function(npc, position: Vector3): boolean
	npc.externalWalking = true
	local ok = walkTo(npc, position)
	npc.externalWalking = false
	return ok
end
Registry.emote = function(npc, name: string, duration: number?)
	if npc.alive then
		npc.anim.emote(name, duration)
	end
end
Registry.sfx = sfx
Registry.standUp = standUp

-- Взять жителя под управление (полиция): он бросает свои дела и ждёт команд
Registry.claim = function(npc, reason: string): boolean
	if not npc.alive or npc.inVehicle or npc.controlled or npc.officer or npc.lock ~= nil or npc.following or npc.talkingTo then
		return false
	end
	npc.controlled = reason
	stopMoving(npc)
	task.wait(0.3)
	npc.externalWalking = true
	standUp(npc)
	npc.externalWalking = false
	if npc.prompt then
		npc.prompt.Enabled = false
	end
	return true
end
Registry.release = function(npc)
	npc.controlled = nil
	npc.model:SetAttribute("Cuffed", nil)
	setMood(npc, nil)
	npc.abort = true
	if npc.prompt and npc.alive then
		npc.prompt.Enabled = true
	end
end
-- Найти жителя: из зоны zone или рядом с точкой
Registry.findResident = function(zone: string?, near: Vector3, radius: number)
	local best, bestDist = nil, math.huge
	for _, npc in pairs(npcs) do
		if npc.alive and not npc.officer and not npc.controlled and not npc.inVehicle and npc.lock == nil
			and not npc.following and not npc.talkingTo and not npc.job and not npc.route then
			local dist = (npc.hrp.Position - near).Magnitude
			local inZone = zone ~= nil and (npc.homeZone == zone or npc.zone == zone)
			local score = inZone and dist or dist + 1000
			if (inZone or dist < radius) and score < bestDist then
				best, bestDist = npc, score
			end
		end
	end
	return best
end
Registry.say = say
Registry.toast = toast
Registry.addCoins = addCoins
Registry.getCoins = getCoins
Registry.addFriendship = addFriendship
Registry.setMood = setMood
Registry.setPose = setPose
Registry.face = face
Registry.spawnCustom = function(cframe: CFrame, options)
	options = options or {}
	options.custom = true
	options.cframe = cframe
	return createNPC(nil, options)
end

-- Расселяем жителей по точкам появления
task.wait(1)
local spawnList = {}
for _, d in spawnsFolder:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(spawnList, d)
	end
end
if #spawnList == 0 then
	warn("[NPC] В папке Spawns нет ни одной точки появления")
end
for _, spawnPart in spawnList do
	local count = spawnPart:GetAttribute("Count") or Config.DefaultSpawnCount
	for _ = 1, count do
		task.spawn(spawnNPC, spawnPart)
		task.wait(0.3)
	end
end
