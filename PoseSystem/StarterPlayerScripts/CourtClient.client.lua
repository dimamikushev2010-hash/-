-- LocalScript: StarterPlayer > StarterPlayerScripts > CourtClient
-- Адвокат, залог и суд на экране игрока:
--   🔒 КПЗ: карточка дела, один звонок (адвокат или друг), залог, чат с адвокатом (кнопки или свой текст);
--   📞 другу приходит звонок: внести залог / прийти защитником / «понял»;
--   ⚖️ суд: субтитры, карточки улик (свидетель, запись камеры), последнее слово, приговор, апелляция;
--   📹 «Тебя сняла камера» / «Камера сломана — запись пропала».

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CourtConfig"))
if not Config.Enabled then
	return
end
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local DebugTimer = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local remote = ReplicatedStorage:WaitForChild("CourtRemote")
local wantedRemote = ReplicatedStorage:WaitForChild("WantedRemote")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local GOLD = Color3.fromRGB(255, 205, 70)
local WHITE = Color3.new(1, 1, 1)
local DIM = Color3.fromRGB(180, 188, 210)
local DARK = Color3.fromRGB(16, 18, 26)
local CARD = Color3.fromRGB(28, 32, 46)
local BLUE = Color3.fromRGB(90, 150, 255)
local RED = Color3.fromRGB(255, 80, 80)
local GREEN = Color3.fromRGB(80, 210, 120)
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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
local function stroke(p: Instance, color: Color3, thickness: number?)
	new("UIStroke", { Color = color, Thickness = thickness or 1.5, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function pad(p: Instance, px: number)
	new("UIPadding", { PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px), PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px) }, p)
end
local function text(parent: Instance, value: string, size: number, color: Color3?, font: Enum.Font?, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextSize = size,
		TextColor3 = color or WHITE,
		Font = font or Enum.Font.GothamBold,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, size + 8),
	}, parent)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end
local function button(parent: Instance, label: string, color: Color3, props)
	local b = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = color,
		Text = label,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextWrapped = true,
		AutoButtonColor = true,
	}, parent)
	corner(b, 10)
	for k, v in pairs(props or {}) do
		(b :: any)[k] = v
	end
	return b
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
local SW = Sounds.Weapons or {}
local function stars(n: number): string
	return n > 0 and string.rep("★", n) or "—"
end

local gui = new("ScreenGui", { Name = "CourtHud", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 32 }, player:WaitForChild("PlayerGui"))
local scale = new("UIScale", {}, gui)
local function rescale()
	local v = camera.ViewportSize
	scale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 760), 0.6, 1)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()

---------------------------------------------------------------------
-- Всплывающие строки (камера сняла, сломал камеру)
---------------------------------------------------------------------

local pill = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 170), Size = UDim2.fromOffset(560, 40), BackgroundColor3 = Color3.fromRGB(30, 10, 12), BackgroundTransparency = 0.1, Visible = false }, gui)
corner(pill, 20)
stroke(pill, RED)
local pillText = text(pill, "", 15, WHITE, Enum.Font.GothamBold, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
local pillToken = 0
local function showPill(msg: string, color: Color3)
	pillToken += 1
	local token = pillToken
	pillText.Text = msg
	pill.UIStroke.Color = color
	pill.Visible = true
	pill.Size = UDim2.fromOffset(500, 34)
	TweenService:Create(pill, POP, { Size = UDim2.fromOffset(560, 40) }):Play()
	task.delay(4.5, function()
		if token == pillToken then
			pill.Visible = false
		end
	end)
end

---------------------------------------------------------------------
-- 🔒 КПЗ: дело, звонок, залог
---------------------------------------------------------------------

local holding = nil -- последние данные от сервера
local lawyerById = {}
for _, l in Config.Lawyers do
	lawyerById[l.Id] = l
end

local holdPanel = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 20), Size = UDim2.fromOffset(360, 560), BackgroundColor3 = DARK, BackgroundTransparency = 0.05, Visible = false }, gui)
corner(holdPanel, 18)
stroke(holdPanel, BLUE, 2)
local holdHead = text(holdPanel, "🔒 КПЗ", 20, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 26) })
local holdSub = text(holdPanel, "", 13, DIM, Enum.Font.GothamMedium, { Position = UDim2.fromOffset(16, 38), Size = UDim2.new(1, -32, 0, 18) })
local holdBody = new("ScrollingFrame", { Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -24, 1, -74), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, holdPanel)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, holdBody)

local callMode = nil -- nil / "lawyers" / "friends"

