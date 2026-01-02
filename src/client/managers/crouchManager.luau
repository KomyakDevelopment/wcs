--!strict
-- Crouch Manager
-- Handles crouching when player is walking or idle
-- Press Ctrl when not sprinting to toggle crouch
-- LOW PRIORITY: Automatically cancels when any higher-priority action occurs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local WCS = require(ReplicatedStorage.Packages.wcs)

local CrouchManager = {}
CrouchManager.__index = CrouchManager

-- Configuration
local CROUCH_SPEED_MULTIPLIER = 0.75 -- 75% of normal walk speed
local BASE_WALK_SPEED = 16
local ACTION_END_BUFFER = 0.15 -- Seconds to wait after an action ends before allowing crouch

-- Animation IDs
local CROUCH_IDLE_ANIMATION = "rbxassetid://130904732555277"
local CROUCH_WALK_ANIMATION = "rbxassetid://91161961310038"

-- Pre-cache status effects (loaded lazily to avoid circular deps)
local StatusEffects = nil
local function getStatusEffects()
	if StatusEffects == nil then
		StatusEffects = {
			SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun),
			TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun),
			Stun = require(ReplicatedStorage.Shared.statusEffects.stun),
			Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing),
			Sliding = require(ReplicatedStorage.Shared.statusEffects.sliding),
			Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking),
			HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking),
			Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown),
			Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken),
			Iframes = require(ReplicatedStorage.Shared.statusEffects.iframes),
			Parrying = require(ReplicatedStorage.Shared.statusEffects.parrying),
			Parried = require(ReplicatedStorage.Shared.statusEffects.parried),
			BlockStunned = require(ReplicatedStorage.Shared.statusEffects.blockStunned),
			WallRunning = require(ReplicatedStorage.Shared.statusEffects.wallRunning),
			Daze = require(ReplicatedStorage.Shared.statusEffects.daze),
		}
	end
	return StatusEffects
end

function CrouchManager.new()
	local self = setmetatable({}, CrouchManager)

	-- State
	self.isCrouching = false
	self.character = nil
	self.humanoid = nil
	self.lastActionEndTime = 0 -- Track when the last blocking action ended

	-- Animations
	self.crouchIdleAnim = nil
	self.crouchWalkAnim = nil
	self.currentAnimTrack = nil

	-- Connections
	self.inputConnection = nil
	self.updateConnection = nil
	self.stateConnection = nil

	self:_initialize()

	return self
end

function CrouchManager:_initialize()
	local player = Players.LocalPlayer

	if player.Character then
		self:_setupCharacter(player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		-- Reset state on respawn
		self.isCrouching = false
		self.crouchIdleAnim = nil
		self.crouchWalkAnim = nil
		self.currentAnimTrack = nil

		character:WaitForChild("Humanoid", 10)
		self:_setupCharacter(character)
	end)

	-- Input handling
	self.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.LeftControl then
			self:_handleCrouchInput()
		end
	end)

	-- Monitor state changes to auto-cancel crouch AND track action times
	self.updateConnection = RunService.Heartbeat:Connect(function()
		-- Always track when blocking actions are active (for buffer timing)
		-- This ensures buffer counts from when action ENDED, not when crouch was cancelled
		if self.character and self:_hasBlockingStatusEffects() then
			self.lastActionEndTime = tick()
		end

		-- Check crouch validity if crouching
		if self.isCrouching then
			self:_checkCrouchValidity()
		end
	end)

	print("[CrouchManager] Initialized")
end

function CrouchManager:_setupCharacter(character: Model)
	self.character = character
	self.humanoid = character:FindFirstChild("Humanoid") :: Humanoid

	if not self.humanoid then
		warn("[CrouchManager] No humanoid found")
		return
	end

	-- Load animations
	local animator = self.humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local idleAnim = Instance.new("Animation")
		idleAnim.AnimationId = CROUCH_IDLE_ANIMATION
		self.crouchIdleAnim = animator:LoadAnimation(idleAnim)

		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = CROUCH_WALK_ANIMATION
		self.crouchWalkAnim = animator:LoadAnimation(walkAnim)

		print("[CrouchManager] Animations loaded")
	end

	-- Listen for state changes that should cancel crouch
	self.stateConnection = self.humanoid.StateChanged:Connect(function(_, newState)
		if self.isCrouching then
			-- Cancel crouch if player jumps or falls
			if newState == Enum.HumanoidStateType.Jumping or newState == Enum.HumanoidStateType.Freefall then
				self:_stopCrouch()
			end
		end
	end)
end

function CrouchManager:_handleCrouchInput()
	if self.isCrouching then
		self:_stopCrouch()
	else
		self:_tryStartCrouch()
	end
end

function CrouchManager:_hasBlockingStatusEffects(): boolean
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(self.character)
	if not wcsCharacter then
		return false
	end

	local effects = getStatusEffects()

	-- Check all status effects that should block/cancel crouching
	-- This is comprehensive - crouch is LOW PRIORITY
	return wcsCharacter:HasStatusEffects({
		effects.SoftHitstun,
		effects.TrueHitstun,
		effects.Stun,
		effects.Dashing,
		effects.Sliding,
		effects.Attacking,
		effects.HeavyAttacking,
		effects.Knockdown,
		effects.Guardbroken,
		effects.Iframes, -- During dodge
		effects.Parrying,
		effects.Parried,
		effects.BlockStunned,
		effects.WallRunning,
		effects.Daze,
	})
