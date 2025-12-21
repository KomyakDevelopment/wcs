--!strict
-- Wall Run Manager (Client)
-- Direct CFrame manipulation approach (like vault manager)
-- Press A/D + Space to activate, hold Space to continue

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local WallRunning = require(ReplicatedStorage.Shared.statusEffects.wallRunning)
local SmoothShiftLock = require(script.Parent.smoothShiftLock)

local WallRunManager = {}
WallRunManager.__index = WallRunManager

-- Configuration
local CONFIG = {
	-- Detection
	WALL_DETECT_DISTANCE = 3.5,
	MIN_SPEED = 5,

	-- Wall distance (for smooth positioning)
	TARGET_WALL_DISTANCE = 2, -- Studs from wall
	DISTANCE_LERP_SPEED = 10, -- How fast to lerp to target distance

	-- Camera offset (to prevent clipping)
	CAMERA_OFFSET_DISTANCE = 2.5,
	CAMERA_OFFSET_UP = 0.5,

	-- Movement
	HORIZONTAL_SPEED = 32, -- Speed along wall (studs/sec) - much faster
	DESCENT_HORIZONTAL_SPEED = 28, -- Slightly slower during descent but still fast
	UPWARD_SPEED = 2, -- Slight upward drift to stay on wall
	DOWNWARD_SPEED_MIN = -4, -- Initial descent speed (slow start)
	DOWNWARD_SPEED_MAX = -18, -- Maximum descent speed (accelerates to this)
	DESCENT_CURVE_TIME = 1.5, -- Time to reach max descent speed
	MAX_UPWARD_DURATION = 1.5, -- Seconds before descent
	GROUND_CHECK_DISTANCE = 4, -- Distance to check for ground (ends slightly before hitting)

	-- Jump off (30 degrees outward from wall direction)
	JUMP_ANGLE = 30, -- Degrees outward from wall direction
	JUMP_HORIZONTAL_POWER = 85, -- Total horizontal power (split by angle)
	JUMP_UP_POWER = 88, -- Vertical power
	SPEED_BOOST_MULTIPLIER = 1.5,
	SPEED_BOOST_DURATION = 1.8,

	-- Cooldown
	COOLDOWN = 0.5,

	-- Animations
	WALLRUN_RIGHT_ANIM = "rbxassetid://101992096573753",
	WALLRUN_LEFT_ANIM = "rbxassetid://105706301707645",
	WALLJUMP_RIGHT_ANIM = "rbxassetid://127043982553357",
	WALLJUMP_LEFT_ANIM = "rbxassetid://127043982553357",
	WALLRUN_ANIM_SPEED = 1.82, -- Speed multiplier for wallrun animations
	WALLJUMP_ANIM_SPEED = 1.69, -- Speed multiplier for walljump animations
	WALLJUMP_DURATION = 0.5, -- Duration where dodge is blocked after wall jump

	-- Shiftlock camera override (flip to opposite side to prevent clipping)
	SHIFTLOCK_LEFT_OFFSET = Vector3.new(-1.75, 0.25, 0), -- Camera on left side
	SHIFTLOCK_RIGHT_OFFSET = Vector3.new(1.75, 0.25, 0), -- Camera on right side (default)
}

export type WallRunManager = typeof(setmetatable(
	{} :: {
		_player: Player,
		_character: Model?,
		_humanoid: Humanoid?,
		_rootPart: BasePart?,

		_isWallRunning: boolean,
		_wallRunStartTime: number,
		_lastLeftWallRunTime: number,
		_lastRightWallRunTime: number,
		_requestedSide: string?,
		_wallNormal: Vector3?,
		_wallDir: Vector3?,
		_wallPosition: Vector3?, -- Store wall position for distance checking

		_isHoldingA: boolean,
		_isHoldingD: boolean,
		_speedBoostEndTime: number,
		_baseWalkSpeed: number,

		_wallRunRightAnim: AnimationTrack?,
		_wallRunLeftAnim: AnimationTrack?,
		_wallJumpRightAnim: AnimationTrack?,
		_wallJumpLeftAnim: AnimationTrack?,
		_currentAnim: AnimationTrack?,
		_wallRunningEffect: any?,
		_originalCameraOffset: Vector3?,
	},
	WallRunManager
))

