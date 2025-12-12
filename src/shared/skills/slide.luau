--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local WCS = require(ReplicatedStorage.Packages.wcs)

-- Pre-cache status effects at module load (avoid require() in hot paths)
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local Sliding = require(ReplicatedStorage.Shared.statusEffects.sliding)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking)

local Slide = WCS.RegisterSkill("Slide")

-- WCS Client Prediction Configuration
Slide.CheckClientState = false
Slide.CheckOthersActive = false

-- Configuration
local SLIDE_DISTANCE = 20 -- Studs to travel (slightly longer than dodge)
local SLIDE_DURATION = 0.5 -- Seconds for slide to complete
local SLIDE_COOLDOWN = 1.2 -- Cooldown after slide completes
local SLOPE_MOMENTUM_MULTIPLIER = 1.5 -- Extra speed on downward slopes

-- Animation ID
local SLIDE_ANIMATION = "rbxassetid://101660172801114"

function Slide:OnConstructServer()
	self.slideActive = false
	self.slidingEffect = nil
	self.bodyVelocity = nil
	self.completedNaturally = false
end

function Slide:OnConstructClient()
	self.slideAnimation = nil
	self.currentAnimTrack = nil
	self.cancelConnection = nil
	self.slideVFXAttachment = nil
	self.slideSFX = nil
	self.slideStartTime = 0 -- Track when slide started for cancel delay

	-- Preload slide animation
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

function Slide:OnStartServer()
	-- Check if player is in hitstun, guardbroken, knocked down, or attacking
	if
		self.Character.IsGuardbroken
		or self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Knockdown, Attacking, HeavyAttacking, Dashing, Sliding })
	then
		print("[Slide] Server: Cannot slide - Player is in blocking status")
		return
	end

	-- Get character components
	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid

	if not humanoidRootPart or not humanoid then
		warn("[Slide] Server: Missing HumanoidRootPart or Humanoid")
		return
	end

	-- Check if grounded - sliding only works on ground
	local humanoidState = humanoid:GetState()
	local isInAirState = humanoidState == Enum.HumanoidStateType.Freefall
		or humanoidState == Enum.HumanoidStateType.Jumping

	if isInAirState then
		print("[Slide] Server: Cannot slide - Player is in air")
		return
	end

	-- Check if moving forward (or not moving at all)
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude > 0.1 then
		local lookVector = humanoidRootPart.CFrame.LookVector
		local forwardDot = moveDir:Dot(Vector3.new(lookVector.X, 0, lookVector.Z).Unit)
		-- Only allow slide if moving forward (dot product > 0.5 means within ~60 degrees of forward)
		if forwardDot < 0.5 then
			print("[Slide] Server: Cannot slide - not moving forward")
			return
		end
	end

	-- Perform slide
	self:_performSlide(humanoid, humanoidRootPart)
end

