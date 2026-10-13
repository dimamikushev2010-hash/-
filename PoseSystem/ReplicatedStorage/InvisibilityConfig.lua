-- ModuleScript: ReplicatedStorage > InvisibilityConfig
-- Настройки способности «Невидимость».

local InvisibilityConfig = {}

InvisibilityConfig.RemoteName = "InvisibilityRequest"

-- Атрибуты (выставляет сервер, читают все клиенты)
InvisibilityConfig.ActiveAttribute = "Invisible" -- на персонаже: true/false
InvisibilityConfig.UntilAttribute = "InvisibleUntil" -- на персонаже: время окончания (серверное)
InvisibilityConfig.CooldownAttribute = "InvisibilityCooldownUntil" -- на игроке: конец кулдауна

-- Время
InvisibilityConfig.Duration = 8 -- сколько длится невидимость, сек
InvisibilityConfig.Cooldown = 20 -- кулдаун, отсчитывается после окончания невидимости
InvisibilityConfig.CanCancelEarly = true -- повторное нажатие = выйти раньше
InvisibilityConfig.FadeTime = 0.5 -- плавное исчезновение/появление, сек

-- Управление
InvisibilityConfig.Keys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonY }

-- Как ты видишь себя: «стекло»
InvisibilityConfig.SelfTransparency = 0.6 -- 0 = как обычно, 1 = совсем не видно
InvisibilityConfig.SelfMaterial = Enum.Material.Glass
InvisibilityConfig.SelfTint = Color3.fromRGB(170, 215, 255) -- голубоватый оттенок
InvisibilityConfig.SelfTintStrength = 0.35 -- 0 = без оттенка, 1 = полностью голубой

-- Лёгкая синева на экране, пока ты невидим
InvisibilityConfig.ScreenTint = Color3.fromRGB(215, 230, 255)
InvisibilityConfig.ScreenSaturation = -0.15

-- Красная подсветка при выходе из невидимости (её видят все)
InvisibilityConfig.FlashColor = Color3.fromRGB(255, 40, 40)
InvisibilityConfig.FlashTime = 1.5 -- сколько держится и гаснет, сек
InvisibilityConfig.FlashFillTransparency = 0.8 -- слабое свечение внутри тела

-- Что скрывать у невидимого игрока от других
InvisibilityConfig.HideName = true -- ник и полоска здоровья
InvisibilityConfig.HideSounds = true -- шаги и прочие звуки персонажа

-- Интерфейс
InvisibilityConfig.ButtonText = "Невидимость"
InvisibilityConfig.ActiveColor = Color3.fromRGB(120, 200, 255)

return InvisibilityConfig
