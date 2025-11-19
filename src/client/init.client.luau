--!strict
-- Client Initialization
-- Sets up WCS, input manager, and combat controller

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local InputManager = require(ReplicatedStorage.Client.managers.inputManager)
local CombatController = require(ReplicatedStorage.Client.controllers.combatController)

-- Initialize WCS Client
local Client = WCS.CreateClient()

Client:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Client:RegisterDirectory(ReplicatedStorage.Shared.skills)
Client:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Client:Start()

-- Initialize managers and controllers
local inputManager = InputManager.new()
local combatController = CombatController.new()

-- Bind combat actions
inputManager:bindAction("Combat.PrimaryAttack", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		combatController:performPrimaryAttack()
	end
end)

inputManager:bindAction("Combat.SecondaryAttack", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		combatController:performSecondaryAttack()
	end
end)

inputManager:bindAction("Combat.Block", function(actionName, state, input)
	combatController:performBlock(state)
end)

inputManager:bindAction("Combat.Dodge", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		combatController:performDodge()
	end
end)

-- Bind ability hotkeys
for i = 1, 4 do
	inputManager:bindAction(`Abilities.Ability{i}`, function(actionName, state, input)
		if state == Enum.UserInputState.Begin then
			combatController:useAbility(i)
		end
	end)
end

-- Bind UI actions (placeholders for now)
inputManager:bindAction("UI.ToggleInventory", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		print("[Client] Toggle Inventory - Not implemented yet")
	end
end)

inputManager:bindAction("UI.ToggleCharacterSheet", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		print("[Client] Toggle Character Sheet - Not implemented yet")
	end
end)

inputManager:bindAction("UI.ToggleMap", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		print("[Client] Toggle Map - Not implemented yet")
	end
end)

print("[Client] Initialization complete - Input manager and combat controller ready")