local function section(order: number, title: string?)
	local f = new("Frame", { Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = CARD, LayoutOrder = order }, holdBody)
	corner(f, 12)
	pad(f, 10)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	if title then
		text(f, title, 15, GOLD, Enum.Font.GothamBlack, { LayoutOrder = 0 })
	end
	return f
end
local function row(parent: Instance, order: number, value: string, color: Color3?)
	return text(parent, value, 14, color or WHITE, Enum.Font.GothamMedium, { LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 18) })
end

local STRENGTH = {
	Weak = { "Слабые — могут оправдать", GREEN, 0.25 },
	Medium = { "Средние", GOLD, 0.6 },
	Strong = { "Серьёзные", RED, 0.95 },
}

local renderHolding -- объявлена ниже

local function renderCase(d)
	local f = section(1, "📁 Твоё дело")
	row(f, 1, "⭐ Розыск: " .. stars(d.stars or 0))
	local w = (d.witnesses or 0) + (d.calls or 0)
	row(f, 2, string.format("📞 Свидетели: %d%s", w, (d.calls or 0) > 0 and string.format(" (не придут: %d, есть запись звонка)", d.calls) or ""), w > 0 and WHITE or GREEN)
	row(f, 3, string.format("📹 Записи камер: %d%s", d.cameras or 0, (d.lost or 0) > 0 and string.format(" · сломано: %d", d.lost) or ""), (d.cameras or 0) > 0 and WHITE or GREEN)
	row(f, 4, "👮 Полиция видела сама: " .. (d.policeSaw and "да" or "нет"), d.policeSaw and RED or GREEN)
	if d.surrendered then
		row(f, 5, "🙌 При аресте не сопротивлялся — учтут", GREEN)
	elseif d.resisted then
		row(f, 5, "🏃 Сопротивлялся при аресте — срок больше", RED)
	end
	if (d.confessed or 0) > 0 then
		row(f, 6, string.format("🙇 Признался на допросе: %d раз", d.confessed))
	end
	local st = STRENGTH[d.strength] or STRENGTH.Medium
	row(f, 7, "Улики: " .. st[1], st[2])
	local bar = new("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Color3.fromRGB(45, 50, 68), BorderSizePixel = 0, LayoutOrder = 8 }, f)
	corner(bar, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(st[3], 1), BackgroundColor3 = st[2], BorderSizePixel = 0 }, bar)
	corner(fill, 3)
	row(f, 9, "⏳ Ожидаемый срок: " .. tostring(d.estimate or "?"), DIM)
end

local function renderLawyer(d)
	local l = lawyerById[d.lawyer] or Config.Lawyers[1]
	local f = section(2, "💼 Твой адвокат")
	row(f, 1, string.format("%s %s", l.Icon, l.Name))
	row(f, 2, string.format("%s · %s", l.Title, string.rep("★", l.Rating)), DIM)
	if d.defender then
		row(f, 3, "⚖️ Защитник в суде: " .. d.defender, GREEN)
	end
end

local function renderCall(d)
	local f = section(3, "📞 Один звонок")
	if d.called then
		row(f, 1, d.calledFriend and ("Ты позвонил другу: " .. d.calledFriend) or "Звонок использован — адвокат нанят", DIM)
		return
	end
	row(f, 1, "Можно позвонить один раз: нанять адвоката или попросить друга помочь.", DIM)
	local tabs = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 2 }, f)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, tabs)
	local bl = button(tabs, "💼 Адвокат", callMode == "lawyers" and BLUE or Color3.fromRGB(44, 50, 70), { Size = UDim2.new(0.5, -3, 1, 0), TextSize = 14 })
	local bf = button(tabs, "👥 Другу", callMode == "friends" and BLUE or Color3.fromRGB(44, 50, 70), { Size = UDim2.new(0.5, -3, 1, 0), TextSize = 14 })
	bl.Activated:Connect(function()
		callMode = if callMode == "lawyers" then nil else "lawyers"
		renderHolding()
	end)
	bf.Activated:Connect(function()
		callMode = if callMode == "friends" then nil else "friends"
		renderHolding()
	end)
	if callMode == "lawyers" then
		for i, l in d.lawyers or {} do
			if l.Price <= 0 then
				continue
			end
			local card = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(36, 41, 58), LayoutOrder = 10 + i }, f)
			corner(card, 10)
			pad(card, 8)
			new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, card)
			text(card, string.format("%s %s", l.Icon, l.Name), 15, WHITE, Enum.Font.GothamBold, { LayoutOrder = 1 })
			text(card, string.format("%s · %s", l.Title, string.rep("★", l.Rating)), 13, GOLD, Enum.Font.GothamMedium, { LayoutOrder = 2 })
			text(card, l.Perks, 13, DIM, Enum.Font.GothamMedium, { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 16) })
			local can = (d.coins or 0) >= l.Price
			local b = button(card, string.format("Нанять за %d 🪙%s", l.Price, can and "" or " (мало монет)"), can and Color3.fromRGB(46, 120, 70) or Color3.fromRGB(70, 60, 60), { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 32), TextSize = 14 })
			b.Activated:Connect(function()
				if can then
					remote:FireServer("Hire", l.Id)
				end
			end)
		end
	elseif callMode == "friends" then
		if #(d.friends or {}) == 0 then
			row(f, 10, "Других игроков на сервере нет.", DIM)
		end
		for i, fr in d.friends or {} do
			local b = button(f, "📞 " .. fr.name, Color3.fromRGB(46, 90, 140), { LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, 32), TextSize = 14 })
			b.Activated:Connect(function()
				remote:FireServer("CallFriend", fr.userId)
			end)
		end
		row(f, 99, "Друг сможет внести залог или прийти в суд защитником.", DIM)
	end
