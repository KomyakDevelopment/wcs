--!strict
-- Dynamic FOV Manager (Client)
-- Smoothly adjusts camera FOV based on player velocity and movement states
-- Creates a dynamic feeling that responds to speed
-- Robust implementation with failsafes and automatic recovery

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

-- Sanity check interval (seconds)
local SANITY_CHECK_INTERVAL = 0.5

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

		-- Settings
		_enabled: boolean,

		-- FOV state
		_baseFOV: number,
		_currentFOV: number,
		_targetFOV: number,

		-- Connections
		_updateConnection: RBXScriptConnection?,
		_characterConnection: RBXScriptConnection?,
		_characterRemovingConnection: RBXScriptConnection?,

		-- Action tracking
		_activeActions: { [string]: boolean },

		-- Sanity check
		_lastSanityCheck: number,
	},
	DynamicFOVManager
))

function DynamicFOVManager.new(): DynamicFOVManager
	local self = setmetatable({}, DynamicFOVManager) :: DynamicFOVManager

	self._player = Players.LocalPlayer
	self._character = nil

	self._enabled = true -- On by default

	self._baseFOV = BASE_FOV
	self._currentFOV = BASE_FOV
	self._targetFOV = BASE_FOV

	self._updateConnection = nil
	self._characterConnection = nil
	self._characterRemovingConnection = nil

	self._activeActions = {}
	self._lastSanityCheck = 0

	self:_initialize()

	return self
end

-- Get camera safely (always fresh reference)
function DynamicFOVManager:_getCamera(): Camera?
	return workspace.CurrentCamera
end

function DynamicFOVManager:_initialize()
	-- Get current camera FOV as base
	local camera = self:_getCamera()
	if camera then
		self._baseFOV = camera.FieldOfView
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

	-- Reset all state on respawn
	self:_resetToBase()

	-- Listen for character removal (death, etc.)
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.Died:Connect(function()
			self:_onCharacterDied()
		end)
	end

	-- Also listen for character being removed from workspace
	if self._characterRemovingConnection then
		self._characterRemovingConnection:Disconnect()
	end

	self._characterRemovingConnection = character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_onCharacterRemoved()
		end
	end)
end

function DynamicFOVManager:_onCharacterDied()
	-- Clear all actions and reset FOV smoothly
	self._activeActions = {}
	self._targetFOV = self._baseFOV
end

function DynamicFOVManager:_onCharacterRemoved()
	-- Force immediate reset when character is removed
	self._character = nil
	self:_resetToBase()
end

-- Reset FOV to base state
function DynamicFOVManager:_resetToBase()
	self._currentFOV = self._baseFOV
	self._targetFOV = self._baseFOV
	self._activeActions = {}

	local camera = self:_getCamera()
	if camera then
		camera.FieldOfView = self._baseFOV
	end
end

-- Force reset (can be called externally as a failsafe)
function DynamicFOVManager:forceReset()
	self:_resetToBase()
	print("[DynamicFOVManager] Force reset to base FOV:", self._baseFOV)
end

function DynamicFOVManager:_update(deltaTime: number)
	local camera = self:_getCamera()

	-- If disabled or no camera, ensure we're at base FOV
	if not self._enabled then
		if camera and math.abs(camera.FieldOfView - self._baseFOV) > 0.1 then
			camera.FieldOfView = self._baseFOV
			self._currentFOV = self._baseFOV
		end
		return
	end

	if not camera then
		return
	end

	-- Periodic sanity check
	local now = tick()
	if now - self._lastSanityCheck > SANITY_CHECK_INTERVAL then
		self._lastSanityCheck = now
		self:_performSanityCheck(camera)
	end

	-- If no character or HRP, smoothly return to base FOV
	local hrp: BasePart? = nil
	if self._character then
		hrp = self._character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	if not self._character or not hrp then
		-- No character - target base FOV and smooth towards it
		self._targetFOV = self._baseFOV
		self._activeActions = {} -- Clear all actions

		-- Smooth return to base
		self:_smoothFOV(deltaTime, camera)
		return
	end

	-- Check character actions (clears stale actions automatically)
	self:_checkCharacterActions()

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

	-- Calculate action-based FOV bonus (only active actions)
	local actionFOVBonus = 0
	for action, isActive in self._activeActions do
		if isActive == true and ACTION_FOV_BONUSES[action] then
			actionFOVBonus = math.max(actionFOVBonus, ACTION_FOV_BONUSES[action])
		end
	end

	-- Total FOV addition (clamped to max)
	local totalAddition = math.min(speedFOVAddition + actionFOVBonus, MAX_FOV_ADDITION)

	-- Dynamic target FOV (updates every frame based on current speed)
	self._targetFOV = self._baseFOV + totalAddition

	-- Smooth follow
	self:_smoothFOV(deltaTime, camera)
