-- Script: ServerScriptService > CubeServer
-- Превращение в куб. Сервер создаёт сам куб (его видят все), с лицом и
-- светящимися рёбрами, и меняет скорость/прыжок. Тело прячут клиенты,
-- а подскоки, сплющивание и сальто куба тоже рисуются на клиентах.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CubeConfig"))
local AbilityRegistry = require(script.Parent:WaitForChild("AbilityRegistry"))

local remote = ReplicatedStorage:FindFirstChild(Config.RemoteName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = Config.RemoteName
	remote.Parent = ReplicatedStorage
end

local lastRequest: { [Player]: number } = {}
local tokens: { [Player]: number } = {}

local SAVED_SPEED = "CubeSavedWalkSpeed"
local SAVED_JUMP = "CubeSavedJumpPower"
local SAVED_HEIGHT = "CubeSavedJumpHeight"

local function now(): number
	return workspace:GetServerTimeNow()
end

local function makeFace(cube: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(200, 200)
	gui.Parent = cube

	for i, x in { 0.32, 0.68 } do
		local eye = Instance.new("Frame")
		eye.Name = "Eye" .. i
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(x, 0.4)
		eye.Size = UDim2.fromScale(0.13, 0.2)
		eye.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		eye.BorderSizePixel = 0
		eye.Parent = gui
		Instance.new("UICorner", eye).CornerRadius = UDim.new(0.5, 0)

		local shine = Instance.new("Frame")
		shine.Position = UDim2.fromScale(0.2, 0.15)
		shine.Size = UDim2.fromScale(0.35, 0.3)
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BorderSizePixel = 0
		shine.Parent = eye
		Instance.new("UICorner", shine).CornerRadius = UDim.new(0.5, 0)
	end

	local mouth = Instance.new("Frame")
	mouth.Name = "Mouth"
	mouth.AnchorPoint = Vector2.new(0.5, 0.5)
	mouth.Position = UDim2.fromScale(0.5, 0.66)
	mouth.Size = UDim2.fromScale(0.2, 0.06)
	mouth.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	mouth.BorderSizePixel = 0
	mouth.Parent = gui
	Instance.new("UICorner", mouth).CornerRadius = UDim.new(0.5, 0)
end

local function createCube(character: Model, humanoid: Humanoid, hrp: BasePart): BasePart
	local legLength = humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.HipHeight or 2
	local scale = legLength / 2
	local size = Config.Size * scale
	local groundY = -(hrp.Size.Y / 2 + legLength) -- уровень земли относительно центра HumanoidRootPart
	local offsetY = groundY + size / 2

	local cube = Instance.new("Part")
	cube.Name = Config.PartName
	cube.Size = Vector3.new(size, size, size)
	cube.Color = Config.Colors[math.random(1, #Config.Colors)]
	cube.Material = Enum.Material.SmoothPlastic
	cube.TopSurface = Enum.SurfaceType.Smooth
	cube.BottomSurface = Enum.SurfaceType.Smooth
	cube.CanCollide = false
	cube.CanTouch = false
	cube.Massless = true
	cube.CFrame = hrp.CFrame * CFrame.new(0, offsetY, 0)
	cube:SetAttribute("BaseSize", size)
	cube:SetAttribute("OffsetY", offsetY)

	local weld = Instance.new("Weld")
	weld.Name = "CubeWeld"
	weld.Part0 = hrp
	weld.Part1 = cube
	weld.C0 = CFrame.new(0, offsetY, 0)
	weld.Parent = cube

	local edges = Instance.new("SelectionBox")
	edges.Name = "Edges"
	edges.Adornee = cube
	edges.LineThickness = Config.EdgeThickness * scale
	edges.Color3 = Config.EdgeColor
	edges.SurfaceTransparency = 1
	edges.Parent = cube

	local glow = Instance.new("PointLight")
	glow.Color = cube.Color
	glow.Range = 10 * scale
	glow.Brightness = 1.2
	glow.Parent = cube

	makeFace(cube)
	cube.Parent = character
	return cube
end

local function stopCube(player: Player, character: Model)
	if character:GetAttribute(Config.ActiveAttribute) ~= true then
		return
	end
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	player:SetAttribute(Config.CooldownAttribute, now() + Config.Cooldown)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:GetAttribute(SAVED_SPEED) ~= nil then
		humanoid.WalkSpeed = humanoid:GetAttribute(SAVED_SPEED)
		humanoid.JumpPower = humanoid:GetAttribute(SAVED_JUMP)
		humanoid.JumpHeight = humanoid:GetAttribute(SAVED_HEIGHT)
		humanoid:SetAttribute(SAVED_SPEED, nil)
		humanoid:SetAttribute(SAVED_JUMP, nil)
		humanoid:SetAttribute(SAVED_HEIGHT, nil)
	end

	-- Даём клиентам анимировать сжатие куба, потом убираем его
	local cube = character:FindFirstChild(Config.PartName)
	if cube then
		task.delay(Config.PopOutTime, function()
			if character:GetAttribute(Config.ActiveAttribute) ~= true then
				cube:Destroy()
			end
		end)
	end
end

local function startCube(player: Player, character: Model, humanoid: Humanoid)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	AbilityRegistry.Stop("Invisibility", player, character)
	AbilityRegistry.Stop("Flight", player, character)
	AbilityRegistry.ForcePoseStand(character)

	-- Старый куб (если ещё не успел исчезнуть) убираем сразу
	local old = character:FindFirstChild(Config.PartName)
	if old then
		old:Destroy()
	end
	createCube(character, humanoid, hrp)

	humanoid:SetAttribute(SAVED_SPEED, humanoid.WalkSpeed)
	humanoid:SetAttribute(SAVED_JUMP, humanoid.JumpPower)
	humanoid:SetAttribute(SAVED_HEIGHT, humanoid.JumpHeight)
	humanoid.WalkSpeed = Config.WalkSpeed
	humanoid.JumpPower = Config.JumpPower
	humanoid.JumpHeight = Config.JumpPower * Config.JumpPower / (2 * workspace.Gravity)

	local token = (tokens[player] or 0) + 1
	tokens[player] = token
	character:SetAttribute(Config.UntilAttribute, now() + Config.Duration)
	character:SetAttribute(Config.ActiveAttribute, true)

	task.delay(Config.Duration, function()
		if tokens[player] == token and character.Parent then
			stopCube(player, character)
		end
	end)
end

AbilityRegistry.RegisterStopper("Cube", stopCube)

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
			stopCube(player, character)
		end
		return
	end

	if humanoid.Sit or now() < (player:GetAttribute(Config.CooldownAttribute) or 0) then
		return
	end

	startCube(player, character, humanoid)
end)

local function onCharacterAdded(player: Player, character: Model)
	character:SetAttribute(Config.ActiveAttribute, false)
	character:SetAttribute(Config.UntilAttribute, 0)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			stopCube(player, character)
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