end

local function renderBail(d)
	local f = section(4, "💰 Залог")
	if d.bailPaid then
		row(f, 1, "Залог внесён — едем в суд", GREEN)
	elseif not d.bail then
		row(f, 1, "За такое залог не положен.", RED)
	else
		row(f, 1, "Заплати — и сразу в суд, без ожидания в КПЗ. Не возвращается.", DIM)
		local can = (d.coins or 0) >= d.bail
		local b = button(f, string.format("Внести залог %d 🪙%s", d.bail, can and "" or " (мало монет)"), can and Color3.fromRGB(150, 110, 30) or Color3.fromRGB(70, 60, 60), { LayoutOrder = 2 })
		b.Activated:Connect(function()
			if can then
				remote:FireServer("Bail")
			end
		end)
	end
	row(f, 3, string.format("У тебя: %d 🪙", d.coins or 0), DIM)
end

function renderHolding()
	for _, ch in holdBody:GetChildren() do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	local d = holding
	if not d then
		return
	end
	holdHead.Text = "🔒 КПЗ · дело № " .. tostring(d.number or "")
	renderCase(d)
	renderLawyer(d)
	renderCall(d)
	renderBail(d)
end

---------------------------------------------------------------------
-- 💬 Чат с адвокатом
---------------------------------------------------------------------

local chat = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 20), Size = UDim2.fromOffset(380, 560), BackgroundColor3 = DARK, BackgroundTransparency = 0.05, Visible = false }, gui)
corner(chat, 18)
stroke(chat, BLUE, 2)
local chatHead = text(chat, "💬 Адвокат", 18, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 24) })
local chatSub = text(chat, "Спроси кнопкой или напиши сам", 13, DIM, Enum.Font.GothamMedium, { Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, -32, 0, 18) })
local log = new("ScrollingFrame", { Position = UDim2.fromOffset(12, 60), Size = UDim2.new(1, -24, 1, -200), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, chat)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, log)
local typing = text(chat, "", 13, DIM, Enum.Font.GothamMedium, { Position = UDim2.new(0, 16, 1, -138), Size = UDim2.new(1, -32, 0, 18) })
local chips = new("ScrollingFrame", { Position = UDim2.new(0, 12, 1, -116), Size = UDim2.new(1, -24, 0, 62), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new() }, chat)
new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 26), CellPadding = UDim2.fromOffset(6, 6), FillDirection = Enum.FillDirection.Vertical, FillDirectionMaxCells = 2, SortOrder = Enum.SortOrder.LayoutOrder }, chips)
local inputRow = new("Frame", { Position = UDim2.new(0, 12, 1, -48), Size = UDim2.new(1, -24, 0, 36), BackgroundTransparency = 1 }, chat)
local input = new("TextBox", { Size = UDim2.new(1, -46, 1, 0), BackgroundColor3 = CARD, Text = "", PlaceholderText = "Напиши адвокату…", PlaceholderColor3 = Color3.fromRGB(120, 128, 150), TextColor3 = WHITE, Font = Enum.Font.GothamMedium, TextSize = 14, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, inputRow)
corner(input, 10)
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, input)
local send = button(inputRow, "➤", BLUE, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(40, 36), TextSize = 18 })