function WallRunManager.new(): WallRunManager
	local self = setmetatable({}, WallRunManager) :: WallRunManager

	self._player = Players.LocalPlayer
	self._character = nil
	self._humanoid = nil
	self._rootPart = nil

	self._isWallRunning = false
	self._wallRunStartTime = 0
	self._lastLeftWallRunTime = 0
	self._lastRightWallRunTime = 0
	self._requestedSide = nil
	self._wallNormal = nil
	self._wallDir = nil
	self._wallPosition = nil

	self._isHoldingA = false
	self._isHoldingD = false
	self._speedBoostEndTime = 0
	self._baseWalkSpeed = 16

	self._wallRunRightAnim = nil
	self._wallRunLeftAnim = nil
	self._wallJumpRightAnim = nil
	self._wallJumpLeftAnim = nil
	self._currentAnim = nil
	self._wallRunningEffect = nil
	self._originalCameraOffset = nil

	self:_initialize()

	return self
end

function WallRunManager:_initialize()
	if self._player.Character then
		self:_onCharacterAdded(self._player.Character)
	end

	self._player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end)

	-- Input handling - Hold A (left) or D (right) to wall run
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.A then
			self._isHoldingA = true
			self:_tryStartWallRun("Left")
		elseif input.KeyCode == Enum.KeyCode.D then
			self._isHoldingD = true
			self:_tryStartWallRun("Right")
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.KeyCode == Enum.KeyCode.A then
			self._isHoldingA = false
			if self._isWallRunning and self._requestedSide == "Left" then
				self:_jumpOffWall()
			end
		elseif input.KeyCode == Enum.KeyCode.D then
			self._isHoldingD = false
			if self._isWallRunning and self._requestedSide == "Right" then
				self:_jumpOffWall()
			end
		end
	end)

	-- Speed boost monitoring
	RunService.Heartbeat:Connect(function()
		self:_updateSpeedBoost()
	end)

	print("[WallRunManager] Initialized - Hold A (left wall) or D (right wall) to wall run")
end

function WallRunManager:_onCharacterAdded(character: Model)
	self:_endWallRun()

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	if not humanoid or not rootPart then
		return
	end

	self._character = character
	self._humanoid = humanoid
	self._rootPart = rootPart
	self._baseWalkSpeed = humanoid.WalkSpeed

	-- Load animations
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		-- Wallrun animations
		local wallRunRightAnim = Instance.new("Animation")
		wallRunRightAnim.AnimationId = CONFIG.WALLRUN_RIGHT_ANIM
		self._wallRunRightAnim = animator:LoadAnimation(wallRunRightAnim)
		self._wallRunRightAnim.Priority = Enum.AnimationPriority.Action

		local wallRunLeftAnim = Instance.new("Animation")
		wallRunLeftAnim.AnimationId = CONFIG.WALLRUN_LEFT_ANIM
		self._wallRunLeftAnim = animator:LoadAnimation(wallRunLeftAnim)
		self._wallRunLeftAnim.Priority = Enum.AnimationPriority.Action

		-- Walljump animations
		local wallJumpRightAnim = Instance.new("Animation")
		wallJumpRightAnim.AnimationId = CONFIG.WALLJUMP_RIGHT_ANIM
		self._wallJumpRightAnim = animator:LoadAnimation(wallJumpRightAnim)
		self._wallJumpRightAnim.Priority = Enum.AnimationPriority.Action

		local wallJumpLeftAnim = Instance.new("Animation")
		wallJumpLeftAnim.AnimationId = CONFIG.WALLJUMP_LEFT_ANIM
		self._wallJumpLeftAnim = animator:LoadAnimation(wallJumpLeftAnim)
		self._wallJumpLeftAnim.Priority = Enum.AnimationPriority.Action
	end

	-- Reset cooldowns on landing
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed then
			self._lastLeftWallRunTime = 0
			self._lastRightWallRunTime = 0
		end
	end)
