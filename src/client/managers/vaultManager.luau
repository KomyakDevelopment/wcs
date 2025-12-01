--!strict
-- Vault Manager (Ledge Climb/Mantle)
-- Smoothly climbs up onto higher platforms without jumping
-- Maintains momentum and sprint state

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local VaultManager = {}
VaultManager.__index = VaultManager

-- Configuration
local CONFIG = {
	-- Detection
	MAX_CLIMB_HEIGHT = 3.5, -- Maximum height difference to climb (studs)
	MIN_CLIMB_HEIGHT = 1.5, -- Minimum height to trigger climb (increased to avoid stairs, typical stair is 0.5-1 stud)
	DETECTION_DISTANCE = 4.5, -- How far ahead to detect ledges (generous for easy timing)
	MIN_MOVEMENT_SPEED = 1.5, -- Minimum velocity to trigger climb (very forgiving)
	MIN_LEDGE_DEPTH = 1.5, -- Minimum horizontal depth of ledge (avoids stairs which have short steps)
	MIN_SURFACE_FLATNESS = 0.95, -- Minimum dot product with Y axis for flat surfaces (avoids slopes)

	-- Climb motion
	CLIMB_DURATION = 0.3, -- How long the climb takes (seconds) - smooth and fluid

	-- Animation
	ANIMATION_ID = "rbxassetid://100770125981931", -- 74508440985641
	ANIMATION_SPEED = 1.35,

	-- Cooldown
	COOLDOWN = 0.3,

	-- Timing tolerance
	VAULT_BUFFER_TIME = 0.5, -- How long to keep trying after space press (generous window)
}

export type VaultManager = typeof(setmetatable(
	{} :: {
		_player: Player,
		_character: Model?,
		_humanoid: Humanoid?,
		_rootPart: BasePart?,
		_animator: Animator?,
		_vaultAnimation: AnimationTrack?,
		_isClimbing: boolean,
		_lastClimbTime: number,
		_vaultBufferEnd: number, -- When the vault buffer expires
	},
	VaultManager
))

function VaultManager.new(): VaultManager
	local self = setmetatable({}, VaultManager) :: VaultManager

	self._player = Players.LocalPlayer
	self._character = nil
	self._humanoid = nil
	self._rootPart = nil
	self._animator = nil
	self._vaultAnimation = nil
	self._isClimbing = false
	self._lastClimbTime = 0
	self._vaultBufferEnd = 0

	self:_initialize()

	return self
end

function VaultManager:_initialize()
	-- Setup current character
	if self._player.Character then
		self:_onCharacterAdded(self._player.Character)
	end

	-- Handle respawns
	self._player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end)

	-- Listen for space key press to start vault buffer
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			-- Set buffer - will try to vault for the next VAULT_BUFFER_TIME seconds
			self._vaultBufferEnd = tick() + CONFIG.VAULT_BUFFER_TIME
			-- Try immediately first
			self:_tryVault()
		end
	end)

	-- Heartbeat to check for vault during buffer window
	RunService.Heartbeat:Connect(function()
		-- Only check if we're in the buffer window and haven't vaulted yet
		if tick() < self._vaultBufferEnd and not self._isClimbing then
			self:_tryVault()
		end
	end)

	print("[VaultManager] Initialized (Ledge Climb Mode - Press Space)")
end

function VaultManager:_onCharacterAdded(character: Model)
	-- Wait for essential parts
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	if not humanoid or not rootPart then
		warn("[VaultManager] Failed to setup character - missing parts")
		return
	end

	self._character = character
	self._humanoid = humanoid
	self._rootPart = rootPart

	-- Disable auto-climbing so players must use vault (press space)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	-- Load animation
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		self._animator = animator
		local animation = Instance.new("Animation")
		animation.AnimationId = CONFIG.ANIMATION_ID
		self._vaultAnimation = animator:LoadAnimation(animation)
		self._vaultAnimation.Priority = Enum.AnimationPriority.Action4
	end

	-- Reset state
	self._isClimbing = false
	self._lastClimbTime = 0

	print("[VaultManager] Character setup complete (auto-climb disabled)")
end

