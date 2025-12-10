--!strict
-- Sprint Manager
-- Handles double-tap sprint detection and sprint state management
-- Works independently of WCS movesets - always available to the player

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local WCS = require(ReplicatedStorage.Packages.wcs)
local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking)

-- Pre-cache attack skill references for client-side state checks
local Punch = require(ReplicatedStorage.Shared.skills.punch)
local Slash = require(ReplicatedStorage.Shared.skills.slash)

local SprintManager = {}
SprintManager.__index = SprintManager

-- Configuration
local SPRINT_SPEED_MULTIPLIER = 1.75 -- 175% of normal walk speed (16 -> 28)
local DOUBLE_TAP_WINDOW = 0.4 -- Time window to detect double tap (seconds) - increased for better detection
local MIN_SPRINT_VELOCITY = 3 -- Minimum velocity to maintain sprint - lowered for better fluidity
local SPRINT_GRACE_PERIOD = 0.3 -- Grace period before checking velocity after sprint starts
local LANDING_GRACE_PERIOD = 0.3 -- Grace period after landing before velocity check applies
local BACKWARD_SPEED_PENALTY = 0.85 -- 15% slower when holding S (backward movement)

-- Animation
local SPRINT_ANIMATION_ID = "rbxassetid://94461174611915"
local SPRINT_RIGHTARM_ANIMATION_ID = "rbxassetid://122819437317127" -- Plays when weapon equipped
local SPRINT_ANIM_SPEED_NORMAL = 1.0 -- Normal sprint animation speed
local SPRINT_ANIM_SPEED_AIRBORNE = 0.3 -- Slowed animation speed while mid-air
local ANIM_SPEED_TRANSITION_TIME = 0.15 -- How quickly to transition between speeds

-- Movement keys for double-tap detection
local MOVEMENT_KEYS = {
	[Enum.KeyCode.W] = "Forward",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.S] = "Backward",
	[Enum.KeyCode.D] = "Right",
}

function SprintManager.new()
	local self = setmetatable({}, SprintManager)

	-- State tracking
	self.doubleTapReady = {} -- Tracks if first tap occurred for each key
	self.doubleTapTimers = {} -- Tracks timeout tasks for each key
	self.sprintActive = false
	self.loadedAnimation = nil
	self.loadedRightArmAnimation = nil -- Right arm animation for when weapon is equipped
	self.currentAnimTrack = nil
	self.currentRightArmTrack = nil -- Right arm animation track
	self.sprintDirection = nil
	self.baseWalkSpeed = 16 -- Default walkspeed
	self.sprintStartTime = 0 -- Track when sprint started for grace period
	self.postDodgeGraceEnd = 0 -- Track when post-dodge grace period ends
	self.wasSprintingBeforeDodge = false -- Track if player was sprinting before dodge
	self.isAirborne = false -- Track if player is mid-air for animation speed adjustment
	self.currentAnimSpeed = SPRINT_ANIM_SPEED_NORMAL -- Track current animation speed
	self.isHoldingBackward = false -- Track if S key is held for backward speed penalty
	self.lastLandingTime = 0 -- Track when player last landed (for landing grace period)

	-- Setup
	self:_initialize()

	return self
end

function SprintManager:_initialize()
	local player = Players.LocalPlayer

	-- Setup character (current and future)
	if player.Character then
		self:_setupCharacter(player.Character)
	end

	-- Handle respawns - reinitialize for each new character
	player.CharacterAdded:Connect(function(character)
		-- Stop any active sprint from old character
		self.sprintActive = false
		self.loadedAnimation = nil
		self.loadedRightArmAnimation = nil
		self.currentAnimTrack = nil
		self.currentRightArmTrack = nil
		self.isAirborne = false
		self.currentAnimSpeed = SPRINT_ANIM_SPEED_NORMAL
		self.isHoldingBackward = false
		self.lastLandingTime = 0

		-- Wait for character to be fully loaded
		character:WaitForChild("Humanoid", 10)

		self:_setupCharacter(character)
		print("[SprintManager] Reinitialized for new character")
	end)

	-- Setup double-tap detection
	self:_setupDoubleTapDetection()

	-- Monitor sprint state
	self:_monitorSprint()

	-- Monitor backward movement for speed penalty
	self:_monitorBackwardMovement()

	print("[SprintManager] Initialized")
