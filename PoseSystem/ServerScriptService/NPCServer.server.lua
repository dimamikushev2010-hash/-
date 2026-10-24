-- Script: ServerScriptService > NPCServer
-- Жители города (NPC):
--   * появляются на точках Spawns, «просыпаются» (лёжа → на колени → встают);
--   * ходят по точкам Points с поиском пути: по дому, потом на улицу, в другие дома;
--   * в точках занимаются делами: стоят, смотрят в окно, сидят, лежат, танцуют, ждут собеседника;
--   * болтают друг с другом (облачка с текстом и жесты), машут проходящим игрокам;
--   * с ними можно поговорить (кнопка E) и выбрать тему;
--   * получив урон, вскрикивают и убегают; погибнув — возрождаются на своей точке.
-- Анимации — стандартные анимации Roblox (их видят все), сидение/лежание на полу —
-- через систему поз (PoseClient).

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("NPCConfig"))

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

local function registerPoint(part: Instance)
	if not part:IsA("BasePart") or points[part] then
		return
	end
	hideMarker(part)
	local activity = part:GetAttribute("Activity") or (part:IsA("Seat") and "Sit") or "Idle"
	points[part] = {
		part = part,
		activity = activity,
		zone = part:GetAttribute("Zone"),
		occupants = 0,
		capacity = activity == "Talk" and 2 or 1,
	}
end

for _, d in pointsFolder:GetDescendants() do
	registerPoint(d)
end
pointsFolder.DescendantAdded:Connect(registerPoint)
pointsFolder.DescendantRemoving:Connect(function(d)
	points[d] = nil
end)

for _, d in spawnsFolder:GetDescendants() do
	if d:IsA("BasePart") then
		hideMarker(d)
	end
end

---------------------------------------------------------------------
-- Внешность
---------------------------------------------------------------------

local function makeDescription(): HumanoidDescription
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

local npcs = {} -- [model] = npc
local total = 0

local function say(npc, text: string, duration: number?)
	if not npc.alive then
		return
	end
	npc.model:SetAttribute("SayDuration", duration or Config.BubbleTime)
	npc.model:SetAttribute("SayText", text)
	npc.model:SetAttribute("SayId", (npc.model:GetAttribute("SayId") or 0) + 1)
end

local function shouldStop(npc): boolean
	return not npc.alive or npc.abort or npc.lock ~= nil
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
local function standUp(npc)
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
	npc.humanoid.WalkSpeed = npc.speed
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

local function freeForChat(npc, now: number): boolean
	return npc.alive
		and npc.lock == nil
		and now >= npc.chatCooldown
		and npc.model:GetAttribute("Pose") ~= "Lie"
		and not npc.humanoid.Sit
		and now >= npc.fleeUntil
end

local function runConversation(a, b, lines)
	a.lock, b.lock = "chat", "chat"
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
		end
		npc.chatCooldown = now + rng:NextNumber(30, 60)
		npc.abort = true -- после разговора выбираем новое дело
	end
end

local function tryStartChat(npc, now: number)
	if now < npc.nextSocialCheck then
		return
	end
	npc.nextSocialCheck = now + 0.6

	-- Помахать проходящему игроку
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - npc.hrp.Position).Magnitude < Config.GreetDistance then
			if now >= (npc.greeted[player] or 0) then
				npc.greeted[player] = now + 45
				if rng:NextNumber() < Config.GreetPlayerChance then
					task.spawn(function()
						npc.anim.emote("Wave")
						say(npc, pick(Config.Phrases.Greet), 2.5)
					end)
				end
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
	end
	return false
end

---------------------------------------------------------------------
-- Выбор дела
---------------------------------------------------------------------

