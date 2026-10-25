-- LocalScript: StarterPlayer > StarterPlayerScripts > WantedClient
-- Розыск и правосудие на экране игрока:
--   ⭐ звёзды сверху, «📞 Вызвали полицию», «🚨 Тебя видят», «🔍 Ищут — уйдёшь через …»;
--   АРЕСТОВАН / ПОТРАЧЕНО; в отделе: фото с ростомером, отпечатки пальцев, допрос;
--   КПЗ, суд (приговор), тюрьма (срок), освобождение.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
if not Config.Enabled then
	return
end
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local remote = ReplicatedStorage:WaitForChild("WantedRemote")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local GOLD = Color3.fromRGB(255, 205, 70)
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(16, 18, 26)
local POP = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local function corner(p: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end
local function text(parent: Instance, value: string, size: number, color: Color3?, font: Enum.Font?, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextSize = size,
		TextColor3 = color or WHITE,
		Font = font or Enum.Font.GothamBold,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 8),
	}, parent)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end
local function play(def)
	if def and def.Id ~= "" then
		local s = new("Sound", { SoundId = def.Id, Volume = def.Volume or 0.5 }, workspace)
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
end
local W = Sounds.Weapons or {}

local gui = new("ScreenGui", { Name = "WantedHud", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30 }, player:WaitForChild("PlayerGui"))

---------------------------------------------------------------------
-- ⭐ Звёзды
---------------------------------------------------------------------

local starBar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(260, 64), BackgroundTransparency = 1, Visible = false }, gui)
local starRow = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, starBar)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4) }, starRow)
local stars = {}
for i = 1, 5 do
	stars[i] = new("TextLabel", { Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, Text = "★", TextSize = 34, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(70, 70, 80), TextStrokeTransparency = 0.3, LayoutOrder = i }, starRow)
end
local starScale = new("UIScale", {}, starRow)
local status = text(starBar, "", 14, WHITE, Enum.Font.GothamBold, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 18), TextStrokeTransparency = 0.4 })
local evadeBack = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 57), Size = UDim2.fromOffset(160, 4), BackgroundColor3 = Color3.fromRGB(40, 44, 58), BorderSizePixel = 0 }, starBar)
local evadeFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, evadeBack)

-- Мигалки по краям экрана, когда тебя видят
local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local flashStroke = new("UIStroke", { Color = Color3.fromRGB(255, 40, 40), Thickness = 0, Transparency = 0.5 }, flash)

local toastLabel = text(gui, "", 18, WHITE, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.fromOffset(520, 26), TextStrokeTransparency = 0.3, Visible = false })
local toastToken = 0
local function toast(msg: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = msg
	toastLabel.TextColor3 = color or WHITE
	toastLabel.Visible = true
	task.delay(3.5, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

local lastStars = 0
local function updateStars()
	local n = player:GetAttribute("WantedStars") or 0
	local mode = player:GetAttribute("WantedMode") or "free"
	starBar.Visible = n > 0 and (mode == "wanted" or mode == "arrested")
	for i, s in stars do
		s.TextColor3 = i <= n and GOLD or Color3.fromRGB(70, 70, 80)
	end
	if n > lastStars then
		starScale.Scale = 1.5
		TweenService:Create(starScale, POP, { Scale = 1 }):Play()
		play(W.Wanted)
	end
	lastStars = n
end
player:GetAttributeChangedSignal("WantedStars"):Connect(updateStars)
player:GetAttributeChangedSignal("WantedMode"):Connect(updateStars)
updateStars()

---------------------------------------------------------------------
-- Этапы правосудия
---------------------------------------------------------------------

local stageFrame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)
local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 50 }, gui)
local timerCard = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(330, 56), BackgroundColor3 = DARK, BackgroundTransparency = 0.15, Visible = false }, gui)
corner(timerCard, 14)
new("UIStroke", { Color = Color3.fromRGB(110, 120, 160), Thickness = 1.5, Transparency = 0.3 }, timerCard)
local timerTitle = text(timerCard, "", 14, Color3.fromRGB(190, 200, 225), Enum.Font.GothamBold, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 18) })
local timerText = text(timerCard, "", 22, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 26) })
local timerEnd = 0

local function clearStage()
	for _, c in stageFrame:GetChildren() do
		c:Destroy()
	end
	stageFrame.Visible = false
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local stageToken = 0
local function done(data)
	remote:FireServer("StageDone", data)
end

