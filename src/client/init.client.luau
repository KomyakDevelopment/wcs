--!strict
-- Client Initialization
-- Sets up WCS, input manager, combat controller, and equipment

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Load loading manager FIRST (shows black screen immediately)
local LoadingManager = require(ReplicatedStorage.Client.managers.loadingManager)
local loadingManager = LoadingManager.new()

-- Wait for server to be ready (remotes, character, etc.)
if not loadingManager:load() then
	warn("[Client] Failed to load - some resources not available")
end

-- Now safe to require modules that depend on remotes
local WCS = require(ReplicatedStorage.Packages.wcs)
local InputManager = require(ReplicatedStorage.Client.managers.inputManager)
local SprintManager = require(ReplicatedStorage.Client.managers.sprintManager)
local HitEffectsManager = require(ReplicatedStorage.Client.managers.hitEffectsManager)
local BlockVFXManager = require(ReplicatedStorage.Client.managers.blockVFXManager)
local GuardbreakManager = require(ReplicatedStorage.Client.managers.guardbreakManager)
local DoubleJumpManager = require(ReplicatedStorage.Client.managers.doubleJumpManager)
local PostureUIManager = require(ReplicatedStorage.Client.managers.postureUIManager)
local HealthUIManager = require(ReplicatedStorage.Client.managers.healthUIManager)
local DeathEffectsManager = require(ReplicatedStorage.Client.managers.deathEffectsManager)
local KnockdownEffectsManager = require(ReplicatedStorage.Client.managers.knockdownEffectsManager)
local CombatController = require(ReplicatedStorage.Client.controllers.combatController)
local EquipmentController = require(ReplicatedStorage.Client.controllers.equipmentController)

-- Initialize WCS Client
local Client = WCS.CreateClient()

Client:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Client:RegisterDirectory(ReplicatedStorage.Shared.skills)
Client:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Client:Start()

-- Initialize managers and controllers (remotes are guaranteed to exist now)
local inputManager = InputManager.new()
local sprintManager = SprintManager.new()
local hitEffectsManager = HitEffectsManager.new()
local blockVFXManager = BlockVFXManager.new()
local guardbreakManager = GuardbreakManager.new()
local doubleJumpManager = DoubleJumpManager.new()
local postureUIManager = PostureUIManager.new()
local healthUIManager = HealthUIManager.new()
local deathEffectsManager = DeathEffectsManager.new()
local knockdownEffectsManager = KnockdownEffectsManager.new()
local combatController = CombatController.new()
local equipmentController = EquipmentController.new()

-- Link controllers and managers
combatController:setEquipmentController(equipmentController)
combatController:setSprintManager(sprintManager)

-- Create BindableEvent for dodge -> sprint communication
local resumeSprintEvent = Instance.new("BindableEvent")
resumeSprintEvent.Name = "ResumeSprintAfterDodge"
resumeSprintEvent.Parent = ReplicatedStorage

-- Connect sprint resume handler (called when dodge ends)
resumeSprintEvent.Event:Connect(function()
	sprintManager:resumeSprintIfHoldingW()
end)

-- Bind combat actions
inputManager:bindAction("Combat.PrimaryAttack", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		combatController:setM1Held(true)
		combatController:performPrimaryAttack()
	elseif state == Enum.UserInputState.End then
		combatController:setM1Held(false)
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

inputManager:bindAction("Combat.CriticalAttack", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		combatController:performCriticalAttack()
	end
end)

-- Bind hotbar slots (1 = fists, 2 = kunai)
inputManager:bindAction(`Abilities.Ability1`, function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		equipmentController:selectSlot(1)
	end
end)

inputManager:bindAction(`Abilities.Ability2`, function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		equipmentController:selectSlot(2)
	end
end)

-- Slots 3-4 for future abilities
for i = 3, 4 do
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

-- Fade out loading screen now that everything is ready
loadingManager:fadeOut()

print("[Client] Initialization complete - Input manager, combat controller, and equipment ready")
