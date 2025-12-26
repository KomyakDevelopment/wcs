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

-- Pre-cache status effects
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local Sliding = require(ReplicatedStorage.Shared.statusEffects.sliding)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking)
local WallRunning = require(ReplicatedStorage.Shared.statusEffects.wallRunning)

local Slide = WCS.RegisterSkill("Slide")

-- WCS Configuration
Slide.CheckClientState = false
Slide.CheckOthersActive = false

-- =============================================================================
-- CONFIGURATION
-- =============================================================================
local SLIDE_DISTANCE = 20
local SLIDE_DURATION = 0.5
local SLIDE_COOLDOWN = 1.2
local MAX_SLIDE_DURATION = 5.0

-- Physics
local BASE_SLIDE_SPEED = SLIDE_DISTANCE / SLIDE_DURATION
local SLOPE_ACCELERATION = 10 -- Studs/sec^2 acceleration when going downhill
local MAX_TURN_ANGLE = 70 -- Degrees - cancel slide if turning beyond this
local FLAT_DECELERATION = 50 -- Studs/sec^2 deceleration on flat ground
local UPHILL_DECELERATION = 150 -- Studs/sec^2 deceleration when going uphill (quick stop)
local MIN_SPEED = 8
local MAX_SPEED = 55

-- Y-velocity thresholds for slope detection (stricter to avoid false positives)
local DOWNHILL_Y_THRESHOLD = -4 -- Y velocity below this = actually going downhill
local UPHILL_Y_THRESHOLD = 1 -- Y velocity above this = going uphill

-- Slide-jump boost (adds to existing momentum)
local SLIDE_JUMP_EXTRA_SPEED = 18 -- Extra studs/sec added to current velocity
local SLIDE_JUMP_MOMENTUM_TIME = 0.3 -- How long to maintain momentum after jump

-- Enhanced slide jump (triggered from momentum system at 100%)
local ENHANCED_SLIDE_JUMP_POWER = 70 -- Base upward velocity
local ENHANCED_SLIDE_JUMP_FORWARD_BOOST = 130 -- Forward momentum
local ENHANCED_SLIDE_JUMP_CAMERA_Y_BOOST = 70 -- Camera Y boost
local ENHANCED_SLIDE_JUMP_ANIMATION = "rbxassetid://131915305278984" -- Same as enhanced dash

-- Animation
local SLIDE_ANIMATION = "rbxassetid://101660172801114"

-- =============================================================================
-- SERVER
-- =============================================================================
function Slide:OnConstructServer()
	self.slideActive = false
	self.slidingEffect = nil
	self.bodyVelocity = nil
end

function Slide:OnStartServer()
	-- Block if in blocking status
	if
		self.Character.IsGuardbroken
		or self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Knockdown, Attacking, HeavyAttacking, Dashing, Sliding, WallRunning })
	then
		return
	end

	local character = self.Character.Instance
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid

	if not hrp or not humanoid then
		return
	end

	-- Must be grounded
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
		return
	end

	-- Must be moving forward
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude > 0.1 then
		local lookVector = hrp.CFrame.LookVector
		local forwardDot = moveDir:Dot(Vector3.new(lookVector.X, 0, lookVector.Z).Unit)
		if forwardDot < 0.5 then
			return
		end
	end

	self:_performSlide(humanoid, hrp)
end

