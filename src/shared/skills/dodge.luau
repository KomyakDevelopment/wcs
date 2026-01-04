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

-- Pre-cache status effects at module load (avoid require() in hot paths)
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local Iframes = require(ReplicatedStorage.Shared.statusEffects.iframes)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking)
local Daze = require(ReplicatedStorage.Shared.statusEffects.daze)

-- Lazy-loaded to avoid circular dependency (punch requires dodge)
local Punch = nil
local Slash = nil

local Dodge = WCS.RegisterSkill("Dodge")

-- WCS Client Prediction Configuration
-- These settings make the skill feel responsive by not waiting for server validation
Dodge.CheckClientState = false -- Don't wait for server to validate before playing client effects
Dodge.CheckOthersActive = false -- Don't check if other skills are active (we handle this manually)

-- Configuration
local DODGE_DISTANCE = 17 -- Studs to travel (slightly longer than 16)
local DODGE_DURATION = 0.345 -- Seconds for dodge to complete (15% slower: 0.3 * 1.15 = 0.345)
local DODGE_COOLDOWN = 1 -- Cooldown after dodge completes
local MAX_CANCELS = 1 -- Maximum number of times you can cancel (1 cancel = 2 total rolls)

-- Air dash configuration
local AIR_DASH_DISTANCE = 17 -- Same distance as ground dodge
local AIR_DASH_DURATION = 0.295 -- Faster than ground dodge 79892666286494
local AIR_DASH_ANIMATION = "rbxassetid://127043982553357" -- Different animation for air dash 96765830085186
local AIR_DASH_Y_INFLUENCE = 0.5 -- How much camera pitch tilts the dash direction (0 = horizontal only, 1 = full camera direction)

-- Enhanced dash configuration (triggered from momentum system at 100%)
local ENHANCED_DASH_DISTANCE = 40 -- Fixed 40 stud distance
local ENHANCED_DASH_SPEED_MULTIPLIER = 2 -- 2x the speed
local ENHANCED_DASH_ANIMATION = "rbxassetid://131915305278984" -- Special animation for enhanced dash

-- Iframes configuration
local IFRAME_START = 0 -- Iframes start immediately when dodge begins
local IFRAME_END = 0.55 -- Iframes end right before dodge completes (increased for better dodge window)

-- Animation IDs for each direction
local DODGE_ANIMATIONS = {
	Forward = "rbxassetid://85622930154432",
	Backward = "rbxassetid://97514479751497",
	Left = "rbxassetid://82194383365576",
	Right = "rbxassetid://97514479751497",
}

function Dodge:OnConstructServer()
	self.dodgeActive = false
	self.dashingEffect = nil
	self.bodyVelocity = nil
	self.iframesEffect = nil
	self.isAirDash = false
	self.landedConnection = nil
	self.completedNaturally = false -- Track if skill completed naturally vs cancelled

	-- Retrieve persistent cancel count from character instance
	-- Store it in the character model itself for persistence across skill instances
	local character = self.Character.Instance
	local cancelCountValue = character:FindFirstChild("_DodgeCancelCount") :: IntValue

	if not cancelCountValue then
		-- Create IntValue to store cancel count persistently
		local newValue = Instance.new("IntValue")
		newValue.Name = "_DodgeCancelCount"
		newValue.Value = 0
		newValue.Parent = character
		cancelCountValue = newValue
	end

	self.cancelCountRef = cancelCountValue
end

function Dodge:OnConstructClient()
	self.loadedAnimations = {}
	self.currentAnimTrack = nil
	self.m2Connection = nil
	self.rollVFXAttachment = nil
	self.dodgeSFX = nil
	self.isAirDash = false
	self.isEnhancedDashClient = false
	self.airDashAnimation = nil
	self.enhancedDashAnimation = nil

	-- Preload all dodge animations
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for direction, animId in pairs(DODGE_ANIMATIONS) do
				local animation = Instance.new("Animation")
				animation.AnimationId = animId
				self.loadedAnimations[direction] = animator:LoadAnimation(animation)
			end

			-- Preload air dash animation
			local airDashAnim = Instance.new("Animation")
			airDashAnim.AnimationId = AIR_DASH_ANIMATION
			self.airDashAnimation = animator:LoadAnimation(airDashAnim)

			-- Preload enhanced dash animation
			local enhancedDashAnim = Instance.new("Animation")
			enhancedDashAnim.AnimationId = ENHANCED_DASH_ANIMATION
			self.enhancedDashAnimation = animator:LoadAnimation(enhancedDashAnim)
		end
	end
end

