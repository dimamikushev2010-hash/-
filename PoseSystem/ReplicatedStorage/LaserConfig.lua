-- ModuleScript: ReplicatedStorage > LaserConfig
-- Настройки способности «Лазеры из глаз».

local LaserConfig = {}

LaserConfig.RemoteName = "LaserRequest" -- включить/выключить
LaserConfig.AimRemoteName = "LaserAim" -- куда целится игрок (часто, без гарантии доставки)

-- Атрибуты (выставляет сервер, читают все клиенты)
LaserConfig.ActiveAttribute = "LaserActive" -- на персонаже: true/false
LaserConfig.UntilAttribute = "LaserUntil" -- на персонаже: время окончания (серверное)
LaserConfig.AimAttribute = "LaserAimPoint" -- на персонаже: точка прицела (Vector3)
LaserConfig.CooldownAttribute = "LaserCooldownUntil" -- на игроке: конец кулдауна

-- Время
LaserConfig.Duration = 3 -- сколько секунд бьют лазеры
LaserConfig.Cooldown = 12 -- кулдаун после окончания
LaserConfig.CanCancelEarly = true -- повторное нажатие = выключить раньше

-- Урон
LaserConfig.DamagePerSecond = 35
LaserConfig.DamageInterval = 0.1 -- как часто сервер наносит урон, сек
LaserConfig.Range = 200 -- дальность, стады
LaserConfig.FriendlyFire = false -- бить игроков своей команды (если есть Teams)

-- Управление: целишься мышкой (на телефоне — центром экрана)
LaserConfig.Keys = { Enum.KeyCode.R, Enum.KeyCode.ButtonX }
LaserConfig.AimSendRate = 20 -- сколько раз в секунду клиент шлёт прицел
LaserConfig.TurnToAim = true -- персонаж разворачивается туда, куда стреляет

-- Внешний вид
LaserConfig.Color = Color3.fromRGB(255, 30, 30) -- внешнее свечение луча
LaserConfig.CoreColor = Color3.fromRGB(255, 220, 220) -- яркая середина луча
LaserConfig.OuterWidth = 0.35
LaserConfig.CoreWidth = 0.1
LaserConfig.ChargeTime = 0.15 -- лучи «разгораются» и гаснут за это время
LaserConfig.EyeLightRange = 5 -- красное свечение у глаз
LaserConfig.ImpactLightRange = 10 -- свечение в точке попадания
LaserConfig.SparkColor = Color3.fromRGB(255, 120, 40)

-- Звук (необязательно): вставь rbxassetid://ID любого звука лазера из Toolbox
LaserConfig.SoundId = ""
LaserConfig.SoundVolume = 0.5

-- Интерфейс
LaserConfig.ButtonText = "Лазеры"
LaserConfig.ButtonIcon = "🔴"
LaserConfig.ButtonSlot = 2 -- левее кнопки невидимости
LaserConfig.ActiveColor = Color3.fromRGB(255, 70, 70)

return LaserConfig
