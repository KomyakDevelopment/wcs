--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Sprint = WCS.RegisterSkill("Sprint")

-- Configuration
local SPRINT_SPEED_MULTIPLIER = 1.5 -- 150% of normal walk speed
local DOUBLE_TAP_WINDOW = 0.3 -- Time window to detect double tap (seconds)
local MIN_SPRINT_VELOCITY = 5 -- Minimum velocity to maintain sprint

-- Animation
local SPRINT_ANIMATION_ID = "rbxassetid://104453488066690"

-- Movement keys for double-tap detection
local MOVEMENT_KEYS = {
	[Enum.KeyCode.W] = "Forward",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.S] = "Backward",
	[Enum.KeyCode.D] = "Right",
}

function Sprint:OnConstructServer()
	-- Server doesn't need to track sprint state (managed client-side with validation)
end

function Sprint:OnConstructClient()
	-- Track double-tap state for each movement key
	self.doubleTapReady = {} -- Tracks if first tap occurred for each key
	self.doubleTapTimers = {} -- Tracks timeout tasks for each key
	self.sprintActive = false
	self.loadedAnimation = nil
	self.currentAnimTrack = nil
	self.sprintDirection = nil

	-- Preload sprint animation
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = SPRINT_ANIMATION_ID
			self.loadedAnimation = animator:LoadAnimation(animation)
		end
	end

	-- Connect to input for double-tap detection
	self:_setupDoubleTapDetection()

	-- Monitor sprint state
	self:_monitorSprint()
end

function Sprint:OnStartServer()
	-- Server validates sprint state via HumanoidData applied by client
	print("[Sprint] Server: Sprint started")
end

function Sprint:OnStartClient()
	-- Check if player has any status effects that prevent sprinting
	local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
	local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)

	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Blocking }) then
		print("[Sprint] Client: Blocked - Player is in hitstun/stun/blocking")
		return
	end

	self.sprintActive = true

	-- Play sprint animation
	if self.loadedAnimation then
		self.currentAnimTrack = self.loadedAnimation
		self.currentAnimTrack:Play(0.1) -- Smooth transition
		print("[Sprint] Client: Playing sprint animation")
	end

	-- Apply sprint speed
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local baseSpeed = humanoid.WalkSpeed
		self:SetHumanoidData({
			WalkSpeed = { baseSpeed * SPRINT_SPEED_MULTIPLIER, "Set" },
		})
		print(`[Sprint] Client: Sprint activated - Speed: {baseSpeed * SPRINT_SPEED_MULTIPLIER}`)
	end
end

function Sprint:OnEndServer()
	print("[Sprint] Server: Sprint ended")
end

function Sprint:OnEndClient()
	self.sprintActive = false
	self.sprintDirection = nil

	-- Stop animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	print("[Sprint] Client: Sprint deactivated")
end

-- Setup double-tap detection for movement keys
function Sprint:_setupDoubleTapDetection()
	if not RunService:IsClient() then
		return
	end

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
function Sprint:_handleDoubleTap(direction: string)
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
	print(`[Sprint] Double-tap detected: {direction} -> Sprint: {sprintDirection}`)

	-- Start sprint skill
	self:Start()
end

-- Check if player is in shiftlock mode
function Sprint:_isInShiftLock(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end

	-- Check if shiftlock is enabled in player settings
	-- Note: This checks the mouse behavior which changes when shiftlock is active
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

-- Get actual sprint direction based on camera and movement
function Sprint:_getActualSprintDirection(): string
	local humanoidRootPart = self.Character.Instance:FindFirstChild("HumanoidRootPart")
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
function Sprint:_monitorSprint()
	if not RunService:IsClient() then
		return
	end

	RunService.Heartbeat:Connect(function()
		if not self.sprintActive then
			return
		end

		-- Check if sprint should be cancelled
		if self:_shouldCancelSprint() then
			print("[Sprint] Auto-cancelling sprint")
			self:Stop()
		end
	end)
end

-- Check if sprint should be cancelled
function Sprint:_shouldCancelSprint(): boolean
	-- Check if player is in hitstun
	local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)

	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun }) then
		return true
	end

	-- Check if player stopped moving
	local humanoidRootPart = self.Character.Instance:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart then
		local velocity = Vector3.new(humanoidRootPart.AssemblyLinearVelocity.X, 0, humanoidRootPart.AssemblyLinearVelocity.Z)
		if velocity.Magnitude < MIN_SPRINT_VELOCITY then
			return true
		end
	end

	-- Check if player is not pressing any movement keys
	local isMoving = UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.A)
		or UserInputService:IsKeyDown(Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.D)

	if not isMoving then
		return true
	end

	return false
end

return Sprint
