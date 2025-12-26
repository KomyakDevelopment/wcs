--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WCS = require(ReplicatedStorage.Packages.wcs)

-- SFXManager lazy-loaded on client only (for volume control)
local SFXManager = nil
local function getSFXManager()
	if SFXManager == nil and RunService:IsClient() then
		SFXManager = require(ReplicatedStorage.Client.managers.sfxManager)
	end
	return SFXManager
end

local Jump = WCS.RegisterSkill("Jump")

-- WCS Client Prediction Configuration
Jump.CheckClientState = false
Jump.CheckOthersActive = false

-- Configuration
local DEFAULT_MAX_JUMPS = 2 -- Default: double jump (ground jump + 1 air jump)
local DOUBLE_JUMP_POWER = 85 -- Upward velocity for air jumps
local JUMP_COOLDOWN = 0.1 -- Small cooldown to prevent spam

-- Animation ID for air jump (flip/boost animation)
local AIR_JUMP_ANIMATION = "rbxassetid://76293994701034"

-- Store connections and non-serializable data outside of self to avoid WCS sync issues
-- Keyed by skill instance (not character) to prevent race conditions during moveset transitions
local clientConnections: { [any]: { state: RBXScriptConnection?, jumpRequest: RBXScriptConnection? } } = {}
local loadedAnimations: { [any]: AnimationTrack? } = {}

function Jump:OnConstructServer()
	-- Server tracks max jumps (can be upgraded via skills/perks)
	self.maxJumps = DEFAULT_MAX_JUMPS
	-- Server doesn't track jump count - relies on raycast validation in OnStartServer
end

function Jump:OnConstructClient()
	self.maxJumps = DEFAULT_MAX_JUMPS
	self.currentJumpCount = 0
	self.isGrounded = true
	self.airJumpDebounce = false -- Prevents rapid multi-trigger from JumpRequest

	-- Preload air jump animation (stored outside self to avoid sync issues)
	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator and AIR_JUMP_ANIMATION ~= "rbxassetid://0" then
			local animation = Instance.new("Animation")
			animation.AnimationId = AIR_JUMP_ANIMATION
			loadedAnimations[self] = animator:LoadAnimation(animation)
		end
	end

	-- Setup ground detection and jump input handling
	self:_setupJumpSystem()
end

-- Setup the jump tracking system (client-only)
function Jump:_setupJumpSystem()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid

	if not humanoid then
		warn("[Jump] No humanoid found")
		return
	end

	-- Initialize connections table for this skill instance
	clientConnections[self] = {}

	-- Track grounded state via Humanoid.StateChanged
	clientConnections[self].state = humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed then
			-- Reset everything on landing
			self.currentJumpCount = 0
			self.isGrounded = true
			self.airJumpDebounce = false
		elseif newState == Enum.HumanoidStateType.Jumping then
			-- First jump (from ground)
			if self.isGrounded then
				self.currentJumpCount = 1
				self.isGrounded = false
				-- Block trailing JumpRequest events from consuming air jump
				self.airJumpDebounce = true
				-- Reset debounce after a short delay to allow actual double jump
				task.delay(0.15, function()
					self.airJumpDebounce = false
				end)
				-- Play SFX for ground jump
				self:_playJumpSFX()
			end
		elseif newState == Enum.HumanoidStateType.Freefall then
			self.isGrounded = false
		end
	end)

	-- Listen for jump input to handle air jumps
	clientConnections[self].jumpRequest = UserInputService.JumpRequest:Connect(function()
		self:_handleJumpRequest()
	end)

	print("[Jump] Jump system initialized")
end

-- Handle jump request (called when player presses jump)
function Jump:_handleJumpRequest()
	-- Only process on client
	if not RunService:IsClient() then
		return
	end

	-- If grounded, let Roblox handle the normal jump
	if self.isGrounded then
		return
	end

	-- Debounce to prevent JumpRequest firing multiple times per press
	if self.airJumpDebounce then
		return
	end

	-- Block air jump during wall running or wall jumping
	local character = self.Character.Instance
	if character:GetAttribute("IsWallRunning") or character:GetAttribute("IsWallJumping") then
		return
	end

	-- Check if we can air jump (count 1 = did ground jump, can do 1 more air jump)
	-- With maxJumps=2: ground jump is count 1, air jump will be count 2
	if self.currentJumpCount >= self.maxJumps then
		return
	end

	-- Check WCS cooldown
	local state = self:GetState()
	if state.Debounce then
		return
	end

	-- Set debounce IMMEDIATELY before any async operations
	self.airJumpDebounce = true

	-- Increment count IMMEDIATELY to prevent race conditions
	self.currentJumpCount = self.currentJumpCount + 1

	-- Reset debounce after short delay to allow next air jump
	task.delay(0.2, function()
		self.airJumpDebounce = false
	end)

	-- Perform air jump
	self:Start()
end

function Jump:OnStartServer()
	-- Server validates and performs the air jump
	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart

	if not humanoid or not humanoidRootPart then
		return
	end

	-- Check if player is actually in the air (not grounded)
	-- This is the primary validation - if they're on the ground, reject the air jump
	local rayOrigin = humanoidRootPart.Position
	local rayDirection = Vector3.new(0, -3.5, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult then
		-- Player is grounded, don't allow air jump
		return
	end

	-- Apply upward velocity for air jump (server authoritative)
	local currentVelocity = humanoidRootPart.AssemblyLinearVelocity
	humanoidRootPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, DOUBLE_JUMP_POWER, currentVelocity.Z)

	-- Apply cooldown to prevent spam
	self:ApplyCooldown(JUMP_COOLDOWN)

	print("[Jump] Server: Air jump performed")