end

function WallRunManager:_tryStartWallRun(side: string)
	-- Per-side cooldown
	local lastRunTime = if side == "Left" then self._lastLeftWallRunTime else self._lastRightWallRunTime
	if tick() - lastRunTime < CONFIG.COOLDOWN then
		return
	end

	if not self._character or not self._humanoid or not self._rootPart then
		return
	end

	if self._isWallRunning then
		return
	end

	-- Must be airborne
	if self._humanoid.FloorMaterial ~= Enum.Material.Air then
		return
	end

	-- Must be moving
	local vel = self._rootPart.AssemblyLinearVelocity
	if Vector3.new(vel.X, 0, vel.Z).Magnitude < CONFIG.MIN_SPEED then
		return
	end

	-- Detect wall
	local wallData = self:_detectWallOnSide(side)
	if wallData then
		self:_startWallRun(wallData)
	end
end

type WallData = {
	side: string,
	normal: Vector3,
	direction: Vector3,
	position: Vector3, -- Position where we hit the wall
}

function WallRunManager:_detectWallOnSide(requestedSide: string): WallData?
	if not self._rootPart or not self._character then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self._character }

	local pos = self._rootPart.Position
	local cframe = self._rootPart.CFrame

	local dir = if requestedSide == "Right" then cframe.RightVector else -cframe.RightVector
	local result = workspace:Raycast(pos, dir * CONFIG.WALL_DETECT_DISTANCE, params)

	if result then
		local normal = result.Normal
		if math.abs(normal.Y) < 0.4 then
			-- Calculate horizontal direction along wall
			local wallDir = normal:Cross(Vector3.yAxis)
			wallDir = Vector3.new(wallDir.X, 0, wallDir.Z).Unit

			-- Match camera look direction (where player is looking determines wall run direction)
			local camera = workspace.CurrentCamera
			if camera then
				local cameraLook = camera.CFrame.LookVector
				local cameraHorizontal = Vector3.new(cameraLook.X, 0, cameraLook.Z)
				if cameraHorizontal.Magnitude > 0.1 and cameraHorizontal:Dot(wallDir) < 0 then
					wallDir = -wallDir
				end
			end

			return {
				side = requestedSide,
				normal = normal,
				direction = wallDir,
				position = result.Position,
			}
		end
	end

	return nil
end

