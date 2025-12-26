--!strict
-- Dynamic FOV Manager (Client)
-- Smoothly adjusts camera FOV based on player velocity and movement states
-- Creates a dynamic feeling that responds to speed

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DynamicFOVManager = {}
DynamicFOVManager.__index = DynamicFOVManager

-- Configuration
local BASE_FOV = 70 -- Default Roblox FOV
local MAX_FOV_ADDITION = 45 -- Maximum FOV increase (70 + 45 = 115 max for momentum moves)
local SMOOTHING_SPEED_UP = 1 / 0.12 -- FOV increase speed (faster)
local SMOOTHING_SPEED_DOWN = 1 / 0.08 -- FOV decrease speed (even faster for snappy return)

-- Speed thresholds for FOV scaling
local MIN_SPEED_THRESHOLD = 16 -- Below this, no FOV change (normal walk speed)
local MAX_SPEED_THRESHOLD = 60 -- At or above this, max FOV addition

-- Bonus FOV for specific actions (added on top of speed-based FOV)
local ACTION_FOV_BONUSES = {
	-- Momentum actions (extremely exaggerated)
	EnhancedDash = 42, -- Extreme burst for momentum-powered dash
	MomentumWallRun = 33, -- Huge FOV during wall run with momentum
	-- Regular actions
	Dashing = 10, -- Quick burst of FOV during dash
	Sliding = 6, -- Moderate FOV during slide
	WallRunning = 5, -- Slight FOV during wall run
	Sprinting = 3, -- Small FOV when sprinting
}

-- In Exponential easing curve (slow start, fast acceleration)
local function easeInExponential(t: number): number
	if t == 0 then
		return 0
	end
	return math.pow(2, 10 * t - 10)
end

export type DynamicFOVManager = typeof(setmetatable(
	{} :: {
		_player: Player,
		_character: Model?,
		_camera: Camera?,

		-- Settings
		_enabled: boolean,

		-- FOV state
		_baseFOV: number,
		_currentFOV: number,
		_targetFOV: number,

		-- Connections
		_updateConnection: RBXScriptConnection?,
		_characterConnection: RBXScriptConnection?,

		-- Action tracking
		_activeActions: { [string]: boolean },
	},
	DynamicFOVManager
))

function DynamicFOVManager.new(): DynamicFOVManager
	local self = setmetatable({}, DynamicFOVManager) :: DynamicFOVManager

	self._player = Players.LocalPlayer
	self._character = nil
	self._camera = workspace.CurrentCamera

	self._enabled = true -- On by default

	self._baseFOV = BASE_FOV
	self._currentFOV = BASE_FOV
	self._targetFOV = BASE_FOV

	self._updateConnection = nil
	self._characterConnection = nil

	self._activeActions = {}

	self:_initialize()

	return self
end

function DynamicFOVManager:_initialize()
	-- Get current camera FOV as base
	if self._camera then
		self._baseFOV = self._camera.FieldOfView
		self._currentFOV = self._baseFOV
		self._targetFOV = self._baseFOV
	end

	-- Character setup
	if self._player.Character then
		self:_onCharacterAdded(self._player.Character)
	end

	self._characterConnection = self._player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end)

	-- Main update loop
	self._updateConnection = RunService.RenderStepped:Connect(function(deltaTime)
		self:_update(deltaTime)
	end)

	print("[DynamicFOVManager] Initialized with base FOV:", self._baseFOV)
end

function DynamicFOVManager:_onCharacterAdded(character: Model)
	self._character = character

	-- Reset FOV on respawn
	self._currentFOV = self._baseFOV
	self._targetFOV = self._baseFOV
	self._activeActions = {}

	if self._camera then
		self._camera.FieldOfView = self._baseFOV
	end
end

