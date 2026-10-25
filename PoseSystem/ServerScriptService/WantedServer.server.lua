-- Script: ServerScriptService > WantedServer
-- Розыск и правосудие (настройки — ReplicatedStorage > WeaponConfig.Wanted / Justice).
--
-- Как в жизни: полиция НЕ знает, где ты. Узнаёт только от свидетелей или когда видит сама.
--   * Залез в чужой дом — хозяин кричит и звонит в 911.
--   * Достал оружие — жителям страшно: держат дистанцию, кто-то убегает и звонит.
--   * Целишься — пугливые кричат, бегут в укрытие, звонят.
--   * Стреляешь — паника, полиция едет быстрее. Убил — огонь на поражение.
--   * ⭐ 1–5: от звёзд зависит, сколько машин приедет. Полиция едет туда, где тебя видели, и прочёсывает район.
--   * Не видели долго — ушёл от погони. Стрелял в полицию — отстреливаются.
-- Арест: наручники → машина → отдел (фото, отпечатки, допрос) → КПЗ → суд → тюрьма; оружие и часть денег конфискуют.
--
-- Метки (необязательно, без них этапы проходят в участке):
--   TrafficSystem > PoliceStation: Mugshot, Fingerprint, Interview, Holding
--   Workspace > JusticeSystem > Court: Judge, Dock, CourtDoor
--   Workspace > JusticeSystem > Prison: PrisonDoor, PrisonCell (1 и больше), PrisonExit

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
if not Config.Enabled then
	return
end
local W = Config.Wanted
local J = Config.Justice
local L = Config.Lines
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local Registry = require(script.Parent:WaitForChild("NPCRegistry"))
local AbilityRegistry = require(ServerScriptService:WaitForChild("AbilityRegistry"))

local rng = Random.new()
local remote = Instance.new("RemoteEvent")
remote.Name = "WantedRemote"
remote.Parent = ReplicatedStorage

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
local function now(): number
	return os.clock()
end
local function serverNow(): number
	return workspace:GetServerTimeNow()
end
local function say(npc, text: string, seconds: number?)
	if Registry.say and npc and npc.alive then
		Registry.say(npc, text, seconds)
	end
end
local function toast(player: Player, text: string)
	if Registry.toast then
		Registry.toast(player, text)
	end
end
local function event(text: string)
	if Registry.debugEvent then
		Registry.debugEvent(text)
	end
end

-- Набор полиции из TrafficServer
local kit = nil
task.spawn(function()
	local t = os.clock()
	while not Registry.policeKit and os.clock() - t < 20 do
		task.wait(0.5)
	end
	kit = Registry.policeKit
	if not kit then
		warn("[Wanted] Нет транспорта (TrafficServer) — полиция не сможет выезжать на розыск")
	end
end)