function Dodge:OnStartServer()
	-- Check if player is in hitstun, guardbroken, knocked down, attacking, or dazed
	if
		self.Character.IsGuardbroken
		or self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Knockdown, Attacking, HeavyAttacking, Daze })
	then
		print("[Dodge] Server: Cannot dodge - Player is in hitstun, guardbroken, knocked down, attacking, or dazed")
		return
	end

	-- ALSO check if M1 skills are active (catches race condition before Attacking status applies)
	-- Lazy-load skills to avoid circular dependency
	if not Punch then
		Punch = require(ReplicatedStorage.Shared.skills.punch)
	end
	if not Slash then
		Slash = require(ReplicatedStorage.Shared.skills.slash)
	end

	local punchSkill = self.Character:GetSkillFromConstructor(Punch)
	if punchSkill then
		local punchState = punchSkill:GetState()
		if punchState.IsActive then
			print("[Dodge] Server: Cannot dodge - Punch skill is active")
			return
		end
	end

	local slashSkill = self.Character:GetSkillFromConstructor(Slash)
	if slashSkill then
		local slashState = slashSkill:GetState()
		if slashState.IsActive then
			print("[Dodge] Server: Cannot dodge - Slash skill is active")
			return
		end
	end

	-- Get character components
	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid

	if not humanoidRootPart or not humanoid then
		warn("[Dodge] Server: Missing HumanoidRootPart or Humanoid")
		return
	end

	-- Check if player is wall jumping - cannot dodge during wall jump
	if character:GetAttribute("IsWallJumping") then
		print("[Dodge] Server: Cannot dodge - Player is wall jumping")
		return
	end

	-- Check if player is wall running - dodge cancels wall run
	if character:GetAttribute("IsWallRunning") then
		print("[Dodge] Server: Player is wall running - cancelling wall run for dodge")
		character:SetAttribute("CancelWallRun", true)
		-- Small delay to let wall run end before dodge starts
		task.wait(0.05)
	end

	-- Check if character is grounded using humanoid state (more reliable than raycast alone)
	local humanoidState = humanoid:GetState()
	local isInAirState = humanoidState == Enum.HumanoidStateType.Freefall
		or humanoidState == Enum.HumanoidStateType.Jumping

	-- Also do a short raycast as backup check (requires at least 5 studs height for airdash)
	local rayOrigin = humanoidRootPart.Position
	local rayDirection = Vector3.new(0, -5, 0) -- Require 5 studs height minimum for airdash
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local isGroundedByRaycast = raycastResult ~= nil

	-- Player is in air if EITHER humanoid says so OR raycast doesn't hit ground
	local isGrounded = not isInAirState and isGroundedByRaycast

	-- Determine if this is an air dash or ground dodge
	self.isAirDash = not isGrounded
	print(
		`[Dodge] Server: Grounded check - State: {humanoidState.Name}, InAirState: {isInAirState}, RayHit: {isGroundedByRaycast}, IsAirDash: {self.isAirDash}`
	)

	if self.isAirDash then
		self:_performAirDash(humanoid, humanoidRootPart)
	else
		self:_performGroundDodge(humanoid, humanoidRootPart)
	end
end

-- Perform ground dodge (original behavior)
function Dodge:_performGroundDodge(humanoid: Humanoid, humanoidRootPart: BasePart)
	-- Apply Dashing status effect to block attacks
	self.dashingEffect = Dashing.new(self.Character)
	if self.dashingEffect then
		self.dashingEffect:Start(DODGE_DURATION)
		print("[Dodge] Server: Applied Dashing status effect")
	end

	-- Calculate initial dash direction and strength
	local dashStrength = DODGE_DISTANCE / DODGE_DURATION
	local rate = 0.0167

	print(`[Dodge] Server: Starting ground dodge - Strength: {dashStrength}`)

	-- Create BodyVelocity for smooth movement
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVelocity.P = 15000 -- High P value to overcome Humanoid movement interference when no input
	bodyVelocity.Parent = humanoidRootPart

	self.bodyVelocity = bodyVelocity
	self.dodgeActive = true
	self.Character.Instance:SetAttribute("_DashActive", true)

	-- Apply iframes immediately if IFRAME_START is 0, otherwise schedule for later
	if IFRAME_START == 0 then
		-- Immediate iframe application (no delay)
		self.iframesEffect = Iframes.new(self.Character)
		if self.iframesEffect then
			local iframeDuration = IFRAME_END - IFRAME_START
			self.iframesEffect:Start(iframeDuration)
			-- Set rollcancel window end time (first 75% of DODGE duration, not iframe duration)
			-- This ensures rollcancel only works in the early part of the actual roll animation
			self.Character.Instance:SetAttribute("_RollcancelWindowEnd", tick() + (DODGE_DURATION * 0.75))
			print(
				`[Dodge] Server: Applied iframes immediately for {iframeDuration}s, rollcancel window: {DODGE_DURATION * 0.75}s`
			)
		end
	else
		-- Schedule iframes to start after IFRAME_START delay
		task.delay(IFRAME_START, function()
			if not self.dodgeActive then
				return -- Dodge was cancelled
			end

			self.iframesEffect = Iframes.new(self.Character)
			if self.iframesEffect then
				local iframeDuration = IFRAME_END - IFRAME_START
				self.iframesEffect:Start(iframeDuration)
				-- Set rollcancel window end time (first 75% of DODGE duration, not iframe duration)
				self.Character.Instance:SetAttribute("_RollcancelWindowEnd", tick() + (DODGE_DURATION * 0.75))
				print(
					`[Dodge] Server: Applied iframes for {iframeDuration}s, rollcancel window: {DODGE_DURATION * 0.75}s`
				)
			end
		end)
	end

	-- Apply velocity with direction updates for control
	local elapsed = 0

	while elapsed < DODGE_DURATION do
		if not self.dodgeActive then
			-- Cancelled early
			break
		end

		-- Recalculate direction each frame for more responsive control
		local direction = self:_calculateDashDirection(humanoid, humanoidRootPart)

		-- Apply subtle easing at the end (last 20% of duration slows down slightly)
		local progress = elapsed / DODGE_DURATION
		local speedMultiplier = 1

		if progress > 0.8 then
			-- Gentle ease out in the last 20% of the dodge
			local easeProgress = (progress - 0.8) / 0.2 -- 0 to 1 in the last 20%
			speedMultiplier = 1 - (easeProgress * 0.175) -- Gradually reduce by 17.5%
		end

		bodyVelocity.Velocity = direction * dashStrength * speedMultiplier

		-- Check for wall collision (velocity suddenly drops)
		-- Only check horizontal velocity since ground dodge only controls X/Z (MaxForce Y = 0)
		local currentVelocity = humanoidRootPart.AssemblyLinearVelocity
		local horizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
		local expectedSpeed = dashStrength * speedMultiplier
		local actualSpeed = horizontalVelocity.Magnitude
		local threshold = expectedSpeed * 0.2 -- 20% threshold (more lenient than 30%)

		-- If actual horizontal speed is much lower than expected, we hit a wall
		-- Use 0.15s elapsed threshold to give more time for velocity to stabilize
		if actualSpeed < threshold and elapsed > 0.15 then
			print(`[Dodge] Wall collision detected - Actual: {actualSpeed}, Threshold: {threshold}, Elapsed: {elapsed}`)
			self.dodgeActive = false
			break
		end

		task.wait(rate)
		elapsed = elapsed + rate
	end

	print("[Dodge] Ground dodge loop completed - Cleaning up")

	-- Clean up BodyVelocity
	if self.bodyVelocity then
		self.bodyVelocity:Destroy()
		self.bodyVelocity = nil
	end

	self.dodgeActive = false
	self.completedNaturally = true

	-- End the skill properly (OnEndServer will handle cooldown/cancel logic)
	self:End()