local msgOrder = 0
local function bubble(who: string, value: string, mine: boolean)
	msgOrder += 1
	local holder = new("Frame", { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = msgOrder }, log)
	local b = new("Frame", { AnchorPoint = Vector2.new(mine and 1 or 0, 0), Position = UDim2.fromScale(mine and 1 or 0, 0), Size = UDim2.new(0.86, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = mine and Color3.fromRGB(46, 90, 160) or CARD }, holder)
	corner(b, 12)
	pad(b, 8)
	new("UIListLayout", { Padding = UDim.new(0, 2) }, b)
	if not mine then
		text(b, who, 12, GOLD, Enum.Font.GothamBold, { Size = UDim2.new(1, 0, 0, 14) })
	end
	text(b, value, 14, WHITE, Enum.Font.GothamMedium, { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 16) })
	task.defer(function()
		log.CanvasPosition = Vector2.new(0, math.max(0, log.AbsoluteCanvasSize.Y - log.AbsoluteWindowSize.Y))
	end)
end

local function clearChat()
	for _, ch in log:GetChildren() do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	msgOrder = 0
end

local function ask(topicId: string?, label: string?, freeText: string?)
	if typing.Text ~= "" then
		return
	end
	bubble("", label or freeText or "", true)
	remote:FireServer("Ask", topicId, freeText)
end

local chipsBuilt = false
local function buildChips(topics)
	if chipsBuilt then
		return
	end
	chipsBuilt = true
	for i, t in topics or Config.Topics do
		if t.Button then
			local b = button(chips, t.Button, Color3.fromRGB(44, 50, 70), { TextSize = 12, LayoutOrder = i })
			b.Activated:Connect(function()
				ask(t.Id, t.Button, nil)
			end)
		end
	end
end

local function submit()
	local value = input.Text
	if #value > 0 then
		input.Text = ""
		ask(nil, nil, string.sub(value, 1, 300))
	end
end
send.Activated:Connect(submit)
input.FocusLost:Connect(function(enter)
	if enter then
		submit()
	end
end)

local function updateChatHead()
	local l = holding and lawyerById[holding.lawyer] or Config.Lawyers[1]
	chatHead.Text = string.format("💬 %s %s", l.Icon, l.Name)
	chatSub.Text = l.Title .. " · спроси кнопкой или напиши сам"
end

local function showHolding(on: boolean)
	holdPanel.Visible = on
	chat.Visible = on
	if not on then
		callMode = nil
		typing.Text = ""
	end
end

---------------------------------------------------------------------
-- 📞 Звонок другу (у друга)
---------------------------------------------------------------------

local callCard = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 220), Size = UDim2.fromOffset(440, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = DARK, Visible = false }, gui)
corner(callCard, 18)
stroke(callCard, GREEN, 2)
pad(callCard, 14)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, callCard)
local callToken = 0

local function showFriendCall(d)
	callToken += 1
	local token = callToken
	for _, ch in callCard:GetChildren() do
		if ch:IsA("TextLabel") or ch:IsA("TextButton") then
			ch:Destroy()
		end
	end
	text(callCard, "📞 Звонок из КПЗ", 20, WHITE, Enum.Font.GothamBlack, { LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center })
	text(callCard, string.format("%s арестован (%s) и просит помочь.", d.name or "?", stars(d.stars or 0)), 15, DIM, Enum.Font.GothamMedium, { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.Y, TextXAlignment = Enum.TextXAlignment.Center })
	local timer = text(callCard, "", 13, DIM, Enum.Font.GothamMedium, { LayoutOrder = 9, TextXAlignment = Enum.TextXAlignment.Center })
	local function answer(choice: string)
		callCard.Visible = false
		callToken += 1
		remote:FireServer("FriendAnswer", d.from, choice)
	end
	if d.bail then
		local b = button(callCard, string.format("💰 Внести залог за друга (%d 🪙)%s", d.bail, d.canBail and "" or " — мало монет"), d.canBail and Color3.fromRGB(150, 110, 30) or Color3.fromRGB(70, 60, 60), { LayoutOrder = 3 })
		b.Activated:Connect(function()
			if d.canBail then
				answer("bail")
			end
		end)
	end
	button(callCard, "⚖️ Прийти в суд защитником", Color3.fromRGB(46, 90, 160), { LayoutOrder = 4 }).Activated:Connect(function()
		answer("defend")
	end)
	button(callCard, "👍 Понял, держись!", Color3.fromRGB(50, 56, 76), { LayoutOrder = 5 }).Activated:Connect(function()
		answer("ok")
	end)
	callCard.Visible = true
	play(SW.Wanted)
	task.spawn(function()
		local left = d.seconds or 30
		while token == callToken and left > 0 do
			timer.Text = string.format("Ответить: %d с", left)
			task.wait(1)
			left -= 1
		end
		if token == callToken then
			callCard.Visible = false
		end
	end)