function Slide:_performSlide(humanoid: Humanoid, hrp: BasePart)
	-- Apply status effect
	self.slidingEffect = Sliding.new(self.Character)
	if self.slidingEffect then
		self.slidingEffect:Start(MAX_SLIDE_DURATION)
	end

	-- Get initial velocity and direction
	local currentVelocity = hrp.AssemblyLinearVelocity
	local currentHorizontalSpeed = Vector3.new(currentVelocity.X, 0, currentVelocity.Z).Magnitude
	local speed = math.max(currentHorizontalSpeed, BASE_SLIDE_SPEED) * 1.1
	local direction = self:_getSlideDirection(humanoid, hrp)

	-- Create BodyVelocity (same approach as Dodge)
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(30000, 0, 30000)
	bodyVelocity.P = 1250
	bodyVelocity.Velocity = direction * speed
	bodyVelocity.Parent = hrp

	self.bodyVelocity = bodyVelocity
	self.slideActive = true

	-- Attributes for client
	self.Character.Instance:SetAttribute("_SlideActive", true)
	self.Character.Instance:SetAttribute("_SlideGainingVelocity", false)

	local elapsed = 0
	local rate = 1 / 60
	local framesNotDownhill = 0
	local initialDirection = direction -- Store initial direction for turn check
	local turnThreshold = math.cos(math.rad(MAX_TURN_ANGLE)) -- Pre-calculate cosine

	while elapsed < MAX_SLIDE_DURATION and self.slideActive do
		-- Update direction for steering
		direction = self:_getSlideDirection(humanoid, hrp)

		-- Check turn angle - cancel if turned too far from initial direction
		local turnDot = direction:Dot(initialDirection)
		if turnDot < turnThreshold then
			break -- Turned more than MAX_TURN_ANGLE degrees
		end

		-- Check for slide-jump: if player jumps, give them extra momentum
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
			-- Add extra speed and maintain momentum briefly
			self:_applySlideJumpBoost(hrp, direction, speed, bodyVelocity)
			-- Don't cleanup yet - the boost function handles it
			self.bodyVelocity = nil -- Prevent cleanup from destroying it
			break
		end

		-- Y-velocity based slope detection (simple and reliable)
		local yVelocity = hrp.AssemblyLinearVelocity.Y
		local isDownhill = yVelocity < DOWNHILL_Y_THRESHOLD
		local isUphill = yVelocity > UPHILL_Y_THRESHOLD

		-- Track consecutive frames not going downhill
		if isDownhill then
			framesNotDownhill = 0
		else
			framesNotDownhill = framesNotDownhill + 1
		end

		-- Apply physics based on Y velocity
		if isDownhill then
			-- DOWNHILL: Accelerate (steeper = faster)
			local steepnessFactor = math.clamp(math.abs(yVelocity) / 10, 1, 2)
			speed = speed + (SLOPE_ACCELERATION * steepnessFactor * rate)
		elseif isUphill then
			-- UPHILL: Rapid deceleration (feels responsive, not instant cancel)
			speed = speed - (UPHILL_DECELERATION * rate)
		else
			-- FLAT: Gradual deceleration
			speed = speed - (FLAT_DECELERATION * rate)
		end

		-- Clamp speed
		speed = math.clamp(speed, MIN_SPEED, MAX_SPEED)

		-- Update velocity
		bodyVelocity.Velocity = direction * speed

		-- Update attribute for client
		self.Character.Instance:SetAttribute("_SlideGainingVelocity", isDownhill)

		-- END CONDITIONS
		-- 1. Base duration passed AND not going downhill
		if elapsed >= SLIDE_DURATION then
			if framesNotDownhill > 5 then -- ~0.08 seconds not downhill
				break
			end
		end

		-- 2. Speed too low
		if speed <= MIN_SPEED then
			break
		end

		task.wait(rate)
		elapsed = elapsed + rate
	end

	-- Cleanup
	self:_cleanup()
	self:End()
end

function Slide:_getSlideDirection(_humanoid: Humanoid, hrp: BasePart): Vector3
	-- Use look vector for steering
	local lookVector = hrp.CFrame.LookVector
	return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
end