local function banner(title: string, sub: string, color: Color3, seconds: number)
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(700, 150), BackgroundTransparency = 1 }, stageFrame)
	local t = text(holder, title, 84, color, Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 0, 96), TextStrokeTransparency = 0.2, TextStrokeColor3 = Color3.new(0, 0, 0) })
	text(holder, sub, 20, WHITE, Enum.Font.GothamBold, { Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 28), TextStrokeTransparency = 0.3 })
	local sc = new("UIScale", { Scale = 1.6 }, holder)
	TweenService:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	t.TextTransparency = 1
	TweenService:Create(t, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	task.delay(seconds, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

local function photoFlash()
	local f = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, ZIndex = 40 }, stageFrame)
	TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(f, 0.7)
	play(W.Camera)
end

local function lookAtMe(offsetFn: (CFrame) -> CFrame)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local cf = head.CFrame
	camera.CFrame = offsetFn(cf)
end

local STAGES = {}

function STAGES.Busted(data, seconds)
	play(W.Busted)
	play(W.Cuffs)
	local tint = new("ColorCorrectionEffect", { Name = "BustedTint", Saturation = -0.5, Contrast = 0.1 }, Lighting)
	game:GetService("Debris"):AddItem(tint, seconds)
	banner("АРЕСТОВАН", string.format("Розыск %s  ·  Тебя везут в отдел полиции", string.rep("★", data.stars or 0)), Color3.fromRGB(90, 150, 255), seconds)
end

function STAGES.Wasted(data, seconds)
	local tint = new("ColorCorrectionEffect", { Name = "WastedTint", Saturation = -1, Contrast = 0.2, TintColor = Color3.fromRGB(255, 225, 225) }, Lighting)
	game:GetService("Debris"):AddItem(tint, seconds)
	banner("ПОТРАЧЕНО", string.format("-%d монет · оружие потеряно", data.lost or 0), Color3.fromRGB(220, 40, 40), seconds)
end

function STAGES.Mugshot(data)
	-- Камера напротив лица, ростомер, табличка, две вспышки (анфас и профиль)
	lookAtMe(function(cf)
		local p = cf.Position + cf.LookVector * 6.5
		return CFrame.lookAt(p, cf.Position)
	end)
	camera.FieldOfView = 45
	local board = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, stageFrame)
	for i = 0, 14 do
		local y = 0.08 + i * 0.06
		new("Frame", { Position = UDim2.new(0, 0, y, 0), Size = UDim2.new(1, 0, 0, i % 2 == 0 and 2 or 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.7, BorderSizePixel = 0 }, board)
		text(board, tostring(200 - i * 5), 14, WHITE, Enum.Font.Code, { Position = UDim2.new(0, 12, y, -18), Size = UDim2.fromOffset(40, 16), TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 0.3 })
	end
	local plate = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(380, 110), BackgroundColor3 = Color3.fromRGB(15, 15, 18) }, board)
	corner(plate, 6)
	new("UIStroke", { Color = WHITE, Thickness = 2 }, plate)
	text(plate, "ПОЛИЦИЯ ГОРОДА", 18, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 22) })
	text(plate, string.format("№ %d", data.number or 0), 30, WHITE, Enum.Font.Code, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 34) })
	text(plate, string.format("%s   ·   %s   ·   %s", data.name or "", data.date or "", string.rep("★", data.stars or 0)), 15, WHITE, Enum.Font.GothamBold, { Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 22) })
	local hint = text(stageFrame, "📸 Смотрите в камеру…", 20, WHITE, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(500, 28), TextStrokeTransparency = 0.3 })
	task.wait(2)
	photoFlash()
	task.wait(1.6)
	hint.Text = "↪ Повернитесь направо"
	task.wait(1)
	lookAtMe(function(cf)
		local p = cf.Position + cf.RightVector * 6.5
		return CFrame.lookAt(p, cf.Position)
	end)
	task.wait(1)
	photoFlash()
	task.wait(1.4)
	camera.FieldOfView = 70
	done()
end

