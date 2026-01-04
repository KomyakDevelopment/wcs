--!strict
-- Climb Manager (Client)
-- Deepwoken-style wall climbing system
-- Hold Space while facing a wall to climb vertically

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local Climbing = require(ReplicatedStorage.Shared.statusEffects.climbing)

-- Hitstun status effects for hit detection
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)

local ClimbManager = {}
ClimbManager.__index = ClimbManager

-- Configuration
local CONFIG = {
	-- Detection
	WALL_DETECT_DISTANCE = 2.5, -- Raycast distance to detect wall
	MIN_FORWARD_DOT = 0.7, -- Must be facing wall (dot product threshold)
	MIN_MOVEMENT_SPEED = 3, -- Minimum speed to trigger climb from ground

	-- Climbing
	CLIMB_SPEED = 30, -- Studs per second upward (fast climbing)
	MAX_CLIMB_DURATION = 2.0, -- Seconds before grip fails
	WALL_DISTANCE = 1.5, -- Distance to maintain from wall
	DISTANCE_LERP_SPEED = 10, -- How fast to snap to wall distance

	-- Cooldown
	COOLDOWN = 0.5, -- Seconds between climbs

	-- Animation
	CLIMB_ANIMATION = "rbxassetid://83509350557114",
	CLIMB_ANIM_SPEED = 2.0, -- Faster animation to match climb speed
}

type WallData = {
	normal: Vector3,
	position: Vector3,
}

export type ClimbManager = typeof(setmetatable(
	{} :: {
		_player: Player,
		_character: Model?,
		_humanoid: Humanoid?,
		_rootPart: BasePart?,

		_isClimbing: boolean,
		_climbStartTime: number,
		_lastClimbTime: number,
		_wallNormal: Vector3?,

		_isHoldingSpace: boolean,

		_climbAnimTrack: AnimationTrack?,
		_climbingEffect: any?,

		-- Connections
		_characterConnection: RBXScriptConnection?,

		-- Callback for ledge hang integration (returns true if successfully attached)
		_onClimbEndAtTop: ((wallNormal: Vector3, position: Vector3) -> boolean)?,
	},
	ClimbManager
))

function ClimbManager.new(): ClimbManager
	local self = setmetatable({}, ClimbManager) :: ClimbManager

	self._player = Players.LocalPlayer
	self._character = nil
	self._humanoid = nil
	self._rootPart = nil

	self._isClimbing = false
	self._climbStartTime = 0
	self._lastClimbTime = 0
	self._wallNormal = nil

	self._isHoldingSpace = false

	self._climbAnimTrack = nil
	self._climbingEffect = nil

	self._characterConnection = nil
	self._onClimbEndAtTop = nil

	self:_initialize()

	return self
end

function ClimbManager:_initialize()
	-- Character setup
	if self._player.Character then
		self:_onCharacterAdded(self._player.Character)
	end

	self._characterConnection = self._player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end)

	-- Input handling
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.Space then
			self._isHoldingSpace = true
			self:_tryStartClimb()
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.KeyCode == Enum.KeyCode.Space then
			self._isHoldingSpace = false
			if self._isClimbing then
				self:_endClimb()
			end
		end
	end)

	-- Continuous check for climb opportunity
	RunService.Heartbeat:Connect(function()
		if self._isHoldingSpace and not self._isClimbing then
			self:_tryStartClimb()
		end
	end)

	print("[ClimbManager] Initialized - Hold Space while facing a wall to climb")
end

function ClimbManager:_onCharacterAdded(character: Model)
	-- End any existing climb
	self:_endClimb()

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	if not humanoid or not rootPart then
		return
	end

	self._character = character
	self._humanoid = humanoid
	self._rootPart = rootPart

	-- Load climb animation
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local climbAnim = Instance.new("Animation")
		climbAnim.AnimationId = CONFIG.CLIMB_ANIMATION
		self._climbAnimTrack = animator:LoadAnimation(climbAnim)
		self._climbAnimTrack.Priority = Enum.AnimationPriority.Action
		self._climbAnimTrack.Looped = true
	end

	-- Reset state
	self._lastClimbTime = 0
