--!strict
-- Double Jump Manager
-- Handles double jump functionality independently of WCS movesets
-- This ensures double jump is always available regardless of equipment state

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DoubleJumpManager = {}
DoubleJumpManager.__index = DoubleJumpManager

-- Configuration
local DEFAULT_MAX_JUMPS = 2 -- Ground jump + 1 air jump
local DOUBLE_JUMP_POWER = 85 -- Upward velocity for air jumps
local AIR_JUMP_ANIMATION = "rbxassetid://96765830085186"

function DoubleJumpManager.new()
	local self = setmetatable({}, DoubleJumpManager)

	self.maxJumps = DEFAULT_MAX_JUMPS
	self.currentJumpCount = 0
	self.isGrounded = true
	self.airJumpDebounce = false

	self.stateConnection = nil
	self.jumpRequestConnection = nil
	self.loadedAnimation = nil

	self:_setup()

	return self
end

function DoubleJumpManager:_setup()
	local player = Players.LocalPlayer

	-- Setup for current character
	if player.Character then
		self:_setupCharacter(player.Character)
	end

	-- Setup for future characters (respawns)
	player.CharacterAdded:Connect(function(character)
		self:_setupCharacter(character)
	end)
end

function DoubleJumpManager:_setupCharacter(character: Model)
	-- Clean up old connections
	self:_cleanup()

	-- Reset state
	self.currentJumpCount = 0
	self.isGrounded = true
	self.airJumpDebounce = false

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Preload animation
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator and AIR_JUMP_ANIMATION ~= "rbxassetid://0" then
		local animation = Instance.new("Animation")
		animation.AnimationId = AIR_JUMP_ANIMATION
		self.loadedAnimation = animator:LoadAnimation(animation)
	end

	-- Track grounded state
	self.stateConnection = humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed then
			self.currentJumpCount = 0
			self.isGrounded = true
			self.airJumpDebounce = false
		elseif newState == Enum.HumanoidStateType.Jumping then
			if self.isGrounded then
				self.currentJumpCount = 1
				self.isGrounded = false
				self.airJumpDebounce = true
				task.delay(0.15, function()
					self.airJumpDebounce = false
				end)
				-- Play SFX for ground jump
				self:_playJumpSFX(character)
			end
		elseif newState == Enum.HumanoidStateType.Freefall then
			self.isGrounded = false
		end
	end)

	-- Listen for jump input
	self.jumpRequestConnection = UserInputService.JumpRequest:Connect(function()
		self:_handleJumpRequest(character)
	end)

	print("[DoubleJumpManager] Initialized for character")
end

function DoubleJumpManager:_handleJumpRequest(character: Model)
	-- If grounded, let Roblox handle normal jump
	if self.isGrounded then
		return
	end

	-- Debounce to prevent rapid triggers
	if self.airJumpDebounce then
		return
	end

	-- Check if we can air jump
	if self.currentJumpCount >= self.maxJumps then
		return
	end

	-- Set debounce immediately
	self.airJumpDebounce = true
	self.currentJumpCount = self.currentJumpCount + 1

	-- Reset debounce after short delay
	task.delay(0.2, function()
		self.airJumpDebounce = false
	end)

	-- Perform air jump
	self:_performAirJump(character)
end

function DoubleJumpManager:_performAirJump(character: Model)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart

	if humanoidRootPart then
		local currentVelocity = humanoidRootPart.AssemblyLinearVelocity
		humanoidRootPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, DOUBLE_JUMP_POWER, currentVelocity.Z)
	end

	-- Play animation
	if self.loadedAnimation then
		self.loadedAnimation:Play(0.05)
		self.loadedAnimation.Priority = Enum.AnimationPriority.Action2
	end

	-- Play VFX and SFX
	self:_playAirJumpVFX(character)
	self:_playJumpSFX(character)

	print(`[DoubleJumpManager] Air jump performed ({self.currentJumpCount}/{self.maxJumps})`)
end

function DoubleJumpManager:_playJumpSFX(character: Model)
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
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local sounds = {}
	for _, child in ipairs(jumpSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		return
	end

	local randomSound = sounds[math.random(1, #sounds)]
	local soundClone = randomSound:Clone()
	soundClone.Parent = hrp
	soundClone:Play()

	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)
end

function DoubleJumpManager:_playAirJumpVFX(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

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
		return
	end

	local vfxAttachment = jumpVFXPart:FindFirstChildOfClass("Attachment")
	if not vfxAttachment then
		return
	end

	local vfxClone = vfxAttachment:Clone()
	vfxClone.Parent = hrp

	local maxLifetime = 0
	for _, child in ipairs(vfxClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			local emitCount = child:GetAttribute("EmitCount") or 15
			child:Emit(emitCount)

			local lifetime = child.Lifetime.Max
			if lifetime > maxLifetime then
				maxLifetime = lifetime
			end
		end
	end

	task.delay(maxLifetime + 0.5, function()
		if vfxClone and vfxClone.Parent then
			vfxClone:Destroy()
		end
	end)
end

function DoubleJumpManager:setMaxJumps(maxJumps: number)
	self.maxJumps = maxJumps
	print(`[DoubleJumpManager] Max jumps set to {maxJumps}`)
end

function DoubleJumpManager:_cleanup()
	if self.stateConnection then
		self.stateConnection:Disconnect()
		self.stateConnection = nil
	end
	if self.jumpRequestConnection then
		self.jumpRequestConnection:Disconnect()
		self.jumpRequestConnection = nil
	end
	self.loadedAnimation = nil
end

function DoubleJumpManager:destroy()
	self:_cleanup()
end

return DoubleJumpManager