---------------------------------------------------------------------
-- Видимость
---------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function lineOfSight(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(from, to - from, rayParams)
	return hit == nil
end

-- Видит ли житель/офицер персонажа (дистанция, обзор, прямая видимость, невидимость)
local function sees(npc, character: Model, range: number, fov: number?): boolean
	if not npc.alive then
		return false
	end
	local head = npc.model:FindFirstChild("Head")
	local target = character:FindFirstChild("Head")
	if not head or not target then
		return false
	end
	if character:GetAttribute("Invisible") == true then
		return false
	end
	local delta = target.Position - head.Position
	if delta.Magnitude > range then
		return false
	end
	if fov then
		local look = npc.hrp.CFrame.LookVector
		if flat(delta).Magnitude > 2 and flat(look):Dot(flat(delta).Unit) < fov then
			return false
		end
	end
	return lineOfSight(head.Position, target.Position, { npc.model, character })
end

local function residents()
	local list = {}
	for _, npc in pairs(Registry.npcs) do
		if npc.alive and not npc.officer and not npc.inVehicle then
			table.insert(list, npc)
		end
	end
	return list
end

local function officers()
	local list = {}
	for model, npc in pairs(Registry.npcs) do
		if npc.alive and model:GetAttribute("Police") == true then
			table.insert(list, npc)
		end
	end
	return list
end

---------------------------------------------------------------------
-- Состояние игроков
---------------------------------------------------------------------

local states = {} -- [player] = состояние
local function st(player: Player)
	local s = states[player]
	if not s then
		s = {
			stars = 0,
			mode = "free", -- free / wanted / arrested / booking / holding / court / prison
			units = {},
			lastSeen = 0,
			reportTime = 0,
			knownPos = nil,
			reportPos = nil,
			kills = 0,
			policeKills = 0,
			injuries = 0,
			attackedPolice = false,
			lastShot = 0,
			calls = 0,
			lastCall = {},
			trespass = 0,
			surrender = 0,
		}
		states[player] = s
	end
	return s
end

local function publish(player: Player)
	local s = st(player)
	player:SetAttribute("WantedStars", s.stars)
	player:SetAttribute("WantedMode", s.mode)
	player:SetAttribute("WantedSeen", now() - s.lastSeen < 2)
	local evade = W.EvadeTime + W.EvadePerStar * s.stars
	local ref = math.max(s.lastSeen, s.reportTime)
	player:SetAttribute("WantedEvadeLeft", s.stars > 0 and math.max(0, evade - (now() - ref)) or nil)
	player:SetAttribute("WantedEvadeTotal", evade)
end

local function setStars(player: Player, n: number, reason: string?)
	local s = st(player)
	n = math.clamp(n, 0, 5)
	if n > s.stars then
		event(string.format("⭐ %s: розыск %d★ (%s)", player.Name, n, reason or ""))
		remote:FireClient(player, "Stars", { stars = n, reason = reason })
	end
	s.stars = n
	if n > 0 and s.mode == "free" then
		s.mode = "wanted"
	end
	publish(player)
end

---------------------------------------------------------------------
-- 📞 Звонки в 911 и выезды
---------------------------------------------------------------------

local ensureUnits -- объявлена ниже

local function report(player: Player, level: number, pos: Vector3, exact: boolean?, why: string?)
	local s = st(player)
	if s.mode ~= "free" and s.mode ~= "wanted" then
		return
	end
	local noise = exact and 0 or W.ReportNoise
	local offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * noise
	s.reportPos = pos + offset
	s.reportTime = now()
	player:SetAttribute("PoliceSearch", s.reportPos)
	local before = s.stars
	if level > s.stars then
		setStars(player, level, why)
	else
		publish(player)
	end
	if before == 0 then
		remote:FireClient(player, "Called", { why = why })
	end
	local delay = W.DispatchDelay[math.clamp(s.stars, 1, 5)] or 10
	task.delay(delay, function()
		if ensureUnits then
			ensureUnits(player)
		end
	end)
end

-- Житель звонит (если его остановят — звонка не будет)
local function witnessCall(npc, player: Player, level: number, pos: Vector3, why: string)
	local s = st(player)
	if s.calls >= 2 or now() - (s.lastCall[level] or 0) < 12 then
		return
	end
	s.calls += 1
	s.lastCall[level] = now()
	task.spawn(function()
		local done = Registry.phoneCall and Registry.phoneCall(npc, pick(L.Call), W.CallTime) or true
		s.calls -= 1
		if done and player.Parent then
			event(string.format("📞 %s звонит в 911: %s", npc.name, why))
			report(player, level, pos, false, why)
		end
	end)
end

-- Полицейский увидел сам — сразу и точно
local function policeWitness(player: Player, level: number, pos: Vector3, why: string)
	local character = player.Character
	if not character then
		return false
	end
	for _, o in officers() do
		if sees(o, character, W.PoliceSight, -0.2) then
			local s = st(player)
			s.lastSeen = now()
			s.knownPos = pos
			report(player, level, pos, true, why)
			say(o, pick(L.PoliceSee), 2)
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- 😱 Реакции жителей
---------------------------------------------------------------------

local reacted = {} -- [npc] = { [вид] = время }
local function canReact(npc, kind: string, cooldown: number): boolean
	local r = reacted[npc]
	if not r then
		r = {}
		reacted[npc] = r
	end
	if now() - (r[kind] or -999) < cooldown then
		return false
	end
	r[kind] = now()
	return true
end

local function bravery(npc): number
	return npc.model:GetAttribute("Bravery") or 0.5
end

local function scream(npc)
	if Registry.sfx then
		Registry.sfx(npc, "Scream")
	end
end

-- Увидел оружие
local function onWeaponSeen(npc, player: Player, from: Vector3)
	if not canReact(npc, "WeaponSeen", 30) then
		return
	end
	local fear = 1 - bravery(npc)
	if rng:NextNumber() < 0.7 then
		say(npc, pick(L.SeeWeapon), 2.5)
	end
	if rng:NextNumber() < W.FleeChance.WeaponSeen * (0.5 + fear) then
		Registry.scare(npc, from, "run", 10)
	else
		Registry.scare(npc, from, "distance", 14, W.KeepDistance)
	end
	if rng:NextNumber() < W.CallChance.WeaponSeen * (0.5 + fear) then
		task.delay(1.5, witnessCall, npc, player, W.WeaponSeen, from, "человек с оружием")
	end
end

-- В него целятся
local function onAimed(npc, player: Player, from: Vector3)
	if not canReact(npc, "Aiming", 15) then
		return
	end
	local fear = 1 - bravery(npc)
	if fear > 0.3 then
		say(npc, pick(L.Aimed), 2.5)
		scream(npc)
	end
	if rng:NextNumber() < W.FleeChance.Aiming * (0.5 + fear) then
		Registry.scare(npc, from, "cover", 22)
	else
		Registry.scare(npc, from, "distance", 12, W.KeepDistance + 6)
	end
	if rng:NextNumber() < W.CallChance.Aiming then
		task.delay(2, witnessCall, npc, player, W.Aiming, from, "в людей целятся из оружия")
	end
end

-- Слышал выстрелы
local function onShots(npc, player: Player, from: Vector3, seen: boolean)
	if not canReact(npc, "Shots", 10) then
		return
	end
	if rng:NextNumber() < 0.5 then
		say(npc, pick(L.Shots), 2)
	end
	if rng:NextNumber() < 0.6 then
		scream(npc)
	end
	Registry.scare(npc, from, rng:NextNumber() < W.FleeChance.Shots and "cover" or "run", 25)
	if rng:NextNumber() < W.CallChance.Shots then
		task.delay(2.5, witnessCall, npc, player, W.Shots, from, seen and "стрельба, видел стрелка" or "слышны выстрелы")
	end
end

-- Видел убийство / тело
local function onBody(npc, player: Player, from: Vector3, bodyPos: Vector3)
	if not canReact(npc, "Body", 20) then
		return
	end
	say(npc, pick(L.Body), 3)
	scream(npc)
	Registry.scare(npc, from, "cover", 30)
	if rng:NextNumber() < W.CallChance.Murder then
		task.delay(2, witnessCall, npc, player, W.Murder, from, "убийство")
	end
	local _ = bodyPos
end

-- Выстрел игрока (от WeaponServer)
Registry.gunshot = function(player: Player, pos: Vector3)
	local s = st(player)
	s.lastShot = now()
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local from = root and root.Position or pos
	for _, npc in residents() do
		local d = (npc.hrp.Position - pos).Magnitude
		if d < W.HearShots then
			local seen = d < W.SightRange * 1.5 and sees(npc, character, W.SightRange * 1.5, nil)
			onShots(npc, player, from, seen)
		end
	end
	-- Полицейские слышат выстрелы и едут на звук
	for _, o in officers() do
		if (o.hrp.Position - pos).Magnitude < W.HearShots then
			if not policeWitness(player, W.Shots, pos, "стрельба рядом с полицией") then
				report(player, W.Shots, pos + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8)), false, "полиция слышала выстрелы")
			end
			break
		end
	end