end

-- Perform air dash (new behavior)
function Dodge:_performAirDash(humanoid: Humanoid, humanoidRootPart: BasePart)
	local character = self.Character.Instance

	-- Check for enhanced dash (triggered by momentum system at 100%)
	-- Uses server-side store since client attributes don't replicate
	local Players = game:GetService("Players")
	local player = Players:GetPlayerFromCharacter(character)
	local isEnhancedDash = false

	if player and _G.EnhancedDashStore then
		isEnhancedDash = _G.EnhancedDashStore.get(player)
	end

	if isEnhancedDash then
		self.isEnhancedDash = true
		print("[Dodge] Server: ENHANCED DASH activated!")
	else
		self.isEnhancedDash = false
	end

	-- Calculate distance and speed based on enhanced dash
	local dashDistance = AIR_DASH_DISTANCE
	local dashDuration = AIR_DASH_DURATION

	if self.isEnhancedDash then
		dashDistance = ENHANCED_DASH_DISTANCE
		-- Speed = Distance / Duration, enhanced speed is 2x normal air dash speed
		dashDuration = ENHANCED_DASH_DISTANCE / (AIR_DASH_DISTANCE / AIR_DASH_DURATION * ENHANCED_DASH_SPEED_MULTIPLIER)
	end

	-- Apply Dashing status effect
	self.dashingEffect = Dashing.new(self.Character)
	if self.dashingEffect then
		self.dashingEffect:Start(dashDuration)
		print(`[Dodge] Server: Applied Dashing status effect ({if self.isEnhancedDash then "enhanced" else "air"} dash)`)
	end

	-- Calculate dash direction and strength - LOCKED at start (no control during air dash)
	-- For air dash, use camera direction with Y-axis component
	local dashStrength = dashDistance / dashDuration
	local lockedDirection = self:_calculateDashDirection(humanoid, humanoidRootPart, true) -- true = isAirDash
	local rate = 0.0167

	print(`[Dodge] Server: Starting {if self.isEnhancedDash then "ENHANCED" else "air"} dash - Distance: {dashDistance}, Duration: {dashDuration}, Strength: {dashStrength}`)

	-- Create BodyVelocity for movement
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000) -- Control all 3 axes
	bodyVelocity.P = 20000 -- Very high P value for aggressive velocity control (fights gravity)
	bodyVelocity.Parent = humanoidRootPart

	self.bodyVelocity = bodyVelocity
	self.dodgeActive = true
	self.Character.Instance:SetAttribute("_DashActive", true)

	-- Apply iframes immediately if IFRAME_START is 0, otherwise schedule for later
	if IFRAME_START == 0 then
		-- Immediate iframe application (no delay)
		self.iframesEffect = Iframes.new(self.Character)
		if self.iframesEffect then
			local iframeDuration = math.min(IFRAME_END - IFRAME_START, dashDuration - IFRAME_START)
			self.iframesEffect:Start(iframeDuration)
			-- Set rollcancel window end time (first 75% of dash duration)
			self.Character.Instance:SetAttribute("_RollcancelWindowEnd", tick() + (dashDuration * 0.75))
			print(
				`[Dodge] Server: Applied iframes immediately for {iframeDuration}s ({if self.isEnhancedDash then "enhanced" else "air"} dash), rollcancel window: {dashDuration * 0.75}s`
			)
		end
	else
		-- Schedule iframes (capture dashDuration for closure)
		local capturedDuration = dashDuration
		local capturedEnhanced = self.isEnhancedDash
		task.delay(IFRAME_START, function()
			if not self.dodgeActive then
				return
			end

			self.iframesEffect = Iframes.new(self.Character)
			if self.iframesEffect then
				local iframeDuration = math.min(IFRAME_END - IFRAME_START, capturedDuration - IFRAME_START)
				self.iframesEffect:Start(iframeDuration)
				-- Set rollcancel window end time (first 75% of dash duration)
				self.Character.Instance:SetAttribute("_RollcancelWindowEnd", tick() + (capturedDuration * 0.75))
				print(
					`[Dodge] Server: Applied iframes for {iframeDuration}s ({if capturedEnhanced then "enhanced" else "air"} dash), rollcancel window: {capturedDuration * 0.75}s`
				)
			end
		end)
	end

	-- Listen for landing to cancel air dash (with small delay to prevent false positives)
	task.delay(0.05, function()
		if not self.dodgeActive then
			return
		end
		self.landedConnection = humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Landed then
				print("[Dodge] Server: Air dash cancelled - Player landed")
				self.dodgeActive = false
			end
		end)
	end)

	-- Apply velocity with locked direction (camera-based 3D direction maintained throughout)
	local elapsed = 0

	-- Control all 3 axes (X, Y, Z) to maintain camera-based direction
	bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)

	-- Apply initial velocity in 3D to override current velocity
	humanoidRootPart.AssemblyLinearVelocity = lockedDirection * dashStrength

	while elapsed < dashDuration do
		if not self.dodgeActive then
			-- Cancelled (landed or other reason)
			break
		end

		-- Apply subtle easing at the end
		local progress = elapsed / dashDuration
		local speedMultiplier = 1

		if progress > 0.8 then
			local easeProgress = (progress - 0.8) / 0.2
			speedMultiplier = 1 - (easeProgress * 0.175)
		end

		-- Apply full 3D velocity to maintain camera-based direction
		local dashVelocity = lockedDirection * dashStrength * speedMultiplier

		bodyVelocity.Velocity = dashVelocity

		-- Check for wall collision (velocity suddenly drops)
		local currentVelocity = humanoidRootPart.AssemblyLinearVelocity
		local expectedSpeed = dashStrength * speedMultiplier

		-- If actual speed is much lower than expected, we hit a wall
		if currentVelocity.Magnitude < expectedSpeed * 0.3 and elapsed > 0.1 then
			print("[Dodge] Air dash wall collision detected - Stopping dash")
			self.dodgeActive = false
			break
		end

		task.wait(rate)
		elapsed = elapsed + rate
	end

	print("[Dodge] Air dash loop completed - Cleaning up")

	-- Clean up
	if self.landedConnection then
		self.landedConnection:Disconnect()
		self.landedConnection = nil
	end

	if self.bodyVelocity then
		self.bodyVelocity:Destroy()
		self.bodyVelocity = nil
	end

	self.dodgeActive = false
	self.completedNaturally = true
	-- Keep isAirDash = true so OnEndServer knows this was an air dash

	-- End the skill properly (OnEndServer will handle cooldown)
	self:End()
