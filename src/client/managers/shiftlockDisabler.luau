--!strict
-- ShiftLock Disabler Utility
-- Provides robust shiftlock disabling that works at multiple levels
-- Used by ragdollClient, carryManager, executionEffectsManager, etc.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer

local ShiftlockDisabler = {}

-- State tracking
local isDisabled = false
local originalRotationType: Enum.RotationType? = nil
local renderSteppedConnection: RBXScriptConnection? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local activeDisablers: { [string]: boolean } = {} -- Track which systems have requested disable

-- Force disable shiftlock (called every frame to enforce)
local function forceDisable()
	-- 1. Force UserGameSettings RotationType
	pcall(function()
		local UserGameSettings = UserSettings():GetService("UserGameSettings")
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
	end)

	-- 2. Force MouseBehavior to Default (only if it's LockCenter)
	pcall(function()
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	-- NOTE: CameraOffset is NOT reset every frame - that interferes with camera movement
	-- It's only set once when disable() is called
end

-- Disable shiftlock (call from any system that needs it disabled)
-- source: A unique identifier for the calling system (e.g., "ragdoll", "carry", "death")
function ShiftlockDisabler.disable(source: string)
	activeDisablers[source] = true

	-- If already disabled by another system, just add to the list
	if isDisabled then
		print(`[ShiftlockDisabler] Already disabled, adding source: {source}`)
		return
	end

	isDisabled = true
	print(`[ShiftlockDisabler] Disabling shiftlock (source: {source})`)

	-- Store original rotation type
	pcall(function()
		local UserGameSettings = UserSettings():GetService("UserGameSettings")
		originalRotationType = UserGameSettings.RotationType
	end)

	-- Initial force disable
	forceDisable()

	-- Block shift key from toggling shiftlock
	ContextActionService:BindAction("ShiftlockDisabler_BlockShift", function()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)

	-- Continuously enforce on RenderStepped (runs before frame renders)
	if renderSteppedConnection then
		renderSteppedConnection:Disconnect()
	end
	renderSteppedConnection = RunService.RenderStepped:Connect(forceDisable)

	-- Also enforce on Heartbeat (runs after physics, catches more edge cases)
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
	end
	heartbeatConnection = RunService.Heartbeat:Connect(forceDisable)

	print("[ShiftlockDisabler] Shiftlock fully disabled with dual-loop enforcement")
end

-- Enable shiftlock (call when the system no longer needs it disabled)
-- source: The same identifier used when disabling
function ShiftlockDisabler.enable(source: string)
	activeDisablers[source] = nil

	-- Check if any other system still needs shiftlock disabled
	local stillDisabled = false
	for _, _ in pairs(activeDisablers) do
		stillDisabled = true
		break
	end

	if stillDisabled then
		print(`[ShiftlockDisabler] Source {source} released, but other systems still need it disabled`)
		return
	end

	if not isDisabled then
		print(`[ShiftlockDisabler] Already enabled (source: {source})`)
		return
	end

	isDisabled = false
	print(`[ShiftlockDisabler] Enabling shiftlock (source: {source})`)

	-- Stop enforcement loops
	if renderSteppedConnection then
		renderSteppedConnection:Disconnect()
		renderSteppedConnection = nil
	end

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	-- Unbind shift key block
	pcall(function()
		ContextActionService:UnbindAction("ShiftlockDisabler_BlockShift")
	end)

	-- Restore original rotation type
	pcall(function()
		local UserGameSettings = UserSettings():GetService("UserGameSettings")
		if originalRotationType then
			UserGameSettings.RotationType = originalRotationType
			originalRotationType = nil
		end
	end)

	print("[ShiftlockDisabler] Shiftlock restored")
end

-- Force cleanup all state (use on respawn/character change)
function ShiftlockDisabler.forceCleanup()
	print("[ShiftlockDisabler] Force cleanup")

	isDisabled = false
	activeDisablers = {}

	if renderSteppedConnection then
		renderSteppedConnection:Disconnect()
		renderSteppedConnection = nil
	end

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	pcall(function()
		ContextActionService:UnbindAction("ShiftlockDisabler_BlockShift")
	end)

	-- Restore rotation type if we have it stored
	pcall(function()
		local UserGameSettings = UserSettings():GetService("UserGameSettings")
		if originalRotationType then
			UserGameSettings.RotationType = originalRotationType
			originalRotationType = nil
		end
	end)
end

-- Check if shiftlock is currently disabled
function ShiftlockDisabler.isDisabled(): boolean
	return isDisabled
end

-- Clean up on character respawn
player.CharacterAdded:Connect(function()
	ShiftlockDisabler.forceCleanup()
end)

return ShiftlockDisabler