end

-- Преступление (от WeaponServer): Injury / Murder / PoliceAttack / PoliceKill
Registry.wantedCrime = function(player: Player, kind: string, pos: Vector3, victim: Model?)
	local s = st(player)
	if kind == "Murder" then
		s.kills += 1
	elseif kind == "PoliceKill" then
		s.policeKills += 1
		s.kills += 1
		s.attackedPolice = true
	elseif kind == "PoliceAttack" then
		s.attackedPolice = true
	elseif kind == "Injury" then
		s.injuries += 1
	end
	local level = W[kind] or 2
	if s.kills >= 4 then
		level = math.max(level, W.ManyKills)
	end
	local character = player.Character
	if not character then
		return
	end
	local from = character:FindFirstChild("HumanoidRootPart") and character.HumanoidRootPart.Position or pos
	-- Нападение на полицию — сразу и точно; полиция видела сама — тоже
	if kind == "PoliceAttack" or kind == "PoliceKill" then
		s.lastSeen = now()
		s.knownPos = from
		report(player, level, from, true, kind == "PoliceKill" and "убит полицейский" or "нападение на полицию")
		return
	end
	if policeWitness(player, level, from, kind == "Murder" and "убийство на глазах полиции" or "стрельба по людям") then
		return
	end
	-- Уже в розыске — звёзды растут, если кто-то видел
	for _, npc in residents() do
		local d = (npc.hrp.Position - pos).Magnitude
		if d < 60 and (sees(npc, character, 60, -0.3) or (victim and npc.model:FindFirstChild("Head") and lineOfSight(npc.model.Head.Position, pos, { npc.model, victim, character }))) then
			if kind == "Murder" then
				onBody(npc, player, from, pos)
			else
				onShots(npc, player, from, true)
			end
		end
	end
end

-- Оружие на виду и прицел: проверяем несколько раз в секунду
local zones = nil -- дома: { zone, min, max }
local function homeZones()
	if zones then
		return zones
	end
	zones = {}
	local root = workspace:FindFirstChild(NPCConfig.FolderName)
	if not root then
		return zones
	end
	local boxes = {}
	for _, folderName in { "Points", "Spawns" } do
		local f = root:FindFirstChild(folderName)
		for _, p in f and f:GetDescendants() or {} do
			if p:IsA("BasePart") then
				local z = p:GetAttribute("Zone")
				if type(z) == "string" and z ~= NPCConfig.OutdoorZone then
					local b = boxes[z] or { min = p.Position, max = p.Position }
					b.min = b.min:Min(p.Position)
					b.max = b.max:Max(p.Position)
					boxes[z] = b
				end
			end
		end
	end
	for z, b in pairs(boxes) do
		table.insert(zones, { zone = z, min = b.min - Vector3.new(3, 3, 3), max = b.max + Vector3.new(3, 8, 3) })
	end
	return zones
end

local function zoneAt(pos: Vector3): string?
	for _, z in homeZones() do
		if pos.X > z.min.X and pos.X < z.max.X and pos.Y > z.min.Y and pos.Y < z.max.Y and pos.Z > z.min.Z and pos.Z < z.max.Z then
			return z.zone
		end
	end
	return nil
end

task.spawn(function()
	while true do
		task.wait(0.3)
		if not Registry.scare then
			continue
		end
		for _, player in Players:GetPlayers() do
			local s = st(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or (s.mode ~= "free" and s.mode ~= "wanted") then
				continue
			end
			local armed = character:GetAttribute("AimGun") == true
			local aimDir = character:GetAttribute("AimDir")
			local head = character:FindFirstChild("Head")
			if armed then
				for _, npc in residents() do
					local d = (npc.hrp.Position - root.Position).Magnitude
					if d < W.SightRange and sees(npc, character, W.SightRange, -0.1) then
						onWeaponSeen(npc, player, root.Position)
					end
					-- Прицел на жителя: луч из головы по направлению взгляда
					if typeof(aimDir) == "Vector3" and head and d < 80 and npc.model:FindFirstChild("Head") then
						local to = npc.model.Head.Position - head.Position
						if to.Unit:Dot(aimDir) > math.cos(math.rad(character:GetAttribute("Aiming") and 5 or 8))
							and lineOfSight(head.Position, npc.model.Head.Position, { character, npc.model }) then
							onAimed(npc, player, root.Position)
						end
					end
				end
				-- Полицейский видит оружие
				if s.stars == 0 then
					for _, o in officers() do
						if sees(o, character, W.PoliceSight * 0.6, -0.2) and canReact(o, "SeeArmed", 20) then
							say(o, "Эй! Уберите оружие!", 2.5)
							report(player, W.WeaponSeen, root.Position, true, "вооружённый человек")
							s.lastSeen = now()
							s.knownPos = root.Position
							break
						end
					end
				end
			end
			-- Проникновение в чужой дом
			local zone = zoneAt(root.Position)
			if zone then
				local owner = nil
				for _, npc in residents() do
					if npc.homeZone == zone and npc.zone == zone and sees(npc, character, 30, -0.4) then
						owner = npc
						break
					end
				end
				if owner then
					s.trespass += 0.3
					if s.trespass >= W.TrespassGrace and canReact(owner, "Trespass", 60) then
						say(owner, pick(L.Trespass), 3)
						scream(owner)
						Registry.scare(owner, root.Position, "distance", 12, 12)
						witnessCall(owner, player, W.Trespass, root.Position, "проникновение в дом")
					end
				else
					s.trespass = math.max(0, s.trespass - 0.3)
				end
			else
				s.trespass = 0
			end
		end
	end
end)

---------------------------------------------------------------------
-- 🚓 Наряды на розыск
---------------------------------------------------------------------

local arrest -- объявлена ниже
local damagePlayer -- объявлена ниже

local function attachGun(officer)
	if officer.model:FindFirstChild("PoliceGun") or not Registry.buildGun then
		return
	end
	local hand = officer.model:FindFirstChild("RightHand") or officer.model:FindFirstChild("Right Arm")
	if not hand then
		return
	end
	local gun = Registry.buildGun("Pistol")
	gun:PivotTo(hand.CFrame * CFrame.new(0, -0.3, -0.35) * CFrame.Angles(math.rad(-90), 0, 0))
	for _, p in gun:GetDescendants() do
		if p:IsA("BasePart") then
			p:SetAttribute("BaseT", p.Transparency)
			p.Transparency = 1 -- в кобуре, пока не достал
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = gun.PrimaryPart
	w.Parent = gun.PrimaryPart
	gun.Parent = officer.model
end

local function drawGun(officer, on: boolean)
	if officer.model:GetAttribute("AimGun") == on then
		return
	end
	officer.model:SetAttribute("AimGun", on)
	local gun = officer.model:FindFirstChild("PoliceGun")
	if gun then
		for _, p in gun:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = on and (p:GetAttribute("BaseT") or 0) or 1
			end
		end
	end
end

local function faceTo(npc, pos: Vector3)
	local hrp = npc.hrp
	local d = flat(pos - hrp.Position)
	if d.Magnitude > 0.1 then
		npc.humanoid.AutoRotate = false
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + d.Unit)
	end