function Slide:_applySlideJumpBoost(hrp: BasePart, _direction: Vector3, currentSpeed: number, bodyVelocity: BodyVelocity)
	-- Boost speed and allow steering during the jump
	local boostedSpeed = currentSpeed + SLIDE_JUMP_EXTRA_SPEED
	local startTime = tick()
	local connection: RBXScriptConnection?

	-- Update direction each frame to allow air control
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime

		if elapsed >= SLIDE_JUMP_MOMENTUM_TIME or not hrp or not hrp.Parent or not bodyVelocity or not bodyVelocity.Parent then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			if bodyVelocity and bodyVelocity.Parent then
				bodyVelocity:Destroy()
			end
			return
		end

		-- Update direction based on current look vector (allows steering)
		local lookVector = hrp.CFrame.LookVector
		local currentDirection = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
		bodyVelocity.Velocity = currentDirection * boostedSpeed
	end)
end

function Slide:_cleanup()
	if self.bodyVelocity then
		self.bodyVelocity:Destroy()
		self.bodyVelocity = nil
	end

	self.Character.Instance:SetAttribute("_SlideActive", nil)
	self.Character.Instance:SetAttribute("_SlideGainingVelocity", nil)

	self.slideActive = false
end

function Slide:OnEndServer()
	self:_cleanup()

	if self.slidingEffect then
		self.slidingEffect:End()
		self.slidingEffect = nil
	end

	self:ApplyCooldown(SLIDE_COOLDOWN)
end

-- =============================================================================
-- CLIENT
-- =============================================================================
function Slide:OnConstructClient()
	self.slideAnimation = nil
	self.currentAnimTrack = nil
	self.cancelConnection = nil
	self.slideVFXAttachment = nil
	self.slideSFX = nil
	self.slideStartTime = 0

	-- Preload animation
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = SLIDE_ANIMATION
			self.slideAnimation = animator:LoadAnimation(animation)
		end
	end
end

function Slide:OnStartClient()
	-- Check if player is wall running (direct attribute check - more reliable than status effect)
	local character = self.Character.Instance
	if character:GetAttribute("IsWallRunning") then
		print("[Slide] Client: Blocked - Player is wall running")
		return
	end

	-- Block checks
	if
		self.Character:HasStatusEffects({
			SoftHitstun, TrueHitstun, Stun, Dashing, Sliding,
			Guardbroken, Knockdown, Attacking, HeavyAttacking,
		})
	then
		return
	end
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid

	if humanoid then
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
			return
		end

		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
		if hrp then
			local moveDir = humanoid.MoveDirection
			if moveDir.Magnitude > 0.1 then
				local lookVector = hrp.CFrame.LookVector
				local forwardDot = moveDir:Dot(Vector3.new(lookVector.X, 0, lookVector.Z).Unit)
				if forwardDot < 0.5 then
					return
				end
			end
		end
	end

	self.slideStartTime = tick()

	-- Play animation (looped for extended slides)
	if self.slideAnimation then
		self.currentAnimTrack = self.slideAnimation
		self.slideAnimation.Looped = true
		self.slideAnimation:Play(0.05)
		self.slideAnimation.Priority = Enum.AnimationPriority.Action2
	end

	-- VFX
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local rollVFXSource = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Movement")
		and ReplicatedStorage.Assets.VFX.Movement:FindFirstChild("roll")
		and ReplicatedStorage.Assets.VFX.Movement.roll:FindFirstChild("Attachment")

	if rollVFXSource and hrp then
		local vfxClone = rollVFXSource:Clone()
		vfxClone.Parent = hrp
		self.slideVFXAttachment = vfxClone

		for _, child in ipairs(vfxClone:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = true
			end
		end
	end

	-- SFX
	self:_playSlideSFX()

	-- Cancel listener
	self.cancelConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.LeftControl then
			self:_attemptCancel()
		end
	end)
end