end

function Dodge:OnStartClient()
	-- Check if player has any hitstun status effects active, is guardbroken, dashing, attacking, or dazed
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Dashing,
			Guardbroken,
			Knockdown,
			Attacking,
			HeavyAttacking,
			Daze,
		})
	then
		print("[Dodge] Client: Blocked - Player is in hitstun/stun/guardbroken/dashing/knocked down/attacking/dazed")
		return
	end

	local character = self.Character.Instance

	-- Read sprint state - check both the pre-saved attribute AND current IsSprinting
	-- The pre-saved attribute is set by combatController before skill starts
	-- We also check IsSprinting directly as a fallback
	local savedSprintState = character:GetAttribute("_WasSprintingBeforeDodge")
	local currentSprintState = character:GetAttribute("IsSprinting")
	self.wasSprintingBeforeDodge = (savedSprintState == true) or (currentSprintState == true)
	-- Clear the saved attribute after reading
	character:SetAttribute("_WasSprintingBeforeDodge", nil)
	print(`[Dodge] Client: Sprint state - saved: {savedSprintState}, current: {currentSprintState}, using: {self.wasSprintingBeforeDodge}`)

	-- Check if player is wall jumping - cannot dodge during wall jump
	if character:GetAttribute("IsWallJumping") then
		print("[Dodge] Client: Cannot dodge - Player is wall jumping")
		return
	end

	-- Check if player is wall running - dodge cancels wall run
	if character:GetAttribute("IsWallRunning") then
		print("[Dodge] Client: Player is wall running - cancelling wall run for dodge")
		character:SetAttribute("CancelWallRun", true)
	end

	-- Stop any M1 animations that might be playing
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local tracks = animator:GetPlayingAnimationTracks()
			for _, track in ipairs(tracks) do
				-- Stop combat animations (punch animations)
				if
					track.Animation
					and (
						track.Animation.AnimationId:match("71780482128433")
						or track.Animation.AnimationId:match("122171966838136")
						or track.Animation.AnimationId:match("102972252804338")
					)
				then
					track:Stop(0.05) -- Quick fade out
					print("[Dodge] Client: Stopped M1 animation")
				end
			end
		end
	end

	-- Check if grounded for air dash detection (matching server logic)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local isGrounded = true
	if hrp and humanoid then
		-- Check humanoid state first
		local humanoidState = humanoid:GetState()
		local isInAirState = humanoidState == Enum.HumanoidStateType.Freefall
			or humanoidState == Enum.HumanoidStateType.Jumping

		-- Also do raycast (requires at least 5 studs height for airdash)
		local rayOrigin = hrp.Position
		local rayDirection = Vector3.new(0, -5, 0) -- Require 5 studs height minimum for airdash
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = { character }
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		local isGroundedByRaycast = raycastResult ~= nil

		-- Player is in air if EITHER humanoid says so OR raycast doesn't hit ground
		isGrounded = not isInAirState and isGroundedByRaycast
	end

	self.isAirDash = not isGrounded
	print(`[Dodge] Client: Air dash detection - IsAirDash: {self.isAirDash}`)

	-- Camera direction is now stored in combatController BEFORE skill activation
	-- This eliminates replication delay issues

	local activeDuration = self.isAirDash and AIR_DASH_DURATION or DODGE_DURATION

	if self.isAirDash then
		-- Check if this is an enhanced dash (client-side attribute set by momentum manager)
		local isEnhancedDash = character:GetAttribute("UseEnhancedDashAnim") == true
		if isEnhancedDash then
			-- Clear the attribute immediately
			character:SetAttribute("UseEnhancedDashAnim", nil)
		end

		-- Air dash: use enhanced or normal air dash animation
		if isEnhancedDash and self.enhancedDashAnimation then
			self.isEnhancedDashClient = true
			self.currentAnimTrack = self.enhancedDashAnimation
			self.enhancedDashAnimation:Play(0.05)
			self.enhancedDashAnimation.Priority = Enum.AnimationPriority.Action2
			print("[Dodge] Client: Playing ENHANCED dash animation")

			-- Set attribute to signal Jump skill to reset counter (more reliable than GetSkillFromConstructor)
			character:SetAttribute("_EnhancedDashResetJump", true)
			print("[Dodge] Client: Set _EnhancedDashResetJump attribute for double jump reset")
		elseif self.airDashAnimation then
			self.isEnhancedDashClient = false
			self.currentAnimTrack = self.airDashAnimation
			self.airDashAnimation:Play(0.05)
			self.airDashAnimation.Priority = Enum.AnimationPriority.Action2
			print("[Dodge] Client: Playing air dash animation")
		end
	else
		-- Ground dodge: determine direction and play appropriate animation
		local animDirection = "Forward" -- Default
		if humanoid and hrp then
			local moveDir = humanoid.MoveDirection

			if moveDir.Magnitude > 0.1 then
				-- Calculate animation direction based on movement relative to character facing
				local lookVector = hrp.CFrame.LookVector
				local rightVector = hrp.CFrame.RightVector

				-- Project movement onto character's forward and right vectors
				local forwardDot = moveDir:Dot(Vector3.new(lookVector.X, 0, lookVector.Z).Unit)
				local rightDot = moveDir:Dot(Vector3.new(rightVector.X, 0, rightVector.Z).Unit)

				-- Determine primary direction based on which component is stronger
				if math.abs(forwardDot) > math.abs(rightDot) then
					-- Moving primarily forward/backward
					animDirection = forwardDot > 0 and "Forward" or "Backward"
				else
					-- Moving primarily left/right
					animDirection = rightDot > 0 and "Right" or "Left"
				end
			end
		end

		-- Play animation for dodge direction immediately (don't wait)
		local animTrack = self.loadedAnimations[animDirection]
		if animTrack then
			self.currentAnimTrack = animTrack
			local animLength = animTrack.Length

			-- Play with adjusted speed to match dodge duration
			if animLength and animLength > 0 then
				-- Calculate speed but find middle ground between default and matched speed, 40% faster
				local perfectSpeed = animLength / DODGE_DURATION
				local speedMultiplier = 1 + ((perfectSpeed - 1) * 0.6) -- 60% toward perfect speed
				speedMultiplier = speedMultiplier * 0.8 -- Make it 40% faster

				animTrack:Play(0.05) -- Quick fade-in (0.05s)
				animTrack:AdjustSpeed(speedMultiplier) -- Adjust speed after playing
				print(
					`[Dodge] Client: Playing {animDirection} dodge animation - Length: {animLength}s, Perfect: {perfectSpeed}x, Using: {speedMultiplier}x`
				)
			else
				-- Fallback if length not available - 40% faster than before
				animTrack:Play(0.05)
				animTrack:AdjustSpeed(1.96) -- 1.4 * 1.4 = 1.96
				print(`[Dodge] Client: Playing {animDirection} dodge animation - Using default speed 1.96x`)
			end
		else
			warn(`[Dodge] Client: No animation loaded for direction: {animDirection}`)
		end
	end

	-- Setup VFX (different for ground dodge vs air dash)
	if self.isAirDash then
		-- Setup air dash VFX (emit once at start)
		local airDashVFXSource = ReplicatedStorage.Assets.VFX.Movement.air_dash.smoke
		if airDashVFXSource and hrp then
			-- CLONE the attachment so each client has their own copy
			local airDashVFXClone = airDashVFXSource:Clone()
			airDashVFXClone.Parent = hrp

			print("[Dodge] Client: Cloned and parented air dash VFX to HumanoidRootPart")

			-- Emit particles once (burst emission at air dash start)
			for _, child in ipairs(airDashVFXClone:GetChildren()) do
				if child:IsA("ParticleEmitter") then
					local emitCount = child:GetAttribute("EmitCount") or child.Rate
					child:Emit(emitCount)
					print(`[Dodge] Client: Emitted {emitCount} particles from {child.Name}`)
				end
			end

			-- Calculate max particle lifetime to know when to destroy
			local maxLifetime = 0
			for _, child in ipairs(airDashVFXClone:GetChildren()) do
				if child:IsA("ParticleEmitter") then
					local lifetime = child.Lifetime.Max
					if lifetime > maxLifetime then
						maxLifetime = lifetime
					end
				end
			end

			-- Destroy after all particles have faded out
			task.delay(maxLifetime + 0.5, function()
				if airDashVFXClone and airDashVFXClone.Parent then
					airDashVFXClone:Destroy()
					print("[Dodge] Client: Destroyed air dash VFX clone after fade")
				end
			end)
		else
			warn("[Dodge] Client: Air dash VFX attachment not found")
		end
	else
		-- Setup roll VFX (ground dodge)
		local rollVFXSource = ReplicatedStorage.Assets.VFX.Movement.roll.Attachment
		if rollVFXSource and hrp then
			-- CLONE the attachment so each client has their own copy
			local rollVFXClone = rollVFXSource:Clone()
			rollVFXClone.Parent = hrp
			self.rollVFXAttachment = rollVFXClone

			print("[Dodge] Client: Cloned and parented roll VFX to HumanoidRootPart")

			-- Raycast downward to get surface color for squares VFX
			local surfaceColor: Color3? = nil
			local rayParams = RaycastParams.new()
			rayParams.FilterDescendantsInstances = { character }
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			local groundRay = workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0), rayParams)
			if groundRay and groundRay.Instance then
				surfaceColor = groundRay.Instance.Color
			end

			-- Enable all ParticleEmitters and apply surface color to squares
			for _, child in ipairs(rollVFXClone:GetChildren()) do
				if child:IsA("ParticleEmitter") then
					child.Enabled = true
					-- Apply surface color to squares emitter
					if child.Name == "squares" and surfaceColor then
						child.Color = ColorSequence.new(surfaceColor)
					end
					print(`[Dodge] Client: Enabled {child.Name} particle emitter`)
				end
			end

			-- Schedule disabling emitters when dodge ends (let particles fade out naturally)
			task.delay(activeDuration, function()
				if rollVFXClone and rollVFXClone.Parent then
					-- Disable emitters so they stop spawning new particles
					for _, child in ipairs(rollVFXClone:GetChildren()) do
						if child:IsA("ParticleEmitter") then
							child.Enabled = false
						end
					end
					print("[Dodge] Client: Disabled roll VFX emitters (fading out)")

					-- Calculate max particle lifetime to know when to destroy
					local maxLifetime = 0
					for _, child in ipairs(rollVFXClone:GetChildren()) do
						if child:IsA("ParticleEmitter") then
							local lifetime = child.Lifetime.Max
							if lifetime > maxLifetime then
								maxLifetime = lifetime
							end
						end
					end

					-- Destroy after all particles have faded out
					task.delay(maxLifetime + 0.5, function()
						if rollVFXClone and rollVFXClone.Parent then
							rollVFXClone:Destroy()
							self.rollVFXAttachment = nil
							print("[Dodge] Client: Destroyed roll VFX clone after fade")
						end
					end)
				end
			end)
		else
			warn("[Dodge] Client: Roll VFX attachment not found")
		end
	end

	-- Play appropriate SFX based on dodge type
	if self.isAirDash then
		self:_playAirDashSFX()
	else
		self:_playDodgeSFX()
	end

	-- Setup M2 listener for canceling (ONLY for ground dodge, not air dash)
	if not self.isAirDash then
		self.m2Connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end

			-- Check for M2 (right mouse button)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				self:_attemptCancel()
			end
		end)

		-- Auto-disconnect M2 listener after a generous window (50% longer than dodge duration)
		task.delay(activeDuration * 1.5, function()
			if self.m2Connection then
				self.m2Connection:Disconnect()
				self.m2Connection = nil
			end
		end)
	else
		print("[Dodge] Client: Air dash - Roll cancel disabled")
	end