end

-- Полицейский стреляет
local function policeShoot(officer, player: Player)
	local character = player.Character
	local target = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart"))
	local head = officer.model:FindFirstChild("Head")
	if not target or not head or not Registry.fireShot then
		return
	end
	local gun = officer.model:FindFirstChild("PoliceGun")
	local muzzle = gun and gun:FindFirstChild("Muzzle", true)
	local origin = muzzle and muzzle.WorldPosition or (head.Position + officer.hrp.CFrame.LookVector * 1.5)
	local dist = (target.Position - origin).Magnitude
	local speed = target.AssemblyLinearVelocity.Magnitude
	local chance = Config.PoliceAccuracy * math.clamp(20 / math.max(dist, 1), 0.25, 1.3) * (speed > 12 and 0.6 or 1)
	local aim = target.Position
	if rng:NextNumber() > chance then
		aim += Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 1), rng:NextNumber(-1, 1)).Unit * rng:NextNumber(2.5, 5)
	end
	local _, model, humanoid = Registry.fireShot(origin, aim - origin, 260, { officer.model }, "Pistol", officer.model)
	if humanoid and model == character then
		damagePlayer(player, Config.PoliceDamage)
	elseif humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(Config.PoliceDamage)
	end
end

-- Точка дороги для появления наряда: подальше от игрока, чтобы машина ехала по городу
local function spawnNode(target: Vector3): string?
	local good, any = {}, {}
	for name, n in pairs(kit.nodes) do
		local d = (n.pos - target).Magnitude
		table.insert(any, { name = name, d = d })
		if d > 90 and d < 240 then
			table.insert(good, name)
		end
	end
	if #good > 0 then
		return pick(good)
	end
	table.sort(any, function(a, b)
		return a.d > b.d
	end)
	return any[1] and any[1].name or nil
end

local function unitAlive(unit): boolean
	return unit.car and unit.car.model and unit.car.model.Parent ~= nil
end

local function dismissUnit(unit)
	unit.state = "leave"
end

local function cleanupUnit(unit)
	for _, o in unit.officers do
		if o.alive and o.inVehicle and kit then
			o.inVehicle = nil
		end
		if o.model and o.model.Parent then
			o.alive = false
			o.model:Destroy()
		end
	end
	unit.officers = {}
	if unit.car and kit then
		kit.removeCar(unit.car)
	end
	unit.car = nil
end

local officerLoop -- объявлена ниже

local function unitLoop(unit)
	local player = unit.player
	local s = st(player)
	while player.Parent and unitAlive(unit) and unit.state ~= "leave" and unit.state ~= "arrest" do
		if unit.state == "drive" then
			local dest = (now() - s.lastSeen < 6 and s.knownPos) or s.reportPos or s.knownPos
			if not dest then
				break
			end
			unit.car.model:SetAttribute("Siren", true)
			kit.drive(unit.car, { node = kit.nearestNode(dest), curb = 4 })
			if unit.state ~= "drive" then
				break
			end
			-- Выходим и ищем
			for _, o in unit.officers do
				if o.alive and o.inVehicle then
					task.spawn(kit.unseatNPC, o)
				end
			end
			task.wait(1.4)
			for _, o in unit.officers do
				if o.alive then
					if rng:NextNumber() < 0.6 then
						say(o, pick(L.PoliceArrive), 2.5)
					end
					task.spawn(officerLoop, unit, o)
				end
			end
			unit.searchCenter = dest
			unit.state = "foot"
		elseif unit.state == "foot" then
			task.wait(1)
			-- Подозреваемого видели далеко отсюда — снова в машину
			local center = (now() - s.lastSeen < 10 and s.knownPos) or s.reportPos
			local near = false
			for _, o in unit.officers do
				if o.alive and center and (o.hrp.Position - center).Magnitude < 110 then
					near = true
				end
			end
			if center and not near then
				unit.state = "board"
				local people = {}
				for i, o in unit.officers do
					if o.alive then
						table.insert(people, { npc = o, seat = i == 1 and unit.car.driverSeat or unit.car.seats[i - 1] })
					end
				end
				kit.boardAll(unit.car, people)
				if unit.state == "board" then
					unit.state = "drive"
				end
			end
			-- Все офицеры погибли
			local any = false
			for _, o in unit.officers do
				any = any or o.alive
			end
			if not any then
				break
			end
		else
			task.wait(0.5)
		end
	end
	if unit.state == "arrest" then
		return -- машиной распоряжается арест
	end
	-- Отбой: садятся и уезжают
	if unitAlive(unit) then
		unit.state = "leave"
		unit.car.model:SetAttribute("Siren", false)
		local people = {}
		for i, o in unit.officers do
			if o.alive and not o.inVehicle then
				table.insert(people, { npc = o, seat = i == 1 and unit.car.driverSeat or unit.car.seats[i - 1] })
			end
		end
		if #people > 0 then
			kit.boardAll(unit.car, people)
		end
		local far = spawnNode(unit.car.pos)
		if far then
			kit.drive(unit.car, { node = far })
		end
	end
	cleanupUnit(unit)
	local i = table.find(s.units, unit)
	if i then
		table.remove(s.units, i)
	end
