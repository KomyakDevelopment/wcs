--[[

	@ Name: SmoothShiftLock
	@ Author: x33
	@ Version: 1.3.0

	@ Variables:
	└	.Enabled - ShiftLock's enabled state.

	@ Methods:
	│	:Enable() - Enables the whole module.
	│	:Disable() - Disables the whole module.
	│	:IsEnabled(): boolean - Returns ShiftLock's enabled state.
	│	:ToggleShiftLock(Enable: boolean?) - Toggles the ShiftLock, if Enable parameter is provided then ShiftLock will be toggled to it.
	│	:SetCameraOffsetOverride(offset: Vector3?) - Temporarily overrides the camera offset (pass nil to clear).
	└	:SetCharacterRotationEnabled(enabled: boolean) - Enable/disable character rotation (for wall running, etc.).

--]]

local SmoothShiftLock = {}
SmoothShiftLock.__index = SmoothShiftLock

--// [ Locals: ]

--// Services
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

--// Utilities
local Maid = require(script:WaitForChild("Maid"))
local Spring = require(script:WaitForChild("Spring"))

--// External modules
local ShiftlockDisabler = require(script.Parent.shiftlockDisabler)

--// Instances
local LocalPlayer = Players.LocalPlayer
local PlayerMouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera

--// Configuration
local Config = {
	MOBILE_SUPPORT = false, --// Adds a button to toggle the shift lock for touchscreen devices
	SMOOTH_CHARACTER_ROTATION = false, --// If your character should rotate smoothly or not
	CHARACTER_ROTATION_SPEED = 5, --// How quickly character rotates smoothly
	TRANSITION_SPRING_DAMPER = 0.7, --// Camera transition spring damper, test it out to see what works for you
	CAMERA_TRANSITION_IN_SPEED = 15, --// How quickly locked camera moves to offset position
	CAMERA_TRANSITION_OUT_SPEED = 19, --// How quickly locked camera moves back from offset position
	LOCKED_CAMERA_OFFSET = Vector3.new(1.75, 0.25, 0), --// Locked camera offset
	--// Locked mouse icon
	LOCKED_MOUSE_ICON = "rbxasset://textures/MouseLockedCursor.png",
	--// Shift lock keybinds
	SHIFT_LOCK_KEYBINDS = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
}

--// [ Constructor: ]
function SmoothShiftLock.new()
	local self = setmetatable({}, SmoothShiftLock)

	--// Utilities
	self._runtimeMaid = Maid.new()
	self._shiftlockMaid = Maid.new()
	self._cameraOffsetSpring = Spring.new(Vector3.new(0, 0, 0))
	self._cameraOffsetSpring.Damper = Config.TRANSITION_SPRING_DAMPER

	--// Variables
	self.Enabled = false
	self._overrideOffset = nil :: Vector3?
	self._skipCameraOffset = false -- When true, completely skip camera offset rendering (for wall running)
	self._characterRotationEnabled = true
	self._forcedDisabled = false -- When true, shiftlock is completely disabled and cannot be toggled
	self._enabledBeforeForceDisable = false -- Stores Enabled state before force disable for restoration

	--// Setup
	self:Enable()

	return self
end

--// [ Module Functions: ]
function SmoothShiftLock:Enable()
	self:_refreshCharacterVariables()
	self._runtimeMaid:GiveTask(LocalPlayer.CharacterAdded:Connect(function()
		self:_refreshCharacterVariables()
	end))

	--// Bind Keybinds
	ContextActionService:BindActionAtPriority("ShiftLockSwitchAction", function(Name, State, Input)
		return self:_doShiftLockSwitch(Name, State, Input)
	end, Config.MOBILE_SUPPORT, Enum.ContextActionPriority.Medium.Value, unpack(Config.SHIFT_LOCK_KEYBINDS))

	--// Camera Offset - Run at LAST priority to ensure nothing overrides our offset
	RunService:BindToRenderStep("SmoothShiftLock_CameraOffset", Enum.RenderPriority.Last.Value, function()
		--// Skip completely if wall running is handling camera offset
		if self._skipCameraOffset then
			return
		end

		--// Skip all processing if shiftlock is externally disabled (knockdown, carry, etc.)
		--// UNLESS there's an override offset (wall running needs camera offset even when "disabled")
		if ShiftlockDisabler.isDisabled() and not self._overrideOffset then
			return
		end

		if not self.Head or self.Head.LocalTransparencyModifier > 0.6 then
			return
		end

		local CameraCFrame = Camera.CoordinateFrame
		local Distance = (self.Head.Position - CameraCFrame.p).magnitude

		--// Camera offset
		if Distance > 1 then
			local offset = self._cameraOffsetSpring.Position

			-- Apply offset in world space using camera vectors
			local worldOffset = Camera.CFrame.RightVector * offset.X
				+ Camera.CFrame.UpVector * offset.Y
				+ Camera.CFrame.LookVector * offset.Z

			Camera.CFrame = Camera.CFrame + worldOffset
			-- Don't reset MouseBehavior if character rotation is disabled (wall running handles its own mouse state)
			if self.Enabled and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter and self._characterRotationEnabled then
				self:_updateMouseState()
			end
		end
	end)
	self._runtimeMaid:GiveTask(function()
		RunService:UnbindFromRenderStep("SmoothShiftLock_CameraOffset")
	end)
