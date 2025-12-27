--!strict
-- Crouch Manager
-- Handles crouching when player is walking or idle
-- Press Ctrl when not sprinting to toggle crouch

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

-- Animation IDs
local CROUCH_IDLE_ANIMATION = "rbxassetid://130904732555277"
local CROUCH_WALK_ANIMATION = "rbxassetid://91161961310038"

function CrouchManager.new()
	local self = setmetatable({}, CrouchManager)

	-- State
	self.isCrouching = false
	self.character = nil
	self.humanoid = nil

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

	-- Monitor state changes to auto-cancel crouch
	self.updateConnection = RunService.Heartbeat:Connect(function()
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

function CrouchManager:_canCrouch(): boolean
	if not self.character or not self.humanoid then
		return false
	end

	-- Must be grounded
	local state = self.humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
		return false
	end

	-- Check if sprinting
	if self.character:GetAttribute("IsSprinting") then
		return false
	end

	-- Check if wall running
	if self.character:GetAttribute("IsWallRunning") then
		return false
	end

	-- Check WCS status effects that block crouching
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(self.character)
	if wcsCharacter then
		local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
		local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
		local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
		local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
		local Sliding = require(ReplicatedStorage.Shared.statusEffects.sliding)
		local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
		local HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking)
		local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
		local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)

		if wcsCharacter:HasStatusEffects({
			SoftHitstun, TrueHitstun, Stun, Dashing, Sliding,
			Attacking, HeavyAttacking, Knockdown, Guardbroken
		}) then
			return false
		end
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

function CrouchManager:_stopCrouch()
	if not self.isCrouching then
		return
	end

	self.isCrouching = false

	-- Clear attribute
	if self.character then
		self.character:SetAttribute("IsCrouching", nil)
	end

	-- Restore walk speed
	if self.humanoid then
		self.humanoid.WalkSpeed = BASE_WALK_SPEED
	end

	-- Stop animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	print("[CrouchManager] Crouch stopped")
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

	-- Check if crouch should be cancelled
	if not self:_canCrouch() then
		self:_stopCrouch()
		return
	end

	-- Enforce crouch speed (in case something else tried to change it)
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
