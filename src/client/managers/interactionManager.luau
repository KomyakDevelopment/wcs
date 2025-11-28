--!strict
-- Interaction Manager (Client)
-- Detects nearby knocked players and shows interaction UI
-- Handles Carry (V) and Grip (B) interactions

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local WCS = require(ReplicatedStorage.Packages.wcs)
local Grip = require(ReplicatedStorage.Shared.skills.grip)

local InteractionManager = {}
InteractionManager.__index = InteractionManager

-- Configuration
local INTERACTION_RANGE = 8 -- Distance to detect knocked players
local UI_UPDATE_INTERVAL = 0.1 -- How often to check for nearby targets (seconds)
local UI_TWEEN_DURATION = 0.25 -- Duration of slide/fade animation

function InteractionManager.new()
	local self = setmetatable({}, InteractionManager)

	self._player = Players.LocalPlayer
	self._connections = {} :: { RBXScriptConnection }
	self._nearbyKnockedPlayer = nil :: Model?
	self._lastUIUpdate = 0
	self._interactUI = nil :: TextLabel?
	self._originalText = ""
	self._originalPosition = nil :: UDim2?
	self._currentTween = nil :: Tween?
	self._isUIVisible = false

	self:_setup()

	print("[InteractionManager] Initialized")
	return self
end

function InteractionManager:_setup()
	-- Find the UI element
	self:_findInteractUI()

	-- Start checking for nearby knocked players
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function()
			self:_update()
		end)
	)
end

-- Find the interaction UI element
function InteractionManager:_findInteractUI()
	local playerGui = self._player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("[InteractionManager] PlayerGui not found")
		return
	end

	-- Navigate to StarterGui.Main.Interact.UI.TextTemp
	local mainGui = playerGui:WaitForChild("Main", 5)
	if not mainGui then
		-- UI doesn't exist yet, will retry on next update
		return
	end

	local interact = mainGui:FindFirstChild("Interact")
	if not interact then
		return
	end

	local ui = interact:FindFirstChild("UI")
	if not ui then
		return
	end

	local textTemp = ui:FindFirstChild("TextTemp") :: TextLabel?
	if textTemp and textTemp:IsA("TextLabel") then
		self._interactUI = textTemp
		self._originalText = textTemp.Text
		self._originalPosition = textTemp.Position
		-- Start hidden
		textTemp.Visible = false
		textTemp.TextTransparency = 1
		print("[InteractionManager] Found interaction UI")
	end
end

-- Update loop - check for nearby knocked players
function InteractionManager:_update()
	local now = tick()
	if now - self._lastUIUpdate < UI_UPDATE_INTERVAL then
		return
	end
	self._lastUIUpdate = now

	-- Retry finding UI if not found
	if not self._interactUI then
		self:_findInteractUI()
		if not self._interactUI then
			return
		end
	end

	-- Find nearest knocked player
	local knockedPlayer = self:_findNearestKnockedPlayer()

	if knockedPlayer then
		-- Show interaction options
		if self._nearbyKnockedPlayer ~= knockedPlayer then
			self._nearbyKnockedPlayer = knockedPlayer
			self:_showInteractionUI(knockedPlayer)
		end
	else
		-- Hide interaction options
		if self._nearbyKnockedPlayer then
			self._nearbyKnockedPlayer = nil
			self:_hideInteractionUI()
		end
	end
end

-- Find the nearest knocked player within range
function InteractionManager:_findNearestKnockedPlayer(): Model?
	local character = self._player.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return nil
	end

	local myPosition = rootPart.Position
	local nearestTarget: Model? = nil
	local nearestDistance = INTERACTION_RANGE + 1

	-- Check all characters in workspace
	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid") :: Humanoid?
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart") :: BasePart?

			if targetHumanoid and targetRootPart then
				-- Check if target is knocked down (PlatformStand = true means ragdolled)
				-- Also check they're not already marked for execution
				local isMarkedForExecution = potentialTarget:GetAttribute("MarkedForExecution") == true
				if targetHumanoid.PlatformStand and targetHumanoid.Health > 0 and not isMarkedForExecution then
					local distance = (targetRootPart.Position - myPosition).Magnitude
					if distance <= INTERACTION_RANGE and distance < nearestDistance then
						nearestTarget = potentialTarget
						nearestDistance = distance
					end
				end
			end
		end
	end

	return nearestTarget
