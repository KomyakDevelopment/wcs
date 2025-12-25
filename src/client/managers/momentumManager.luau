--!strict
-- Momentum Manager (Client)
-- Handles momentum buildup for various actions (wall running, etc.)
-- Modular system - each action can have its own buildup delay and duration

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MomentumManager = {}
MomentumManager.__index = MomentumManager

-- Action configurations
-- Each action can have different buildup parameters
export type ActionConfig = {
	buildupDelay: number, -- Seconds before momentum starts building
	buildupDuration: number, -- Seconds to reach 100% from 0%
	resetOnEnd: boolean, -- Whether momentum resets when action ends
}

local ACTION_CONFIGS: { [string]: ActionConfig } = {
	WallRun = {
		buildupDelay = 0.5, -- Start building after 0.5 seconds
		buildupDuration = 1.0, -- Reach 100% in 1 second
		resetOnEnd = true, -- Reset when wall run ends
	},
}

export type MomentumManager = typeof(setmetatable(
	{} :: {
		_player: Player,
		_character: Model?,

		-- Momentum state
		_momentum: number, -- 0 to 100
		_activeAction: string?, -- Current action contributing to momentum
		_actionStartTime: number, -- When current action started
		_isBuildingUp: boolean, -- Whether momentum is currently building

		-- Connections
		_updateConnection: RBXScriptConnection?,
		_inputConnection: RBXScriptConnection?,

		-- Callbacks
		_onMomentumChanged: ((number) -> ())?,
		_onEnhancedDashAvailable: ((boolean) -> ())?,
		_onActionStarted: ((string) -> ())?,
		_onActionEnded: ((string) -> ())?,
		_onTriggerEnhancedDash: (() -> ())?, -- Callback to trigger the actual dodge skill

		-- Enhanced dash state
		_enhancedDashAvailable: boolean,
		_enhancedDashConsumed: boolean, -- Track if enhanced dash was used this action
	},
	MomentumManager
))

function MomentumManager.new(): MomentumManager
	local self = setmetatable({}, MomentumManager) :: MomentumManager

	self._player = Players.LocalPlayer
	self._character = nil

	self._momentum = 0
	self._activeAction = nil
	self._actionStartTime = 0
	self._isBuildingUp = false

	self._updateConnection = nil
	self._inputConnection = nil

	self._onMomentumChanged = nil
	self._onEnhancedDashAvailable = nil
	self._onActionStarted = nil
	self._onActionEnded = nil
	self._onTriggerEnhancedDash = nil

	self._enhancedDashAvailable = false
	self._enhancedDashConsumed = false

	self:_initialize()

	return self
end

function MomentumManager:_initialize()
	-- Character setup
	if self._player.Character then
		self:_onCharacterAdded(self._player.Character)
	end

	self._player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end)

	-- Update loop for momentum buildup
	self._updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:_update(deltaTime)
	end)

	-- Input handling for enhanced dash (Q key while wall running at 100%)
	self._inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.Q then
			self:_tryEnhancedDash()
		end
	end)

	print("[MomentumManager] Initialized")
end

function MomentumManager:_onCharacterAdded(character: Model)
	self._character = character

	-- Reset momentum on respawn
	self:_resetMomentum()
end

function MomentumManager:_update(_deltaTime: number)
	if not self._activeAction then
		return
	end

	local config = ACTION_CONFIGS[self._activeAction]
	if not config then
		return
	end

	local timeInAction = tick() - self._actionStartTime

	-- Check if we've passed the buildup delay
	if timeInAction < config.buildupDelay then
		-- Still in delay period, momentum stays at 0
		if self._momentum ~= 0 then
			self:_setMomentum(0)
		end
		return
	end

	-- Calculate momentum based on time since delay ended
	local buildupTime = timeInAction - config.buildupDelay
	local progress = math.min(buildupTime / config.buildupDuration, 1)
	local newMomentum = progress * 100

	self:_setMomentum(newMomentum)

	-- Check for enhanced dash availability
	local wasAvailable = self._enhancedDashAvailable
	self._enhancedDashAvailable = self._momentum >= 100 and not self._enhancedDashConsumed

	if self._enhancedDashAvailable ~= wasAvailable then
		if self._onEnhancedDashAvailable then
			self._onEnhancedDashAvailable(self._enhancedDashAvailable)
		end

		if self._enhancedDashAvailable then
			print("[MomentumManager] Enhanced dash now available!")
		end
	end
end

