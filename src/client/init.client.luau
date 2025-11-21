--!strict
-- Client Initialization
-- Sets up WCS, input manager, combat controller, and equipment

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local InputManager = require(ReplicatedStorage.Client.managers.inputManager)
local SprintManager = require(ReplicatedStorage.Client.managers.sprintManager)
local HitEffectsManager = require(ReplicatedStorage.Client.managers.hitEffectsManager)
local BlockVFXManager = require(ReplicatedStorage.Client.managers.blockVFXManager)
local CombatController = require(ReplicatedStorage.Client.controllers.combatController)
local EquipmentController = require(ReplicatedStorage.Client.controllers.equipmentController)

-- Initialize WCS Client
local Client = WCS.CreateClient()

Client:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Client:RegisterDirectory(ReplicatedStorage.Shared.skills)
Client:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Client:Start()

-- Initialize managers and controllers
local inputManager = InputManager.new()
local sprintManager = SprintManager.new()
local hitEffectsManager = HitEffectsManager.new() -- Handles client-side hit effects replication
local blockVFXManager = BlockVFXManager.new() -- Handles block/parry VFX
local combatController = CombatController.new()
local equipmentController = EquipmentController.new()

-- Link controllers and managers
combatController:setEquipmentController(equipmentController)
combatController:setSprintManager(sprintManager)

-- Create BindableEvent for dodge -> sprint communication
local resumeSprintEvent = Instance.new("BindableEvent")
resumeSprintEvent.Name = "ResumeSprintAfterDodge"
resumeSprintEvent.Parent = ReplicatedStorage

-- Connect sprint resume handler
resumeSprintEvent.Event:Connect(function()
	sprintManager:resumeSprintIfHoldingW()
end)

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

inputManager:bindAction("Combat.Block", function(_actionName, state, _input)
	combatController:performBlock(state)
end)

inputManager:bindAction("Combat.Dodge", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		combatController:performDodge()
	end
end)

-- Bind ability hotkeys (slot 1 now SELECTS fists, M1 to confirm)
inputManager:bindAction(`Abilities.Ability1`, function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		equipmentController:selectSlot(1)
	end
end)

-- Slots 2-4 for future abilities
for i = 2, 4 do
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

print("[Client] Initialization complete - Input manager, combat controller, and equipment ready")