end

-- Setup sprint for a specific character
function SprintManager:_setupCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		warn("[SprintManager] Humanoid not found")
		return
	end

	self.baseWalkSpeed = humanoid.WalkSpeed

	-- Load sprint animation for this character's animator
	-- Use robust retry logic since Animator may not exist immediately on fast loads
	task.spawn(function()
		local animator = humanoid:FindFirstChildOfClass("Animator")

		-- If no animator, wait for it to be added (up to 5 seconds)
		if not animator then
			local waitStart = tick()
			while not animator and tick() - waitStart < 5 do
				animator = humanoid:WaitForChild("Animator", 1)
				if animator then
					break
				end
				task.wait(0.1)
			end
		end

		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = SPRINT_ANIMATION_ID
			self.loadedAnimation = animator:LoadAnimation(animation)

			-- Also load right arm animation for when weapon is equipped
			local rightArmAnimation = Instance.new("Animation")
			rightArmAnimation.AnimationId = SPRINT_RIGHTARM_ANIMATION_ID
			self.loadedRightArmAnimation = animator:LoadAnimation(rightArmAnimation)

			print("[SprintManager] Sprint animations loaded for character")
		else
			warn("[SprintManager] Animator not found after 5 second wait - sprint animation unavailable")
		end
	end)

	-- Store base walk speed on character setup
	self.baseWalkSpeed = humanoid.WalkSpeed

	-- PROTECT against external WalkSpeed changes while sprinting
	-- Something else (status effects, animations, equipment) might reset WalkSpeed
	-- BUT respect intentional speed locks (grip, stun, etc. set WalkSpeed to 0)
	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if self.sprintActive then
			-- If WalkSpeed is 0 or very low, it's intentional (grip, stun, etc.) - stop sprint
			if humanoid.WalkSpeed <= 1 then
				print(`[SprintManager] WalkSpeed set to {humanoid.WalkSpeed} (grip/stun) - stopping sprint`)
				self:_stopSprint()
				return
			end

			-- Calculate expected sprint speed (with backward penalty if applicable)
			local holdingS = UserInputService:IsKeyDown(Enum.KeyCode.S)
			local expectedSpeed = holdingS
				and (self.baseWalkSpeed * SPRINT_SPEED_MULTIPLIER * BACKWARD_SPEED_PENALTY)
				or (self.baseWalkSpeed * SPRINT_SPEED_MULTIPLIER)

			-- If WalkSpeed was changed to something unexpected, restore it
			if math.abs(humanoid.WalkSpeed - expectedSpeed) > 0.1 then
				print(`[SprintManager] WalkSpeed changed externally to {humanoid.WalkSpeed}, restoring to {expectedSpeed}`)
				task.defer(function()
					if humanoid and humanoid.Parent and self.sprintActive then
						humanoid.WalkSpeed = expectedSpeed
					end
				end)
			end
		end
	end)
end

-- Setup double-tap detection for movement keys
function SprintManager:_setupDoubleTapDetection()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		-- Check if it's a movement key
		local direction = MOVEMENT_KEYS[input.KeyCode]
		if not direction then
			return
		end

		-- Check if sprint is already active
		if self.sprintActive then
			return
		end

		local keyCode = input.KeyCode

		-- Check if this is the second tap (double-tap ready is true)
		if self.doubleTapReady[keyCode] == true then
			-- Double tap detected!
			self:_handleDoubleTap(direction)

			-- Cancel the timeout timer
			if self.doubleTapTimers[keyCode] then
				task.cancel(self.doubleTapTimers[keyCode])
				self.doubleTapTimers[keyCode] = nil
			end

			-- Reset double-tap state
			self.doubleTapReady[keyCode] = false
		else
			-- First tap - set ready state and start timeout
			self.doubleTapReady[keyCode] = true

			-- Start timeout to reset if second tap doesn't come
			self.doubleTapTimers[keyCode] = task.delay(DOUBLE_TAP_WINDOW, function()
				if self.doubleTapReady[keyCode] == true then
					self.doubleTapReady[keyCode] = false
				end
			end)
		end
	end)
