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

local WallRunManager = {}
WallRunManager.__index = WallRunManager

-- Configuration
local CONFIG = {
	-- Detection
	WALL_DETECT_DISTANCE = 3.5,
	MIN_SPEED = 5,

	-- Movement
	HORIZONTAL_SPEED = 32, -- Speed along wall (studs/sec) - much faster
	DESCENT_HORIZONTAL_SPEED = 28, -- Slightly slower during descent but still fast
	UPWARD_SPEED = 2, -- Slight upward drift to stay on wall
	DOWNWARD_SPEED = -12, -- Fast descent after time limit
	MAX_UPWARD_DURATION = 1.5, -- Seconds before descent
	GROUND_CHECK_DISTANCE = 4, -- Distance to check for ground (ends slightly before hitting)

	-- Jump off
	JUMP_AWAY_POWER = 30,
	JUMP_UP_POWER = 50,
	SPEED_BOOST_MULTIPLIER = 1.4,
	SPEED_BOOST_DURATION = 1.5,

	-- Cooldown
	COOLDOWN = 0.5,

	-- Animation
	ANIMATION_ID = "rbxassetid://94461174611915",
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

		_updateConnection: RBXScriptConnection?,
		_animation: AnimationTrack?,
		_wallRunningEffect: any?,
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

	self._updateConnection = nil
	self._animation = nil
	self._wallRunningEffect = nil

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

	-- Load animation
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = CONFIG.ANIMATION_ID
		self._animation = animator:LoadAnimation(anim)
		self._animation.Priority = Enum.AnimationPriority.Action
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

			-- Match current movement
			local currentVel = self._rootPart.AssemblyLinearVelocity
			local currentHorizontal = Vector3.new(currentVel.X, 0, currentVel.Z)
			if currentHorizontal.Magnitude > 1 and currentHorizontal:Dot(wallDir) < 0 then
				wallDir = -wallDir
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

	-- Play animation
	if self._animation then
		self._animation:Play(0.1)
	end

	-- Start update loop (RenderStepped for smoothness)
	self._updateConnection = RunService.RenderStepped:Connect(function(deltaTime)
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
		-- Descent phase: faster down, still fast horizontally
		verticalSpeed = CONFIG.DOWNWARD_SPEED
		horizontalSpeed = CONFIG.DESCENT_HORIZONTAL_SPEED
	end

	-- Calculate velocity: horizontal along wall + vertical
	local horizontalVelocity = self._wallDir * horizontalSpeed
	local verticalVelocity = Vector3.new(0, verticalSpeed, 0)
	local totalVelocity = horizontalVelocity + verticalVelocity

	-- Apply velocity directly
	self._rootPart.AssemblyLinearVelocity = totalVelocity
	self._rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Face forward along wall
	local lookCFrame = CFrame.lookAt(self._rootPart.Position, self._rootPart.Position + self._wallDir)
	self._rootPart.CFrame = CFrame.new(self._rootPart.Position) * lookCFrame.Rotation
end

function WallRunManager:_jumpOffWall()
	if not self._rootPart or not self._wallNormal then
		self:_endWallRun()
		return
	end

	print("[WallRunManager] Jumping off wall")

	-- Apply jump velocity
	local jumpVel = self._wallNormal * CONFIG.JUMP_AWAY_POWER + Vector3.new(0, CONFIG.JUMP_UP_POWER, 0)
	self._rootPart.AssemblyLinearVelocity = jumpVel

	-- Speed boost
	self:_applySpeedBoost()

	self:_endWallRun()
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

	-- Disconnect update loop
	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end

	if self._character then
		self._character:SetAttribute("IsWallRunning", false)
	end

	-- Re-enable physics
	if self._humanoid then
		self._humanoid.PlatformStand = false
		self._humanoid.AutoRotate = true
	end

	if self._wallRunningEffect then
		self._wallRunningEffect:End()
		self._wallRunningEffect = nil
	end

	if self._animation then
		self._animation:Stop(0.1)
	end

	print("[WallRunManager] Ended wall run")
end

function WallRunManager:destroy()
	self:_endWallRun()
end

return WallRunManager