end

function ClimbManager:_tryStartClimb()
	-- Validation checks
	if self._isClimbing then
		return
	end

	if not self._character or not self._humanoid or not self._rootPart then
		return
	end

	-- Cooldown check
	if tick() - self._lastClimbTime < CONFIG.COOLDOWN then
		return
	end

	-- Must be holding space
	if not self._isHoldingSpace then
		return
	end

	-- Check if wall running or other conflicting state
	if self._character:GetAttribute("IsWallRunning") then
		return
	end

	-- Detect wall
	local wallData = self:_detectWall()
	if not wallData then
		return
	end

	-- Check movement conditions
	local isAirborne = self._humanoid.FloorMaterial == Enum.Material.Air
	local velocity = self._rootPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	-- Must be either airborne OR moving forward on ground
	if not isAirborne then
		-- On ground - must be moving forward toward the wall
		if horizontalSpeed < CONFIG.MIN_MOVEMENT_SPEED then
			return
		end

		-- Check if moving toward wall
		local moveDir = Vector3.new(velocity.X, 0, velocity.Z).Unit
		local towardWall = -wallData.normal
		local movingTowardWall = moveDir:Dot(Vector3.new(towardWall.X, 0, towardWall.Z).Unit)
		if movingTowardWall < 0.5 then
			return
		end
	end

	-- Start climbing
	self:_startClimb(wallData)
end

function ClimbManager:_detectWall(): WallData?
	if not self._rootPart or not self._character then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { self._character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local pos = self._rootPart.Position
	local forward = self._rootPart.CFrame.LookVector

	local result = workspace:Raycast(pos, forward * CONFIG.WALL_DETECT_DISTANCE, params)

	if result then
		local normal = result.Normal
		-- Must be vertical wall (normal mostly horizontal)
		if math.abs(normal.Y) < 0.3 then
			-- Must be facing wall
			local facingDot = -forward:Dot(normal)
			if facingDot > CONFIG.MIN_FORWARD_DOT then
				return {
					normal = normal,
					position = result.Position,
				}
			end
		end
	end

	return nil
end

function ClimbManager:_startClimb(wallData: WallData)
	if not self._rootPart or not self._humanoid or not self._character then
		return
	end

	self._isClimbing = true
	self._climbStartTime = tick()
	self._wallNormal = wallData.normal

	print("[ClimbManager] Started climbing")

	-- Disable physics
	self._humanoid.PlatformStand = true
	self._humanoid.AutoRotate = false

	-- Apply status effect
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(self._character)
	if wcsCharacter then
		self._climbingEffect = Climbing.new(wcsCharacter)
		if self._climbingEffect then
			self._climbingEffect:Start(999) -- Long duration, we end manually
		end
	end

	-- Set attribute for other systems to check
	self._character:SetAttribute("IsClimbing", true)

	-- Play animation
	if self._climbAnimTrack then
		self._climbAnimTrack:Play(0.1)
		self._climbAnimTrack:AdjustSpeed(CONFIG.CLIMB_ANIM_SPEED)
	end

	-- Bind update loop
	RunService:BindToRenderStep("ClimbUpdate", 300, function(deltaTime)
		self:_updateClimb(deltaTime)
	end)

	-- Bind rotation enforcement (like wall run)
	RunService:BindToRenderStep("ClimbRotationEnforce", Enum.RenderPriority.Last.Value + 1, function()
		if self._isClimbing and self._rootPart and self._wallNormal then
			-- Face the wall (look into it)
			local lookDir = -self._wallNormal
			local lookCFrame = CFrame.lookAt(self._rootPart.Position, self._rootPart.Position + lookDir)
			self._rootPart.CFrame = CFrame.new(self._rootPart.Position) * lookCFrame.Rotation
		end
	end)
end

function ClimbManager:_updateClimb(_deltaTime: number)
	if not self._rootPart or not self._humanoid or not self._character or not self._wallNormal then
		self:_endClimb()
		return
	end

	-- Check if Space still held
	if not self._isHoldingSpace then
		print("[ClimbManager] Ending - Space released")
		self:_endClimb()
		return
	end

	-- Check time limit
	local elapsed = tick() - self._climbStartTime
	if elapsed > CONFIG.MAX_CLIMB_DURATION then
		print("[ClimbManager] Ending - Grip failed (time limit)")
		self:_endClimb()
		return
	end

	-- Check if player was hit
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(self._character)
	if wcsCharacter and wcsCharacter:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun }) then
		print("[ClimbManager] Ending - Player was hit")
		self:_endClimb()
		return
	end

	-- Check if wall still exists
	local wallCheck = self:_detectWallContinuous()
	if not wallCheck then
		print("[ClimbManager] Ending - Wall ended")
		-- Notify ledge hang system BEFORE ending climb (for auto-attach)
		local attachedToLedge = false
		if self._onClimbEndAtTop and self._wallNormal and self._rootPart then
			attachedToLedge = self._onClimbEndAtTop(self._wallNormal, self._rootPart.Position)
		end
		-- If attached to ledge, skip physics reset (ledge hang controls physics now)
		self:_endClimb(attachedToLedge)
		return
	end

	-- Apply upward velocity
	self._rootPart.AssemblyLinearVelocity = Vector3.new(0, CONFIG.CLIMB_SPEED, 0)
	self._rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Maintain distance from wall
	local currentDistance = wallCheck.distance
	local distanceError = currentDistance - CONFIG.WALL_DISTANCE
	if math.abs(distanceError) > 0.1 then
		local correction = distanceError * math.min(_deltaTime * CONFIG.DISTANCE_LERP_SPEED, 1)
		local correctionVector = -self._wallNormal * correction
		self._rootPart.CFrame = self._rootPart.CFrame + correctionVector
	end
