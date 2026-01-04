--!strict
-- Ledge Hang Manager (Client)
-- Allows players to grab ledges while airborne, hang from them, then vault over or drop down
-- Press Space while airborne near a ledge to grab it
-- Press Space while hanging to vault over, Press S to drop down

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local Hanging = require(ReplicatedStorage.Shared.statusEffects.hanging)

-- Hitstun status effects for hit detection
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)

local LedgeHangManager = {}
LedgeHangManager.__index = LedgeHangManager

-- Configuration
local CONFIG = {
	-- Detection
	WALL_DETECT_DISTANCE = 3.0, -- Raycast distance to detect ledge
	MAX_GRAB_HEIGHT = 5.0, -- Max height above current position to grab
	MIN_GRAB_HEIGHT = 1.0, -- Min height (don't grab ledges at foot level)
	MIN_LEDGE_DEPTH = 1.0, -- Minimum platform depth
	MIN_SURFACE_FLATNESS = 0.9, -- Dot product with Y axis for flat surface

	-- Positioning
	HANG_OFFSET_FROM_WALL = 1.2, -- Distance from wall while hanging
	HANG_OFFSET_BELOW_LEDGE = 2.5, -- How far below ledge top to hang

	-- Timing
	VAULT_DURATION = 0.35, -- Time to vault up onto ledge

	-- Input
	INPUT_BUFFER_TIME = 0.3, -- Grace period for Space press
	COOLDOWN = 0.3, -- Seconds between grabs
}

-- Ease out sine for smooth vault motion
local function easeOutSine(t: number): number
	return math.sin((t * math.pi) / 2)
end

type HangState = "none" | "hanging" | "vaulting" | "dropping"

type LedgeData = {
	wallNormal: Vector3,
	ledgeTopY: number,
	wallPosition: Vector3,
	attachPosition: Vector3,
}

export type LedgeHangManager = typeof(setmetatable(
	{} :: {
		_player: Player,
		_character: Model?,
		_humanoid: Humanoid?,
		_rootPart: BasePart?,

		_currentState: HangState,
		_ledgeData: LedgeData?,
		_lastHangTime: number,
		_inputBufferEnd: number,

		_hangingEffect: any?,

		-- Connections
		_characterConnection: RBXScriptConnection?,
	},
	LedgeHangManager
))

function LedgeHangManager.new(): LedgeHangManager
	local self = setmetatable({}, LedgeHangManager) :: LedgeHangManager

	self._player = Players.LocalPlayer
	self._character = nil
	self._humanoid = nil
	self._rootPart = nil

	self._currentState = "none"
	self._ledgeData = nil
	self._lastHangTime = 0
	self._inputBufferEnd = 0

	self._hangingEffect = nil

	self._characterConnection = nil

	self:_initialize()

	return self
end

function LedgeHangManager:_initialize()
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
			if self._currentState == "hanging" then
				-- Vault over the ledge
				self:_vault()
			else
				-- Try to grab ledge (set buffer)
				self._inputBufferEnd = tick() + CONFIG.INPUT_BUFFER_TIME
				self:_tryGrabLedge()
			end
		end

		if input.KeyCode == Enum.KeyCode.S then
			if self._currentState == "hanging" then
				-- Drop down
				self:_drop()
			end
		end
	end)

	-- Continuous check during input buffer
	RunService.Heartbeat:Connect(function()
		if tick() < self._inputBufferEnd and self._currentState == "none" then
			self:_tryGrabLedge()
		end
	end)

	print("[LedgeHangManager] Initialized - Press Space near ledge while airborne to grab")
end

function LedgeHangManager:_onCharacterAdded(character: Model)
	-- End any existing hang
	self:_endHang()

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	if not humanoid or not rootPart then
		return
	end

	self._character = character
	self._humanoid = humanoid
	self._rootPart = rootPart

	-- Reset state
	self._lastHangTime = 0
	self._currentState = "none"
end