end

-- Play air dash SFX
function Dodge:_playAirDashSFX()
	local airDashSFXFolder = ReplicatedStorage.Assets.SFX.Movement.Airdash
	if not airDashSFXFolder then
		warn("[Dodge] Air dash SFX folder not found")
		return
	end

	local character = self.Character.Instance
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Get all Sound instances from folder
	local sounds = {}
	for _, child in ipairs(airDashSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[Dodge] No air dash sounds found")
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

	-- Store reference for potential cleanup
	self.dodgeSFX = soundClone

	-- Clean up after sound finishes
	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)

	print(`[Dodge] Playing air dash SFX: {randomSound.Name}`)
end

-- Play dodge roll SFX
function Dodge:_playDodgeSFX()
	local dodgeSFXFolder = ReplicatedStorage.Assets.SFX.Movement.Dodges
	if not dodgeSFXFolder then
		warn("[Dodge] Dodge SFX folder not found")
		return
	end

	local character = self.Character.Instance
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Get all Sound instances from folder
	local sounds = {}
	for _, child in ipairs(dodgeSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[Dodge] No dodge sounds found")
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

	-- Store reference for potential fade-out on cancel
	self.dodgeSFX = soundClone

	-- Clean up after sound finishes
	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)

	print(`[Dodge] Playing dodge SFX: {randomSound.Name}`)
