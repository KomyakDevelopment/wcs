--!strict
-- Sprint Manager
-- Handles double-tap sprint detection and sprint state management
-- Works independently of WCS movesets - always available to the player

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local WCS = require(ReplicatedStorage.Packages.wcs)

local SprintManager = {}
SprintManager.__index = SprintManager

-- Configuration
local SPRINT_SPEED_MULTIPLIER = 1.75 -- 175% of normal walk speed (16 -> 28)
local DOUBLE_TAP_WINDOW = 0.4 -- Time window to detect double tap (seconds) - increased for better detection
local MIN_SPRINT_VELOCITY = 3 -- Minimum velocity to maintain sprint - lowered for better fluidity
local SPRINT_GRACE_PERIOD = 0.3 -- Grace period before checking velocity after sprint starts

-- Animation
local SPRINT_ANIMATION_ID = "rbxassetid://94461174611915"

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
	self.currentAnimTrack = nil
	self.sprintDirection = nil
	self.baseWalkSpeed = 16 -- Default walkspeed
	self.sprintStartTime = 0 -- Track when sprint started for grace period
	self.postDodgeGraceEnd = 0 -- Track when post-dodge grace period ends
	self.wasSprintingBeforeDodge = false -- Track if player was sprinting before dodge

	-- Setup
	self:_initialize()

	return self
end

function SprintManager:_initialize()
	-- Wait for character
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()

	-- Preload sprint animation
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		self.baseWalkSpeed = humanoid.WalkSpeed

		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = SPRINT_ANIMATION_ID
			self.loadedAnimation = animator:LoadAnimation(animation)
		end

		-- Monitor WalkSpeed changes to prevent animations/equipment from overriding sprint
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if self.sprintActive then
				-- Sprint is active - restore sprint speed if something changed it
				local expectedSpeed = self.baseWalkSpeed * SPRINT_SPEED_MULTIPLIER
				if math.abs(humanoid.WalkSpeed - expectedSpeed) > 0.1 then
					-- Something else changed speed - restore sprint multiplier
					task.defer(function()
						humanoid.WalkSpeed = expectedSpeed
						print(`[SprintManager] Sprint speed restored: {expectedSpeed}`)
					end)
				end
			else
				-- Not sprinting - track base speed changes
				self.baseWalkSpeed = humanoid.WalkSpeed
			end
		end)
	end

	-- Setup double-tap detection
	self:_setupDoubleTapDetection()

	-- Monitor sprint state
	self:_monitorSprint()

	print("[SprintManager] Initialized")
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
	-- Check if punch animation is playing - don't start sprint (animation priority)
	if self:_isPunchAnimationPlaying() then
		print("[SprintManager] Double-tap ignored - Punch animation playing")
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

-- Punch animation IDs to check against
local PUNCH_ANIMATION_IDS = {
	["rbxassetid://100518847191051"] = true, -- M1 phase 1
	["rbxassetid://76103103515407"] = true, -- M1 phase 2
	["rbxassetid://128845445156895"] = true, -- M1 phase 3
	["rbxassetid://77003004079538"] = true, -- Flourish (phase 4)
}

-- Check if player is currently in a punch animation
function SprintManager:_isPunchAnimationPlaying(): boolean
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return false
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end

	-- Check all playing animations for punch animations
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation and PUNCH_ANIMATION_IDS[track.Animation.AnimationId] then
			return true
		end
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

	-- Check if punch animation is playing - don't start sprint (animation priority)
	if self:_isPunchAnimationPlaying() then
		print("[SprintManager] Blocked - Punch animation playing")
		return
	end

	-- Record current sprint state before activating
	local wasAlreadySprinting = self.sprintActive

	self.sprintActive = true
	self.sprintStartTime = tick() -- Record sprint start time

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
	end

	-- Apply sprint speed
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		-- Only update base speed if not already sprinting (prevents compound multiplier bug)
		if not wasAlreadySprinting then
			self.baseWalkSpeed = humanoid.WalkSpeed
		end
		humanoid.WalkSpeed = self.baseWalkSpeed * SPRINT_SPEED_MULTIPLIER
		print(`[SprintManager] Sprint activated - Base: {self.baseWalkSpeed}, Speed: {humanoid.WalkSpeed}`)
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

-- Resume sprint if W is held (public method for post-dodge sprint resume)
function SprintManager:resumeSprintIfHoldingW()
	-- Check if W is being held
	if not UserInputService:IsKeyDown(Enum.KeyCode.W) then
		return
	end

	-- Don't resume if already sprinting (prevents double speed bug)
	if self.sprintActive then
		print("[SprintManager] Already sprinting - Skipping resume")
		return
	end

	-- Set post-dodge grace period (0.5s where directional checks are lenient)
	self.postDodgeGraceEnd = tick() + 0.5

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

	-- Stop animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	-- Reset walk speed
	local player = Players.LocalPlayer
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = self.baseWalkSpeed
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

-- Monitor sprint state and auto-cancel when conditions aren't met
function SprintManager:_monitorSprint()
	RunService.Heartbeat:Connect(function()
		if not self.sprintActive then
			return
		end

		-- Check if sprint should be cancelled
		if self:_shouldCancelSprint() then
			self:_stopSprint()
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

	-- Check if punch animation started - cancel sprint (animation priority)
	if self:_isPunchAnimationPlaying() then
		print("[SprintManager] Sprint cancelled - Punch animation playing")
		return true
	end

	-- Grace period - don't check velocity immediately after starting sprint
	local timeSinceSprintStart = tick() - self.sprintStartTime
	if timeSinceSprintStart < SPRINT_GRACE_PERIOD then
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

	-- Check if player stopped moving (only after grace period)
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