function Slide:_performSlide(humanoid: Humanoid, humanoidRootPart: BasePart)
	-- Apply Sliding status effect
	self.slidingEffect = Sliding.new(self.Character)
	if self.slidingEffect then
		self.slidingEffect:Start(SLIDE_DURATION)
		print("[Slide] Server: Applied Sliding status effect")
	end

	-- Calculate slide direction
	local slideStrength = SLIDE_DISTANCE / SLIDE_DURATION
	local rate = 0.0167

	print(`[Slide] Server: Starting slide - Strength: {slideStrength}`)

	-- Create BodyVelocity for movement
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVelocity.P = 5000
	bodyVelocity.Parent = humanoidRootPart

	self.bodyVelocity = bodyVelocity
	self.slideActive = true

	-- Set slide cancel window
	self.Character.Instance:SetAttribute("_SlideCancelWindowEnd", tick() + SLIDE_DURATION)

	local elapsed = 0

	while elapsed < SLIDE_DURATION do
		if not self.slideActive then
			-- Cancelled early
			break
		end

		-- Calculate direction each frame for control
		local direction = self:_calculateSlideDirection(humanoid, humanoidRootPart)

		-- Check for downward slope and apply momentum boost
		local slopeMultiplier = self:_getSlopeMultiplier(humanoidRootPart, direction)

		-- Apply easing at the end
		local progress = elapsed / SLIDE_DURATION
		local speedMultiplier = 1

		if progress > 0.7 then
			local easeProgress = (progress - 0.7) / 0.3
			speedMultiplier = 1 - (easeProgress * 0.3)
		end

		bodyVelocity.Velocity = direction * slideStrength * speedMultiplier * slopeMultiplier

		-- Wall collision check
		local currentVelocity = humanoidRootPart.AssemblyLinearVelocity
		local expectedSpeed = slideStrength * speedMultiplier * slopeMultiplier

		if currentVelocity.Magnitude < expectedSpeed * 0.3 and elapsed > 0.1 then
			print("[Slide] Wall collision detected - Stopping slide")
			self.slideActive = false
			break
		end

		task.wait(rate)
		elapsed = elapsed + rate
	end

	print("[Slide] Slide loop completed - Cleaning up")

	-- Clean up
	if self.bodyVelocity then
		self.bodyVelocity:Destroy()
		self.bodyVelocity = nil
	end

	self.slideActive = false
	self.completedNaturally = true

	self:End()
end

-- Calculate slide direction - always forward (look vector)
function Slide:_calculateSlideDirection(humanoid: Humanoid, hrp: BasePart): Vector3
	-- Slide always goes in character's forward direction
	local lookVector = hrp.CFrame.LookVector
	return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
end

-- Get slope multiplier for momentum boost on downhill
function Slide:_getSlopeMultiplier(hrp: BasePart, direction: Vector3): number
	-- Raycast downward to check slope
	local rayOrigin = hrp.Position
	local rayDirection = Vector3.new(0, -5, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { hrp.Parent }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if result then
		local normal = result.Normal
		-- Check if surface is sloped downward in our direction
		-- Normal pointing up = flat, normal tilted = slope
		local slopeDot = -direction:Dot(Vector3.new(normal.X, 0, normal.Z))

		if slopeDot > 0.1 then
			-- Going downhill - apply momentum boost
			local slopeAmount = math.min(slopeDot * SLOPE_MOMENTUM_MULTIPLIER, SLOPE_MOMENTUM_MULTIPLIER)
			return 1 + slopeAmount
		end
	end

	return 1 -- No slope bonus
end

function Slide:OnStartClient()
	-- Check status effects
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Dashing,
			Sliding,
			Guardbroken,
			Knockdown,
			Attacking,
			HeavyAttacking,
		})
	then
		print("[Slide] Client: Blocked by status effect")
		return
	end

	-- Check if grounded
	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	if humanoid then
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
			print("[Slide] Client: Cannot slide in air")
			return
		end

		-- Check if moving forward (or not moving at all)
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
		if hrp then
			local moveDir = humanoid.MoveDirection
			if moveDir.Magnitude > 0.1 then
				local lookVector = hrp.CFrame.LookVector
				local forwardDot = moveDir:Dot(Vector3.new(lookVector.X, 0, lookVector.Z).Unit)
				-- Only allow slide if moving forward (dot product > 0.5 means within ~60 degrees of forward)
				if forwardDot < 0.5 then
					print("[Slide] Client: Cannot slide - not moving forward")
					return
				end
			end
		end
	end

	-- Track slide start time for cancel delay
	self.slideStartTime = tick()

	-- Play slide animation
	if self.slideAnimation then
		self.currentAnimTrack = self.slideAnimation
		self.slideAnimation:Play(0.05)
		self.slideAnimation.Priority = Enum.AnimationPriority.Action2
		print("[Slide] Client: Playing slide animation")
	end

	-- Setup VFX (reuse roll VFX if exists)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local rollVFXSource = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Movement")
		and ReplicatedStorage.Assets.VFX.Movement:FindFirstChild("roll")
		and ReplicatedStorage.Assets.VFX.Movement.roll:FindFirstChild("Attachment")

	if rollVFXSource and hrp then
		local slideVFXClone = rollVFXSource:Clone()
		slideVFXClone.Parent = hrp
		self.slideVFXAttachment = slideVFXClone

		for _, child in ipairs(slideVFXClone:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = true
			end
		end

		-- Schedule cleanup
		task.delay(SLIDE_DURATION, function()
			if slideVFXClone and slideVFXClone.Parent then
				for _, child in ipairs(slideVFXClone:GetChildren()) do
					if child:IsA("ParticleEmitter") then
						child.Enabled = false
					end
				end

				local maxLifetime = 0
				for _, child in ipairs(slideVFXClone:GetChildren()) do
					if child:IsA("ParticleEmitter") then
						local lifetime = child.Lifetime.Max
						if lifetime > maxLifetime then
							maxLifetime = lifetime
						end
					end
				end

				task.delay(maxLifetime + 0.5, function()
					if slideVFXClone and slideVFXClone.Parent then
						slideVFXClone:Destroy()
						self.slideVFXAttachment = nil
					end
				end)
			end
		end)
	end

	-- Play SFX (reuse dodge SFX if exists)
	self:_playSlideSFX()

	-- Setup Control key listener for slide cancel
	self.cancelConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.LeftControl then
			self:_attemptCancel()
		end
	end)

	-- Auto-disconnect after slide duration
	task.delay(SLIDE_DURATION * 1.2, function()
		if self.cancelConnection then
			self.cancelConnection:Disconnect()
			self.cancelConnection = nil
		end
	end)
