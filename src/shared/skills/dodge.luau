--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = WCS.RegisterSkill("Dodge")

-- Configuration
local DODGE_DISTANCE = 20 -- Studs to travel
local DODGE_DURATION = 0.3 -- Seconds for dodge to complete (matching reference)
local DODGE_COOLDOWN = 1.5 -- Cooldown after dodge completes
local MAX_CANCELS = 1 -- Maximum number of times you can cancel (1 cancel = 2 total rolls)

-- Iframes configuration
local IFRAME_START = 0.1 -- Iframes start 0.1 seconds into dodge
local IFRAME_END = 0.3 -- Iframes end at 0.3 seconds (right before dodge completes)

-- Animation IDs for each direction
local DODGE_ANIMATIONS = {
	Forward = "rbxassetid://74256834635946",
	Backward = "rbxassetid://74256834635946",
	Left = "rbxassetid://74256834635946",
	Right = "rbxassetid://74256834635946",
}

function Dodge:OnConstructServer()
	self.cancelCount = 0
	self.dodgeActive = false
	self.dashingEffect = nil
	self.bodyVelocity = nil
	self.iframesEffect = nil
end

function Dodge:OnConstructClient()
	self.loadedAnimations = {}
	self.currentAnimTrack = nil
	self.cancelCount = 0
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
		bodyVelocity.Velocity = direction * dashStrength

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
	self.cancelCount = 0
	print("[Dodge] Server: Dodge completed - Cooldown applied, cancel count reset")
end

function Dodge:OnStartClient()
	-- Check if player has any hitstun status effects active
	local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)

	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun }) then
		print("[Dodge] Client: Blocked - Player is in hitstun/stun")
		return
	end

	-- Get the actual movement direction (camera-relative) for animation
	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
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

	-- Play animation for dodge direction
	local animTrack = self.loadedAnimations[animDirection]
	if animTrack then
		self.currentAnimTrack = animTrack
		animTrack:Play()
		print(`[Dodge] Client: Playing {animDirection} dodge animation`)
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
	if self.cancelCount < MAX_CANCELS then
		-- First cancel - no cooldown, can dodge again immediately
		self.cancelCount = self.cancelCount + 1
		print(`[Dodge] Server: Dodge cancelled - Can dodge again immediately (cancel {self.cancelCount}/{MAX_CANCELS})`)
	else
		-- Already used the cancel - apply full cooldown and reset
		self:ApplyCooldown(DODGE_COOLDOWN)
		self.cancelCount = 0
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

	print("[Dodge] Client: Skill ended")
end

return Dodge