end

function SmoothShiftLock:Disable()
	self._runtimeMaid:DoCleaning()
	self._shiftlockMaid:DoCleaning()

	--// Unbind Keybinds
	ContextActionService:UnbindAction("ShiftLockSwitchAction")
end

--// [ Internal Functions: ]
function SmoothShiftLock:_refreshCharacterVariables()
	self.Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	self.RootPart = self.Character:WaitForChild("HumanoidRootPart")
	self.Humanoid = self.Character:WaitForChild("Humanoid")
	self.Head = self.Character:WaitForChild("Head")
end

--// Internal function for ContextActionService
function SmoothShiftLock:_doShiftLockSwitch(_, State: Enum.UserInputState)
	--// Block shiftlock toggle if force disabled or externally disabled (knockdown, carry, etc.)
	if self._forcedDisabled or ShiftlockDisabler.isDisabled() then
		return Enum.ContextActionResult.Sink
	end

	if State == Enum.UserInputState.Begin then
		self:ToggleShiftLock()
		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Pass
end

--// Update the mouse behaviour
function SmoothShiftLock:_updateMouseState()
	--// Don't lock mouse if externally disabled (knockdown, carry, etc.)
	if ShiftlockDisabler.isDisabled() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		return
	end
	UserInputService.MouseBehavior = (self.Enabled and Enum.MouseBehavior.LockCenter) or Enum.MouseBehavior.Default
end

--// Update the mouse icon
function SmoothShiftLock:_updateMouseIcon()
	--// Don't show locked cursor if externally disabled (knockdown, carry, etc.)
	if ShiftlockDisabler.isDisabled() then
		PlayerMouse.Icon = ""
		return
	end
	PlayerMouse.Icon = (self.Enabled and Config.LOCKED_MOUSE_ICON :: string) or ""
end

--// Transition the camera to lock offset
function SmoothShiftLock:_transitionLockOffset()
	--// Force camera back to center if externally disabled (knockdown, carry, etc.)
	--// UNLESS there's an override offset (wall running needs camera offset even when "disabled")
	if ShiftlockDisabler.isDisabled() and not self._overrideOffset then
		self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_OUT_SPEED
		self._cameraOffsetSpring.Target = Vector3.new(0, 0, 0)
		return
	end

	-- Apply offset if shiftlock is enabled OR if there's an override (wall running)
	if self.Enabled or self._overrideOffset then
		local targetOffset = self._overrideOffset or Config.LOCKED_CAMERA_OFFSET
		self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_IN_SPEED
		self._cameraOffsetSpring.Target = targetOffset
	else
		self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_OUT_SPEED
		self._cameraOffsetSpring.Target = Vector3.new(0, 0, 0)
	end
end

--// [ External Functions: ]
function SmoothShiftLock:IsEnabled(): boolean
	return self.Enabled
end

--// Temporarily override camera offset
function SmoothShiftLock:SetCameraOffsetOverride(offset: Vector3?)
	if self._overrideOffset == offset then
		return
	end

	self._overrideOffset = offset
	self:_transitionLockOffset()
end

--// Enable/disable character rotation (for wall running, etc.)
function SmoothShiftLock:SetCharacterRotationEnabled(enabled: boolean)
	self._characterRotationEnabled = enabled
end

--// Skip camera offset rendering entirely (for wall running which handles its own camera offset)
function SmoothShiftLock:SetSkipCameraOffset(skip: boolean)
	self._skipCameraOffset = skip