function VaultManager:_tryVault()
	-- Skip if climbing or on cooldown
	if self._isClimbing then
		return
	end

	if tick() - self._lastClimbTime < CONFIG.COOLDOWN then
		return
	end

	-- Skip if no character
	if not self._character or not self._humanoid or not self._rootPart then
		return
	end

	-- Skip if not grounded
	if self._humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	-- Skip if not pressing W (forward only)
	if not UserInputService:IsKeyDown(Enum.KeyCode.W) then
		return
	end

	-- Check if moving fast enough
	local velocity = self._rootPart.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	if horizontalVelocity.Magnitude < CONFIG.MIN_MOVEMENT_SPEED then
		return
	end

	-- Check if moving forward
	local lookDir = self._rootPart.CFrame.LookVector
	local forwardDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local moveDir = horizontalVelocity.Unit

	if forwardDir:Dot(moveDir) < 0.5 then
		return
	end

	-- Detect climbable ledge
	local ledgeData = self:_detectLedge(forwardDir)
	if ledgeData then
		-- Clear buffer since we're vaulting
		self._vaultBufferEnd = 0
		self:_performClimb(ledgeData, forwardDir, horizontalVelocity.Magnitude)
	end
end

type LedgeData = {
	heightDifference: number,
	targetPosition: Vector3,
	surfaceNormal: Vector3,
}

function VaultManager:_detectLedge(forwardDir: Vector3): LedgeData?
	if not self._rootPart or not self._character then
		return nil
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { self._character }
	rayParams.RespectCanCollide = true

	-- Current foot position
	local feetY = self._rootPart.Position.Y - 2.5

	-- Cast ray forward at foot level to find obstacle
	local footRayOrigin = Vector3.new(self._rootPart.Position.X, feetY + 0.5, self._rootPart.Position.Z)
	local footRayResult = workspace:Raycast(footRayOrigin, forwardDir * CONFIG.DETECTION_DISTANCE, rayParams)

	if not footRayResult then
		return nil -- No obstacle ahead
	end

	-- Check if the obstacle surface itself is a slope (not a vertical wall or flat ledge face)
	-- A proper ledge should have a mostly vertical face (normal pointing horizontally away from us)
	local obstacleNormal = footRayResult.Normal
	local obstacleVerticalComponent = math.abs(obstacleNormal.Y)
	-- If the obstacle surface is too sloped (not vertical enough), skip it
	-- A vertical wall has Y component ~0, a slope has higher Y component
	if obstacleVerticalComponent > 0.5 then
		return nil -- This is a slope, not a ledge
	end

	-- Check there's no wall at head height (must be a ledge, not a wall)
	local headCheckOrigin = self._rootPart.Position + Vector3.new(0, 1.5, 0)
	local headCheck = workspace:Raycast(headCheckOrigin, forwardDir * CONFIG.DETECTION_DISTANCE, rayParams)
	if headCheck then
		return nil -- Wall blocks at head level, not climbable
	end

	-- Find the top surface of the ledge
	-- Cast down from above to find where we'd land
	local searchHeight = CONFIG.MAX_CLIMB_HEIGHT + 2
	local topSearchOrigin = footRayResult.Position + Vector3.new(0, searchHeight, 0) + forwardDir * 0.8
	local topResult = workspace:Raycast(topSearchOrigin, Vector3.new(0, -searchHeight - 1, 0), rayParams)

	if not topResult then
		return nil -- Can't find top surface
	end

	-- Check surface is flat enough to stand on (stricter check to avoid slopes)
	local upDot = topResult.Normal:Dot(Vector3.yAxis)
	if upDot < CONFIG.MIN_SURFACE_FLATNESS then
		return nil -- Surface too sloped
	end

	-- Calculate height difference
	local ledgeTopY = topResult.Position.Y
	local heightDiff = ledgeTopY - feetY

	-- Validate height range
	if heightDiff < CONFIG.MIN_CLIMB_HEIGHT or heightDiff > CONFIG.MAX_CLIMB_HEIGHT then
		return nil
	end

	-- Check ledge has sufficient horizontal depth (avoids stairs which have short steps)
	-- Cast another ray further forward on the ledge surface to ensure it's a real platform
	local depthCheckOrigin = topResult.Position + Vector3.new(0, 0.5, 0) + forwardDir * CONFIG.MIN_LEDGE_DEPTH
	local depthCheckResult = workspace:Raycast(depthCheckOrigin, Vector3.new(0, -2, 0), rayParams)
	if not depthCheckResult then
		return nil -- Ledge doesn't have enough depth (likely a stair step)
	end
	-- Verify the depth check hit is at similar height (not a drop-off)
	if math.abs(depthCheckResult.Position.Y - topResult.Position.Y) > 0.5 then
		return nil -- Surface drops off too quickly (stair or thin ledge)
	end

	-- Calculate target landing position (on top of ledge, slightly forward)
	local targetPos = Vector3.new(
		topResult.Position.X + forwardDir.X * 1.5,
		ledgeTopY + 2.5, -- Root part height above feet
		topResult.Position.Z + forwardDir.Z * 1.5
	)

	return {
		heightDifference = heightDiff,
		targetPosition = targetPos,
		surfaceNormal = topResult.Normal,
	}
end

