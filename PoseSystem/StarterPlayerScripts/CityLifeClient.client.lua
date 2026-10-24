-- LocalScript: StarterPlayer > StarterPlayerScripts > CityLifeClient
-- Экранная часть новых механик (настройки — ReplicatedStorage > CityConfig):
--   📦 курьер: подсветка цели, стрелка-луч, таймер; персонажи несут коробку двумя руками;
--   🏆 большое золотое окно при новом достижении;
--   📷 фоторежим (из телефона): видоискатель, фильтры, зум, селфи, вспышка — жители позируют.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CityConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local RigAnimator = require(ReplicatedStorage:WaitForChild("RigAnimator"))
local remote = ReplicatedStorage:WaitForChild("PhoneRemote")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 70)
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

local function playSound(def)
	if not def or def.Id == "" then
		return
	end
	local s = new("Sound", { SoundId = def.Id, Volume = def.Volume or 0.4 }, workspace)
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local gui = new("ScreenGui", { Name = "CityLife", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5 }, playerGui)

---------------------------------------------------------------------
-- 📦 Коробка в руках (у всех персонажей с атрибутом CarryBox)
---------------------------------------------------------------------

local CARRY_POSE = {
	LeftShoulder = Vector3.new(70, 0, 8),
	RightShoulder = Vector3.new(70, 0, -8),
	LeftElbow = Vector3.new(25, 0, 0),
	RightElbow = Vector3.new(25, 0, 0),
	R6 = {
		LeftShoulder = Vector3.new(0, 0, -75),
		RightShoulder = Vector3.new(0, 0, 75),
	},
}

local function carryLayer(model: Model)
	local weight = 0
	return {
		Priority = 30,
		Update = function(rig, dt)
			local on = model:GetAttribute("CarryBox") == true
			weight = math.clamp(weight + (on and dt or -dt) * 5, 0, 1)
			if not on and weight <= 0 then
				return nil, 0, true
			end
			return RigAnimator.Frames(rig, CARRY_POSE), weight
		end,
	}
end

local function watchCharacter(character: Model)
	local function check()
		if character:GetAttribute("CarryBox") == true and not RigAnimator.HasLayer(character, "CarryBox") then
			RigAnimator.SetLayer(character, "CarryBox", carryLayer(character))
		end
	end
	character:GetAttributeChangedSignal("CarryBox"):Connect(check)
	check()
end
local function watchPlayer(p: Player)
	if p.Character then
		watchCharacter(p.Character)
	end
	p.CharacterAdded:Connect(watchCharacter)
end
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)

---------------------------------------------------------------------
-- 📦 Цель заказа: подсветка, значок, луч и карточка с таймером
---------------------------------------------------------------------

local jobCard = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.fromOffset(300, 54),
	BackgroundColor3 = Color3.fromRGB(25, 28, 40),
	BackgroundTransparency = 0.1,
	Visible = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, jobCard)
new("UIStroke", { Color = GOLD, Thickness = 1.5, Transparency = 0.3 }, jobCard)
local jobText = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 22), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, jobCard)
local jobInfo = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 18), Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.fromRGB(190, 200, 225), TextXAlignment = Enum.TextXAlignment.Left }, jobCard)

local highlight = new("Highlight", { FillColor = GOLD, FillTransparency = 0.85, OutlineColor = GOLD, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false }, camera)
local marker = new("BillboardGui", { Size = UDim2.fromOffset(60, 60), StudsOffset = Vector3.new(0, 4.2, 0), AlwaysOnTop = true, Enabled = false }, gui)
local markerIcon = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "📦", TextSize = 34, Font = Enum.Font.GothamBold }, marker)
local beamFrom = new("Attachment", { Name = "JobBeamFrom" })
local beamTo = new("Attachment", { Name = "JobBeamTo" })
local beam = new("Beam", {
	Attachment0 = beamFrom,
	Attachment1 = beamTo,
	Color = ColorSequence.new(GOLD),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.15, 0.4), NumberSequenceKeypoint.new(0.85, 0.4), NumberSequenceKeypoint.new(1, 0.9) }),
	Width0 = 0.25,
	Width1 = 0.25,
	FaceCamera = true,
	LightEmission = 0.8,
	Segments = 20,
	CurveSize0 = 6,
	CurveSize1 = -2,
	Enabled = false,
}, workspace.Terrain)
beamTo.Parent = workspace.Terrain