end

-- Separate smoothing function for clarity
function DynamicFOVManager:_smoothFOV(deltaTime: number, camera: Camera)
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
	else
		-- Close enough - snap to target
		self._currentFOV = self._targetFOV
	end

	-- Apply to camera (with safety clamp)
	camera.FieldOfView = math.clamp(self._currentFOV, 1, 120)
end

-- Sanity check to catch any edge cases
function DynamicFOVManager:_performSanityCheck(camera: Camera)
	-- Check if FOV is in valid range
	if self._currentFOV < 1 or self._currentFOV > 120 then
		warn("[DynamicFOVManager] FOV out of range, resetting:", self._currentFOV)
		self:_resetToBase()
		return
	end

	-- Check if camera FOV matches our tracking (catches external modifications)
	local cameraFOV = camera.FieldOfView
	if math.abs(cameraFOV - self._currentFOV) > 10 then
		-- Camera FOV was modified externally, sync to it
		self._currentFOV = cameraFOV
	end

	-- If no active actions and speed is low, FOV should be near base
	local hrp: BasePart? = nil
	if self._character then
		hrp = self._character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	if hrp then
		local velocity = hrp.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		-- If player is basically stationary and no actions, FOV should be near base
		local hasActiveActions = false
		for _, isActive in self._activeActions do
			if isActive == true then
				hasActiveActions = true
				break
			end
		end

		if horizontalSpeed < 5 and not hasActiveActions then
			-- Should be at or near base FOV
			if math.abs(self._currentFOV - self._baseFOV) > 5 then
				-- Something's wrong, gradually correct
				self._targetFOV = self._baseFOV
			end
		end
	end
end

function DynamicFOVManager:_checkCharacterActions()
	if not self._character then
		-- No character - clear all actions
		self._activeActions = {}
		return
	end

	-- Helper function to safely get boolean attribute
	local function getAttr(name: string): boolean
		local value = self._character:GetAttribute(name)
		return value == true -- Explicitly check for true, nil and false both return false
	end

	-- Check sprinting
	self._activeActions["Sprinting"] = getAttr("IsSprinting")

	-- Check dashing (status effect attribute or sliding effect)
	self._activeActions["Dashing"] = getAttr("_DashActive")

	-- Check enhanced dash (momentum-powered)
	self._activeActions["EnhancedDash"] = getAttr("UseEnhancedDashAnim")

	-- Check sliding
	self._activeActions["Sliding"] = getAttr("_SlideActive")

	-- Check wall running
	local isWallRunning = getAttr("IsWallRunning")
	self._activeActions["WallRunning"] = isWallRunning

	-- Check momentum wall run (wall running with momentum buildup)
	local momentumPercent = self._character:GetAttribute("MomentumPercent")
	local hasMomentum = type(momentumPercent) == "number" and momentumPercent > 0.3
	self._activeActions["MomentumWallRun"] = isWallRunning and hasMomentum
end

-- Manually set an action state (for external control)
function DynamicFOVManager:setAction(actionName: string, isActive: boolean)
	self._activeActions[actionName] = isActive
end

-- Clear a specific action
function DynamicFOVManager:clearAction(actionName: string)
	self._activeActions[actionName] = false
end

-- Clear all actions (useful for resetting state)
function DynamicFOVManager:clearAllActions()
	self._activeActions = {}
end

-- Set base FOV (if player changes FOV in settings)
function DynamicFOVManager:setBaseFOV(fov: number)
	self._baseFOV = math.clamp(fov, 30, 120)
	print("[DynamicFOVManager] Base FOV set to:", self._baseFOV)
end

-- Get current FOV
function DynamicFOVManager:getCurrentFOV(): number
	return self._currentFOV
end

-- Get target FOV
function DynamicFOVManager:getTargetFOV(): number
	return self._targetFOV
end

-- Get base FOV
function DynamicFOVManager:getBaseFOV(): number
	return self._baseFOV
end

-- Enable/disable dynamic FOV (setting toggle)
function DynamicFOVManager:setEnabled(enabled: boolean)
	self._enabled = enabled

	-- Reset FOV to base when disabled
	if not enabled then
		self:_resetToBase()
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

	if self._characterRemovingConnection then
		self._characterRemovingConnection:Disconnect()
		self._characterRemovingConnection = nil
	end

	-- Reset FOV to base
	local camera = self:_getCamera()
	if camera then
		camera.FieldOfView = self._baseFOV
	end
end

return DynamicFOVManager
