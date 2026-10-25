# CLAUDE.md — память проекта

Roblox-игра «город»: способности игрока, жители (NPC), транспорт, полиция, расписание, погода, телефон, курьер/магазин/награды, оружие и розыск, меню отладки. Весь код — в `PoseSystem/`.

## Кто что делает
- **Ты (Claude Code)** пишешь скрипты на Luau, документацию и сборку. В Roblox Studio не запускаешь — честно говори об этом.
- **Claude в Roblox Studio** (у владельца, с Studio MCP и доступом к GitHub) ставит скрипты из `PoseSystem/AllScripts.lua`, строит карту и метки по `PoseSystem/STUDIO_CLAUDE.md`, присылает отчёты. Владелец пересылает их тебе.
- **Владелец** говорит по-русски, отвечай по-русски, просто и без жаргона. Перед большой новой механикой задай 2+ уточняющих вопроса (через AskUserQuestion).
- Ветка: `claude/roblox-sit-lie-mechanics-4527sh`. Коммить и пушить туда.

## Где что
- `PoseSystem/ReplicatedStorage/*.lua` — ModuleScript: конфиги (`*Config`) и общие модули (`RigAnimator`, `AbilityButton`, `AbilityFx`).
- `PoseSystem/ServerScriptService/*.server.lua` — Script; `*.lua` там же — ModuleScript (`NPCRegistry`, `AbilityRegistry`, `VehicleDefaults`).
- `PoseSystem/StarterPlayerScripts/*.client.lua` — LocalScript.
- `PoseSystem/tools/build.py` — собирает `AllScripts.lua` и `PoseSystem.rbxlx`. **Новый скрипт — добавь имя в `SCRIPTS`** в этом файле.
- Документы: `MECHANICS.md` (все механики, для владельца и Studio Claude), `STUDIO_CLAUDE.md` (пошаговая инструкция для Studio Claude: метки, звуки, проверка, отчёт), `README.md`, `NPC_SETUP.md`, `VEHICLE_SETUP.md`.

## Как устроен код
- **`NPCRegistry`** — мост между серверными скриптами: каждый кладёт туда свои функции (`Registry.walkTo`, `say`, `scare`, `phoneCall`, `policeKit`, `fireShot`, `wantedCrime`, `debugEvent`…). Вызывать всегда через проверку `if Registry.x then`.
- **Сервер решает**, клиенты рисуют: состояние — через атрибуты (`workspace`, игрок, персонаж, модель) и RemoteEvent (`PhoneRemote`, `WeaponRemote`, `WantedRemote`, `CourtRemote`, `DebugRemote`, `NPCDialog`, `PoliceRemote`). Сервер проверяет всё, что присылает клиент.
- **Метки на карте** — невидимые Part с атрибутами в папках `Workspace > NPCSystem`, `TrafficSystem`, `JusticeSystem`. Новая механика должна по возможности работать **на существующих метках**; новые метки — необязательные, с запасным вариантом.
- **Доработки — только настройками** в `*Config`, не правкой кода: при обновлении Studio Claude заменяет код целиком.
- Анимации — процедурные через `RigAnimator` (слои по атрибутам, `RigAnimator.Frames`, `Vector3` в градусах; для R6 — ключ `R6`).
- Главные циклы подключай через `DebugTimer.connect(RunService.Heartbeat, "Имя", function(dt) ... end)` (`DebugTimer = require(ReplicatedStorage.DebugConfig)`) — так меню отладки видит, кто тормозит.
- Стиль: комментарии на русском, короткие и по делу; имена как в соседнем коде; табы; фразы и тексты — в конфиге.

## Каждое обновление — чеклист
1. Код + настройки в конфиге.
2. Если новый скрипт — добавь в `tools/build.py` и в список `EXPECTED` в `ServerScriptService/DebugServer.server.lua`.
3. **Запись в `DebugConfig.Changelog`** (в начало): Version, Date, Title, Summary, Details, Files, Tests (с кнопками `Action` где можно) — это вкладки «📋 Проверки» и «📜 История» в меню F2.
4. Если нужны метки — проверка в `runChecks()` в `DebugServer` и раздел в `STUDIO_CLAUDE.md`; звуки — ключи в `SoundConfig` и строки в таблице Шага 7.
5. Обнови `MECHANICS.md` (и число скриптов там, в `STUDIO_CLAUDE.md` Шаг 1 и `README.md`).
6. Проверка: `luau-compile` и `luau-analyze` по изменённым файлам (бинарники — релиз luau на GitHub: `luau-ubuntu.zip`), игнорируй шум про Roblox-глобалы и типы.
7. `cd PoseSystem && python3 tools/build.py`, коммит, пуш.
8. Ответ владельцу: что сделано (кратко, по пунктам) и **готовый текст для Studio Claude** (какие скрипты, что разметить, что проверить в F2 → «📋 Проверки», прислать «🩺 Диагностика → 📋 Скопировать для Claude»).

## Сейчас
- 52 скрипта. Последнее обновление — v2.4 «Живой суд: спор, нейросеть и новые исходы» (см. `DebugConfig.Changelog`). Суд и камеры — `CourtServer` (через `Registry.courtHolding` / `courtTrial` / `courtCommunity` / `cameraCrime` из `WantedServer`); реплики суда — `CourtAI` (нейросеть по ключу из Secrets: `CourtConfig.AI.Provider` = "gemini" (по умолчанию) или "claude"; иначе живой спор без неё).
- Меню отладки: F2 (только админ), F3 — свободная камера.
- Известные ограничения: ничего не тестировалось в Studio тобой; сверяйся с отчётами Studio Claude. Рейтинг игры 17+ (оружие, кровь).