function DynamicFOVManager:_update(deltaTime: number)
	if not self._enabled or not self._character or not self._camera then
		return
	end

	local hrp = self._character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	-- Calculate speed-based FOV addition
	local velocity = hrp.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	-- Map speed to FOV addition (0 at MIN_SPEED, MAX_FOV_ADDITION at MAX_SPEED)
	local speedProgress = math.clamp(
		(horizontalSpeed - MIN_SPEED_THRESHOLD) / (MAX_SPEED_THRESHOLD - MIN_SPEED_THRESHOLD),
		0,
		1
	)

	-- Use quadratic curve for more dynamic feel (faster response at high speeds)
	local speedFOVAddition = speedProgress * speedProgress * MAX_FOV_ADDITION * 0.6

	-- Calculate action-based FOV bonus
	local actionFOVBonus = 0
	for action, isActive in self._activeActions do
		if isActive and ACTION_FOV_BONUSES[action] then
			actionFOVBonus = math.max(actionFOVBonus, ACTION_FOV_BONUSES[action])
		end
	end

	-- Check character attributes for actions
	self:_checkCharacterActions()

	-- Total FOV addition (clamped to max)
	local totalAddition = math.min(speedFOVAddition + actionFOVBonus, MAX_FOV_ADDITION)

	-- Dynamic target FOV (updates every frame based on current speed)
	self._targetFOV = self._baseFOV + totalAddition

	-- Smooth follow with Out Circular feel
	-- Distance-based alpha: move faster when far, slower when close
	local diff = self._targetFOV - self._currentFOV
	local absDiff = math.abs(diff)

	if absDiff > 0.01 then
		-- Normalize distance (0 = at target, 1 = max distance)
		local normalizedDist = math.clamp(absDiff / MAX_FOV_ADDITION, 0, 1)

		-- In Exponential: slow when close, accelerates when far
		local easedSpeed = easeInExponential(normalizedDist)

		-- Use different speeds for increasing vs decreasing FOV
		local smoothingSpeed = diff > 0 and SMOOTHING_SPEED_UP or SMOOTHING_SPEED_DOWN

		-- Apply smoothing with eased speed (minimum 40% speed to always make progress)
		local alpha = (0.4 + 0.6 * easedSpeed) * smoothingSpeed * deltaTime
		alpha = math.clamp(alpha, 0, 1)

		self._currentFOV = self._currentFOV + diff * alpha
	end

	-- Apply to camera
	self._camera.FieldOfView = self._currentFOV
end

function DynamicFOVManager:_checkCharacterActions()
	if not self._character then
		return
	end

	-- Check sprinting
	local isSprinting = self._character:GetAttribute("IsSprinting")
	self._activeActions["Sprinting"] = isSprinting == true

	-- Check dashing (status effect attribute or sliding effect)
	local isDashing = self._character:GetAttribute("_DashActive")
	self._activeActions["Dashing"] = isDashing == true

	-- Check enhanced dash (momentum-powered)
	local isEnhancedDash = self._character:GetAttribute("UseEnhancedDashAnim")
	self._activeActions["EnhancedDash"] = isEnhancedDash == true

	-- Check sliding
	local isSliding = self._character:GetAttribute("_SlideActive")
	self._activeActions["Sliding"] = isSliding == true

	-- Check wall running
	local isWallRunning = self._character:GetAttribute("IsWallRunning")
	self._activeActions["WallRunning"] = isWallRunning == true

	-- Check momentum wall run (wall running with momentum buildup)
	local momentumPercent = self._character:GetAttribute("MomentumPercent") or 0
	self._activeActions["MomentumWallRun"] = isWallRunning == true and momentumPercent > 0.3
end

-- Manually set an action state (for external control)
function DynamicFOVManager:setAction(actionName: string, isActive: boolean)
	self._activeActions[actionName] = isActive
end

-- Set base FOV (if player changes FOV in settings)
function DynamicFOVManager:setBaseFOV(fov: number)
	self._baseFOV = fov
	print("[DynamicFOVManager] Base FOV set to:", fov)
end

-- Get current FOV
function DynamicFOVManager:getCurrentFOV(): number
	return self._currentFOV
end

-- Get target FOV
function DynamicFOVManager:getTargetFOV(): number
	return self._targetFOV
end

-- Enable/disable dynamic FOV (setting toggle)
function DynamicFOVManager:setEnabled(enabled: boolean)
	self._enabled = enabled

	-- Reset FOV to base when disabled
	if not enabled and self._camera then
		self._currentFOV = self._baseFOV
		self._targetFOV = self._baseFOV
		self._camera.FieldOfView = self._baseFOV
	end

	print("[DynamicFOVManager] Dynamic FOV", enabled and "enabled" or "disabled")
end

-- Check if dynamic FOV is enabled
function DynamicFOVManager:isEnabled(): boolean
	return self._enabled
end

function DynamicFOVManager:destroy()
	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end

	if self._characterConnection then
		self._characterConnection:Disconnect()
		self._characterConnection = nil
	end

	-- Reset FOV to base
	if self._camera then
		self._camera.FieldOfView = self._baseFOV
	end
end

return DynamicFOVManager