local function choosePoint(npc)
	local r = rng:NextNumber()
	local mode = (r < Config.SameZoneChance and "same")
		or (r < Config.SameZoneChance + Config.OutdoorChance and "outdoor")
		or "any"

	local candidates, totalWeight = {}, 0
	local function collect(filter)
		table.clear(candidates)
		totalWeight = 0
		for _, point in pairs(points) do
			if point ~= npc.point and point.occupants < point.capacity and point.part.Parent
				and not (point.part:IsA("Seat") and point.part.Occupant) and filter(point) then
				-- Ближние точки чуть вероятнее
				local dist = (point.part.Position - npc.hrp.Position).Magnitude
				local weight = 1 / (1 + dist / 80)
				table.insert(candidates, { point = point, weight = weight })
				totalWeight += weight
			end
		end
	end

	if mode == "same" then
		collect(function(p)
			return p.zone == npc.zone
		end)
	elseif mode == "outdoor" then
		collect(function(p)
			return p.zone == nil or p.zone == Config.OutdoorZone
		end)
	end
	if #candidates == 0 then
		collect(function()
			return true
		end)
	end
	if #candidates == 0 then
		return nil
	end

	local roll = rng:NextNumber() * totalWeight
	for _, c in candidates do
		roll -= c.weight
		if roll <= 0 then
			return c.point
		end
	end
	return candidates[#candidates].point
end

local function doActivity(npc, point)
	local part = point.part
	local activity = point.activity
	local range = Config.ActivityTime[activity] or Config.ActivityTime.Idle
	local duration = randomIn(range)

	if activity == "Sit" and part:IsA("Seat") then
		if part.Occupant then
			return
		end
		part:Sit(npc.humanoid)
		pause(npc, duration)
		standUp(npc)
	elseif activity == "Sit" or activity == "Lie" then
		face(npc, part.CFrame.LookVector)
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
		while npc.alive and npc.lock ~= nil do
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
			npc.humanoid.WalkSpeed = Config.RunSpeed
			local target = fleePoint(npc)
			if target then
				walkTo(npc, target.part.Position)
			else
				task.wait(1)
			end
			npc.humanoid.WalkSpeed = npc.speed
			continue
		end

		local point = choosePoint(npc)
		if not point then
			task.wait(2)
			continue
		end
		point.occupants += 1
		npc.point = point
		local arrived = walkTo(npc, point.part.Position)
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

local function startPlayerTalk(npc, player: Player)
	if not npc.alive or npc.talkingTo then
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

	npc.lock = "player"
	npc.talkingTo = player
	npc.lastTalk = os.clock()
	npc.prompt.Enabled = false
	stopMoving(npc)

	local greeting = pick(Config.PlayerGreeting)
	local topics = {}
	for i, topic in Config.PlayerTopics do
		topics[i] = topic.Text
	end
	dialogRemote:FireClient(player, "Open", npc.model, npc.name, greeting, topics)

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

dialogRemote.OnServerEvent:Connect(function(player: Player, action: any, model: any, index: any)
	local npc = typeof(model) == "Instance" and npcs[model] or nil
	if not npc or npc.talkingTo ~= player then
		return
	end
	if action == "Bye" then
		endPlayerTalk(npc, true)
	elseif action == "Ask" and type(index) == "number" then
		local topic = Config.PlayerTopics[index]
		if not topic or os.clock() - (npc.lastAsk or 0) < 0.6 then
			return
		end
		npc.lastAsk = os.clock()
		npc.lastTalk = os.clock()
		local answer = pick(topic.Answers)
		say(npc, answer)
		if topic.Emote == "Dance" then
			npc.anim.emote(rng:NextNumber() < 0.5 and "Dance" or "Dance2", 4)
		elseif topic.Emote then
			npc.anim.emote(topic.Emote)
		end
		dialogRemote:FireClient(player, "Answer", model, answer)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, npc in pairs(npcs) do
		if npc.talkingTo == player then
			endPlayerTalk(npc, false)
		end
		npc.greeted[player] = nil
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
	npc.anim.stopAll()
	task.delay(Config.CorpseTime, function()
		npcs[npc.model] = nil
		total -= 1
		npc.model:Destroy()
	end)
	task.delay(Config.RespawnTime, function()
		if npc.spawn.Parent then
			spawnNPC(npc.spawn)
		end
	end)
end

function spawnNPC(spawnPart: BasePart)
	if total >= Config.MaxNPCs then
		return
	end
	total += 1

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(makeDescription(), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		total -= 1
		warn("[NPC] Не удалось создать модель жителя:", model)
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		total -= 1
		model:Destroy()
		return
	end
	local oldAnimate = model:FindFirstChild("Animate")
	if oldAnimate then
		oldAnimate:Destroy() -- анимации ведёт сервер
	end

	local name = pick(Config.FirstNames)
	model.Name = name
	humanoid.DisplayName = name
	humanoid.NameDisplayDistance = 40
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	local speed = randomIn(Config.WalkSpeed)
	humanoid.WalkSpeed = speed

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = COLLISION_GROUP
		end
	end

	-- Ставим на точку появления
	local offset = (rng:NextNumber() - 0.5) * 2
	local top = spawnPart.Position + Vector3.new(offset, spawnPart.Size.Y / 2, offset)
	local look = flat(spawnPart.CFrame.LookVector)
	local height = humanoid.HipHeight + hrp.Size.Y / 2 + 0.1
	model:PivotTo(CFrame.lookAt(top + Vector3.new(0, height, 0), top + Vector3.new(0, height, 0) + (look.Magnitude > 0 and look or Vector3.new(0, 0, -1))))
	model:SetAttribute("Pose", "Lie")
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
		zone = spawnPart:GetAttribute("Zone"),
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

	prompt.Triggered:Connect(function(player)
		startPlayerTalk(npc, player)
	end)

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth and health > 0 then
			local now = os.clock()
			if now - npc.lastHurt > 2 then
				npc.lastHurt = now
				say(npc, pick(Config.Phrases.Hurt), 2)
			end
			npc.fleeUntil = now + 6
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

	task.spawn(brain, npc)
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