local function jobTarget(): Instance?
	local v = player:FindFirstChild("JobTarget")
	return v and (v :: ObjectValue).Value or nil
end

local function targetPart(target: Instance?): BasePart?
	if not target then
		return nil
	end
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		return (target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart) :: BasePart?
	end
	return nil
end

---------------------------------------------------------------------
-- 🏆 Новое достижение
---------------------------------------------------------------------

local award = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -140),
	Size = UDim2.fromOffset(340, 96),
	BackgroundColor3 = Color3.fromRGB(40, 32, 12),
	ZIndex = 50,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 20) }, award)
new("UIStroke", { Color = GOLD, Thickness = 2.5 }, award)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 225, 140), Color3.fromRGB(200, 140, 30)), Rotation = 90, Transparency = NumberSequence.new(0.75) }, award)
local awardIcon = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(72, 72), TextSize = 48, Font = Enum.Font.GothamBold, ZIndex = 51 }, award)
local awardIconScale = new("UIScale", {}, awardIcon)
new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(92, 14), Size = UDim2.new(1, -104, 0, 18), Text = "🏆 НОВОЕ ДОСТИЖЕНИЕ", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51 }, award)
local awardName = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(92, 34), Size = UDim2.new(1, -104, 0, 26), TextSize = 22, Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 51 }, award)
local awardReward = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(92, 62), Size = UDim2.new(1, -104, 0, 18), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(255, 225, 150), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51 }, award)

local awardQueue, showingAward = {}, false
local function showNextAward()
	if showingAward or #awardQueue == 0 then
		return
	end
	showingAward = true
	local a = table.remove(awardQueue, 1)
	awardIcon.Text, awardName.Text = a.icon, a.name
	awardReward.Text = string.format("+%d 🪙", a.reward)
	playSound(Sounds.Phone and Sounds.Phone.Notify)
	TweenService:Create(award, POP, { Position = UDim2.new(0.5, 0, 0, 20) }):Play()
	awardIconScale.Scale = 0.3
	TweenService:Create(awardIconScale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- Конфетти
	for _ = 1, 18 do
		local c = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.15, 0.5),
			Size = UDim2.fromOffset(7, 7),
			Rotation = math.random(0, 90),
			BackgroundColor3 = Color3.fromHSV(math.random(), 0.7, 1),
			BorderSizePixel = 0,
			ZIndex = 52,
		}, award)
		local angle = math.random() * math.pi * 2
		local dist = math.random(40, 110)
		local tween = TweenService:Create(c, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.15, math.cos(angle) * dist, 0.5, math.sin(angle) * dist),
			Rotation = c.Rotation + 180,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			c:Destroy()
		end)
	end
	task.delay(3.6, function()
		local hide = TweenService:Create(award, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -140) })
		hide:Play()
		hide.Completed:Wait()
		showingAward = false
		showNextAward()
	end)
end

remote.OnClientEvent:Connect(function(action, payload)
	if action == "Achievement" then
		table.insert(awardQueue, payload)
		showNextAward()
	end
end)

---------------------------------------------------------------------
-- 📷 Фоторежим (включается из телефона: атрибут игрока PhotoMode = true)
---------------------------------------------------------------------

local photoGui = new("ScreenGui", { Name = "PhotoMode", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false, DisplayOrder = 20 }, playerGui)
local frameLines = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, photoGui)
-- Уголки видоискателя
for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
	local x, y = c[1], c[2]
	local holder = new("Frame", { AnchorPoint = Vector2.new(x, y), Position = UDim2.new(x, x == 0 and 30 or -30, y, y == 0 and 30 or -30), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1 }, frameLines)
	new("Frame", { AnchorPoint = Vector2.new(x, y), Position = UDim2.fromScale(x, y), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, holder)
	new("Frame", { AnchorPoint = Vector2.new(x, y), Position = UDim2.fromScale(x, y), Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, holder)
end
-- Сетка третей
for i = 1, 2 do
	new("Frame", { Position = UDim2.fromScale(i / 3, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, frameLines)
	new("Frame", { Position = UDim2.fromScale(0, i / 3), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, frameLines)
end
local rec = new("TextLabel", { Position = UDim2.fromOffset(44, 40), Size = UDim2.fromOffset(160, 24), BackgroundTransparency = 1, Text = "● ФОТО", TextColor3 = Color3.fromRGB(255, 80, 80), Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left }, frameLines)

local controls = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(560, 150), BackgroundTransparency = 1 }, photoGui)
new("UISizeConstraint", { MaxSize = Vector2.new(560, 150) }, controls)

local function pill(parent: Instance, label: string, size: UDim2, position: UDim2, onClick)
	local b = new("TextButton", { Size = size, Position = position, BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.3, Text = label, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 15, AutoButtonColor = true }, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	b.Activated:Connect(onClick)
	return b
end

local filterRow = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X }, controls)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }, filterRow)