function WallRunManager:_startWallRun(wallData: WallData)
	if not self._rootPart or not self._humanoid or not self._character then
		return
	end

	self._isWallRunning = true
	self._wallRunStartTime = tick()
	self._requestedSide = wallData.side
	self._wallNormal = wallData.normal
	self._wallDir = wallData.direction
	self._wallPosition = wallData.position

	print(`[WallRunManager] Started wall running ({wallData.side})`)

	-- Apply status effect
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(self._character)
	if wcsCharacter then
		self._wallRunningEffect = WallRunning.new(wcsCharacter)
		if self._wallRunningEffect then
			self._wallRunningEffect:Start(999)
		end
	end

	self._character:SetAttribute("IsWallRunning", true)

	-- Disable physics
	self._humanoid.PlatformStand = true
	self._humanoid.AutoRotate = false

	-- Adjust camera to prevent wall clipping (offset away from wall + slightly up)
	local humanoid = self._character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self._originalCameraOffset = humanoid.CameraOffset
		-- Offset camera away from wall and slightly up to prevent clipping
		local awayOffset = self._wallNormal * CONFIG.CAMERA_OFFSET_DISTANCE
		local upOffset = Vector3.new(0, CONFIG.CAMERA_OFFSET_UP, 0)
		humanoid.CameraOffset = awayOffset + upOffset
	end

	-- Override shiftlock camera to opposite side (prevents camera clipping through wall)
	-- Also disable shiftlock character rotation so it doesn't fight with our rotation
	SmoothShiftLock:SetCharacterRotationEnabled(false)

	-- Determine wall side relative to CAMERA (not character or input key)
	-- This ensures camera offset is always correct regardless of how player approached the wall
	-- Note: Wall normal points AWAY from the wall surface
	local camera = workspace.CurrentCamera
	if camera then
		local cameraRight = camera.CFrame.RightVector
		-- Dot product: negative = normal points away from camera's right = wall is on RIGHT
		-- Dot product: positive = normal points towards camera's right = wall is on LEFT
		local wallSideDot = self._wallNormal:Dot(cameraRight)
		if wallSideDot < 0 then
			-- Wall is on camera's right (normal points left), put camera on left to avoid clipping
			SmoothShiftLock:SetCameraOffsetOverride(CONFIG.SHIFTLOCK_LEFT_OFFSET)
		end
		-- If wall is on left, camera stays on right (default position) - no override needed
	end

	-- Play wallrun animation based on side (with speed multiplier)
	if wallData.side == "Right" and self._wallRunRightAnim then
		self._currentAnim = self._wallRunRightAnim
		self._wallRunRightAnim:Play(0.1)
		self._wallRunRightAnim:AdjustSpeed(CONFIG.WALLRUN_ANIM_SPEED)
	elseif wallData.side == "Left" and self._wallRunLeftAnim then
		self._currentAnim = self._wallRunLeftAnim
		self._wallRunLeftAnim:Play(0.1)
		self._wallRunLeftAnim:AdjustSpeed(CONFIG.WALLRUN_ANIM_SPEED)
	end

	-- Start update loop with priority AFTER camera (300) to override shiftlock rotation
	-- Camera priority is 200, so we use 300 to run after it
	RunService:BindToRenderStep("WallRunUpdate", 300, function(deltaTime)
		self:_updateWallRun(deltaTime)
	end)
end