end

---------------------------------------------------------------------
-- ⚖️ Суд
---------------------------------------------------------------------

local trial = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)
local top = new("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = Color3.new(0, 0, 0) }, trial)
local trialTitle = text(top, "⚖️  ЗАСЕДАНИЕ СУДА", 22, GOLD, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -40, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
local bottom = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 170), BackgroundColor3 = Color3.new(0, 0, 0) }, trial)
local speaker = text(bottom, "", 16, GOLD, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.new(0.8, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
local subtitle = text(bottom, "", 22, WHITE, Enum.Font.GothamMedium, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.new(0.8, 0, 0, 90), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
local sideInfo = text(top, "", 13, DIM, Enum.Font.GothamMedium, { Position = UDim2.new(0, 20, 1, -30), Size = UDim2.new(0.3, 0, 0, 18) })

local evidence = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.45, 0), Size = UDim2.fromOffset(360, 220), BackgroundColor3 = Color3.fromRGB(8, 10, 12), Visible = false }, trial)
corner(evidence, 10)
local evStroke = new("UIStroke", { Color = WHITE, Thickness = 2 }, evidence)
local evTop = text(evidence, "", 14, RED, Enum.Font.Code, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18) })
local evBig = text(evidence, "", 40, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 0, 50), TextXAlignment = Enum.TextXAlignment.Center })
local evText = text(evidence, "", 16, WHITE, Enum.Font.GothamMedium, { Position = UDim2.fromOffset(12, 100), Size = UDim2.new(1, -24, 0, 70), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
local evStamp = text(evidence, "", 26, RED, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, Rotation = -12, TextStrokeTransparency = 0.3, Visible = false })
local noise = {} -- полосы помех на «записи»
for i = 1, 6 do
	noise[i] = new("Frame", { Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0, Visible = false }, evidence)
end
local evCamera = false

local ROLE_COLOR = {
	judge = GOLD,
	prosecutor = Color3.fromRGB(255, 120, 120),
	lawyer = Color3.fromRGB(120, 180, 255),
	witness = Color3.fromRGB(200, 220, 160),
	police = Color3.fromRGB(120, 170, 255),
	friend = GREEN,
	defendant = WHITE,
	court = DIM,
}
local ROLE_NAME = {
	judge = "Судья",
	prosecutor = "Обвинение",
	lawyer = "Защита",
	witness = "Свидетель",
	police = "Полиция",
	friend = "Защитник-друг",
	defendant = "Подсудимый",
	court = "",
}

local function showEvidence(e)
	if not e then
		return
	end
	evidence.Visible = true
	evStamp.Visible = e.doubted == true
	evStamp.Text = "ПОД СОМНЕНИЕМ"
	evCamera = false
	if e.kind == "camera" then
		evCamera = true
		evStroke.Color = Color3.fromRGB(200, 200, 200)
		evTop.Text = string.format("● REC   %s   %s", string.upper(e.cam or "CAM"), e.time or "")
		evBig.Text = "📹"
		evText.Text = "На записи: " .. tostring(e.why or "")
		if e.doubted then
			evStamp.Text = "НЕ ПРИНЯТО"
		end
	elseif e.kind == "witness" then
		evStroke.Color = Color3.fromRGB(200, 220, 160)
		evTop.Text = "ПОКАЗАНИЯ СВИДЕТЕЛЯ"
		evBig.Text = "🧑"
		evText.Text = string.format("%s: «%s»", e.name or "", e.why or "")
	elseif e.kind == "call" then
		evStroke.Color = GOLD
		evTop.Text = "ЗАПИСЬ ЗВОНКА В 911"
		evBig.Text = "📞"
		evText.Text = string.format("%s: «%s»", e.name or "", e.why or "")
	elseif e.kind == "police" then
		evStroke.Color = BLUE
		evTop.Text = "ПОКАЗАНИЯ ПОЛИЦИИ"
		evBig.Text = "👮"
		evText.Text = "Офицер видел подсудимого на месте"
	elseif e.kind == "lost" then
		evStroke.Color = RED
		evTop.Text = "НЕТ СИГНАЛА"
		evBig.Text = "📵"
		evText.Text = string.format("Камера «%s» сломана — записи нет", e.cam or "")
	end
	for _, n in noise do
		n.Visible = evCamera
	end
	evidence.Size = UDim2.fromOffset(320, 196)
	TweenService:Create(evidence, POP, { Size = UDim2.fromOffset(360, 220) }):Play()
end

local lineToken = 0
local waitToken = 0 -- «судья совещается…»
local function showLine(d)
	waitToken += 1
	lineToken += 1
	local token = lineToken
	local role = d.role or "court"
	local roleName = ROLE_NAME[role] or ""
	speaker.Text = (roleName ~= "" and roleName ~= d.name) and string.format("%s · %s", roleName, d.name or "") or (d.name or "")
	speaker.TextColor3 = ROLE_COLOR[role] or WHITE
	if d.evidence then
		showEvidence(d.evidence)
	elseif role == "judge" or role == "prosecutor" then
		evidence.Visible = false
	end
	local value = d.text or ""
	local count = utf8.len(value) or #value
	task.spawn(function()
		for k = 1, count do
			if token ~= lineToken then
				return
			end
			subtitle.Text = string.sub(value, 1, (utf8.offset(value, k + 1) or (#value + 1)) - 1)
			task.wait(0.022)
		end
	end)
end

-- ⚖️ Весы правосудия: слева — оправдание, справа — обвинение
local scaleBox = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -8), Size = UDim2.fromOffset(300, 30), BackgroundTransparency = 1 }, top)
text(scaleBox, "оправдать", 11, GREEN, Enum.Font.GothamBold, { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(80, 12) })
text(scaleBox, "виновен", 11, RED, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(80, 12), TextXAlignment = Enum.TextXAlignment.Right })
local scaleBar = new("Frame", { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, scaleBox)
corner(scaleBar, 4)
new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, GREEN), ColorSequenceKeypoint.new(0.5, GOLD), ColorSequenceKeypoint.new(1, RED) }) }, scaleBar)
local needle = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 18), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, scaleBar)
corner(needle, 3)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5 }, needle)
local scaleIcon = text(scaleBox, "⚖️", 16, WHITE, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(30, 18), TextXAlignment = Enum.TextXAlignment.Center })
local function setScale(v: number)
	TweenService:Create(needle, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromScale(math.clamp((v + 1) / 2, 0.02, 0.98), 0.5) }):Play()
	local sc = new("UIScale", { Scale = 1.4 }, scaleIcon)
	TweenService:Create(sc, POP, { Scale = 1 }):Play()
	game:GetService("Debris"):AddItem(sc, 0.5)