function STAGES.Fingerprint()
	camera.CameraType = Enum.CameraType.Custom
	local panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 340), BackgroundColor3 = DARK }, stageFrame)
	corner(panel, 18)
	new("UIStroke", { Color = Color3.fromRGB(90, 150, 255), Thickness = 2 }, panel)
	text(panel, "🫆 Дактилоскопия", 22, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 28) })
	local info = text(panel, "Прижми каждый палец к сканеру (нажми на него)", 14, Color3.fromRGB(190, 200, 225), Enum.Font.GothamMedium, { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 20) })
	local row = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(470, 200), BackgroundTransparency = 1 }, panel)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }, row)
	local names = { "Большой", "Указат.", "Средний", "Безым.", "Мизинец" }
	local doneCount = 0
	for i, name in names do
		local cell = new("TextButton", { Size = UDim2.fromOffset(84, 190), BackgroundColor3 = Color3.fromRGB(30, 34, 48), Text = "", AutoButtonColor = true, LayoutOrder = i }, row)
		corner(cell, 12)
		local pad = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(60, 80), BackgroundColor3 = Color3.fromRGB(230, 225, 215) }, cell)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pad)
		text(cell, name, 12, Color3.fromRGB(190, 200, 225), Enum.Font.GothamBold, { Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 16) })
		local mark = text(cell, "○", 22, Color3.fromRGB(120, 130, 160), Enum.Font.GothamBold, { Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 26) })
		local scanned = false
		cell.Activated:Connect(function()
			if scanned then
				return
			end
			scanned = true
			-- Узор отпечатка: кольца появляются по очереди
			for r = 1, 6 do
				local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(r * 9, r * 12), BackgroundTransparency = 1 }, pad)
				new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
				new("UIStroke", { Color = Color3.fromRGB(40, 40, 60), Thickness = 1.5 }, ring)
				task.wait(0.06)
			end
			local scan = new("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Color3.fromRGB(90, 200, 255), BorderSizePixel = 0 }, pad)
			TweenService:Create(scan, TweenInfo.new(0.5), { Position = UDim2.fromScale(0, 1) }):Play()
			task.wait(0.5)
			scan:Destroy()
			mark.Text = "✓"
			mark.TextColor3 = Color3.fromRGB(80, 210, 120)
			doneCount += 1
			if doneCount == #names then
				info.Text = "✅ Отпечатки внесены в базу"
				task.wait(1.2)
				done()
			end
		end)
	end
end

function STAGES.Interview(data)
	local questions = data.questions or {}
	local answers = {}
	local panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(640, 250), BackgroundColor3 = DARK }, stageFrame)
	corner(panel, 18)
	new("UIStroke", { Color = Color3.fromRGB(90, 150, 255), Thickness = 2 }, panel)
	text(panel, "👮  Допрос", 20, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 26), TextXAlignment = Enum.TextXAlignment.Left })
	local question = text(panel, "", 18, Color3.fromRGB(220, 228, 250), Enum.Font.GothamMedium, { Position = UDim2.fromOffset(20, 46), Size = UDim2.new(1, -40, 0, 50), TextXAlignment = Enum.TextXAlignment.Left })
	local list = new("Frame", { Position = UDim2.fromOffset(20, 104), Size = UDim2.new(1, -40, 0, 130), BackgroundTransparency = 1 }, panel)
	new("UIListLayout", { Padding = UDim.new(0, 8) }, list)
	for qi, q in questions do
		question.Text = string.format("Вопрос %d из %d: %s", qi, #questions, q.Text)
		for _, c in list:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local chosen = nil
		for ai, a in q.Answers do
			local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Color3.fromRGB(34, 38, 54), Text = "  " .. a[1], TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = WHITE, Font = Enum.Font.GothamMedium, TextSize = 15, LayoutOrder = ai }, list)
			corner(b, 10)
			b.Activated:Connect(function()
				chosen = a[2]
			end)
		end
		while not chosen and stageFrame.Visible do
			task.wait(0.1)
		end
		table.insert(answers, chosen or "silent")
		question.Text = chosen == "confess" and "— Записываю. Это зачтётся в суде." or chosen == "lie" and "— Странно… Проверим." or "— Молчание тоже ответ."
		task.wait(1.4)
	end
	done(answers)
end

function STAGES.Holding(_, seconds)
	timerTitle.Text = "🔒 КПЗ — ожидание суда"
	timerEnd = os.clock() + seconds
	timerCard.Visible = true
end