end

function officerLoop(unit, officer)
	local player = unit.player
	local s = st(player)
	officer.humanoid.WalkSpeed = 16
	local walking = false
	local nextShot = 0
	local lastShout = 0
	local calm = 0
	while officer.alive and unit.state == "foot" and player.Parent and s.mode == "wanted" do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local t = now()
		if root and humanoid and humanoid.Health > 0 and sees(officer, character, W.PoliceSight, -0.35) then
			s.lastSeen = t
			s.knownPos = root.Position
			player:SetAttribute("PoliceSearch", root.Position)
			if walking then
				officer.abort = true
				walking = false
			end
			local dist = (root.Position - officer.hrp.Position).Magnitude
			local hostile = s.stars >= W.ShootOnSight or s.attackedPolice
			local armed = character:GetAttribute("AimGun") == true
			if hostile then
				drawGun(officer, true)
				faceTo(officer, root.Position)
				if dist > 30 then
					officer.humanoid.WalkSpeed = 18
					officer.humanoid:MoveTo(root.Position)
				elseif dist < 10 then
					officer.humanoid:MoveTo(officer.hrp.Position - flat(root.Position - officer.hrp.Position).Unit * 4)
				else
					officer.humanoid:MoveTo(officer.hrp.Position)
				end
				if t > lastShout + 6 then
					lastShout = t
					say(officer, pick(L.PoliceShoot), 1.5)
				end
				if t >= nextShot then
					nextShot = t + rng:NextNumber(Config.PoliceFireInterval.Min, Config.PoliceFireInterval.Max)
					policeShoot(officer, player)
				end
			else
				drawGun(officer, armed)
				if t > lastShout + 5 then
					lastShout = t
					say(officer, dist < 15 and "Руки вверх! Не двигаться!" or pick(L.PoliceSee), 2)
				end
				if dist > W.ArrestDistance then
					officer.humanoid.WalkSpeed = 18
					officer.humanoid:MoveTo(root.Position - flat(root.Position - officer.hrp.Position).Unit * 2.5)
					calm = 0
				else
					officer.humanoid:MoveTo(officer.hrp.Position)
					faceTo(officer, root.Position)
					local quiet = t - s.lastShot > 3 and root.AssemblyLinearVelocity.Magnitude < 5
					calm = quiet and calm + 0.25 or 0
					if character:GetAttribute("HandsUp") or calm >= W.SurrenderTime then
						arrest(player, unit, officer)
						return
					end
				end
			end
		else
			drawGun(officer, s.stars >= W.ShootOnSight and t - s.lastSeen < 15)
			officer.humanoid.AutoRotate = true
			if not walking then
				-- Идём туда, где видели, и прочёсываем район
				local center = (t - s.lastSeen < 20 and s.knownPos) or s.reportPos or unit.searchCenter
				if center then
					walking = true
					officer.abort = false
					local r = (t - s.lastSeen < 5) and 4 or W.SearchRadius
					local goal = center + Vector3.new(rng:NextNumber(-r, r), 0, rng:NextNumber(-r, r))
					task.spawn(function()
						officer.humanoid.WalkSpeed = (t - s.lastSeen < 10) and 16 or 10
						if Registry.walkTo then
							Registry.walkTo(officer, goal)
						end
						task.wait(rng:NextNumber(1, 3))
						walking = false
					end)
				end
			end
		end
		task.wait(0.25)
	end
	officer.abort = true
	drawGun(officer, false)
	officer.humanoid.AutoRotate = true
end

local function spawnUnit(player: Player)
	local s = st(player)
	local target = s.reportPos or s.knownPos
	if not kit or not target then
		return
	end
	local node = spawnNode(target)
	if not node then
		return
	end
	local dir = flat(target - kit.nodes[node].pos)
	local car = kit.spawnPoliceAt(node, dir)
	if not car then
		return
	end
	local unit = { car = car, officers = {}, player = player, state = "spawn" }
	table.insert(s.units, unit)
	for i = 1, VehicleConfig.PoliceOfficersPerCar or 2 do
		local seat = i == 1 and car.driverSeat or car.seats[i - 1]
		local at = CFrame.new(kit.doorSide(car, seat or car.driverSeat) + Vector3.new(0, 3, 0))
		local officer = kit.spawnOfficer(at)
		if officer then
			attachGun(officer)
			table.insert(unit.officers, officer)
			if seat then
				task.spawn(kit.seatNPC, officer, car, seat)
			end
		end
	end
	task.wait(1)
	event(string.format("🚓 Наряд на розыск %s (%d★)", player.Name, s.stars))
	unit.state = "drive"
	task.spawn(unitLoop, unit)
end

function ensureUnits(player: Player)
	local s = st(player)
	if s.mode ~= "wanted" or s.stars <= 0 or not kit then
		return
	end
	local need = W.Units[math.clamp(s.stars, 1, 5)] or 1
	local active = 0
	for _, u in s.units do
		if u.state ~= "leave" then
			active += 1
		end
	end
	for _ = active + 1, need do
		task.spawn(spawnUnit, player)
		task.wait(0.5)
	end
end