end

--// Force disable shiftlock completely (for knockdown, carry, execution, etc.)
--// This is more aggressive than just checking isDisabled() - it actually toggles shiftlock OFF
--// and prevents any re-enabling until ForceEnable is called
function SmoothShiftLock:ForceDisable()
	if self._forcedDisabled then
		return -- Already force disabled
	end

	print("[SmoothShiftLock] Force disabling shiftlock")

	-- Store current state for restoration
	self._enabledBeforeForceDisable = self.Enabled
	self._forcedDisabled = true

	-- If shiftlock is currently enabled, turn it OFF completely
	-- This cleans up the shiftlock maid, stops character rotation, restores AutoRotate, etc.
	if self.Enabled then
		self:ToggleShiftLock(false)
	end

	-- Force restore all states to ensure nothing is stuck
	if self.Humanoid then
		self.Humanoid.AutoRotate = true
	end

	-- Force mouse to default state
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	PlayerMouse.Icon = ""

	-- Force camera offset to center
	self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_OUT_SPEED
	self._cameraOffsetSpring.Target = Vector3.new(0, 0, 0)
end

--// Re-enable shiftlock after force disable (restores previous state)
function SmoothShiftLock:ForceEnable()
	if not self._forcedDisabled then
		return -- Not force disabled
	end

	print("[SmoothShiftLock] Force enabling shiftlock")

	self._forcedDisabled = false

	-- Restore previous enabled state
	if self._enabledBeforeForceDisable then
		self:ToggleShiftLock(true)
	end

	self._enabledBeforeForceDisable = false
end

--// Check if shiftlock is force disabled
function SmoothShiftLock:IsForcedDisabled(): boolean
	return self._forcedDisabled
end

--// ShiftLock toggle function
function SmoothShiftLock:ToggleShiftLock(Enable: boolean?)
	--// Block enabling if force disabled (but allow disabling)
	if self._forcedDisabled and Enable ~= false then
		print("[SmoothShiftLock] Toggle blocked - force disabled")
		return
	end

	if Enable ~= nil then
		self.Enabled = Enable
	else
		self.Enabled = not self.Enabled
	end

	self:_updateMouseState()
	self:_updateMouseIcon()
	self:_transitionLockOffset()
	if self.Enabled then
		-- Use BindToRenderStep at priority Last-100 so wall running can override at Last+1
		local rotationStepName = "SmoothShiftLock_CharacterRotation"
		RunService:BindToRenderStep(rotationStepName, Enum.RenderPriority.Last.Value - 100, function()
			--// Skip all processing if shiftlock is externally disabled (knockdown, carry, etc.)
			if ShiftlockDisabler.isDisabled() then
				--// Ensure AutoRotate is restored when externally disabled
				if self.Humanoid then
					self.Humanoid.AutoRotate = true
				end
				return
			end

			--// Skip character rotation if disabled (e.g., during wall running)
			--// When disabled, don't touch AutoRotate - let wallRunManager control it
			if not self._characterRotationEnabled then
				return
			end

			--// Skip if there's an override (but restore AutoRotate since we're not in wall run mode)
			if self._overrideOffset then
				if self.Humanoid then
					self.Humanoid.AutoRotate = true
				end
				return
			end

			if self.Humanoid and self.RootPart then
				self.Humanoid.AutoRotate = not self.Enabled
			end

			--// Rotate the character
			if self.Humanoid.Sit then
				return
			end
			if Config.SMOOTH_CHARACTER_ROTATION then
				local _, y, _ = Camera.CFrame:ToOrientation()
				self.RootPart.CFrame = self.RootPart.CFrame:Lerp(
					CFrame.new(self.RootPart.Position) * CFrame.Angles(0, y, 0),
					1/60 * 5 * Config.CHARACTER_ROTATION_SPEED
				)
			else
				local _, y, _ = Camera.CFrame:ToOrientation()
				self.RootPart.CFrame = CFrame.new(self.RootPart.Position) * CFrame.Angles(0, y, 0)
			end
		end)
		self._shiftlockMaid:GiveTask(function()
			RunService:UnbindFromRenderStep(rotationStepName)
		end)
	else
		self.Humanoid.AutoRotate = true
		self._shiftlockMaid:DoCleaning()
	end
end

return SmoothShiftLock.new()