local shutter = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(84, 84), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, controls)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, shutter)
new("UIStroke", { Color = Color3.fromRGB(200, 200, 210), Thickness = 5 }, shutter)
local shutterScale = new("UIScale", {}, shutter)

local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 100 }, photoGui)
local zoomLabel = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 40), Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 1, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right }, frameLines)

local photo = { on = false, fov = 70, baseFov = 70, filter = 1, selfie = false, selfieAngle = 0, hiddenGuis = {} }
local grade = nil -- ColorCorrectionEffect фильтра

local function applyFilter(index: number)
	photo.filter = index
	local f = Config.Photo.Filters[index]
	if not grade then
		grade = new("ColorCorrectionEffect", { Name = "PhotoFilter" }, Lighting)
	end
	grade.TintColor = f.Tint or WHITE
	grade.Saturation = f.Saturation or 0
	grade.Contrast = f.Contrast or 0
	grade.Brightness = f.Brightness or 0
	for _, b in filterRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = b.LayoutOrder == index and GOLD or Color3.fromRGB(20, 22, 30)
			b.TextColor3 = b.LayoutOrder == index and Color3.fromRGB(30, 25, 10) or WHITE
		end
	end
end

for i, f in Config.Photo.Filters do
	local b = pill(filterRow, f.Name, UDim2.fromOffset(0, 34), UDim2.new(), function()
		applyFilter(i)
	end)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.LayoutOrder = i
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, b)
end

local function setZoom(fov: number)
	photo.fov = math.clamp(fov, 20, 90)
	zoomLabel.Text = string.format("🔍 %.1f×", photo.baseFov / photo.fov)
end

local exitPhoto -- объявлена ниже

pill(controls, "✕", UDim2.fromOffset(52, 52), UDim2.new(0, 10, 1, -68), function()
	exitPhoto()
end)
local selfieButton = pill(controls, "🤳 Селфи", UDim2.fromOffset(120, 44), UDim2.new(0, 72, 1, -64), function()
	photo.selfie = not photo.selfie
	photo.selfieAngle = 0
end)
pill(controls, "−", UDim2.fromOffset(44, 44), UDim2.new(1, -164, 1, -64), function()
	setZoom(photo.fov + 10)
end)
pill(controls, "+", UDim2.fromOffset(44, 44), UDim2.new(1, -112, 1, -64), function()
	setZoom(photo.fov - 10)
end)
local hideButton = pill(controls, "👁", UDim2.fromOffset(44, 44), UDim2.new(1, -56, 1, -64), function() end)

local function takePhoto()
	if not photo.on then
		return
	end
	shutterScale.Scale = 0.85
	TweenService:Create(shutterScale, POP, { Scale = 1 }):Play()
	playSound(Sounds.Phone and (Sounds.Phone.Shutter and Sounds.Phone.Shutter.Id ~= "" and Sounds.Phone.Shutter or Sounds.Phone.Tap))
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	remote:FireServer("Photo")
end
shutter.Activated:Connect(takePhoto)

-- Спрятать интерфейс на 3 секунды — чтобы сделать чистый скриншот
hideButton.Activated:Connect(function()
	controls.Visible = false
	frameLines.Visible = false
	task.delay(3, function()
		if photo.on then
			controls.Visible = true
			frameLines.Visible = true
		end
	end)
end)