end

-- Play rollcancel SFX with fade-out of current dodge SFX
function Dodge:_playRollCancelSFX()
	local cancelSFXFolder = ReplicatedStorage.Assets.SFX.Movement.Dodges.Cancel
	if not cancelSFXFolder then
		warn("[Dodge] Rollcancel SFX folder not found")
		return
	end

	-- Fade out current dodge SFX if playing
	if self.dodgeSFX and self.dodgeSFX.Parent then
		local fadeTime = 0.2
		local originalVolume = self.dodgeSFX.Volume
		local startTime = tick()

		task.spawn(function()
			while tick() - startTime < fadeTime do
				local progress = (tick() - startTime) / fadeTime
				if self.dodgeSFX and self.dodgeSFX.Parent then
					self.dodgeSFX.Volume = originalVolume * (1 - progress)
				else
					break
				end
				task.wait()
			end

			-- Destroy after fade
			if self.dodgeSFX and self.dodgeSFX.Parent then
				self.dodgeSFX:Destroy()
				self.dodgeSFX = nil
			end
		end)
	end

	local character = self.Character.Instance
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Get all Sound instances from cancel folder
	local sounds = {}
	for _, child in ipairs(cancelSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[Dodge] No rollcancel sounds found")
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

	print(`[Dodge] Playing rollcancel SFX: {randomSound.Name}`)
end

-- Calculate dash direction using Humanoid.MoveDirection (industry standard) or camera for airdash
function Dodge:_calculateDashDirection(humanoid: Humanoid, hrp: BasePart, isAirDash: boolean?): Vector3
	-- For air dash, use camera direction only with Y-axis aiming
	if isAirDash then
		-- Get camera direction from server storage (sent via RemoteEvent)
		local Players = game:GetService("Players")
		local player = Players:GetPlayerFromCharacter(self.Character.Instance)

		if player and _G.AirdashCameraStore then
			local cameraLook = _G.AirdashCameraStore.get(player)

			if cameraLook then
				-- Lerp between horizontal direction and full camera direction
				-- This preserves the tilt better than scaling Y directly
				local horizontalDirection = Vector3.new(cameraLook.X, 0, cameraLook.Z).Unit
				local fullCameraDirection = cameraLook

				-- Blend based on influence: 0 = horizontal, 1 = full camera direction
				local direction = horizontalDirection:Lerp(fullCameraDirection, AIR_DASH_Y_INFLUENCE)

				print(
					`[Dodge] Air dash direction - Camera Y: {cameraLook.Y}, Final Y: {direction.Y}, Direction: {direction}, Influence: {AIR_DASH_Y_INFLUENCE}`
				)
				return direction
			end
		end

		-- Fallback to horizontal forward if camera direction not available
		warn("[Dodge] Camera direction not available for air dash, using fallback")
		local lookVector = hrp.CFrame.LookVector
		return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	end

	-- Ground dodge: use MoveDirection for camera-relative directional dashing (like Deepwoken)
	local moveDir = humanoid.MoveDirection

	-- If not moving, use character's forward direction
	if moveDir.Magnitude < 0.1 then
		local lookVector = hrp.CFrame.LookVector
		return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	end

	-- Use actual movement direction (already horizontal)
	return Vector3.new(moveDir.X, 0, moveDir.Z).Unit
end

-- Attempt to cancel dodge with M2 (client-side)
function Dodge:_attemptCancel()
	print("[Dodge] Client: Cancelling dodge")

	-- Stop current dodge animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	-- Play rollcancel SFX with fade-out
	self:_playRollCancelSFX()

	-- Determine rollcancel direction based on movement
	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart

	if humanoid and hrp then
		-- Determine direction (left/right/forward/backward)
		local rollCancelAnimId = "rbxassetid://96765830085186" -- Default to right
		local moveDir = humanoid.MoveDirection

		if moveDir.Magnitude > 0.1 then
			local lookVector = hrp.CFrame.LookVector
			local rightVector = hrp.CFrame.RightVector

			-- Project movement onto character's forward and right vectors
			local forwardDot = moveDir:Dot(Vector3.new(lookVector.X, 0, lookVector.Z).Unit)
			local rightDot = moveDir:Dot(Vector3.new(rightVector.X, 0, rightVector.Z).Unit)

			-- Determine primary direction
			if math.abs(forwardDot) > math.abs(rightDot) then
				-- Moving primarily forward/backward
				if forwardDot > 0 then
					rollCancelAnimId = "rbxassetid://96765830085186" -- Forward = right anim
				else
					rollCancelAnimId = "rbxassetid://135861148893814" -- Backward = left anim
				end
			else
				-- Moving primarily left/right
				if rightDot > 0 then
					rollCancelAnimId = "rbxassetid://96765830085186" -- Right = right anim
				else
					rollCancelAnimId = "rbxassetid://135861148893814" -- Left = left anim
				end
			end
		end

		-- Play rollcancel animation with high priority
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local rollCancelAnim = Instance.new("Animation")
			rollCancelAnim.AnimationId = rollCancelAnimId
			local rollCancelTrack = animator:LoadAnimation(rollCancelAnim)

			-- Set high priority to prevent sprint animation from overriding
			rollCancelTrack.Priority = Enum.AnimationPriority.Action
			rollCancelTrack:Play(0.05)
			print(`[Dodge] Client: Playing rollcancel animation ({rollCancelAnimId}) with Action priority`)

			-- Store the track so sprint doesn't resume until animation finishes
			self.rollCancelTrack = rollCancelTrack
		end
	end

	-- Cleanup roll VFX on cancel (fade out like normal roll finish)
	if self.rollVFXAttachment then
		local rollVFXClone = self.rollVFXAttachment
		self.rollVFXAttachment = nil -- Clear reference immediately

		-- Disable emitters so they stop spawning new particles
		for _, child in ipairs(rollVFXClone:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		print("[Dodge] Client: Disabled roll VFX emitters on cancel (fading out)")

		-- Calculate max particle lifetime to know when to destroy
		local maxLifetime = 0
		for _, child in ipairs(rollVFXClone:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				local lifetime = child.Lifetime.Max
				if lifetime > maxLifetime then
					maxLifetime = lifetime
				end
			end
		end

		-- Destroy after all particles have faded out
		task.delay(maxLifetime + 0.5, function()
			if rollVFXClone and rollVFXClone.Parent then
				rollVFXClone:Destroy()
				print("[Dodge] Client: Destroyed roll VFX clone after cancel fade")
			end
		end)
	end

	-- Disconnect M2 listener
	if self.m2Connection then
		self.m2Connection:Disconnect()
		self.m2Connection = nil
	end

	-- End the skill (which will trigger server to cancel)
	self:End()
end

function Dodge:OnEndServer()
	-- Common cleanup
	self.dodgeActive = false
	self.Character.Instance:SetAttribute("_DashActive", nil)

	-- Clean up landed connection (air dash)
	if self.landedConnection then
		self.landedConnection:Disconnect()
		self.landedConnection = nil
	end

	-- Remove BodyVelocity
	if self.bodyVelocity then
		self.bodyVelocity:Destroy()
		self.bodyVelocity = nil
	end

	-- End Dashing status effect immediately to release controls
	if self.dashingEffect then
		self.dashingEffect:End()
		self.dashingEffect = nil
		print("[Dodge] Server: Ended Dashing status effect")
	end

	-- End iframes if active
	if self.iframesEffect then
		self.iframesEffect:End()
		self.iframesEffect = nil
		print("[Dodge] Server: Ended iframes")
	end

	-- Handle cooldown/cancel logic based on how skill ended
	if self.isAirDash then
		-- Air dash completed (or ended by landing) - always apply full cooldown, no cancel
		self:ApplyCooldown(DODGE_COOLDOWN)
		self.cancelCountRef.Value = 0
		self.isAirDash = false
		print("[Dodge] Server: Air dash ended - Cooldown applied")
	elseif self.completedNaturally then
		-- Ground dodge completed naturally - apply full cooldown
		self:ApplyCooldown(DODGE_COOLDOWN)
		self.cancelCountRef.Value = 0
		print("[Dodge] Server: Ground dodge completed - Cooldown applied")
	else
		-- Ground dodge cancelled by player (M2) - run cancel logic
		if self.cancelCountRef.Value < MAX_CANCELS then
			-- First cancel - no cooldown, can dodge again immediately
			self.cancelCountRef.Value = self.cancelCountRef.Value + 1
			print(
				`[Dodge] Server: Dodge cancelled - Can dodge again immediately (cancel {self.cancelCountRef.Value}/{MAX_CANCELS})`
			)
		else
			-- Already used the cancel - apply full cooldown and reset
			self:ApplyCooldown(DODGE_COOLDOWN)
			self.cancelCountRef.Value = 0
			print("[Dodge] Server: Second dodge cancelled - Cooldown applied, cancel count reset")
		end
	end

	-- Reset completion flag for next use
	self.completedNaturally = false
end

function Dodge:OnEndClient()
	-- Stop dodge animation (not rollcancel)
	if self.currentAnimTrack then
		-- Air dash (normal and enhanced) uses slower fade out for smoother transition to running
		local fadeTime = self.isAirDash and 0.35 or 0.1
		self.currentAnimTrack:Stop(fadeTime)
		self.currentAnimTrack = nil
	end
	self.isEnhancedDashClient = false

	-- Disconnect M2 listener
	if self.m2Connection then
		self.m2Connection:Disconnect()
		self.m2Connection = nil
	end

	-- Resume sprinting ONLY if player was sprinting before the dodge
	print(`[Dodge] Client: Checking sprint resume - wasSprintingBeforeDodge: {self.wasSprintingBeforeDodge}`)
	if self.wasSprintingBeforeDodge then
		task.defer(function()
			-- If rollcancel animation is playing, wait for it to finish
			if self.rollCancelTrack and self.rollCancelTrack.IsPlaying then
				local animLength = self.rollCancelTrack.Length or 0.5
				print(`[Dodge] Client: Waiting {animLength}s for rollcancel animation to finish`)
				task.wait(animLength)
			end

			local resumeSprintEvent = ReplicatedStorage:FindFirstChild("ResumeSprintAfterDodge")
			if resumeSprintEvent then
				resumeSprintEvent:Fire()
			end
		end)
	end

	print("[Dodge] Client: Skill ended")
end

return Dodge