end

-- ✋ Шепнуть адвокату «протест!»
local protestBtn = button(trial, "✋ Протест!", Color3.fromRGB(150, 50, 50), { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -182), Size = UDim2.fromOffset(170, 40), Visible = false })
local protestsLeft = 0
local function updateProtest()
	protestBtn.Text = string.format("✋ Протест! (%d)", protestsLeft)
	protestBtn.Visible = protestsLeft > 0
end
protestBtn.Activated:Connect(function()
	if protestsLeft > 0 then
		remote:FireServer("Protest")
		protestBtn.Text = "✋ Адвокат услышал…"
		protestBtn.Visible = true
	end
end)

-- «Судья совещается…» — пока нейросеть пишет
local function showWait(msg: string)
	waitToken += 1
	local token = waitToken
	speaker.Text = "⏳"
	speaker.TextColor3 = DIM
	task.spawn(function()
		local dots = 0
		while token == waitToken do
			dots = dots % 3 + 1
			subtitle.Text = string.gsub(msg, "…$", "") .. string.rep(".", dots)
			task.wait(0.4)
		end
	end)
end

-- 🧹 Общественные работы
local communityCard = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(380, 60), BackgroundColor3 = DARK, BackgroundTransparency = 0.1, Visible = false }, gui)
corner(communityCard, 14)
stroke(communityCard, Color3.fromRGB(255, 140, 40), 2)
local communityTitle = text(communityCard, "", 16, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
text(communityCard, "Иди по оранжевому лучу и удерживай E у кучи мусора", 12, DIM, Enum.Font.GothamMedium, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
local community = nil

-- Выбор: вопрос, последнее слово, речь друга, апелляция
local choicePanel = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -186), Size = UDim2.fromOffset(560, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = DARK, Visible = false }, gui)
corner(choicePanel, 16)
stroke(choicePanel, GOLD, 2)
pad(choicePanel, 12)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, choicePanel)
local CHOICE_TITLE = {
	Question = "❓ Вопрос тебе",
	LastWord = "🗣 Твоё последнее слово",
	Speech = "⚖️ Что скажешь в защиту друга?",
	Appeal = "📄 Обжаловать приговор?",
}
local choiceToken = 0
local function showChoice(d)
	choiceToken += 1
	local token = choiceToken
	for _, ch in choicePanel:GetChildren() do
		if ch:IsA("TextLabel") or ch:IsA("TextButton") then
			ch:Destroy()
		end
	end
	local title = text(choicePanel, CHOICE_TITLE[d.kind] or "Выбери", 17, GOLD, Enum.Font.GothamBlack, { LayoutOrder = 0, TextXAlignment = Enum.TextXAlignment.Center })
	if d.title and d.title ~= "" and d.kind ~= "Appeal" then
		text(choicePanel, "«" .. d.title .. "»", 15, WHITE, Enum.Font.GothamMedium, { LayoutOrder = 0, AutomaticSize = Enum.AutomaticSize.Y, TextXAlignment = Enum.TextXAlignment.Center })
	end
	for i, label in d.options or {} do
		local b = button(choicePanel, label, Color3.fromRGB(40, 46, 66), { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.Y })
		b.Activated:Connect(function()
			remote:FireServer("Choice", d.kind, i)
			choicePanel.Visible = false
		end)
	end
	choicePanel.Visible = true
	task.spawn(function()
		local left = d.seconds or 10
		while token == choiceToken and left > 0 and choicePanel.Visible do
			title.Text = string.format("%s  ·  %d", CHOICE_TITLE[d.kind] or "Выбери", left)
			task.wait(1)
			left -= 1
		end
	end)