end

-- Handle double-tap sprint activation
function SprintManager:_handleDoubleTap(direction: string)
	-- Check if player is blocking - don't start sprint while blocking
	if self:_isBlocking() then
		print("[SprintManager] Double-tap ignored - Player is blocking")
		return
	end

	-- Check if player is attacking (M1 windup) - don't start sprint
	if self:_isAttacking() then
		print("[SprintManager] Double-tap ignored - Player is attacking")
		return
	end

	-- Check if player is in shiftlock
	local isShiftLock = self:_isInShiftLock()

	-- Determine sprint direction based on mode
	local sprintDirection = direction

	if isShiftLock then
		-- In shiftlock, only W-W (forward) triggers sprint
		if direction ~= "Forward" then
			return
		end
	else
		-- Not in shiftlock - check camera-relative direction
		-- If pressing S while looking backward, treat as forward sprint
		if direction == "Backward" then
			sprintDirection = self:_getActualSprintDirection()
		end
	end

	self.sprintDirection = sprintDirection
	print(`[SprintManager] Double-tap detected: {direction} -> Sprint: {sprintDirection}`)

	-- Start sprint
	self:_startSprint()
end

-- Check if player is currently attacking (has Attacking status effect OR attack skill is active)
-- We check BOTH because status effect might not replicate fast enough from server
function SprintManager:_isAttacking(): boolean
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return false
	end

	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if not wcsCharacter then
		return false
	end

	-- Check status effect first (authoritative from server)
	if wcsCharacter:HasStatusEffects({ Attacking, HeavyAttacking }) then
		return true
	end

	-- Also check if M1 skill is currently active (client-side state check for faster response)
	local punchSkill = wcsCharacter:GetSkillFromConstructor(Punch)
	if punchSkill then
		local state = punchSkill:GetState()
		if state.IsActive then
			return true
		end
	end

	local slashSkill = wcsCharacter:GetSkillFromConstructor(Slash)
	if slashSkill then
		local state = slashSkill:GetState()
		if state.IsActive then
			return true
		end
	end

	return false
end

-- Check if player is currently blocking
function SprintManager:_isBlocking(): boolean
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return false
	end

	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if not wcsCharacter then
		return false
	end

	return wcsCharacter:HasStatusEffects({ Blocking })
end

-- Check if player has a weapon in hand (selected and drawn, not just equipped)
function SprintManager:_isWeaponInHand(): boolean
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return false
	end

	-- Check both conditions: weapon must be equipped (not fists) AND in hand
	local equippedWeapon = character:GetAttribute("EquippedWeapon")
	local weaponInHand = character:GetAttribute("WeaponInHand")

	-- Must have a real weapon (not fists) and it must be in hand
	if equippedWeapon and equippedWeapon ~= "fists" and weaponInHand == true then
		return true
	end

	return false
end

