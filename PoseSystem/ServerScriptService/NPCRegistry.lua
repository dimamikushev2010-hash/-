-- ModuleScript: ServerScriptService > NPCRegistry
-- Мост между жителями (NPCServer) и транспортом (TrafficServer).
-- NPCServer кладёт сюда свои функции, TrafficServer — свои, и они вызывают друг друга.

local NPCRegistry = {}

-- Заполняет NPCServer:
--   npcs                         — таблица [model] = npc
--   walkTo(npc, position) → bool
--   say(npc, text, duration?)
--   setMood(npc, moodKey?, duration?)
--   setPose(npc, pose)
--   face(npc, direction, time?)
--   spawnCustom(cframe, options) → npc   (жители без обычного «мозга», например полицейские)
NPCRegistry.npcs = {}

-- Заполняет TrafficServer:
--   assignCar(npc)                         — дать жителю машину, если есть свободная
--   tryTrip(npc, targetPosition) → bool    — доехать (своя машина, такси или автобус); false — идти пешком
NPCRegistry.assignCar = nil
NPCRegistry.tryTrip = nil

return NPCRegistry
