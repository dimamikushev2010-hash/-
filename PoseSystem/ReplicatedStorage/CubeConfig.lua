-- ModuleScript: ReplicatedStorage > CubeConfig
-- Настройки способности «Превращение в куб».

local CubeConfig = {}

CubeConfig.RemoteName = "CubeRequest"

CubeConfig.ActiveAttribute = "CubeForm" -- на персонаже: true/false
CubeConfig.UntilAttribute = "CubeFormUntil" -- на персонаже: время окончания
CubeConfig.CooldownAttribute = "CubeCooldownUntil" -- на игроке: конец кулдауна
CubeConfig.PartName = "AbilityCube" -- деталь-куб внутри персонажа

-- Время
CubeConfig.Duration = 15
CubeConfig.Cooldown = 15
CubeConfig.CanCancelEarly = true
CubeConfig.PopTime = 0.5 -- «выпрыгивание» куба с пружинкой
CubeConfig.PopOutTime = 0.35 -- сжатие куба при выходе

CubeConfig.Keys = { Enum.KeyCode.T, Enum.KeyCode.ButtonR1 }

-- Внешний вид
CubeConfig.Size = 4 -- размер куба для персонажа обычного роста
CubeConfig.Colors = { -- цвет выбирается случайно при каждом превращении
	Color3.fromRGB(255, 170, 40),
	Color3.fromRGB(60, 200, 255),
	Color3.fromRGB(255, 80, 160),
	Color3.fromRGB(120, 230, 90),
	Color3.fromRGB(170, 110, 255),
	Color3.fromRGB(255, 225, 60),
}
CubeConfig.EdgeColor = Color3.fromRGB(255, 255, 255) -- светящиеся рёбра
CubeConfig.EdgeThickness = 0.08

-- Движение в форме куба
CubeConfig.WalkSpeed = 22
CubeConfig.JumpPower = 65 -- куб прыгучий
CubeConfig.HopHeight = 0.9 -- высота подскоков при ходьбе
CubeConfig.HopRate = 2.6 -- подскоков в секунду

-- Интерфейс
CubeConfig.ButtonText = "Куб"
CubeConfig.ButtonIcon = "🧊"
CubeConfig.ButtonSlot = 4
CubeConfig.ActiveColor = Color3.fromRGB(255, 190, 70)

return CubeConfig