function LedgeHangManager:_tryGrabLedge()
	-- Validation checks
	if self._currentState ~= "none" then
		return
	end

	if not self._character or not self._humanoid or not self._rootPart then
		return
	end

	-- Must be airborne
	if self._humanoid.FloorMaterial ~= Enum.Material.Air then
		return
	end

	-- Cooldown check
	if tick() - self._lastHangTime < CONFIG.COOLDOWN then
		return
	end

	-- Not during other movement states
	if self._character:GetAttribute("IsClimbing") then
		return
	end
	if self._character:GetAttribute("IsWallRunning") then
		return
	end
	if self._character:GetAttribute("IsWallJumping") then
		return
	end

	-- Detect ledge
	local ledgeData = self:_detectLedge()
	if not ledgeData then
		return
	end

	-- Clear buffer and start hang
	self._inputBufferEnd = 0
	self:_startHang(ledgeData)
end

function LedgeHangManager:_detectLedge(): LedgeData?
	if not self._rootPart or not self._character then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { self._character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local pos = self._rootPart.Position
	local forward = self._rootPart.CFrame.LookVector

	-- Ray 1: Forward ray at chest level to detect wall/ledge face
	local forwardRay = workspace:Raycast(pos, forward * CONFIG.WALL_DETECT_DISTANCE, params)
	if not forwardRay then
		return nil
	end

	local wallNormal = forwardRay.Normal
	-- Must be vertical wall (normal mostly horizontal)
	if math.abs(wallNormal.Y) > 0.3 then
		return nil
	end

	-- Ray 2: Head clearance ray - ensure no wall at head level (must be open above)
	local headPos = pos + Vector3.new(0, 2, 0)
	local headRay = workspace:Raycast(headPos, forward * CONFIG.WALL_DETECT_DISTANCE, params)
	if headRay then
		-- Wall continues at head level - not a grabbable ledge
		return nil
	end

	-- Ray 3: Top surface ray - find the ledge top
	-- Cast from above the wall hit, looking down
	local aboveWall = forwardRay.Position + Vector3.new(0, CONFIG.MAX_GRAB_HEIGHT, 0) + forward * 0.5
	local topRay = workspace:Raycast(aboveWall, Vector3.new(0, -CONFIG.MAX_GRAB_HEIGHT - 1, 0), params)
	if not topRay then
		return nil
	end

	-- Check if surface is flat enough
	local surfaceFlatness = topRay.Normal:Dot(Vector3.new(0, 1, 0))
	if surfaceFlatness < CONFIG.MIN_SURFACE_FLATNESS then
		return nil
	end

	local ledgeTopY = topRay.Position.Y

	-- Check height is within grabbable range
	local heightDiff = ledgeTopY - pos.Y
	if heightDiff < CONFIG.MIN_GRAB_HEIGHT or heightDiff > CONFIG.MAX_GRAB_HEIGHT then
		return nil
	end

	-- Ray 4: Depth check - ensure ledge has enough depth
	local depthCheckPos = topRay.Position + Vector3.new(0, 0.5, 0) + forward * CONFIG.MIN_LEDGE_DEPTH
	local depthRay = workspace:Raycast(depthCheckPos, Vector3.new(0, -1, 0), params)
	if not depthRay then
		-- No surface at depth check - ledge too thin
		return nil
	end

	-- Calculate hang position
	local attachPosition = Vector3.new(
		forwardRay.Position.X + wallNormal.X * CONFIG.HANG_OFFSET_FROM_WALL,
		ledgeTopY - CONFIG.HANG_OFFSET_BELOW_LEDGE,
		forwardRay.Position.Z + wallNormal.Z * CONFIG.HANG_OFFSET_FROM_WALL
	)

	return {
		wallNormal = wallNormal,
		ledgeTopY = ledgeTopY,
		wallPosition = forwardRay.Position,
		attachPosition = attachPosition,
	}
end

function LedgeHangManager:_startHang(ledgeData: LedgeData)
	if not self._rootPart or not self._humanoid or not self._character then
		return
	end

	self._currentState = "hanging"
	self._ledgeData = ledgeData

	print("[LedgeHangManager] Started hanging from ledge")

	-- Disable physics
	self._humanoid.PlatformStand = true
	self._humanoid.AutoRotate = false

	-- Apply status effect
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(self._character)
	if wcsCharacter then
		self._hangingEffect = Hanging.new(wcsCharacter)
		if self._hangingEffect then
			self._hangingEffect:Start(999) -- Long duration, we end manually
		end
	end

	-- Set attribute for other systems to check
	self._character:SetAttribute("IsHanging", true)

	-- Snap to hang position
	local lookDir = -ledgeData.wallNormal
	self._rootPart.CFrame = CFrame.new(ledgeData.attachPosition) * CFrame.lookAt(Vector3.zero, lookDir).Rotation

	-- Kill velocity
	self._rootPart.AssemblyLinearVelocity = Vector3.zero
	self._rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Bind update loop to maintain position
	RunService:BindToRenderStep("LedgeHangUpdate", 300, function(_deltaTime)
		self:_updateHang()
	end)

	-- Bind rotation enforcement at high priority
	RunService:BindToRenderStep("LedgeHangRotation", Enum.RenderPriority.Last.Value + 1, function()
		if self._currentState == "hanging" and self._rootPart and self._ledgeData then
			local lookDir2 = -self._ledgeData.wallNormal
			self._rootPart.CFrame = CFrame.new(self._ledgeData.attachPosition)
				* CFrame.lookAt(Vector3.zero, lookDir2).Rotation
		end
	end)
end

function LedgeHangManager:_updateHang()
	if self._currentState ~= "hanging" then
		return
	end

	if not self._rootPart or not self._character then
		self:_endHang()
		return
	end

	-- Zero out velocity continuously
	self._rootPart.AssemblyLinearVelocity = Vector3.zero
	self._rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Check if player was hit
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(self._character)
	if wcsCharacter and wcsCharacter:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun }) then
		print("[LedgeHangManager] Ending - Player was hit")
		self:_drop()
	end