function Slide:_playSlideSFX()
	local sfxFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("SFX")
		and ReplicatedStorage.Assets.SFX:FindFirstChild("Movement")
		and ReplicatedStorage.Assets.SFX.Movement:FindFirstChild("Dodges")

	if not sfxFolder then return end

	local hrp = self.Character.Instance:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local sounds = {}
	for _, child in ipairs(sfxFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then return end

	local randomSound = sounds[math.random(1, #sounds)]
	local soundClone = randomSound:Clone()
	-- Route through SFX volume control
	local sfxManager = getSFXManager()
	if sfxManager then
		soundClone.SoundGroup = sfxManager.getSoundGroup()
	end
	soundClone.Parent = hrp
	soundClone:Play()

	self.slideSFX = soundClone

	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)
end

function Slide:_attemptCancel()
	local elapsed = tick() - self.slideStartTime
	if elapsed < 0.3 then return end

	local isGainingVelocity = self.Character.Instance:GetAttribute("_SlideGainingVelocity")
	if isGainingVelocity then return end

	self:End()
end

function Slide:OnEndClient()
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	if self.cancelConnection then
		self.cancelConnection:Disconnect()
		self.cancelConnection = nil
	end

	-- Stop slide SFX immediately when ending (prevents double sound with enhanced slide jump)
	if self.slideSFX then
		self.slideSFX:Stop()
		self.slideSFX:Destroy()
		self.slideSFX = nil
	end

	if self.slideVFXAttachment then
		local vfx = self.slideVFXAttachment
		self.slideVFXAttachment = nil

		for _, child in ipairs(vfx:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end

		local maxLifetime = 0
		for _, child in ipairs(vfx:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				local lifetime = child.Lifetime.Max
				if lifetime > maxLifetime then
					maxLifetime = lifetime
				end
			end
		end

		task.delay(maxLifetime + 0.5, function()
			if vfx and vfx.Parent then
				vfx:Destroy()
			end
		end)
	end

	task.defer(function()
		local resumeSprintEvent = ReplicatedStorage:FindFirstChild("ResumeSprintAfterDodge")
		if resumeSprintEvent then
			resumeSprintEvent:Fire()
		end
	end)
end

-- =============================================================================
-- ENHANCED SLIDE JUMP (Static method callable from momentum system)
-- =============================================================================

-- Perform enhanced slide jump (called from momentum manager at 100% momentum)
-- This is a static method that can be called without a skill instance
function Slide.PerformEnhancedSlideJump(wcsCharacter: any)
	if not RunService:IsClient() then
		return -- Only runs on client
	end

	local character = wcsCharacter.Instance
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoid or not hrp then
		return
	end

	-- End the current slide skill
	local slideSkill = wcsCharacter:GetSkillFromConstructor(Slide)
	if slideSkill then
		local state = slideSkill:GetState()
		if state.IsActive then
			slideSkill:End()
		end
	end

	-- Apply enhanced jump velocity using camera direction
	local camera = workspace.CurrentCamera
	local cameraLook = camera.CFrame.LookVector

	-- Calculate horizontal direction for forward boost
	local horizontalDirection = Vector3.new(cameraLook.X, 0, cameraLook.Z).Unit
	local forwardBoost = horizontalDirection * ENHANCED_SLIDE_JUMP_FORWARD_BOOST

	-- Camera Y directly influences vertical velocity (looking up = higher jump, looking down = lower)
	local cameraYBoost = cameraLook.Y * ENHANCED_SLIDE_JUMP_CAMERA_Y_BOOST

	-- Apply velocity: horizontal boost + base power + camera Y boost
	hrp.AssemblyLinearVelocity = Vector3.new(forwardBoost.X, ENHANCED_SLIDE_JUMP_POWER + cameraYBoost, forwardBoost.Z)

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
			-- Route through SFX volume control
			local sfxManager = getSFXManager()
			if sfxManager then
				soundClone.SoundGroup = sfxManager.getSoundGroup()
			end
			soundClone.Parent = hrp
			soundClone:Play()

			task.delay(soundClone.TimeLength + 0.1, function()
				if soundClone and soundClone.Parent then
					soundClone:Destroy()
				end
			end)
		end
	end

	print("[Slide] Enhanced slide jump performed!")
end

return Slide
