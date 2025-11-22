--!strict
-- Input Manager
-- Handles all player input and binds actions to callbacks
-- This is a singleton that manages input across the entire client

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputConfig = require(ReplicatedStorage.Shared.config.inputConfig)

local InputManager = {}
InputManager.__index = InputManager

-- Stores all active action bindings
local boundActions: { [string]: { callback: (string, Enum.UserInputState, InputObject) -> (), enabled: boolean } } = {}

-- Pre-built lookup tables for O(1) input matching (built once at module load)
local keyCodeToAction: { [Enum.KeyCode]: string } = {}
local inputTypeToAction: { [Enum.UserInputType]: string } = {}

-- Build lookup tables at module load time for instant matching
for category, actions in pairs(InputConfig) do
	for actionName, actionConfig in pairs(actions) do
		local fullActionName = `{category}.{actionName}`
		if actionConfig.KeyCode then
			keyCodeToAction[actionConfig.KeyCode] = fullActionName
		end
		if actionConfig.InputType and not actionConfig.KeyCode then
			-- Only map InputType if KeyCode is not set (mouse buttons)
			inputTypeToAction[actionConfig.InputType] = fullActionName
		end
	end
end

function InputManager.new()
	local self = setmetatable({}, InputManager)

	-- Listen to all input
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:_handleInput(input, Enum.UserInputState.Begin, gameProcessed)
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		self:_handleInput(input, Enum.UserInputState.End, gameProcessed)
	end)

	return self
end

-- Bind an action to a callback
function InputManager:bindAction(actionName: string, callback: (string, Enum.UserInputState, InputObject) -> ())
	if boundActions[actionName] then
		warn(`[InputManager] Action "{actionName}" is already bound. Overwriting.`)
	end

	boundActions[actionName] = {
		callback = callback,
		enabled = true,
	}
end

-- Unbind an action
function InputManager:unbindAction(actionName: string)
	if not boundActions[actionName] then
		warn(`[InputManager] Attempted to unbind action "{actionName}" that doesn't exist.`)
		return
	end

	boundActions[actionName] = nil
end

-- Enable/disable an action without unbinding it
function InputManager:setActionEnabled(actionName: string, enabled: boolean)
	if not boundActions[actionName] then
		warn(`[InputManager] Action "{actionName}" doesn't exist.`)
		return
	end

	boundActions[actionName].enabled = enabled
end

-- Internal: Handle input and route to appropriate callbacks (O(1) lookup)
function InputManager:_handleInput(input: InputObject, state: Enum.UserInputState, gameProcessed: boolean)
	-- Don't process input if player is typing in chat, etc.
	if gameProcessed then
		return
	end

	-- Fast O(1) lookup using pre-built tables
	local fullActionName = keyCodeToAction[input.KeyCode] or inputTypeToAction[input.UserInputType]

	if fullActionName then
		local boundAction = boundActions[fullActionName]
		if boundAction and boundAction.enabled then
			boundAction.callback(fullActionName, state, input)
		end
	end
end

-- Get action config by name
function InputManager:getActionConfig(category: string, actionName: string)
	if not InputConfig[category] then
		warn(`[InputManager] Category "{category}" doesn't exist.`)
		return nil
	end

	return InputConfig[category][actionName]
end

return InputManager
