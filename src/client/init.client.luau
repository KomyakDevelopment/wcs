--!strict
-- Client Initialization
-- Sets up WCS, input manager, combat controller, and equipment

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- =============================================================================
-- EARLY SETTINGS LOADING
-- Apply audio settings BEFORE MenuManager to ensure correct volume from the start
-- =============================================================================
local MusicManager = require(ReplicatedStorage.Client.managers.musicManager)
local SFXManager = require(ReplicatedStorage.Client.managers.sfxManager)

local localPlayer = Players.LocalPlayer

-- Wait briefly for server to cache settings (they're loaded on PlayerAdded)
local settingsCache = localPlayer:GetAttribute("_SettingsCache")
if not settingsCache then
	-- Wait up to 1 second for settings to be cached by server
	local startTime = tick()
	while not settingsCache and (tick() - startTime) < 1 do
		task.wait(0.05)
		settingsCache = localPlayer:GetAttribute("_SettingsCache")
	end
end

-- Apply audio settings if we have cached settings
if settingsCache then
	local success, settings = pcall(function()
		return HttpService:JSONDecode(settingsCache)
	end)
	if success and settings then
		-- Apply master volume first (affects both music and SFX)
		if settings.masterVolume ~= nil then
			MusicManager.setMasterVolume(settings.masterVolume)
			SFXManager.setMasterVolume(settings.masterVolume)
		end
		-- Apply individual volumes
		if settings.musicVolume ~= nil then
			MusicManager.setVolume(settings.musicVolume)
		end
		if settings.sfxVolume ~= nil then
			SFXManager.setVolume(settings.sfxVolume)
		end
		print(
			"[Client] Applied audio settings early (master:",
			settings.masterVolume,
			"music:",
			settings.musicVolume,
			"sfx:",
			settings.sfxVolume,
			")"
		)
	end
else
	print("[Client] No cached settings found, using defaults")
end

-- =============================================================================
-- MENU AND LOADING
-- =============================================================================

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
local CrouchManager = require(ReplicatedStorage.Client.managers.crouchManager)
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
local DazeVFXManager = require(ReplicatedStorage.Client.managers.dazeVFXManager)
local DebugManager = require(ReplicatedStorage.Client.managers.debugManager)
local ServerInfoUIManager = require(ReplicatedStorage.Client.managers.serverInfoUIManager)
local MomentumManager = require(ReplicatedStorage.Client.managers.momentumManager)
local DynamicFOVManager = require(ReplicatedStorage.Client.managers.dynamicFOVManager)
local ClimbManager = require(ReplicatedStorage.Client.managers.climbManager)
local LedgeHangManager = require(ReplicatedStorage.Client.managers.ledgeHangManager)
local SettingsUIManager = require(ReplicatedStorage.Client.managers.settingsUIManager)
-- local HitboxVisualizerManager = require(ReplicatedStorage.Client.managers.hitboxVisualizerManager) -- DISABLED
local _SmoothShiftLock = require(ReplicatedStorage.Client.managers.smoothShiftLock)
local CombatController = require(ReplicatedStorage.Client.controllers.combatController)
local EquipmentController = require(ReplicatedStorage.Client.controllers.equipmentController)
local MomentumUI = require(ReplicatedStorage.Client.ui.momentumUI)

-- Initialize WCS Client
local Client = WCS.CreateClient()

Client:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Client:RegisterDirectory(ReplicatedStorage.Shared.statusEffects) -- Register BEFORE skills (skills may import status effects)
Client:RegisterDirectory(ReplicatedStorage.Shared.skills)

Client:Start()

-- Initialize managers and controllers (remotes are guaranteed to exist now)
local inputManager = InputManager.new()
local sprintManager = SprintManager.new()
local _crouchManager = CrouchManager.new() -- Self-contained, handles its own input
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
local dazeVFXManager = DazeVFXManager.new() -- Observes all WCS characters for Daze status effect
local debugManager = DebugManager.new() -- Debug panels (only visible for whitelisted users)
local serverInfoUIManager = ServerInfoUIManager.new() -- Updates TopInfo UI labels
local momentumManager = MomentumManager.new() -- Momentum system for wall running and enhanced dash
local momentumUI = MomentumUI.new() -- Momentum percentage display
local dynamicFOVManager = DynamicFOVManager.new() -- Dynamic FOV based on speed/actions
local climbManager = ClimbManager.new() -- Wall climbing system (Deepwoken-style)
local _ledgeHangManager = LedgeHangManager.new() -- Ledge hang/vault system
local settingsUIManager = SettingsUIManager.new() -- Settings menu (ESC to open)

-- Link climb manager to ledge hang manager for auto-attach when climb reaches top
climbManager:setOnClimbEndAtTop(function(wallNormal, position)
	return _ledgeHangManager:tryAutoAttachFromClimb(wallNormal, position)
end)
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