local function clearWanted(player: Player, why: string?)
	local s = st(player)
	for _, u in s.units do
		if u.state ~= "arrest" then
			dismissUnit(u)
		end
	end
	if s.stars > 0 and why then
		event(string.format("✅ %s: розыск снят (%s)", player.Name, why))
	end
	s.stars = 0
	s.kills, s.policeKills, s.injuries = 0, 0, 0
	s.attackedPolice = false
	s.knownPos, s.reportPos = nil, nil
	s.trespass = 0
	if s.mode == "wanted" then
		s.mode = "free"
	end
	player:SetAttribute("PoliceSearch", nil)
	publish(player)
end
Registry.clearWanted = clearWanted

-- Ушёл от погони
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local s = st(player)
			if s.mode == "wanted" then
				local limit = W.EvadeTime + W.EvadePerStar * s.stars
				local ref = math.max(s.lastSeen, s.reportTime)
				if now() - ref > limit then
					for _, u in s.units do
						for _, o in u.officers do
							if o.alive and rng:NextNumber() < 0.5 then
								say(o, pick(L.PoliceLost), 2.5)
								break
							end
						end
					end
					remote:FireClient(player, "Evaded", {})
					toast(player, "✅ Ты ушёл от погони")
					clearWanted(player, "ушёл от погони")
				end
			end
			publish(player)
		end
	end
end)

---------------------------------------------------------------------
-- Урон игроку от полиции, «потрачено»
---------------------------------------------------------------------