function STAGES.Court(data, seconds)
	timerCard.Visible = false
	local top = new("Frame", { Size = UDim2.new(1, 0, 0.12, 0), BackgroundColor3 = Color3.new(0, 0, 0) }, stageFrame)
	local bottom = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.22, 0), BackgroundColor3 = Color3.new(0, 0, 0) }, stageFrame)
	text(top, "⚖️  ЗАСЕДАНИЕ СУДА", 22, GOLD, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.6) })
	local speaker = text(bottom, data.judge or "Судья", 16, GOLD, Enum.Font.GothamBold, { Position = UDim2.new(0, 0, 0, 14), Size = UDim2.new(1, 0, 0, 20) })
	local line = text(bottom, "", 22, WHITE, Enum.Font.GothamMedium, { Position = UDim2.new(0.1, 0, 0, 40), Size = UDim2.new(0.8, 0, 0, 60) })
	local _ = speaker
	local lines = data.lines or {}
	local per = math.max(2, (seconds - 3) / math.max(#lines, 1))
	for i, l in lines do
		if not stageFrame.Visible then
			return
		end
		if l then
			line.Text = ""
			local count = utf8.len(l) or #l
			for k = 1, count do
				line.Text = string.sub(l, 1, (utf8.offset(l, k + 1) or (#l + 1)) - 1)
				task.wait(0.025)
			end
			if string.find(l, "Приговор") then
				play(W.Gavel)
				photoFlash()
			end
			task.wait(math.max(0.8, per - 0.025 * count))
		end
	end
end

function STAGES.Prison(data, seconds)
	timerTitle.Text = "⛓ Тюрьма — срок"
	timerEnd = os.clock() + seconds
	timerCard.Visible = true
	toast("Отбывай срок. Сбежать нельзя — уйдёшь далеко, вернут обратно.", Color3.fromRGB(200, 210, 230))
	local _ = data
end

function STAGES.Released(_, seconds)
	timerCard.Visible = false
	banner("НА СВОБОДЕ", "Оружие конфисковано — новое можно купить в 📱 Магазине", Color3.fromRGB(80, 210, 120), seconds)
end

---------------------------------------------------------------------
-- Ограничения на время ареста: без прыжка, без рюкзака, без «сброса»
---------------------------------------------------------------------

local restricted = false
local function setRestricted(on: boolean)
	if on == restricted then
		return
	end
	restricted = on
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not on)
	end)
	task.spawn(function()
		for _ = 1, 10 do
			if pcall(function()
				StarterGui:SetCore("ResetButtonCallback", not on)
			end) then
				break
			end
			task.wait(0.5)
		end
	end)
	if on then
		ContextActionService:BindActionAtPriority("JusticeNoJump", function()
			return Enum.ContextActionResult.Sink
		end, false, 4000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	else
		ContextActionService:UnbindAction("JusticeNoJump")
	end
end

local function updateRestricted()
	local mode = player:GetAttribute("WantedMode") or "free"
	local cuffed = player.Character and player.Character:GetAttribute("Cuffed") == true
	setRestricted(cuffed or (mode ~= "free" and mode ~= "wanted"))
end
player:GetAttributeChangedSignal("WantedMode"):Connect(updateRestricted)

---------------------------------------------------------------------
-- Сервер
---------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action, a, b, c)
	if action == "Stage" then
		local name, data, seconds = a, b or {}, c or 5
		clearStage()
		if name ~= "Holding" and name ~= "Prison" then
			timerCard.Visible = false
		end
		stageFrame.Visible = true
		local fn = STAGES[name]
		if fn then
			task.spawn(fn, data, seconds)
		end
		stageToken += 1
		local token = stageToken
		if name == "Released" or name == "Wasted" or name == "Busted" then
			task.delay(seconds, function()
				if token == stageToken then
					clearStage()
				end
			end)
		end
		updateRestricted()
	elseif action == "Fade" then
		black.BackgroundTransparency = 1
		TweenService:Create(black, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
		task.delay(math.max(0.5, a or 1), function()
			TweenService:Create(black, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		end)
	elseif action == "Called" then
		toast("📞 Свидетель вызвал полицию: " .. tostring(a and a.why or ""), Color3.fromRGB(255, 205, 90))
	elseif action == "Stars" then
		if a and a.reason then
			toast("⭐ Розыск: " .. a.reason, GOLD)
		end
	elseif action == "Evaded" then
		toast("✅ Ты ушёл от погони", Color3.fromRGB(80, 210, 120))
	end
end)

---------------------------------------------------------------------
-- Каждый кадр
---------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local n = player:GetAttribute("WantedStars") or 0
	if starBar.Visible then
		local seen = player:GetAttribute("WantedSeen") == true
		local left = player:GetAttribute("WantedEvadeLeft")
		local total = player:GetAttribute("WantedEvadeTotal") or 60
		if seen then
			status.Text = "🚨 Полиция тебя видит!"
			status.TextColor3 = Color3.fromRGB(255, 120, 120)
			for i, s in stars do
				if i <= n then
					s.TextColor3 = (t * 4) % 1 < 0.5 and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(90, 150, 255)
				end
			end
			flashStroke.Thickness = 6
			flashStroke.Color = (t * 3) % 1 < 0.5 and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(40, 110, 255)
		else
			for i, s in stars do
				s.TextColor3 = i <= n and GOLD or Color3.fromRGB(70, 70, 80)
			end
			flashStroke.Thickness = 0
			if type(left) == "number" then
				status.Text = string.format("🔍 Тебя ищут · уйдёшь через %d с", math.ceil(left))
				evadeFill.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
			end
			status.TextColor3 = WHITE
		end
		evadeBack.Visible = not seen
	else
		flashStroke.Thickness = 0
	end
	if timerCard.Visible then
		local left = math.max(0, timerEnd - t)
		timerText.Text = string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
	end
end)

player.CharacterAdded:Connect(function(character)
	character:GetAttributeChangedSignal("Cuffed"):Connect(updateRestricted)
	updateRestricted()
end)
if player.Character then
	player.Character:GetAttributeChangedSignal("Cuffed"):Connect(updateRestricted)
end
