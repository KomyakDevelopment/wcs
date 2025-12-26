--!strict
-- Client Initialization
-- Sets up WCS, input manager, combat controller, and equipment

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Initialize menu manager FIRST (handles loading screen and continue flow)
local MenuManager = require(ReplicatedStorage.Client.managers.menuManager)
local menuManager = MenuManager.new()

-- Load loading manager (waits for server resources)
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
local VaultManager = require(ReplicatedStorage.Client.managers.vaultManager)
local WallRunManager = require(ReplicatedStorage.Client.managers.wallRunManager)
local HitEffectsManager = require(ReplicatedStorage.Client.managers.hitEffectsManager)
local BlockVFXManager = require(ReplicatedStorage.Client.managers.blockVFXManager)
local GuardbreakManager = require(ReplicatedStorage.Client.managers.guardbreakManager)
local DoubleJumpManager = require(ReplicatedStorage.Client.managers.doubleJumpManager)
local PostureUIManager = require(ReplicatedStorage.Client.managers.postureUIManager)
local HealthUIManager = require(ReplicatedStorage.Client.managers.healthUIManager)
local DeathEffectsManager = require(ReplicatedStorage.Client.managers.deathEffectsManager)
local KnockdownEffectsManager = require(ReplicatedStorage.Client.managers.knockdownEffectsManager)
local ExecutionEffectsManager = require(ReplicatedStorage.Client.managers.executionEffectsManager)
local InteractionManager = require(ReplicatedStorage.Client.managers.interactionManager)
local CarryManager = require(ReplicatedStorage.Client.managers.carryManager)
local GripEffectsManager = require(ReplicatedStorage.Client.managers.gripEffectsManager)
local CritVFXManager = require(ReplicatedStorage.Client.managers.critVFXManager)
local CombatTagUIManager = require(ReplicatedStorage.Client.managers.combatTagUIManager)
local DebugManager = require(ReplicatedStorage.Client.managers.debugManager)
local ServerInfoUIManager = require(ReplicatedStorage.Client.managers.serverInfoUIManager)
local MomentumManager = require(ReplicatedStorage.Client.managers.momentumManager)
local DynamicFOVManager = require(ReplicatedStorage.Client.managers.dynamicFOVManager)
local SettingsUIManager = require(ReplicatedStorage.Client.managers.settingsUIManager)
-- local HitboxVisualizerManager = require(ReplicatedStorage.Client.managers.hitboxVisualizerManager) -- DISABLED
local _SmoothShiftLock = require(ReplicatedStorage.Client.managers.smoothShiftLock)
local CombatController = require(ReplicatedStorage.Client.controllers.combatController)
local EquipmentController = require(ReplicatedStorage.Client.controllers.equipmentController)
local MomentumUI = require(ReplicatedStorage.Client.ui.momentumUI)

-- Initialize WCS Client
local Client = WCS.CreateClient()

Client:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Client:RegisterDirectory(ReplicatedStorage.Shared.skills)
Client:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Client:Start()

-- Initialize managers and controllers (remotes are guaranteed to exist now)
local inputManager = InputManager.new()
local sprintManager = SprintManager.new()
local vaultManager = VaultManager.new()
local wallRunManager = WallRunManager.new()
local hitEffectsManager = HitEffectsManager.new()
local blockVFXManager = BlockVFXManager.new()
local guardbreakManager = GuardbreakManager.new()
local doubleJumpManager = DoubleJumpManager.new()
local postureUIManager = PostureUIManager.new()
local healthUIManager = HealthUIManager.new()
local deathEffectsManager = DeathEffectsManager.new()
local knockdownEffectsManager = KnockdownEffectsManager.new()
local executionEffectsManager = ExecutionEffectsManager.new() -- Event-driven, listens for PlayerExecuted
local interactionManager = InteractionManager.new()
local carryManager = CarryManager.new()
local gripEffectsManager = GripEffectsManager.new() -- Event-driven, listens for GripStart/GripCancel
local critVFXManager = CritVFXManager.new() -- Event-driven, listens for PlayCritVFX
local combatTagUIManager = CombatTagUIManager.new() -- Event-driven, listens for CombatTagUpdate
local debugManager = DebugManager.new() -- Debug panels (only visible for whitelisted users)
local serverInfoUIManager = ServerInfoUIManager.new() -- Updates TopInfo UI labels
local momentumManager = MomentumManager.new() -- Momentum system for wall running and enhanced dash
local momentumUI = MomentumUI.new() -- Momentum percentage display
local dynamicFOVManager = DynamicFOVManager.new() -- Dynamic FOV based on speed/actions
local settingsUIManager = SettingsUIManager.new() -- Settings menu (ESC to open)
-- local hitboxVisualizerManager = HitboxVisualizerManager.new() -- Shows weapon hitboxes (DISABLED)

-- Link settings to managers
settingsUIManager:setDynamicFOVManager(dynamicFOVManager)
local combatController = CombatController.new()
local equipmentController = EquipmentController.new()

-- Link controllers and managers
combatController:setEquipmentController(equipmentController)
combatController:setSprintManager(sprintManager)

-- Link momentum system
wallRunManager:setMomentumManager(momentumManager)

-- Connect momentum UI to momentum manager
momentumManager:setOnMomentumChanged(function(momentum)
	momentumUI:setMomentum(momentum)
end)

-- Show UI immediately when action starts, hide when action ends
momentumManager:setOnActionStarted(function(_actionName)
	momentumUI:show()
end)

momentumManager:setOnActionEnded(function(_actionName)
	momentumUI:hide()
end)

-- When enhanced dash is triggered (Q at 100% momentum), perform the actual dodge
momentumManager:setOnTriggerEnhancedDash(function()
	combatController:performDodge()
end)

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

-- Bind movement actions
inputManager:bindAction("Movement.Slide", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		combatController:performSlide()
	end
end)

-- Hotbar keybinds (1-9, 0) are handled internally by HotbarUI
-- No need to bind them here anymore

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

-- Bind interaction actions (for knocked players)
inputManager:bindAction("Interaction.Grip", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		interactionManager:performGrip()
	end
end)

inputManager:bindAction("Interaction.Carry", function(actionName, state, input)
	if state == Enum.UserInputState.Begin then
		carryManager:performCarry()
	end
end)

-- Fade out loading screen now that everything is ready
loadingManager:fadeOut()

print("[Client] Initialization complete - Input manager, combat controller, and equipment ready")