end

function Slide:_playSlideSFX()
	local dodgeSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("SFX")
		and ReplicatedStorage.Assets.SFX:FindFirstChild("Movement")
		and ReplicatedStorage.Assets.SFX.Movement:FindFirstChild("Dodges")

	if not dodgeSFXFolder then
		return
	end

	local character = self.Character.Instance
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local sounds = {}
	for _, child in ipairs(dodgeSFXFolder:GetChildren()) do
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

	self.slideSFX = soundClone

	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)
end

local SLIDE_CANCEL_DELAY = 0.3 -- Minimum time before slide can be cancelled

function Slide:_attemptCancel()
	-- Check if enough time has passed (0.3s minimum)
	local elapsed = tick() - self.slideStartTime
	if elapsed < SLIDE_CANCEL_DELAY then
		print(`[Slide] Client: Cannot cancel yet - only {elapsed}s elapsed, need {SLIDE_CANCEL_DELAY}s`)
		return
	end

	print("[Slide] Client: Cancelling slide")

	-- Stop animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	-- Cleanup VFX
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

	-- Disconnect cancel listener
	if self.cancelConnection then
		self.cancelConnection:Disconnect()
		self.cancelConnection = nil
	end

	-- End skill
	self:End()
end

function Slide:OnEndServer()
	self.slideActive = false

	-- Remove BodyVelocity
	if self.bodyVelocity then
		self.bodyVelocity:Destroy()
		self.bodyVelocity = nil
	end

	-- End Sliding status effect
	if self.slidingEffect then
		self.slidingEffect:End()
		self.slidingEffect = nil
		print("[Slide] Server: Ended Sliding status effect")
	end

	-- Apply cooldown
	self:ApplyCooldown(SLIDE_COOLDOWN)
	print("[Slide] Server: Slide ended - Cooldown applied")

	self.completedNaturally = false
end

function Slide:OnEndClient()
	-- Stop animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	-- Disconnect cancel listener
	if self.cancelConnection then
		self.cancelConnection:Disconnect()
		self.cancelConnection = nil
	end

	-- Resume sprinting if W is held
	task.defer(function()
		local resumeSprintEvent = ReplicatedStorage:FindFirstChild("ResumeSprintAfterDodge")
		if resumeSprintEvent then
			resumeSprintEvent:Fire()
		end
	end)

	print("[Slide] Client: Skill ended")
end

return Slide