function WallRunManager:_updateWallRun(_deltaTime: number)
	if not self._rootPart or not self._humanoid or not self._character or not self._wallNormal or not self._wallDir or not self._wallPosition then
		self:_endWallRun()
		return
	end

	-- Check if grounded or near ground (PlatformStand prevents FloorMaterial updates)
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { self._character }

	local groundCheck = workspace:Raycast(
		self._rootPart.Position,
		Vector3.new(0, -CONFIG.GROUND_CHECK_DISTANCE, 0),
		groundParams
	)

	if groundCheck then
		print("[WallRunManager] Ending - near ground")
		self:_endWallRun()
		return
	end

	-- Check if dodge cancelled wall run
	if self._character:GetAttribute("CancelWallRun") then
		print("[WallRunManager] Ending - cancelled by dodge")
		self._character:SetAttribute("CancelWallRun", nil)
		self:_endWallRun()
		return
	end

	-- Check if wall is still there (raycast towards wall)
	local wallCheckParams = RaycastParams.new()
	wallCheckParams.FilterType = Enum.RaycastFilterType.Exclude
	wallCheckParams.FilterDescendantsInstances = { self._character }

	local wallCheck = workspace:Raycast(
		self._rootPart.Position,
		-self._wallNormal * CONFIG.WALL_DETECT_DISTANCE,
		wallCheckParams
	)

	if not wallCheck then
		print("[WallRunManager] Ending - wall ended, launching off edge")
		-- Store side before ending (for walljump animation)
		local side = self._requestedSide

		-- Launch diagonally forward off the wall edge (70% power of normal jump)
		local angleRad = math.rad(CONFIG.JUMP_ANGLE)
		local edgePower = CONFIG.JUMP_HORIZONTAL_POWER * 0.7
		local forwardPower = math.cos(angleRad) * edgePower
		local awayPower = math.sin(angleRad) * edgePower

		local forwardVel = self._wallDir * forwardPower
		local awayVel = self._wallNormal * awayPower
		local upVel = Vector3.new(0, CONFIG.JUMP_UP_POWER * 0.5, 0)
		self._rootPart.AssemblyLinearVelocity = forwardVel + awayVel + upVel
		self:_applySpeedBoost()
		self:_endWallRun()

		-- Play walljump animation after ending wallrun (with speed multiplier)
		if side == "Right" and self._wallJumpRightAnim then
			self._wallJumpRightAnim:Play(0.1)
			self._wallJumpRightAnim:AdjustSpeed(CONFIG.WALLJUMP_ANIM_SPEED)
		elseif side == "Left" and self._wallJumpLeftAnim then
			self._wallJumpLeftAnim:Play(0.1)
			self._wallJumpLeftAnim:AdjustSpeed(CONFIG.WALLJUMP_ANIM_SPEED)
		end

		-- Block dodge during wall jump
		if self._character then
			self._character:SetAttribute("IsWallJumping", true)
			task.delay(CONFIG.WALLJUMP_DURATION, function()
				if self._character then
					self._character:SetAttribute("IsWallJumping", nil)
				end
			end)
		end
		return
	end

	-- Check if appropriate key is still held
	local shouldContinue = (self._requestedSide == "Left" and self._isHoldingA)
		or (self._requestedSide == "Right" and self._isHoldingD)

	if not shouldContinue then
		print(`[WallRunManager] Ending - key released (Side: {self._requestedSide}, A: {self._isHoldingA}, D: {self._isHoldingD})`)
		self:_endWallRun()
		return
	end

	-- Calculate vertical speed and horizontal speed based on time
	local timeOnWall = tick() - self._wallRunStartTime
	local verticalSpeed = CONFIG.UPWARD_SPEED
	local horizontalSpeed = CONFIG.HORIZONTAL_SPEED

	if timeOnWall > CONFIG.MAX_UPWARD_DURATION then
		-- Descent phase with eased curve (starts slow, accelerates)
		local descentTime = timeOnWall - CONFIG.MAX_UPWARD_DURATION
		local descentProgress = math.min(descentTime / CONFIG.DESCENT_CURVE_TIME, 1)
		-- Quadratic ease-in for natural acceleration
		local easedProgress = descentProgress * descentProgress
		-- Interpolate between min and max descent speed
		verticalSpeed = CONFIG.DOWNWARD_SPEED_MIN + (CONFIG.DOWNWARD_SPEED_MAX - CONFIG.DOWNWARD_SPEED_MIN) * easedProgress
		horizontalSpeed = CONFIG.DESCENT_HORIZONTAL_SPEED
	end

	-- Calculate velocity: horizontal along wall + vertical
	local horizontalVelocity = self._wallDir * horizontalSpeed
	local verticalVelocity = Vector3.new(0, verticalSpeed, 0)
	local totalVelocity = horizontalVelocity + verticalVelocity

	-- Apply velocity directly
	self._rootPart.AssemblyLinearVelocity = totalVelocity
	self._rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Smoothly adjust distance to wall (target 2 studs)
	local currentDistance = wallCheck.Distance
	local distanceError = currentDistance - CONFIG.TARGET_WALL_DISTANCE
	if math.abs(distanceError) > 0.1 then
		-- Lerp towards target distance
		local correction = distanceError * math.min(_deltaTime * CONFIG.DISTANCE_LERP_SPEED, 1)
		local correctionVector = -self._wallNormal * correction
		self._rootPart.CFrame = self._rootPart.CFrame + correctionVector
	end

	-- Face forward along wall
	local lookCFrame = CFrame.lookAt(self._rootPart.Position, self._rootPart.Position + self._wallDir)
	self._rootPart.CFrame = CFrame.new(self._rootPart.Position) * lookCFrame.Rotation
end

