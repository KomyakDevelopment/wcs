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
		print("[Client] Applied audio settings early (master:", settings.masterVolume, "music:", settings.musicVolume, "sfx:", settings.sfxVolume, ")")
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

-- Enhanced slide jump configuration
local ENHANCED_SLIDE_JUMP_POWER = 120 -- Powerful upward velocity
local ENHANCED_SLIDE_JUMP_FORWARD_BOOST = 30 -- Forward momentum boost
local ENHANCED_SLIDE_JUMP_ANIMATION = "rbxassetid://131915305278984" -- Same as enhanced dash

-- When enhanced slide jump is triggered (Q at 100% momentum while sliding)
momentumManager:setOnTriggerEnhancedSlideJump(function()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoid or not hrp then return end

	-- End the current slide by getting the slide skill and ending it
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if wcsCharacter then
		local Slide = require(ReplicatedStorage.Shared.skills.slide)
		local slideSkill = wcsCharacter:GetSkillFromConstructor(Slide)
		if slideSkill then
			local state = slideSkill:GetState()
			if state.IsActive then
				slideSkill:End()
			end
		end
	end

	-- Apply enhanced jump velocity
	local lookVector = hrp.CFrame.LookVector
	local forwardBoost = Vector3.new(lookVector.X, 0, lookVector.Z).Unit * ENHANCED_SLIDE_JUMP_FORWARD_BOOST
	hrp.AssemblyLinearVelocity = Vector3.new(forwardBoost.X, ENHANCED_SLIDE_JUMP_POWER, forwardBoost.Z)

	-- Play enhanced animation
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = ENHANCED_SLIDE_JUMP_ANIMATION
		local animTrack = animator:LoadAnimation(animation)
		animTrack.Priority = Enum.AnimationPriority.Action2
		animTrack:Play(0.05)
	end

	-- Play VFX (use air dash VFX)
	local airDashVFXSource = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Movement")
		and ReplicatedStorage.Assets.VFX.Movement:FindFirstChild("air_dash")
		and ReplicatedStorage.Assets.VFX.Movement.air_dash:FindFirstChild("smoke")

	if airDashVFXSource then
		local vfxClone = airDashVFXSource:Clone()
		vfxClone.Parent = hrp

		-- Emit particles
		local maxLifetime = 0
		for _, child in ipairs(vfxClone:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				local emitCount = child:GetAttribute("EmitCount") or 5
				child:Emit(emitCount)
				local lifetime = child.Lifetime.Max
				if lifetime > maxLifetime then
					maxLifetime = lifetime
				end
			end
		end

		-- Cleanup after particles fade
		task.delay(maxLifetime + 0.5, function()
			if vfxClone and vfxClone.Parent then
				vfxClone:Destroy()
			end
		end)
	end

	-- Play SFX (use air dash SFX)
	local airDashSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("SFX")
		and ReplicatedStorage.Assets.SFX:FindFirstChild("Movement")
		and ReplicatedStorage.Assets.SFX.Movement:FindFirstChild("Airdash")

	if airDashSFXFolder then
		local sounds = {}
		for _, child in ipairs(airDashSFXFolder:GetChildren()) do
			if child:IsA("Sound") then
				table.insert(sounds, child)
			end
		end

		if #sounds > 0 then
			local randomSound = sounds[math.random(1, #sounds)]
			local soundClone = randomSound:Clone()
			soundClone.SoundGroup = SFXManager.getSoundGroup()
			soundClone.Parent = hrp
			soundClone:Play()

			task.delay(soundClone.TimeLength + 0.1, function()
				if soundClone and soundClone.Parent then
					soundClone:Destroy()
				end
			end)
		end
	end

	print("[Client] Enhanced slide jump performed!")
end)

-- Track slide state for momentum system
local slideAttributeConnection: RBXScriptConnection? = nil

local function setupSlideTracking(character: Model)
	-- Disconnect previous connection
	if slideAttributeConnection then
		slideAttributeConnection:Disconnect()
		slideAttributeConnection = nil
	end

	-- Listen for _SlideActive attribute changes
	slideAttributeConnection = character:GetAttributeChangedSignal("_SlideActive"):Connect(function()
		local isSliding = character:GetAttribute("_SlideActive") == true
		if isSliding then
			momentumManager:startAction("Slide")
		else
			momentumManager:endAction("Slide")
		end
	end)
end

-- Setup for current character
if localPlayer.Character then
	setupSlideTracking(localPlayer.Character)
end

-- Setup for future characters (respawns)
localPlayer.CharacterAdded:Connect(function(character)
	setupSlideTracking(character)
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