local function enterPhoto()
	if photo.on then
		return
	end
	photo.on = true
	photo.baseFov = camera.FieldOfView
	setZoom(photo.baseFov)
	photo.selfie = false
	photo.hiddenGuis = {}
	for _, g in playerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= photoGui and g.Enabled then
			g.Enabled = false
			table.insert(photo.hiddenGuis, g)
		end
	end
	photoGui.Enabled = true
	controls.Visible = true
	frameLines.Visible = true
	applyFilter(photo.filter)
	ContextActionService:BindActionAtPriority("PhotoShutter", function(_, state)
		if state == Enum.UserInputState.Begin then
			takePhoto()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Return, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority("PhotoExit", function(_, state)
		if state == Enum.UserInputState.Begin then
			exitPhoto()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.P, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
end

function exitPhoto()
	if not photo.on then
		return
	end
	photo.on = false
	player:SetAttribute("PhotoMode", false)
	ContextActionService:UnbindAction("PhotoShutter")
	ContextActionService:UnbindAction("PhotoExit")
	photoGui.Enabled = false
	for _, g in photo.hiddenGuis do
		if g.Parent then
			g.Enabled = true
		end
	end
	photo.hiddenGuis = {}
	if grade then
		grade:Destroy()
		grade = nil
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = photo.baseFov
end

player:GetAttributeChangedSignal("PhotoMode"):Connect(function()
	if player:GetAttribute("PhotoMode") == true then
		enterPhoto()
	else
		exitPhoto()
	end
end)
player.CharacterRemoving:Connect(exitPhoto)

-- Селфи: поворот камеры вокруг лица — перетаскиванием мыши/пальца
UserInputService.InputChanged:Connect(function(input, processed)
	if photo.on and photo.selfie and not processed then
		if input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			or input.UserInputType == Enum.UserInputType.Touch then
			photo.selfieAngle = math.clamp(photo.selfieAngle - input.Delta.X * 0.006, -1.4, 1.4)
		end
	end
	if photo.on and input.UserInputType == Enum.UserInputType.MouseWheel then
		setZoom(photo.fov - input.Position.Z * 4)
	end
end)

---------------------------------------------------------------------
-- Каждый кадр
---------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Заказ курьера
	local stage = player:GetAttribute("JobStage")
	local target = targetPart(jobTarget())
	local active = stage ~= nil and target ~= nil and root ~= nil and not photo.on
	jobCard.Visible = stage ~= nil and not photo.on
	highlight.Enabled = active
	marker.Enabled = active
	beam.Enabled = active
	if stage then
		jobText.Text = "📦 " .. (player:GetAttribute("JobText") or "")
		local ends = player:GetAttribute("JobEnds")
		local left = ends and math.max(0, ends - workspace:GetServerTimeNow()) or 0
		local dist = (target and root) and math.floor((target.Position - root.Position).Magnitude) or 0
		jobInfo.Text = string.format("⏱ %d:%02d   📍 %d стадов", math.floor(left / 60), math.floor(left % 60), dist)
		jobInfo.TextColor3 = left < 30 and Color3.fromRGB(255, 120, 100) or Color3.fromRGB(190, 200, 225)
	end
	if active and target and root then
		local model = target:FindFirstAncestorOfClass("Model")
		highlight.Adornee = (model and model ~= workspace and model:FindFirstChildOfClass("Humanoid")) and model or target
		marker.Adornee = target
		marker.StudsOffset = Vector3.new(0, 4.2 + math.sin(now * 4) * 0.3, 0)
		markerIcon.Text = stage == "pickup" and "📦" or "🎁"
		beamFrom.Parent = root
		beamFrom.Position = Vector3.new(0, -1.5, 0)
		beamTo.WorldPosition = target.Position + Vector3.new(0, -1, 0)
		beam.TextureSpeed = 1
	end

	-- Фоторежим
	if photo.on then
		rec.TextTransparency = (now % 1 < 0.5) and 0 or 0.6
		camera.FieldOfView += (photo.fov - camera.FieldOfView) * math.min(1, dt * 10)
		local head = character and character:FindFirstChild("Head") :: BasePart?
		selfieButton.Text = photo.selfie and "🎥 Обычная" or "🤳 Селфи"
		if photo.selfie and head and root then
			camera.CameraType = Enum.CameraType.Scriptable
			local look = root.CFrame.LookVector
			local dir = (CFrame.Angles(0, photo.selfieAngle, 0) * Vector3.new(look.X, 0, look.Z)).Unit
			local eye = head.Position + dir * 6 + Vector3.new(0, 0.8, 0)
			camera.CFrame = CFrame.lookAt(eye, head.Position + Vector3.new(0, 0.2, 0))
		elseif camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end)