function WallRunManager:_jumpOffWall()
	if not self._rootPart or not self._wallNormal or not self._wallDir then
		self:_endWallRun()
		return
	end

	print("[WallRunManager] Jumping off wall")

	-- Store side before ending (for walljump animation)
	local side = self._requestedSide

	-- Calculate 30 degree diagonal jump (forward along wall + outward from wall)
	local angleRad = math.rad(CONFIG.JUMP_ANGLE)
	local forwardPower = math.cos(angleRad) * CONFIG.JUMP_HORIZONTAL_POWER
	local awayPower = math.sin(angleRad) * CONFIG.JUMP_HORIZONTAL_POWER

	local forwardVel = self._wallDir * forwardPower
	local awayVel = self._wallNormal * awayPower
	local upVel = Vector3.new(0, CONFIG.JUMP_UP_POWER, 0)
	self._rootPart.AssemblyLinearVelocity = forwardVel + awayVel + upVel

	-- Speed boost
	self:_applySpeedBoost()

	self:_endWallRun()

	-- Play walljump animation after ending wallrun (with speed multiplier)
	if side == "Right" and self._wallJumpRightAnim then
		self._wallJumpRightAnim:Play(0.1)
		self._wallJumpRightAnim:AdjustSpeed(CONFIG.WALLJUMP_ANIM_SPEED)
	elseif side == "Left" and self._wallJumpLeftAnim then
		self._wallJumpLeftAnim:Play(0.1)
		self._wallJumpLeftAnim:AdjustSpeed(CONFIG.WALLJUMP_ANIM_SPEED)
	end

	-- Block dodge during wall jump
	if self._character then
		self._character:SetAttribute("IsWallJumping", true)
		task.delay(CONFIG.WALLJUMP_DURATION, function()
			if self._character then
				self._character:SetAttribute("IsWallJumping", nil)
			end
		end)
	end
end

function WallRunManager:_applySpeedBoost()
	if not self._humanoid then
		return
	end

	self._speedBoostEndTime = tick() + CONFIG.SPEED_BOOST_DURATION
	self._humanoid.WalkSpeed = self._baseWalkSpeed * CONFIG.SPEED_BOOST_MULTIPLIER
end

function WallRunManager:_updateSpeedBoost()
	if not self._humanoid then
		return
	end

	if tick() > self._speedBoostEndTime and self._speedBoostEndTime > 0 then
		self._speedBoostEndTime = 0
		self._humanoid.WalkSpeed = self._baseWalkSpeed
	end
end

function WallRunManager:_endWallRun()
	if not self._isWallRunning then
		return
	end

	-- Set per-side cooldown
	if self._requestedSide == "Left" then
		self._lastLeftWallRunTime = tick()
	elseif self._requestedSide == "Right" then
		self._lastRightWallRunTime = tick()
	end

	self._isWallRunning = false
	self._requestedSide = nil
	self._wallNormal = nil
	self._wallDir = nil
	self._wallPosition = nil

	-- Unbind update loop
	RunService:UnbindFromRenderStep("WallRunUpdate")

	if self._character then
		self._character:SetAttribute("IsWallRunning", false)
	end

	-- Re-enable physics
	if self._humanoid then
		self._humanoid.PlatformStand = false
		self._humanoid.AutoRotate = true

		-- Restore camera offset
		if self._originalCameraOffset then
			self._humanoid.CameraOffset = self._originalCameraOffset
			self._originalCameraOffset = nil
		else
			self._humanoid.CameraOffset = Vector3.zero
		end
	end

	-- Clear shiftlock overrides and re-enable character rotation
	SmoothShiftLock:SetCameraOffsetOverride(nil)
	SmoothShiftLock:SetCharacterRotationEnabled(true)

	if self._wallRunningEffect then
		self._wallRunningEffect:End()
		self._wallRunningEffect = nil
	end

	-- Stop current wallrun animation
	if self._currentAnim then
		self._currentAnim:Stop(0.1)
		self._currentAnim = nil
	end

	print("[WallRunManager] Ended wall run")
end

function WallRunManager:destroy()
	self:_endWallRun()
end

return WallRunManager