end

local verdictCard = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(640, 130), BackgroundTransparency = 1, Visible = false }, trial)
local verdictBig = text(verdictCard, "", 72, RED, Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 0, 84), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2 })
local verdictSub = text(verdictCard, "", 20, WHITE, Enum.Font.GothamBold, { Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 })
local verdictScale = new("UIScale", {}, verdictCard)

local function flashWhite()
	local f = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, ZIndex = 40 }, trial)
	TweenService:Create(f, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(f, 0.6)
end

local function showVerdict(d)
	verdictCard.Visible = true
	local kind = d.kind or (d.acquitted and "acquit" or "prison")
	local appeal = d.appeal == "win" and " · жалоба удовлетворена" or d.appeal == "lose" and " · жалоба отклонена" or ""
	if kind == "acquit" then
		verdictBig.Text = "ОПРАВДАН"
		verdictBig.TextColor3 = GREEN
		verdictSub.Text = "Суд не убеждён — свобода!"
	elseif kind == "fine" then
		verdictBig.Text = "ШТРАФ"
		verdictBig.TextColor3 = GOLD
		verdictSub.Text = string.format("%d 🪙 — и свободен%s", d.fine or 0, appeal)
	elseif kind == "probation" then
		verdictBig.Text = "УСЛОВНО"
		verdictBig.TextColor3 = Color3.fromRGB(255, 170, 60)
		verdictSub.Text = string.format("Штраф %d 🪙 · попадёшься снова — срок ×2%s", d.fine or 0, appeal)
	elseif kind == "community" then
		verdictBig.Text = "ОБЩЕСТВЕННЫЕ РАБОТЫ"
		verdictBig.TextColor3 = Color3.fromRGB(255, 140, 40)
		verdictSub.Text = string.format("Убрать мусор: %d куч · штраф %d 🪙%s", d.bags or 0, d.fine or 0, appeal)
	else
		verdictBig.Text = "ВИНОВЕН"
		verdictBig.TextColor3 = RED
		verdictSub.Text = string.format("%s тюрьмы · штраф %d 🪙%s", d.sentence or "", d.fine or 0, appeal)
	end
	verdictBig.TextScaled = utf8.len(verdictBig.Text) > 12
	verdictScale.Scale = 1.6
	TweenService:Create(verdictScale, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	play(SW.Gavel)
	flashWhite()
	task.delay(4, function()
		verdictCard.Visible = false
	end)
end

local function endTrial()
	waitToken += 1
	protestsLeft = 0
	protestBtn.Visible = false
	trial.Visible = false
	choicePanel.Visible = false
	evidence.Visible = false
	verdictCard.Visible = false
	lineToken += 1
	choiceToken += 1
end

---------------------------------------------------------------------
-- Сервер
---------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action: string, d)
	d = d or {}
	if action == "Holding" then
		local first = holding == nil
		holding = d
		if first then
			clearChat()
		end
		buildChips(d.topics)
		updateChatHead()
		renderHolding()
		showHolding(true)
	elseif action == "HoldingEnd" then
		holding = nil
		showHolding(false)
		if d.bail then
			showPill("💰 Залог внесён — едем в суд", GOLD)
		end
	elseif action == "Lawyer" then
		typing.Text = ""
		local l = lawyerById[d.lawyer] or Config.Lawyers[1]
		bubble(l.Icon .. " " .. l.Name, d.text or "", false)
	elseif action == "Typing" then
		local l = holding and lawyerById[holding.lawyer] or Config.Lawyers[1]
		typing.Text = l.Name .. " печатает…"
		play(Sounds.Weapons and Sounds.Weapons.Typing)
	elseif action == "FriendCall" then
		showFriendCall(d)
	elseif action == "TrialStart" then
		showHolding(false)
		trial.Visible = true
		evidence.Visible = false
		subtitle.Text = ""
		speaker.Text = ""
		trialTitle.Text = string.format("⚖️  ЗАСЕДАНИЕ СУДА  ·  ДЕЛО № %s  ·  %s", tostring(d.number or ""), d.ai and "🤖 живой суд" or "🎲 живой спор")
		local l = d.lawyer or {}
		sideInfo.Text = string.format("%s (%s)  ·  Защита: %s %s%s", d.judge or "Судья", d.mood or "", l.Icon or "", l.Name or "", d.defender and ("  ·  друг: " .. d.defender) or "")
		protestsLeft = d.defendantId == player.UserId and (d.protests or 0) or 0
		updateProtest()
		needle.Position = UDim2.fromScale(0.5, 0.5)
	elseif action == "Scale" then
		setScale(d.value or 0)
	elseif action == "Wait" then
		showWait(d.text or "Судья совещается…")
	elseif action == "WaitEnd" then
		waitToken += 1
	elseif action == "Mode" then
		trialTitle.Text = string.gsub(trialTitle.Text, "🤖 живой суд", "🎲 живой спор")
	elseif action == "Protests" then
		protestsLeft = d.left or 0
		task.delay(1.5, updateProtest)
	elseif action == "Community" then
		community = d
		communityCard.Visible = true
	elseif action == "CommunityEnd" then
		community = nil
		communityCard.Visible = false
		showPill(d.ok and "🧹 Общественные работы выполнены!" or "⏰ Время вышло — в тюрьму", d.ok and GREEN or RED)
	elseif action == "Line" then
		trial.Visible = true
		showLine(d)
	elseif action == "Choice" then
		showChoice(d)
	elseif action == "ChoiceEnd" then
		choicePanel.Visible = false
	elseif action == "Verdict" then
		showVerdict(d)
	elseif action == "TrialEnd" then
		task.delay(1.5, endTrial)
	elseif action == "Recorded" then
		showPill(string.format("● REC  Камера «%s» сняла: %s. Сломай её (выстрел или E) — и записи не будет", d.name or "", d.why or ""), RED)
	elseif action == "CameraBroken" then
		if (d.lost or 0) > 0 then
			showPill(string.format("💥 Камера «%s» сломана — записей против тебя: −%d", d.name or "", d.lost), GREEN)
		else
			showPill(string.format("💥 Камера «%s» сломана", d.name or ""), GOLD)
		end
	end
end)