function damagePlayer(player: Player, amount: number)
	local s = st(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if s.mode == "wanted" and humanoid.Health - amount <= W.DownedHealth then
		-- Не убивают — задерживают
		humanoid.Health = W.DownedHealth
		local best, unitBest, bestD = nil, nil, math.huge
		for _, u in s.units do
			for _, o in u.officers do
				if o.alive then
					local d = (o.hrp.Position - humanoid.RootPart.Position).Magnitude
					if d < bestD then
						best, unitBest, bestD = o, u, d
					end
				end
			end
		end
		arrest(player, unitBest, best)
		return
	end
	humanoid:TakeDamage(amount)
end

local function stopAbilities(player: Player, block: boolean)
	local character = player.Character
	if character and block then
		for _, name in { "Flight", "Cube", "Invisibility" } do
			pcall(AbilityRegistry.Stop, name, player, character)
		end
	end
	for _, name in { "InvisibilityConfig", "LaserConfig", "FlightConfig", "CubeConfig" } do
		local m = ReplicatedStorage:FindFirstChild(name)
		if m then
			player:SetAttribute(require(m).CooldownAttribute, block and serverNow() + 100000 or 0)
		end
	end
end

local function coinsOf(player: Player): IntValue?
	return Registry.getCoins and Registry.getCoins(player) or nil
end

---------------------------------------------------------------------
-- ⚖️ Арест и правосудие
---------------------------------------------------------------------

local function marker(path: { string }): BasePart?
	local node: Instance? = workspace
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("BasePart") then
		return node
	end
	return nil
end

local function stationPart(name: string): BasePart?
	return marker({ VehicleConfig.MapFolder, "PoliceStation", name })
end

local function justicePart(group: string, name: string): BasePart?
	local root = workspace:FindFirstChild("JusticeSystem")
	local g = root and root:FindFirstChild(group)
	if not g then
		return nil
	end
	for _, d in g:GetDescendants() do
		if d:IsA("BasePart") and string.find(d.Name, "^" .. name) then
			return d
		end
	end
	return nil
end

local function placeAt(player: Player, part: BasePart?, fallback: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local pos = part and part.Position or fallback
	if not pos then
		return
	end
	local look = part and flat(part.CFrame.LookVector) or Vector3.new(0, 0, -1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local p = pos + Vector3.new(0, 3.2, 0)
	character:PivotTo(CFrame.lookAt(p, p + look))
end

local stageDone = {} -- [player] = данные ответа клиента

local function stage(player: Player, name: string, data, seconds: number, waitClient: boolean?)
	player:SetAttribute("JusticeStage", name)
	player:SetAttribute("JusticeEnd", serverNow() + seconds)
	stageDone[player] = nil
	remote:FireClient(player, "Stage", name, data or {}, seconds)
	local deadline = now() + seconds
	while player.Parent and now() < deadline do
		if waitClient and stageDone[player] then
			break
		end
		task.wait(0.2)
	end
	return stageDone[player]
end

local function fade(player: Player, seconds: number)
	remote:FireClient(player, "Fade", seconds)
	task.wait(0.45)
end

-- Перевезти в полицейской машине (или переход с затемнением, если дорог нет)
local function transport(player: Player, car, dest: Vector3, unit)
	local character = player.Character
	if not kit or not character then
		fade(player, 1.2)
		return
	end
	local temporary = false
	if not car or not car.model or not car.model.Parent then
		local root = character:FindFirstChild("HumanoidRootPart")
		local node = root and kit.nearestNode(root.Position)
		car = node and kit.spawnPoliceAt(node, nil)
		temporary = true
		if not car then
			fade(player, 1.2)
			return
		end
		local driver = kit.spawnOfficer(CFrame.new(kit.doorSide(car, car.driverSeat) + Vector3.new(0, 3, 0)))
		if driver then
			kit.seatNPC(driver, car, car.driverSeat)
			unit = { officers = { driver } }
		end
	end
	local seat = kit.freeSeat(car)
	if seat then
		fade(player, 1.2)
		local side = kit.doorSide(car, seat)
		character:PivotTo(CFrame.new(side + Vector3.new(0, 3.2, 0)))
		task.wait(0.2)
		kit.seatPlayer(player, car, seat)
	end
	car.model:SetAttribute("Siren", false)
	car.state = "busy"
	local ok = kit.drive(car, { node = kit.nearestNode(dest), curb = 4 })
	if seat then
		kit.unseatPlayer(player, car)
	end
	fade(player, 1.2)
	if temporary then
		if unit then
			cleanupUnit({ officers = unit.officers, car = car })
		else
			kit.removeCar(car)
		end
	end
	return ok
end

local judge = nil
local function ensureJudge(): any
	local spot = justicePart("Court", "Judge")
	if not spot or not Registry.spawnCustom then
		return nil
	end
	if judge and judge.alive then
		return judge
	end
	local look = flat(spot.CFrame.LookVector)
	local p = spot.Position + Vector3.new(0, 3, 0)
	judge = Registry.spawnCustom(CFrame.lookAt(p, p + (look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1))), {
		prefix = J.JudgeName,
		shirt = J.JudgeShirt,
		pants = J.JudgeShirt,
		role = "Суд",
	})
	if judge then
		judge.officer = true
		judge.noSocial = true
		if judge.prompt then
			judge.prompt.Enabled = false
		end
		judge.humanoid.WalkSpeed = 0
	end
	return judge
end

local function sentenceOf(s, modifier: number): number
	local base = J.Sentence.Base + J.Sentence.PerStar * s.finalStars + J.Sentence.PerKill * s.finalKills
	return math.floor(math.clamp(base * modifier, J.Sentence.Base, J.Sentence.Max))
end

-- Держим внутри (КПЗ, тюрьма)
local function confine(player: Player, center: Vector3, radius: number, untilFn: () -> boolean)
	task.spawn(function()
		while player.Parent and not untilFn() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - center).Magnitude > radius then
				player.Character:PivotTo(CFrame.new(center + Vector3.new(0, 3.2, 0)))
			end
			task.wait(0.5)
		end
	end)
end

local function setCuffed(player: Player, on: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	character:SetAttribute("Cuffed", on or nil)
	-- Под арестом урон не проходит (иначе можно «сбежать», погибнув)
	local shield = character:FindFirstChild("JusticeShield")
	if not shield then
		shield = Instance.new("ForceField")
		shield.Name = "JusticeShield"
		shield.Visible = false
		shield.Parent = character
	end
	character:SetAttribute("HandsUp", nil)
	character:SetAttribute("AimGun", nil)
	if on then
		humanoid:UnequipTools()
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	else
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
	end
end

local function release(player: Player)
	local s = st(player)
	local exit = justicePart("Prison", "PrisonExit") or justicePart("Prison", "PrisonDoor")
	fade(player, 1.5)
	setCuffed(player, false)
	local shield = player.Character and player.Character:FindFirstChild("JusticeShield")
	if shield then
		shield:Destroy()
	end
	if exit then
		placeAt(player, exit)
	else
		player:LoadCharacter()
	end
	stopAbilities(player, false)
	if Registry.blockWeapons then
		Registry.blockWeapons(player, false)
	end
	local p = Registry.weaponProfile and Registry.weaponProfile(player)
	if p then
		p.jail = nil
		if Registry.weaponSave then
			Registry.weaponSave(player)
		end
	end
	s.mode = "free"
	clearWanted(player, nil)
	player:SetAttribute("JusticeStage", nil)
	remote:FireClient(player, "Stage", "Released", {}, 4)
	event("🔓 " .. player.Name .. " вышел на свободу")
end

-- Срок в тюрьме (и после перезахода)
local function servePrison(player: Player, seconds: number)
	local s = st(player)
	s.mode = "prison"
	publish(player)
	local cells = {}
	local root = workspace:FindFirstChild("JusticeSystem")
	local prison = root and root:FindFirstChild("Prison")
	for _, d in prison and prison:GetDescendants() or {} do
		if d:IsA("BasePart") and string.find(d.Name, "^PrisonCell") then
			table.insert(cells, d)
		end
	end
	local cell = (#cells > 0 and pick(cells)) or (kit and kit.station.cell)
	setCuffed(player, false)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 10 -- в тюрьме ходить можно, медленно
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
	if cell then
		placeAt(player, cell)
	end
	local endAt = now() + seconds
	if cell then
		confine(player, cell.Position, prison and J.PrisonRadius or 10, function()
			return now() >= endAt or s.mode ~= "prison"
		end)
	end
	task.spawn(function()
		while player.Parent and now() < endAt and s.mode == "prison" do
			local p = Registry.weaponProfile and Registry.weaponProfile(player)
			if p then
				p.jail = math.ceil(endAt - now())
			end
			task.wait(5)
		end
	end)
	stage(player, "Prison", { seconds = seconds }, seconds)
	if player.Parent and s.mode == "prison" then
		release(player)
	end
end

local bookingNumber = 1000
local function justiceFlow(player: Player, unit, officer)
	local s = st(player)
	s.finalStars = s.stars
	s.finalKills = s.kills
	bookingNumber += 1
	local number = bookingNumber
	event(string.format("🚔 %s арестован (%d★, убийств: %d)", player.Name, s.stars, s.kills))
	stage(player, "Busted", { stars = s.stars }, 3.5)

	-- 1. В участок
	s.mode = "booking"
	publish(player)
	local desk = kit and kit.station.desk
	local stationPos = desk and desk.Position or (player.Character and player.Character:GetPivot().Position)
	if unit and unit.car and stationPos then
		for i, o in unit.officers do
			if o.alive and not o.inVehicle then
				task.spawn(function()
					local seat = i == 1 and unit.car.driverSeat or nil
					if seat and Registry.walkTo(o, kit.doorSide(unit.car, seat)) then
						kit.seatNPC(o, unit.car, seat)
					end
				end)
			end
		end
		task.wait(2)
		if unit.car.occupants[unit.car.driverSeat] == nil and officer and officer.alive then
			kit.seatNPC(officer, unit.car, unit.car.driverSeat)
		end
		transport(player, unit.car, stationPos, unit)
	elseif stationPos then
		transport(player, nil, stationPos, nil)
	end
	if unit then
		cleanupUnit(unit)
		local i = table.find(s.units, unit)
		if i then
			table.remove(s.units, i)
		end
	end
	-- Остальные наряды уезжают
	for _, u in s.units do
		dismissUnit(u)
	end

	-- 2. Фото
	placeAt(player, stationPart("Mugshot") or desk, stationPos)
	stage(player, "Mugshot", {
		number = number,
		name = player.DisplayName,
		date = os.date("!%d.%m.%Y"),
		stars = s.finalStars,
	}, 14, true)

	-- 3. Отпечатки
	placeAt(player, stationPart("Fingerprint") or desk, stationPos)
	stage(player, "Fingerprint", {}, 25, true)

	-- 4. Допрос
	placeAt(player, stationPart("Interview") or desk, stationPos)
	local answers = stage(player, "Interview", { questions = J.Questions }, 60, true)
	local modifier = 1
	local confessed = 0
	if type(answers) == "table" then
		for _, a in answers do
			if a == "confess" then
				confessed += 1
				modifier -= J.ConfessDiscount / #J.Questions
			elseif a == "lie" then
				modifier += J.LieExtra / #J.Questions
			end
		end
	end

	-- 5. КПЗ — ждёт суда
	s.mode = "holding"
	publish(player)
	local holding = stationPart("Holding") or (kit and kit.station.cell)
	placeAt(player, holding, stationPos)
	setCuffed(player, false)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 8
		hum.JumpPower = 0
		hum.JumpHeight = 0
	end
	local holdEnd = now() + J.HoldingTime
	if holding then
		confine(player, holding.Position, 8, function()
			return now() >= holdEnd
		end)
	end
	stage(player, "Holding", {}, J.HoldingTime)

	-- 6. Суд
	s.mode = "court"
	publish(player)
	local dock = justicePart("Court", "Dock")
	local door = justicePart("Court", "CourtDoor")
	setCuffed(player, true)
	if dock then
		transport(player, nil, (door or dock).Position, nil)
		placeAt(player, dock)
	end
	local sentence = sentenceOf(s, modifier)
	local wallet = coinsOf(player)
	local fine = 0
	if wallet then
		fine = math.floor(J.FineBase + wallet.Value * J.FineFraction)
		fine = math.min(fine, wallet.Value)
	end
	local j = ensureJudge()
	local lines = {
		pick(J.Verdicts),
		string.format("Розыск: %d★. Убийств: %d. Ранений: %d.", s.finalStars, s.finalKills, s.injuries),
		confessed > 0 and "Суд учитывает чистосердечное признание." or "Подсудимый не признал вину.",
		string.format("Приговор: %d с лишения свободы и штраф %d монет.", sentence, fine),
		J.ConfiscateWeapons and "Оружие конфисковать." or nil,
	}
	if j then
		task.spawn(function()
			for _, line in lines do
				if line then
					say(j, line, 3)
					task.wait(2.6)
				end
			end
		end)
	end
	stage(player, "Court", { judge = j and j.name or J.JudgeName, lines = lines, sentence = sentence, fine = fine }, 14)
	if wallet then
		wallet.Value -= fine
	end
	if J.ConfiscateWeapons and Registry.confiscateWeapons then
		Registry.confiscateWeapons(player)
	end
	event(string.format("⚖️ %s: %d с, штраф %d", player.Name, sentence, fine))

	-- 7. Тюрьма
	local prisonDoor = justicePart("Prison", "PrisonDoor")
	if prisonDoor then
		transport(player, nil, prisonDoor.Position, nil)
	end
	servePrison(player, sentence)
end

function arrest(player: Player, unit, officer)
	local s = st(player)
	if s.mode ~= "wanted" then
		return
	end
	s.mode = "arrested"
	if unit then
		unit.state = "arrest"
	end
	if officer then
		drawGun(officer, false)
		say(officer, pick(L.PoliceArrest), 3)
	end
	setCuffed(player, true)
	stopAbilities(player, true)
	if Registry.blockWeapons then
		Registry.blockWeapons(player, true)
	end
	publish(player)
	task.spawn(justiceFlow, player, unit, officer)
end
Registry.arrestPlayer = function(player: Player)
	local s = st(player)
	if s.mode == "free" then
		s.mode = "wanted"
		s.stars = math.max(s.stars, 1)
	end
	arrest(player, nil, nil)
end

---------------------------------------------------------------------
-- Клиент, игроки
---------------------------------------------------------------------

remote.OnServerEvent:Connect(function(player: Player, action: any, data: any)
	if action == "StageDone" then
		stageDone[player] = type(data) == "table" and data or true
	end
end)

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		local s = st(player)
		if s.mode == "wanted" then
			-- «Потрачено»: штраф, конфискация, розыск снят
			local wallet = coinsOf(player)
			local lost = wallet and math.floor(wallet.Value * J.WastedFine) or 0
			if wallet then
				wallet.Value -= lost
			end
			if Registry.confiscateWeapons then
				Registry.confiscateWeapons(player)
			end
			remote:FireClient(player, "Stage", "Wasted", { lost = lost }, 5)
			event("💀 " .. player.Name .. ": потрачено")
			clearWanted(player, "погиб")
		end
	end)
	-- Тюремный срок после перезахода
	task.delay(2, function()
		local s = st(player)
		if s.mode == "free" then
			local p = Registry.weaponProfile and Registry.weaponProfile(player)
			if p and type(p.jail) == "number" and p.jail > 0 then
				if Registry.blockWeapons then
					Registry.blockWeapons(player, true)
				end
				stopAbilities(player, true)
				servePrison(player, p.jail)
			end
		end
	end)
end

local function onPlayer(player: Player)
	st(player)
	publish(player)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
end
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	local s = states[player]
	if s then
		for _, u in s.units do
			task.spawn(cleanupUnit, u)
		end
	end
	states[player] = nil
	stageDone[player] = nil
end)

-- Для меню отладки
Registry.debugWanted = function(player: Player, stars: number)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if stars <= 0 then
		clearWanted(player, "меню отладки")
	elseif root then
		report(player, stars, root.Position, false, "меню отладки")
	end
end