end

function ClimbManager:_detectWallContinuous(): { distance: number }?
	if not self._rootPart or not self._character or not self._wallNormal then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { self._character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local pos = self._rootPart.Position
	-- Raycast toward the wall we're on
	local result = workspace:Raycast(pos, -self._wallNormal * CONFIG.WALL_DETECT_DISTANCE, params)

	if result then
		return { distance = result.Distance }
	end

	return nil
end

function ClimbManager:_endClimb(skipPhysicsReset: boolean?)
	if not self._isClimbing then
		return
	end

	self._isClimbing = false
	self._lastClimbTime = tick()

	-- Unbind update loops
	RunService:UnbindFromRenderStep("ClimbUpdate")
	RunService:UnbindFromRenderStep("ClimbRotationEnforce")

	-- Re-enable physics (unless skipped because another system took over)
	if not skipPhysicsReset and self._humanoid then
		self._humanoid.PlatformStand = false
		self._humanoid.AutoRotate = true
	end

	-- End status effect
	if self._climbingEffect then
		self._climbingEffect:End()
		self._climbingEffect = nil
	end

	-- Clear attribute
	if self._character then
		self._character:SetAttribute("IsClimbing", nil)
	end

	-- Stop animation
	if self._climbAnimTrack then
		self._climbAnimTrack:Stop(0.15)
	end

	self._wallNormal = nil

	print("[ClimbManager] Ended climbing")
end

-- Set callback for when climb ends at top of wall (for ledge hang auto-attach)
-- Callback should return true if successfully attached to ledge (to skip physics reset)
function ClimbManager:setOnClimbEndAtTop(callback: (wallNormal: Vector3, position: Vector3) -> boolean)
	self._onClimbEndAtTop = callback
end

function ClimbManager:destroy()
	self:_endClimb()

	if self._characterConnection then
		self._characterConnection:Disconnect()
		self._characterConnection = nil
	end
end

return ClimbManager
