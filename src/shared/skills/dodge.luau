--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = WCS.RegisterSkill("Dodge")

-- Configuration
local DODGE_DISTANCE = 17 -- Studs to travel (slightly longer than 16)
local DODGE_DURATION = 0.345 -- Seconds for dodge to complete (15% slower: 0.3 * 1.15 = 0.345)
local DODGE_COOLDOWN = 1.5 -- Cooldown after dodge completes
local MAX_CANCELS = 1 -- Maximum number of times you can cancel (1 cancel = 2 total rolls)

-- Iframes configuration
local IFRAME_START = 0.1 -- Iframes start 0.1 seconds into dodge
local IFRAME_END = 0.345 -- Iframes end right before dodge completes

-- Animation IDs for each direction
local DODGE_ANIMATIONS = {
	Forward = "rbxassetid://85622930154432",
	Backward = "rbxassetid://85622930154432",
	Left = "rbxassetid://85622930154432",
	Right = "rbxassetid://85622930154432",
}

function Dodge:OnConstructServer()
	self.dodgeActive = false
	self.dashingEffect = nil
	self.bodyVelocity = nil
	self.iframesEffect = nil

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
		end
	end
end

function Dodge:OnStartServer()
	-- Get character components
	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid

	if not humanoidRootPart or not humanoid then
		warn("[Dodge] Server: Missing HumanoidRootPart or Humanoid")
		return
	end

	-- Check if character is grounded (raycast down)
	local rayOrigin = humanoidRootPart.Position
	local rayDirection = Vector3.new(0, -4, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if not raycastResult then
		print("[Dodge] Server: Cannot dodge - Not grounded")
		return
	end

	-- Apply Dashing status effect to block attacks
	local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
	self.dashingEffect = Dashing.new(self.Character)
	if self.dashingEffect then
		self.dashingEffect:Start(DODGE_DURATION)
		print("[Dodge] Server: Applied Dashing status effect")
	end

	-- Calculate initial dash direction and strength
	local dashStrength = DODGE_DISTANCE / DODGE_DURATION
	local rate = 0.0167

	print(`[Dodge] Server: Starting dash - Strength: {dashStrength}`)

	-- Create BodyVelocity for smooth movement
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVelocity.P = 5000 -- Moderate P value for responsive but smooth movement
	bodyVelocity.Parent = humanoidRootPart

	self.bodyVelocity = bodyVelocity
	self.dodgeActive = true

	-- Schedule iframes to start after IFRAME_START delay
	task.delay(IFRAME_START, function()
		if not self.dodgeActive then
			return -- Dodge was cancelled
		end

		local Iframes = require(ReplicatedStorage.Shared.statusEffects.iframes)
		self.iframesEffect = Iframes.new(self.Character)
		if self.iframesEffect then
			local iframeDuration = IFRAME_END - IFRAME_START
			self.iframesEffect:Start(iframeDuration)
			print(`[Dodge] Server: Applied iframes for {iframeDuration}s`)
		end
	end)

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

		task.wait(rate)
		elapsed = elapsed + rate
	end

	print("[Dodge] Loop completed - Cleaning up")

	-- Clean up BodyVelocity
	if self.bodyVelocity then
		self.bodyVelocity:Destroy()
		self.bodyVelocity = nil
	end

	self.dodgeActive = false

	-- Normal completion always applies full cooldown and resets cancel count
	self:ApplyCooldown(DODGE_COOLDOWN)
	self.cancelCountRef.Value = 0
	print("[Dodge] Server: Dodge completed - Cooldown applied, cancel count reset")
end

function Dodge:OnStartClient()
	-- Check if player has any hitstun status effects active or is dashing
	local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
	local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)

	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Dashing }) then
		print("[Dodge] Client: Blocked - Player is in hitstun/stun/dashing")
		return
	end

	-- Stop any M1 animations that might be playing
	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local tracks = animator:GetPlayingAnimationTracks()
			for _, track in ipairs(tracks) do
				-- Stop combat animations (punch animations)
				if track.Animation
					and (track.Animation.AnimationId:match("71780482128433")
					or track.Animation.AnimationId:match("122171966838136")
					or track.Animation.AnimationId:match("102972252804338")) then
					track:Stop(0.05) -- Quick fade out
					print("[Dodge] Client: Stopped M1 animation")
				end
			end
		end
	end

	-- Get the actual movement direction (camera-relative) for animation
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart

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

	-- Setup M2 listener for canceling (extended window for easier cancelling)
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
	task.delay(DODGE_DURATION * 1.5, function()
		if self.m2Connection then
			self.m2Connection:Disconnect()
			self.m2Connection = nil
		end
	end)
end

-- Calculate dash direction using Humanoid.MoveDirection (industry standard)
function Dodge:_calculateDashDirection(humanoid: Humanoid, hrp: BasePart): Vector3
	-- Use MoveDirection for camera-relative directional dashing (like Deepwoken)
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

	-- Stop animation immediately
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
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
	print("[Dodge] Server: Skill ended (cancelled by client)")

	-- Cancel-specific cleanup
	self.dodgeActive = false

	-- Remove BodyVelocity
	if self.bodyVelocity then
		self.bodyVelocity:Destroy()
		self.bodyVelocity = nil
	end

	-- End Dashing status effect immediately to release controls
	if self.dashingEffect then
		self.dashingEffect:End()
		self.dashingEffect = nil
		print("[Dodge] Server: Ended Dashing status effect to release controls")
	end

	-- End iframes if active
	if self.iframesEffect then
		self.iframesEffect:End()
		self.iframesEffect = nil
		print("[Dodge] Server: Ended iframes (cancelled)")
	end

	-- Cancelling gives one more dodge (unless already used)
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

function Dodge:OnEndClient()
	-- Stop animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end

	-- Disconnect M2 listener
	if self.m2Connection then
		self.m2Connection:Disconnect()
		self.m2Connection = nil
	end

	-- Resume sprinting if W is held (industry standard behavior)
	task.defer(function()
		local resumeSprintEvent = ReplicatedStorage:FindFirstChild("ResumeSprintAfterDodge")
		if resumeSprintEvent then
			resumeSprintEvent:Fire()
		end
	end)

	print("[Dodge] Client: Skill ended")
end

return Dodge
