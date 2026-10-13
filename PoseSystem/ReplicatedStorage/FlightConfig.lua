-- ModuleScript: ReplicatedStorage > FlightConfig
-- Настройки способности «Полёт».

local FlightConfig = {}

FlightConfig.RemoteName = "FlightRequest"

FlightConfig.ActiveAttribute = "Flying" -- на персонаже: true/false
FlightConfig.UntilAttribute = "FlyingUntil" -- на персонаже: время окончания
FlightConfig.CooldownAttribute = "FlightCooldownUntil" -- на игроке: конец кулдауна

-- Время
FlightConfig.Duration = 15 -- сколько секунд можно летать
FlightConfig.Cooldown = 10 -- кулдаун после приземления
FlightConfig.CanCancelEarly = true

-- Управление:
--   WASD / стик — лететь туда, куда смотрит камера (вверх/вниз тоже)
--   Пробел — вверх, Ctrl или C — вниз
FlightConfig.Keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonL1 }
FlightConfig.UpKeys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA }
FlightConfig.DownKeys = { Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB }

-- Физика
FlightConfig.Speed = 45 -- обычная скорость
FlightConfig.MaxSpeed = 95 -- разгон, если долго лететь в одну сторону
FlightConfig.BoostTime = 2.5 -- за сколько секунд разгоняешься до максимума
FlightConfig.Acceleration = 4 -- насколько резко меняется скорость (больше = резче)
FlightConfig.LaunchSpeed = 45 -- рывок вверх при взлёте
FlightConfig.MaxPitch = 165 -- насколько можно наклониться (90 = горизонтально, 165 = пике вниз)
FlightConfig.TurnResponsiveness = 18 -- как быстро тело поворачивается
FlightConfig.BankStrength = 0.35 -- крен в поворотах

-- Эффекты
FlightConfig.FovBoost = 18 -- насколько расширяется обзор на скорости
FlightConfig.TrailColor = Color3.fromRGB(200, 230, 255)
FlightConfig.BoomColor = Color3.fromRGB(220, 240, 255) -- «звуковой удар» на максимальной скорости
FlightConfig.LandingMinFallSpeed = 30 -- с какой скорости падения будет «супергеройское» приземление

-- Интерфейс
FlightConfig.ButtonText = "Полёт"
FlightConfig.ButtonIcon = "🦅"
FlightConfig.ButtonSlot = 3
FlightConfig.ActiveColor = Color3.fromRGB(140, 220, 255)

return FlightConfig