-- Smooth easing function (ease out sine for very fluid deceleration)
local function easeOutSine(t: number): number
	return math.sin((t * math.pi) / 2)
end

function VaultManager:_performClimb(ledgeData: LedgeData, _forwardDir: Vector3, _currentSpeed: number)
	if self._isClimbing or not self._humanoid or not self._rootPart then
		return
	end

	self._isClimbing = true
	self._lastClimbTime = tick()

	print(`[VaultManager] Climbing ledge (height: {string.format("%.1f", ledgeData.heightDifference)} studs)`)

	-- Play animation
	if self._vaultAnimation then
		self._vaultAnimation:Play(0.15) -- Smooth blend
		self._vaultAnimation:AdjustSpeed(CONFIG.ANIMATION_SPEED)
	end

	-- Store start position and velocity
	local startPos = self._rootPart.Position
	local startRotation = self._rootPart.CFrame.Rotation
	local preservedVelocity = self._rootPart.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(preservedVelocity.X, 0, preservedVelocity.Z)

	-- Calculate target height
	local targetY = ledgeData.targetPosition.Y
	local heightDelta = targetY - startPos.Y

	-- FULLY disable physics during climb
	self._humanoid.PlatformStand = true
	self._humanoid.AutoRotate = false

	-- Use accumulated deltaTime for frame-perfect smoothness
	local elapsedTime = 0
	local connection: RBXScriptConnection?

	connection = RunService.RenderStepped:Connect(function(deltaTime: number)
		if not self._rootPart or not self._rootPart.Parent or not self._humanoid then
			if connection then
				connection:Disconnect()
			end
			self:_endClimb(preservedVelocity)
			return
		end

		-- Accumulate time for smooth progression
		elapsedTime = elapsedTime + deltaTime
		local progress = math.clamp(elapsedTime / CONFIG.CLIMB_DURATION, 0, 1)

		-- Smooth sine easing for natural, fluid motion
		local easedProgress = easeOutSine(progress)

		-- Calculate position
		local currentY = startPos.Y + heightDelta * easedProgress
		local horizontalOffset = horizontalVelocity * elapsedTime
		local currentPos = Vector3.new(
			startPos.X + horizontalOffset.X,
			currentY,
			startPos.Z + horizontalOffset.Z
		)

		-- Kill ALL velocity to prevent physics interference
		self._rootPart.AssemblyLinearVelocity = Vector3.zero
		self._rootPart.AssemblyAngularVelocity = Vector3.zero

		-- Apply position with stored rotation
		self._rootPart.CFrame = CFrame.new(currentPos) * startRotation

		-- Check if complete
		if progress >= 1 then
			if connection then
				connection:Disconnect()
			end
			self:_endClimb(preservedVelocity)
		end
	end)
end

function VaultManager:_endClimb(preservedVelocity: Vector3)
	if not self._humanoid or not self._rootPart then
		self._isClimbing = false
		return
	end

	-- Re-enable humanoid physics
	self._humanoid.PlatformStand = false
	self._humanoid.AutoRotate = true

	-- Horizontal velocity we want to restore
	local horizontalVelocity = Vector3.new(preservedVelocity.X, 0, preservedVelocity.Z)
	local moveDirection = horizontalVelocity.Magnitude > 0.1 and horizontalVelocity.Unit or Vector3.zero

	-- Apply velocity AND tell humanoid to keep moving in that direction
	self._rootPart.AssemblyLinearVelocity = horizontalVelocity
	self._humanoid:Move(moveDirection, false)

	-- Force velocity for multiple frames to overcome humanoid physics reset
	local framesApplied = 0
	local maxFrames = 5
	local velocityConnection: RBXScriptConnection?

	velocityConnection = RunService.RenderStepped:Connect(function()
		framesApplied += 1

		if self._rootPart and self._humanoid then
			-- Keep forcing the velocity
			self._rootPart.AssemblyLinearVelocity = horizontalVelocity
			self._humanoid:Move(moveDirection, false)
		end

		if framesApplied >= maxFrames then
			if velocityConnection then
				velocityConnection:Disconnect()
			end
			-- Resume sprint after velocity is stable
			self:_resumeSprint()
		end
	end)

	self._isClimbing = false
end

-- Fire sprint resume event (uses same event as dodge)
function VaultManager:_resumeSprint()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local resumeEvent = ReplicatedStorage:FindFirstChild("ResumeSprintAfterDodge") :: BindableEvent?
	if resumeEvent then
		resumeEvent:Fire()
	end
end

function VaultManager:destroy()
	self._isClimbing = false
	self._vaultAnimation = nil :: any
	self._character = nil :: any
	self._humanoid = nil :: any
	self._rootPart = nil :: any
	self._animator = nil :: any
end

return VaultManager
