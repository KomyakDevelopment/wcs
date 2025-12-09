--!strict
-- R15 Ragdoll Client
-- Handles client-side ragdoll state changes and camera
-- Also fully disables shiftlock during ragdoll to prevent character rotation issues

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer

local shiftlockBlocker: RBXScriptConnection? = nil
local currentTriggerConnection: RBXScriptConnection? = nil
local originalRotationType: Enum.RotationType? = nil

local function onRagdollChanged(character: Model, isRagdolled: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera

	if isRagdolled then
		print("[RagdollClient] Ragdoll enabled - disabling shiftlock fully")

		-- Set humanoid state
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end

		-- Apply knockdown impulse
		if rootPart then
			rootPart:ApplyAngularImpulse(Vector3.new(
				(math.random() - 0.5) * 100,
				0,
				(math.random() - 0.5) * 100
			))
		end

		-- Switch camera to head
		if camera and head then
			camera.CameraSubject = head
		end

		-- Store and disable shiftlock via UserGameSettings
		pcall(function()
			local UserGameSettings = UserSettings():GetService("UserGameSettings")
			originalRotationType = UserGameSettings.RotationType
			-- MovementRelative = no shiftlock (character faces movement direction)
			-- CameraRelative = shiftlock ON (character faces camera)
			UserGameSettings.RotationType = Enum.RotationType.MovementRelative
		end)

		-- Force mouse behavior to default (unlocked)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default

		-- Block shift key from re-enabling shiftlock
		ContextActionService:BindAction("BlockShiftLockRagdoll", function()
			return Enum.ContextActionResult.Sink -- Consume the input, do nothing
		end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)

		-- Continuously enforce mouse behavior in case something tries to re-enable it
		if shiftlockBlocker then
			shiftlockBlocker:Disconnect()
		end
		shiftlockBlocker = RunService.RenderStepped:Connect(function()
			if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end)
	else
		print("[RagdollClient] Ragdoll disabled - restoring shiftlock")

		-- Restore humanoid state
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end

		-- Restore camera
		if camera and humanoid then
			camera.CameraSubject = humanoid
		end

		-- Stop enforcing mouse behavior
		if shiftlockBlocker then
			shiftlockBlocker:Disconnect()
			shiftlockBlocker = nil
		end

		-- Unbind the shift key block
		ContextActionService:UnbindAction("BlockShiftLockRagdoll")

		-- Restore original rotation type (shiftlock setting)
		pcall(function()
			local UserGameSettings = UserSettings():GetService("UserGameSettings")
			if originalRotationType then
				UserGameSettings.RotationType = originalRotationType
				originalRotationType = nil
			end
		end)
	end
end

local function setupCharacter(character: Model)
	-- Disconnect previous connection
	if currentTriggerConnection then
		currentTriggerConnection:Disconnect()
		currentTriggerConnection = nil
	end

	-- Wait for trigger
	local trigger = character:WaitForChild("RagdollTrigger", 10)
	if not trigger or not trigger:IsA("BoolValue") then
		warn("[RagdollClient] RagdollTrigger not found")
		return
	end

	-- Check current state
	if trigger.Value then
		onRagdollChanged(character, true)
	end

	-- Listen for changes
	currentTriggerConnection = trigger.Changed:Connect(function(isRagdolled)
		onRagdollChanged(character, isRagdolled)
	end)

	print("[RagdollClient] Setup complete for character")
end

-- Handle current character
if player.Character then
	task.spawn(function()
		setupCharacter(player.Character)
	end)
end

-- Handle future characters
player.CharacterAdded:Connect(function(character)
	-- Clean up shiftlock blocker on respawn
	if shiftlockBlocker then
		shiftlockBlocker:Disconnect()
		shiftlockBlocker = nil
	end

	-- Unbind shift key block if still bound
	pcall(function()
		ContextActionService:UnbindAction("BlockShiftLockRagdoll")
	end)

	-- Restore original rotation type if it was changed
	pcall(function()
		local UserGameSettings = UserSettings():GetService("UserGameSettings")
		if originalRotationType then
			UserGameSettings.RotationType = originalRotationType
			originalRotationType = nil
		end
	end)

	task.wait(0.2) -- Wait for server setup
	setupCharacter(character)
end)

print("[RagdollClient] Initialized")