-- Start sprint
function SprintManager:_startSprint()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return
	end

	-- Check if player has any status effects that prevent sprinting
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if wcsCharacter then
		local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
		local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
		local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
		local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)

		if wcsCharacter:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Dashing }) then
			print("[SprintManager] Blocked - Player is in hitstun/stun/dashing")
			return
		end
	end

	-- Check if player is attacking (M1 windup) - don't start sprint
	if self:_isAttacking() then
		print("[SprintManager] Blocked - Player is attacking")
		return
	end

	self.sprintActive = true
	self.sprintStartTime = tick() -- Record sprint start time

	-- Set attribute so other systems (block, etc.) can check sprint state
	if character then
		character:SetAttribute("IsSprinting", true)
		-- Sync to server so server-side checks work too
		local sprintRemote = ReplicatedStorage:FindFirstChild("SprintStateChanged") :: RemoteEvent?
		if sprintRemote then
			sprintRemote:FireServer(true)
		end
	end

	-- Set a brief grace period for directional checks (helps with initial sprint and post-dodge)
	-- Only set if not already in a grace period (don't override longer post-dodge grace)
	if tick() >= self.postDodgeGraceEnd then
		self.postDodgeGraceEnd = tick() + 0.3 -- 0.3s grace for normal sprint start
	end

	-- Play sprint animation
	if self.loadedAnimation then
		self.currentAnimTrack = self.loadedAnimation
		self.currentAnimTrack:Play(0.1) -- Smooth transition
		print("[SprintManager] Playing sprint animation")

		-- Check if player is currently airborne and adjust animation speed accordingly
		-- This handles cases like resuming sprint after airdash while still in the air
		if self:_isPlayerAirborne() then
			self.isAirborne = true
			self:_adjustAnimationSpeed(SPRINT_ANIM_SPEED_AIRBORNE)
			print("[SprintManager] Started airborne - animation slowed")
		else
			self.isAirborne = false
			self:_adjustAnimationSpeed(SPRINT_ANIM_SPEED_NORMAL)
		end
	end

	-- Play right arm animation if weapon is in hand (selected)
	if self.loadedRightArmAnimation and self:_isWeaponInHand() then
		self.currentRightArmTrack = self.loadedRightArmAnimation
		self.currentRightArmTrack:Play(0.1)
		print("[SprintManager] Playing sprint right arm animation (weapon in hand)")
	end

	-- Apply sprint speed (backward penalty handled in _monitorBackwardMovement)
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		local holdingS = UserInputService:IsKeyDown(Enum.KeyCode.S)
		if holdingS then
			humanoid.WalkSpeed = self.baseWalkSpeed * SPRINT_SPEED_MULTIPLIER * BACKWARD_SPEED_PENALTY
		else
			humanoid.WalkSpeed = self.baseWalkSpeed * SPRINT_SPEED_MULTIPLIER
		end
		print(`[SprintManager] Sprint activated - Speed: {humanoid.WalkSpeed}`)
	end
end

-- Stop sprint (public method)
function SprintManager:stopSprint()
	self:_stopSprint()
end

-- Save sprint state before dodge (public method)
function SprintManager:saveSprintStateForDodge()
	self.wasSprintingBeforeDodge = self.sprintActive
	print(`[SprintManager] Saved sprint state before dodge: {self.wasSprintingBeforeDodge}`)
end

-- Resume sprint if movement key is held (public method for post-dodge sprint resume)
function SprintManager:resumeSprintIfHoldingW()
	-- Check if W or S is being held (supports forward and backward sprint)
	local holdingW = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local holdingS = UserInputService:IsKeyDown(Enum.KeyCode.S)

	if not holdingW and not holdingS then
		return
	end

	-- ALWAYS extend grace periods when called from dodge/vault end
	-- This protects against velocity checks during landing/transition
	-- Set BOTH grace periods to ensure full protection
	self.postDodgeGraceEnd = tick() + 0.5
	self.lastLandingTime = tick() -- Treat dodge/vault end as a "landing" for grace purposes

	-- Don't resume if already sprinting (prevents double speed bug)
	if self.sprintActive then
		print("[SprintManager] Already sprinting - Extended grace period")
		return
	end

	-- Start sprint
	self:_startSprint()
	print("[SprintManager] Sprint resumed after dodge - Grace period active for 0.5s")
end

-- Stop sprint (internal)
function SprintManager:_stopSprint()
	if not self.sprintActive then
		return
	end

	self.sprintActive = false
	self.sprintDirection = nil
	self.isAirborne = false
	self.currentAnimSpeed = SPRINT_ANIM_SPEED_NORMAL

	-- Clear sprint attribute so other systems know we stopped
	local stopPlayer = Players.LocalPlayer
	local stopCharacter = stopPlayer.Character
	if stopCharacter then
		stopCharacter:SetAttribute("IsSprinting", false)
		-- Sync to server so server-side checks work too
		local sprintRemote = ReplicatedStorage:FindFirstChild("SprintStateChanged") :: RemoteEvent?
		if sprintRemote then
			sprintRemote:FireServer(false)
		end
	end

	-- Stop animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	-- Stop right arm animation
	if self.currentRightArmTrack then
		self.currentRightArmTrack:Stop(0.1)
		self.currentRightArmTrack = nil
	end

	-- Reset walk speed (backward penalty handled in _monitorBackwardMovement)
	local player = Players.LocalPlayer
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			local holdingS = UserInputService:IsKeyDown(Enum.KeyCode.S)
			if holdingS then
				humanoid.WalkSpeed = self.baseWalkSpeed * BACKWARD_SPEED_PENALTY
			else
				humanoid.WalkSpeed = self.baseWalkSpeed
			end
		end
	end

	print("[SprintManager] Sprint deactivated")
end

-- Check if player is in shiftlock mode
function SprintManager:_isInShiftLock(): boolean
	-- Check if shiftlock is enabled in player settings
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

-- Get actual sprint direction based on camera and movement
function SprintManager:_getActualSprintDirection(): string
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return "Forward"
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return "Forward"
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return "Forward"
	end

	-- Calculate angle between camera look vector and character forward
	local cameraLook = camera.CFrame.LookVector
	local characterForward = humanoidRootPart.CFrame.LookVector

	local dotProduct = cameraLook:Dot(characterForward)

	-- If camera is facing opposite direction (looking backward), S becomes forward sprint
	if dotProduct < -0.5 then
		return "Forward"
	end

	return "Backward"
end

-- Check if player is currently airborne (jumping/falling)
function SprintManager:_isPlayerAirborne(): boolean
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		return false
	end

	-- Check FloorMaterial - Air means not touching ground
	if humanoid.FloorMaterial == Enum.Material.Air then
		return true
	end

	-- Also check humanoid state for additional accuracy
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.FallingDown then
		return true
	end

	return false
end

-- Smoothly adjust sprint animation speed
function SprintManager:_adjustAnimationSpeed(targetSpeed: number)
	if not self.currentAnimTrack or not self.currentAnimTrack.IsPlaying then
		return
	end

	-- Only adjust if speed actually changed
	if math.abs(self.currentAnimSpeed - targetSpeed) < 0.01 then
		return
	end

	self.currentAnimSpeed = targetSpeed
	self.currentAnimTrack:AdjustSpeed(targetSpeed)
end

-- Monitor sprint state and auto-cancel when conditions aren't met
function SprintManager:_monitorSprint()
	RunService.Heartbeat:Connect(function()
		-- Track airborne state FIRST (before cancel check) so landing grace works
		local nowAirborne = self:_isPlayerAirborne()
		if nowAirborne ~= self.isAirborne then
			self.isAirborne = nowAirborne
			if nowAirborne then
				-- Player jumped - slow down animation
				if self.sprintActive and self.currentAnimTrack then
					self:_adjustAnimationSpeed(SPRINT_ANIM_SPEED_AIRBORNE)
				end
			else
				-- Player landed - restore normal speed and record landing time
				self.lastLandingTime = tick()
				if self.sprintActive and self.currentAnimTrack then
					self:_adjustAnimationSpeed(SPRINT_ANIM_SPEED_NORMAL)
				end
			end
		end

		if not self.sprintActive then
			return
		end

		-- Check if sprint should be cancelled
		if self:_shouldCancelSprint() then
			self:_stopSprint()
			return
		end

		-- Monitor weapon equip state for right arm animation
		local hasWeapon = self:_isWeaponInHand()
		local hasRightArmAnim = self.currentRightArmTrack ~= nil

		if hasWeapon and not hasRightArmAnim and self.loadedRightArmAnimation then
			-- Weapon was just drawn while sprinting - start right arm animation
			self.currentRightArmTrack = self.loadedRightArmAnimation
			self.currentRightArmTrack:Play(0.1)
			print("[SprintManager] Started right arm animation (weapon drawn during sprint)")
		elseif not hasWeapon and hasRightArmAnim then
			-- Weapon was just sheathed while sprinting - stop right arm animation
			self.currentRightArmTrack:Stop(0.1)
			self.currentRightArmTrack = nil
			print("[SprintManager] Stopped right arm animation (weapon sheathed during sprint)")
		end
	end)
end

-- Monitor backward movement for speed penalty (ONLY for walking, not sprinting)
-- Sprint speed is handled entirely by _startSprint and _stopSprint
function SprintManager:_monitorBackwardMovement()
	RunService.Heartbeat:Connect(function()
		local player = Players.LocalPlayer
		local character = player.Character
		if not character then
			return
		end

		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
		if not humanoid then
			return
		end

		-- Check if S key is currently held
		local holdingS = UserInputService:IsKeyDown(Enum.KeyCode.S)

		-- Only process if backward state changed
		if holdingS == self.isHoldingBackward then
			return
		end

		self.isHoldingBackward = holdingS

		-- IMPORTANT: Only adjust walk speed when NOT sprinting and NOT in grace period
		-- When sprinting or in grace period, the sprint system controls WalkSpeed entirely
		-- This prevents race conditions that can cause speed desync
		if self.sprintActive or tick() < self.postDodgeGraceEnd then
			-- Still track the state change, but don't touch WalkSpeed
			-- The sprint system will apply the correct speed
			return
		end

		-- Only modify WalkSpeed when definitely not sprinting
		if holdingS then
			humanoid.WalkSpeed = self.baseWalkSpeed * BACKWARD_SPEED_PENALTY
		else
			humanoid.WalkSpeed = self.baseWalkSpeed
		end
	end)
end

-- Check if sprint should be cancelled
function SprintManager:_shouldCancelSprint(): boolean
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return true
	end

	-- Check if player is in hitstun
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if wcsCharacter then
		local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
		local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
		local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)

		if wcsCharacter:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun }) then
			return true
		end
	end

	-- Check if player started attacking - cancel sprint
	if self:_isAttacking() then
		print("[SprintManager] Sprint cancelled - Player is attacking")
		return true
	end

	-- Grace period - don't check velocity immediately after starting sprint or after dodge/vault
	local timeSinceSprintStart = tick() - self.sprintStartTime
	if timeSinceSprintStart < SPRINT_GRACE_PERIOD then
		return false
	end
	if tick() < self.postDodgeGraceEnd then
		return false
	end

	-- Check if humanoid physics are disabled (e.g., during vault climb)
	-- Don't cancel sprint based on velocity if another system controls movement
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid and humanoid.PlatformStand then
		return false
	end

	-- Check if player is pressing any movement keys
	local isMoving = UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.A)
		or UserInputService:IsKeyDown(Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.D)

	if not isMoving then
		return true
	end

	-- In shiftlock mode, validate that W is being held (allows strafing with W+A/W+D)
	local isShiftLock = self:_isInShiftLock()

	if isShiftLock then
		-- In shiftlock, sprint should only continue if W is held
		-- This allows strafing (W+A, W+D) while sprinting
		if not UserInputService:IsKeyDown(Enum.KeyCode.W) then
			print("[SprintManager] Sprint cancelled - W not held in shiftlock")
			return true
		end
	end

	-- Skip velocity check if player is airborne
	-- Velocity is unreliable in the air (can drop at jump apex, during freefall, etc.)
	-- Player is still pressing movement keys, so maintain sprint through the jump
	if self:_isPlayerAirborne() then
		return false
	end

	-- Skip velocity check during landing grace period
	-- Velocity needs time to recover after landing from a jump
	if tick() - self.lastLandingTime < LANDING_GRACE_PERIOD then
		return false
	end

	-- Check if player stopped moving (only after grace periods and when grounded)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart then
		local velocity =
			Vector3.new(humanoidRootPart.AssemblyLinearVelocity.X, 0, humanoidRootPart.AssemblyLinearVelocity.Z)
		if velocity.Magnitude < MIN_SPRINT_VELOCITY then
			return true
		end
	end

	return false
end

return SprintManager