end

function Jump:OnStartClient()
	-- Count already incremented in _handleJumpRequest

	-- Apply velocity locally for responsive feel
	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart

	if humanoidRootPart then
		local currentVelocity = humanoidRootPart.AssemblyLinearVelocity
		humanoidRootPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, DOUBLE_JUMP_POWER, currentVelocity.Z)
	end

	-- Play animation
	local animTrack = loadedAnimations[self]
	if animTrack then
		animTrack:Play(0.05)
		animTrack.Priority = Enum.AnimationPriority.Action2
	end

	-- Play VFX
	self:_playAirJumpVFX()

	-- Play SFX
	self:_playJumpSFX()

	print(`[Jump] Client: Air jump performed ({self.currentJumpCount}/{self.maxJumps})`)
end

-- Play jump SFX (plays on ALL jumps - ground and air)
function Jump:_playJumpSFX()
	if not RunService:IsClient() then
		return
	end

	local jumpSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
	if jumpSFXFolder then
		jumpSFXFolder = jumpSFXFolder:FindFirstChild("SFX")
	end
	if jumpSFXFolder then
		jumpSFXFolder = jumpSFXFolder:FindFirstChild("Movement")
	end
	if jumpSFXFolder then
		jumpSFXFolder = jumpSFXFolder:FindFirstChild("Jump")
	end

	if not jumpSFXFolder then
		warn("[Jump] Jump SFX folder not found at ReplicatedStorage.Assets.SFX.Movement.Jump")
		return
	end

	local character = self.Character.Instance
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Get all Sound instances from folder
	local sounds = {}
	for _, child in ipairs(jumpSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[Jump] No jump sounds found in folder")
		return
	end

	-- Select random sound
	local randomSound = sounds[math.random(1, #sounds)]

	-- Clone and play with spatial audio
	local soundClone = randomSound:Clone()
	-- Route through SFX volume control
	local sfxManager = getSFXManager()
	if sfxManager then
		soundClone.SoundGroup = sfxManager.getSoundGroup()
	end
	soundClone.Parent = hrp
	soundClone:Play()

	-- Clean up after sound finishes
	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)
end

-- Play air jump VFX (only on air jumps, not ground jumps)
function Jump:_playAirJumpVFX()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Get VFX from ReplicatedStorage.Assets.VFX.Movement.jump
	local jumpVFXPart = ReplicatedStorage:FindFirstChild("Assets")
	if jumpVFXPart then
		jumpVFXPart = jumpVFXPart:FindFirstChild("VFX")
	end
	if jumpVFXPart then
		jumpVFXPart = jumpVFXPart:FindFirstChild("Movement")
	end
	if jumpVFXPart then
		jumpVFXPart = jumpVFXPart:FindFirstChild("jump")
	end

	if not jumpVFXPart then
		warn("[Jump] Jump VFX part not found at ReplicatedStorage.Assets.VFX.Movement.jump")
		return
	end

	-- Find the attachment inside the part
	local vfxAttachment = jumpVFXPart:FindFirstChildOfClass("Attachment")
	if not vfxAttachment then
		warn("[Jump] No attachment found in jump VFX part")
		return
	end

	-- Clone the attachment and parent to HumanoidRootPart
	local vfxClone = vfxAttachment:Clone()
	vfxClone.Parent = hrp

	-- Emit particles based on each emitter's properties
	local maxLifetime = 0
	for _, child in ipairs(vfxClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			-- Emit particles (use the emitter's Rate or a burst)
			-- For burst effect, emit a set number of particles
			local emitCount = child:GetAttribute("EmitCount") or 15
			child:Emit(emitCount)

			-- Track max lifetime for cleanup
			local lifetime = child.Lifetime.Max
			if lifetime > maxLifetime then
				maxLifetime = lifetime
			end
		end
	end

	-- Destroy attachment after particles fade
	task.delay(maxLifetime + 0.5, function()
		if vfxClone and vfxClone.Parent then
			vfxClone:Destroy()
		end
	end)
end

-- Set max jumps (called when player gets upgrades)
function Jump:SetMaxJumps(maxJumps: number)
	self.maxJumps = maxJumps
	print(`[Jump] Max jumps set to {maxJumps}`)
end

-- Get current max jumps
function Jump:GetMaxJumps(): number
	return self.maxJumps
end

function Jump:OnEndServer()
	-- Nothing to clean up on server
end

function Jump:OnEndClient()
	-- Nothing to clean up per-use
end

-- Cleanup connections when skill is destroyed
function Jump:Destroy()
	-- Clean up client connections (keyed by self to avoid race conditions)
	local clientConn = clientConnections[self]
	if clientConn then
		if clientConn.state then
			clientConn.state:Disconnect()
		end
		if clientConn.jumpRequest then
			clientConn.jumpRequest:Disconnect()
		end
		clientConnections[self] = nil
	end

	-- Clean up loaded animation
	loadedAnimations[self] = nil
end

return Jump
