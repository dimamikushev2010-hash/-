-- ModuleScript: ServerScriptService > AbilityRegistry
-- Связывает серверные скрипты способностей между собой:
--   * одна способность может мгновенно выключить другую (куб выключает полёт и невидимость);
--   * способности могут поднять персонажа из позы (сидя/лёжа).

local AbilityRegistry = {}

local stoppers = {} -- [имя] = function(player, character)
local poseStandHandler = nil

-- Атрибуты, при которых нельзя садиться/ложиться
AbilityRegistry.BlockPoseAttributes = { "Flying", "CubeForm" }

function AbilityRegistry.RegisterStopper(name: string, stop: (Player, Model) -> ())
	stoppers[name] = stop
end

function AbilityRegistry.Stop(name: string, player: Player, character: Model)
	local stop = stoppers[name]
	if stop then
		stop(player, character)
	end
end

function AbilityRegistry.SetPoseStandHandler(handler: (Model) -> ())
	poseStandHandler = handler
end

function AbilityRegistry.ForcePoseStand(character: Model)
	if poseStandHandler then
		poseStandHandler(character)
	end
end

function AbilityRegistry.BlocksPose(character: Model): boolean
	for _, attribute in AbilityRegistry.BlockPoseAttributes do
		if character:GetAttribute(attribute) == true then
			return true
		end
	end
	return false
end

return AbilityRegistry