-- Если этап сменился (тюрьма, свобода) — прячем окна
wantedRemote.OnClientEvent:Connect(function(action, name)
	if action == "Stage" and name ~= "Holding" and name ~= "Trial" then
		holding = nil
		showHolding(false)
		if name == "Prison" or name == "Released" or name == "Wasted" then
			endTrial()
		end
	end
end)

-- Таймер КПЗ в шапке и помехи на «записи камеры»
DebugTimer.connect(RunService.RenderStepped, "CourtClient", function()
	if holdPanel.Visible and holding and holding.holdEnd then
		local left = math.max(0, holding.holdEnd - workspace:GetServerTimeNow())
		holdSub.Text = string.format("До суда: %d:%02d  ·  розыск %s", math.floor(left / 60), math.floor(left % 60), stars(holding.stars or 0))
	end
	if community then
		local left = math.max(0, (community.endAt or 0) - workspace:GetServerTimeNow())
		communityTitle.Text = string.format("🧹 Общественные работы: %d/%d  ·  %d:%02d", community.done or 0, community.total or 0, math.floor(left / 60), math.floor(left % 60))
	end
	if evidence.Visible and evCamera then
		local t = os.clock()
		for i, n in noise do
			n.Position = UDim2.new(0, 0, ((t * (0.3 + i * 0.07)) + i * 0.17) % 1, 0)
		end
		evTop.TextTransparency = (t * 2) % 1 < 0.5 and 0 or 0.6
	end
end)