end

-- Show the interaction UI with Carry/Grip options
function InteractionManager:_showInteractionUI(_targetCharacter: Model)
	if not self._interactUI or not self._originalPosition then
		return
	end

	-- Already visible, no need to animate again
	if self._isUIVisible then
		return
	end
	self._isUIVisible = true

	-- Cancel any ongoing tween
	if self._currentTween then
		self._currentTween:Cancel()
		self._currentTween = nil
	end

	-- Update UI text (no player name)
	self._interactUI.Text = `"V" - Carry / "B" - Grip`

	-- Start position: slightly below original, fully transparent
	local startOffset = UDim2.fromOffset(0, 20) -- 20 pixels below
	self._interactUI.Position = self._originalPosition + startOffset
	self._interactUI.TextTransparency = 1
	self._interactUI.Visible = true

	-- Tween to original position with fade in
	local tweenInfo = TweenInfo.new(UI_TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	self._currentTween = TweenService:Create(self._interactUI, tweenInfo, {
		Position = self._originalPosition,
		TextTransparency = 0
	})
	self._currentTween:Play()

	print("[InteractionManager] Showing interaction UI")
end

-- Hide the interaction UI
function InteractionManager:_hideInteractionUI()
	if not self._interactUI or not self._originalPosition then
		return
	end

	-- Already hidden, no need to animate again
	if not self._isUIVisible then
		return
	end
	self._isUIVisible = false

	-- Cancel any ongoing tween
	if self._currentTween then
		self._currentTween:Cancel()
		self._currentTween = nil
	end

	-- Tween down and fade out
	local endOffset = UDim2.fromOffset(0, 20) -- 20 pixels below
	local tweenInfo = TweenInfo.new(UI_TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	self._currentTween = TweenService:Create(self._interactUI, tweenInfo, {
		Position = self._originalPosition + endOffset,
		TextTransparency = 1
	})
	self._currentTween:Play()

	-- Hide after tween completes
	self._currentTween.Completed:Once(function()
		if not self._isUIVisible then
			self._interactUI.Visible = false
		end
	end)

	print("[InteractionManager] Hiding interaction UI")
end

-- Check if there's a valid grip target nearby
function InteractionManager:hasGripTarget(): boolean
	return self._nearbyKnockedPlayer ~= nil
end

-- Get the current grip target
function InteractionManager:getGripTarget(): Model?
	return self._nearbyKnockedPlayer
end

-- Perform grip action (called when B is pressed)
function InteractionManager:performGrip()
	if not self._nearbyKnockedPlayer then
		print("[InteractionManager] No grip target nearby")
		return
	end

	-- Get WCS character and grip skill
	local character = self._player.Character
	if not character then
		return
	end

	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if not wcsCharacter then
		return
	end

	-- Get grip skill
	local gripSkill = wcsCharacter:GetSkillFromConstructor(Grip)
	if not gripSkill then
		print("[InteractionManager] Grip skill not found on character")
		return
	end

	-- Check if skill is on cooldown
	local state = gripSkill:GetState()
	if state.Debounce then
		print("[InteractionManager] Grip skill on cooldown")
		return
	end

	-- Start the grip skill
	gripSkill:Start()
	print(`[InteractionManager] Started grip on {self._nearbyKnockedPlayer.Name}`)
end

-- Perform carry action (called when V is pressed) - placeholder for future implementation
function InteractionManager:performCarry()
	if not self._nearbyKnockedPlayer then
		print("[InteractionManager] No carry target nearby")
		return
	end

	print(`[InteractionManager] Carry not implemented yet - target: {self._nearbyKnockedPlayer.Name}`)
	-- TODO: Implement carry functionality
end

function InteractionManager:destroy()
	-- Cancel any ongoing tween
	if self._currentTween then
		self._currentTween:Cancel()
		self._currentTween = nil
	end

	-- Hide UI immediately
	if self._interactUI then
		self._interactUI.Visible = false
		self._interactUI.TextTransparency = 1
	end

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return InteractionManager