function MomentumManager:_setMomentum(value: number)
	local oldMomentum = self._momentum
	self._momentum = math.clamp(value, 0, 100)

	if self._momentum ~= oldMomentum then
		if self._onMomentumChanged then
			self._onMomentumChanged(self._momentum)
		end
	end
end

function MomentumManager:_resetMomentum()
	self:_setMomentum(0)
	self._enhancedDashAvailable = false
	self._enhancedDashConsumed = false

	if self._onEnhancedDashAvailable then
		self._onEnhancedDashAvailable(false)
	end
end

-- Start tracking an action for momentum buildup
function MomentumManager:startAction(actionName: string)
	if not ACTION_CONFIGS[actionName] then
		warn(`[MomentumManager] Unknown action: {actionName}`)
		return
	end

	-- If already doing this action, don't restart
	if self._activeAction == actionName then
		return
	end

	-- End previous action if any
	if self._activeAction then
		self:endAction(self._activeAction)
	end

	self._activeAction = actionName
	self._actionStartTime = tick()
	self._enhancedDashConsumed = false

	-- Notify that action started (UI can show immediately even at 0%)
	if self._onActionStarted then
		self._onActionStarted(actionName)
	end

	print(`[MomentumManager] Started action: {actionName}`)
end

-- End tracking an action
function MomentumManager:endAction(actionName: string)
	if self._activeAction ~= actionName then
		return
	end

	local config = ACTION_CONFIGS[actionName]

	print(`[MomentumManager] Ended action: {actionName} (momentum was {math.floor(self._momentum)}%)`)

	self._activeAction = nil
	self._actionStartTime = 0

	-- Notify that action ended
	if self._onActionEnded then
		self._onActionEnded(actionName)
	end

	-- Reset momentum if configured to do so
	if config and config.resetOnEnd then
		self:_resetMomentum()
	end
end

-- Try to perform enhanced dash
function MomentumManager:_tryEnhancedDash()
	if not self._enhancedDashAvailable then
		return
	end

	if not self._character then
		return
	end

	-- Must be wall running to use enhanced dash
	if self._activeAction ~= "WallRun" then
		return
	end

	-- Fire remote to tell server about enhanced dash (client attributes don't replicate)
	local enhancedDashRemote = ReplicatedStorage:FindFirstChild("SetEnhancedDash")
	if enhancedDashRemote then
		enhancedDashRemote:FireServer(true)
	end

	-- Set client-side attribute for animation (client reads this for enhanced dash anim)
	self._character:SetAttribute("UseEnhancedDashAnim", true)

	-- Mark as consumed so it can't be used again this action
	self._enhancedDashConsumed = true
	self._enhancedDashAvailable = false

	if self._onEnhancedDashAvailable then
		self._onEnhancedDashAvailable(false)
	end

	print("[MomentumManager] Enhanced dash triggered!")

	-- Actually trigger the dodge skill
	if self._onTriggerEnhancedDash then
		self._onTriggerEnhancedDash()
	end
end

-- Check if enhanced dash is currently available
function MomentumManager:isEnhancedDashAvailable(): boolean
	return self._enhancedDashAvailable
end

-- Get current momentum (0-100)
function MomentumManager:getMomentum(): number
	return self._momentum
end

-- Get current active action
function MomentumManager:getActiveAction(): string?
	return self._activeAction
end

-- Set callback for momentum changes
function MomentumManager:setOnMomentumChanged(callback: (number) -> ())
	self._onMomentumChanged = callback
end

-- Set callback for enhanced dash availability changes
function MomentumManager:setOnEnhancedDashAvailable(callback: (boolean) -> ())
	self._onEnhancedDashAvailable = callback
end

-- Set callback for when an action starts (UI can show immediately)
function MomentumManager:setOnActionStarted(callback: (string) -> ())
	self._onActionStarted = callback
end

-- Set callback for when an action ends
function MomentumManager:setOnActionEnded(callback: (string) -> ())
	self._onActionEnded = callback
end

-- Set callback to trigger the actual dodge skill for enhanced dash
function MomentumManager:setOnTriggerEnhancedDash(callback: () -> ())
	self._onTriggerEnhancedDash = callback
end

-- Register a new action configuration
function MomentumManager:registerAction(actionName: string, config: ActionConfig)
	ACTION_CONFIGS[actionName] = config
	print(`[MomentumManager] Registered action: {actionName}`)
end

function MomentumManager:destroy()
	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end

	if self._inputConnection then
		self._inputConnection:Disconnect()
		self._inputConnection = nil
	end
end

return MomentumManager