end

function CrouchManager:_canCrouch(): boolean
	if not self.character or not self.humanoid then
		return false
	end

	-- Must be grounded
	local state = self.humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
		return false
	end

	-- Check attributes (fast checks)
	if self.character:GetAttribute("IsSprinting") then
		return false
	end

	if self.character:GetAttribute("IsWallRunning") then
		return false
	end

	if self.character:GetAttribute("_SlideActive") then
		return false
	end

	-- Check WCS status effects that block crouching
	if self:_hasBlockingStatusEffects() then
		return false
	end

	-- Buffer check: don't allow crouch immediately after an action ends
	-- lastActionEndTime is continuously updated by heartbeat while actions are active
	local timeSinceLastAction = tick() - self.lastActionEndTime
	if timeSinceLastAction < ACTION_END_BUFFER then
		return false
	end

	return true
end

function CrouchManager:_tryStartCrouch()
	if not self:_canCrouch() then
		return
	end

	self.isCrouching = true

	-- Set attribute for other systems
	if self.character then
		self.character:SetAttribute("IsCrouching", true)
	end

	-- Reduce walk speed
	if self.humanoid then
		self.humanoid.WalkSpeed = BASE_WALK_SPEED * CROUCH_SPEED_MULTIPLIER
	end

	-- Start with appropriate animation based on movement
	self:_updateCrouchAnimation()

	print("[CrouchManager] Crouch started")
end

function CrouchManager:_stopCrouch(cancelledByAction: boolean?)
	if not self.isCrouching then
		return
	end

	self.isCrouching = false

	-- If cancelled by an action, update lastActionEndTime for buffer
	-- This prevents instantly re-crouching after the action ends
	if cancelledByAction then
		self.lastActionEndTime = tick()
	end

	-- Clear attribute
	if self.character then
		self.character:SetAttribute("IsCrouching", nil)
	end

	-- Restore walk speed
	if self.humanoid then
		self.humanoid.WalkSpeed = BASE_WALK_SPEED
	end

	-- Stop animation with faster fade for action cancellations
	if self.currentAnimTrack then
		local fadeTime = cancelledByAction and 0.05 or 0.1
		self.currentAnimTrack:Stop(fadeTime)
		self.currentAnimTrack = nil
	end

	print("[CrouchManager] Crouch stopped" .. (cancelledByAction and " (cancelled by action)" or ""))
end

function CrouchManager:_updateCrouchAnimation()
	if not self.isCrouching or not self.humanoid then
		return
	end

	local isMoving = self.humanoid.MoveDirection.Magnitude > 0.1
	local targetAnim = isMoving and self.crouchWalkAnim or self.crouchIdleAnim

	-- Only switch if animation changed
	if self.currentAnimTrack ~= targetAnim then
		if self.currentAnimTrack then
			self.currentAnimTrack:Stop(0.15)
		end

		if targetAnim then
			targetAnim.Looped = true
			targetAnim.Priority = Enum.AnimationPriority.Action
			targetAnim:Play(0.15)
			self.currentAnimTrack = targetAnim
		end
	end
end

function CrouchManager:_checkCrouchValidity()
	if not self.isCrouching then
		return
	end

	-- AGGRESSIVE CANCELLATION: Check if any higher-priority action is happening
	-- Crouch is low priority - immediately cancel for ANY action

	-- Check humanoid state first (fastest check)
	if self.humanoid then
		local state = self.humanoid:GetState()
		if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
			self:_stopCrouch(true) -- Action cancelled the crouch
			return
		end
	end

	-- Check attributes (fast checks before WCS)
	if self.character then
		if self.character:GetAttribute("IsSprinting")
			or self.character:GetAttribute("IsWallRunning")
			or self.character:GetAttribute("_SlideActive") then
			self:_stopCrouch(true) -- Action cancelled the crouch
			return
		end
	end

	-- Check WCS status effects
	if self:_hasBlockingStatusEffects() then
		self:_stopCrouch(true) -- Action cancelled the crouch
		return
	end

	-- If we're still crouching, enforce the crouch speed
	local crouchSpeed = BASE_WALK_SPEED * CROUCH_SPEED_MULTIPLIER
	if self.humanoid and math.abs(self.humanoid.WalkSpeed - crouchSpeed) > 0.1 then
		self.humanoid.WalkSpeed = crouchSpeed
	end

	-- Update animation based on movement
	self:_updateCrouchAnimation()
end

function CrouchManager:isCrouchActive(): boolean
	return self.isCrouching
end

function CrouchManager:destroy()
	self:_stopCrouch()

	if self.inputConnection then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end

	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	if self.stateConnection then
		self.stateConnection:Disconnect()
		self.stateConnection = nil
	end
end

return CrouchManager