end

function LedgeHangManager:_vault()
	if self._currentState ~= "hanging" then
		return
	end

	if not self._rootPart or not self._ledgeData then
		return
	end

	self._currentState = "vaulting"
	print("[LedgeHangManager] Vaulting over ledge")

	-- Unbind hang updates (we'll do our own interpolation)
	RunService:UnbindFromRenderStep("LedgeHangUpdate")
	RunService:UnbindFromRenderStep("LedgeHangRotation")

	local startPos = self._rootPart.Position
	local startRotation = self._rootPart.CFrame.Rotation

	-- Target position: onto the ledge, forward from the wall
	local targetPos = Vector3.new(
		self._ledgeData.wallPosition.X - self._ledgeData.wallNormal.X * 1.5,
		self._ledgeData.ledgeTopY + 2.5, -- Root part height above ground
		self._ledgeData.wallPosition.Z - self._ledgeData.wallNormal.Z * 1.5
	)

	local elapsedTime = 0
	local connection: RBXScriptConnection?

	connection = RunService.RenderStepped:Connect(function(dt)
		elapsedTime = elapsedTime + dt
		local progress = math.clamp(elapsedTime / CONFIG.VAULT_DURATION, 0, 1)
		local easedProgress = easeOutSine(progress)

		if self._rootPart then
			local currentPos = startPos:Lerp(targetPos, easedProgress)
			self._rootPart.CFrame = CFrame.new(currentPos) * startRotation
			self._rootPart.AssemblyLinearVelocity = Vector3.zero
			self._rootPart.AssemblyAngularVelocity = Vector3.zero
		end

		if progress >= 1 then
			if connection then
				connection:Disconnect()
			end
			self:_endHang()
		end
	end)
end

function LedgeHangManager:_drop()
	if self._currentState ~= "hanging" then
		return
	end

	self._currentState = "dropping"
	print("[LedgeHangManager] Dropping from ledge")

	-- Calculate push velocity (away from wall + downward)
	local pushVelocity = Vector3.zero
	if self._ledgeData then
		pushVelocity = self._ledgeData.wallNormal * 5 + Vector3.new(0, -10, 0)
	end

	self:_endHang()

	-- Apply push after physics re-enabled
	task.defer(function()
		if self._rootPart then
			self._rootPart.AssemblyLinearVelocity = pushVelocity
		end
	end)
end

function LedgeHangManager:_endHang()
	if self._currentState == "none" then
		return
	end

	local wasHanging = self._currentState == "hanging"

	self._currentState = "none"
	self._lastHangTime = tick()

	-- Unbind update loops
	pcall(function()
		RunService:UnbindFromRenderStep("LedgeHangUpdate")
	end)
	pcall(function()
		RunService:UnbindFromRenderStep("LedgeHangRotation")
	end)

	-- Re-enable physics
	if self._humanoid then
		self._humanoid.PlatformStand = false
		self._humanoid.AutoRotate = true
	end

	-- End status effect
	if self._hangingEffect then
		self._hangingEffect:End()
		self._hangingEffect = nil
	end

	-- Clear attribute
	if self._character then
		self._character:SetAttribute("IsHanging", nil)
	end

	self._ledgeData = nil

	if wasHanging then
		print("[LedgeHangManager] Ended hanging")
	end
end

-- Called by ClimbManager when climb ends at wall top (auto-attach)
-- Returns true if successfully attached, false otherwise
function LedgeHangManager:tryAutoAttachFromClimb(wallNormal: Vector3, position: Vector3): boolean
	if self._currentState ~= "none" then
		return false
	end

	if not self._character or not self._humanoid or not self._rootPart then
		return false
	end

	-- Don't grab if cooldown active
	if tick() - self._lastHangTime < CONFIG.COOLDOWN then
		return false
	end

	print("[LedgeHangManager] Attempting auto-attach from climb")

	-- For auto-attach, do a simplified detection
	-- We know the wall normal, just need to find the ledge top
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { self._character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Cast from above looking down to find ledge surface
	-- wallNormal points AWAY from wall, so -wallNormal goes INTO the ledge
	-- Go up 4 studs and forward 2.5 studs into the ledge platform area
	local abovePos = position + Vector3.new(0, 4, 0) - wallNormal * 2.5
	local topRay = workspace:Raycast(abovePos, Vector3.new(0, -6, 0), params)

	if not topRay then
		print("[LedgeHangManager] Auto-attach failed - no ledge surface found")
		print("[LedgeHangManager] Debug - raycast origin:", abovePos, "direction: down 6 studs")
		return false
	end

	-- Check if surface is flat enough
	local surfaceFlatness = topRay.Normal:Dot(Vector3.new(0, 1, 0))
	if surfaceFlatness < CONFIG.MIN_SURFACE_FLATNESS then
		print("[LedgeHangManager] Auto-attach failed - surface not flat enough:", surfaceFlatness)
		return false
	end

	print("[LedgeHangManager] Found ledge surface at Y:", topRay.Position.Y)

	local ledgeTopY = topRay.Position.Y

	-- Calculate hang position
	local attachPosition = Vector3.new(
		position.X + wallNormal.X * CONFIG.HANG_OFFSET_FROM_WALL,
		ledgeTopY - CONFIG.HANG_OFFSET_BELOW_LEDGE,
		position.Z + wallNormal.Z * CONFIG.HANG_OFFSET_FROM_WALL
	)

	local ledgeData: LedgeData = {
		wallNormal = wallNormal,
		ledgeTopY = ledgeTopY,
		wallPosition = position - wallNormal * CONFIG.HANG_OFFSET_FROM_WALL,
		attachPosition = attachPosition,
	}

	self:_startHang(ledgeData)
	return true
end

function LedgeHangManager:destroy()
	self:_endHang()

	if self._characterConnection then
		self._characterConnection:Disconnect()
		self._characterConnection = nil
	end
end

return LedgeHangManager
