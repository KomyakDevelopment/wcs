--!strict
-- Carry Manager (Client)
-- Handles carrying knocked players independently of WCS
-- Press V to pick up, V again to drop
-- Also handles being carried (disables controls)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local ShiftlockDisabler = require(script.Parent.shiftlockDisabler)

local CarryManager = {}
CarryManager.__index = CarryManager

-- Configuration
local CARRY_RANGE = 8

-- Animation IDs
local CARRYING_ANIMATION = "rbxassetid://76405414110055"
local CARRIED_ANIMATION = "rbxassetid://132103454609128"

function CarryManager.new()
	local self = setmetatable({}, CarryManager)

	self._player = Players.LocalPlayer
	self._isCarrying = false
	self._isBeingCarried = false
	self._carriedTarget = nil :: Model?
	self._carryingAnimTrack = nil :: AnimationTrack?
	self._carriedAnimTrack = nil :: AnimationTrack?
	self._carryRemote = nil :: RemoteEvent?
	self._carryStateRemote = nil :: RemoteEvent?
	self._connections = {} :: { RBXScriptConnection }

	self:_setup()

	print("[CarryManager] Initialized")
	return self
end

function CarryManager:_setup()
	-- Create or find carry remote
	self._carryRemote = ReplicatedStorage:FindFirstChild("PlayerCarry") :: RemoteEvent?
	if not self._carryRemote then
		task.spawn(function()
			self._carryRemote = ReplicatedStorage:WaitForChild("PlayerCarry", 10) :: RemoteEvent?
			if self._carryRemote then
				self:_setupCarryRemoteHandler()
			end
		end)
	else
		self:_setupCarryRemoteHandler()
	end

	-- Setup carry state remote (for when WE are being carried)
	self._carryStateRemote = ReplicatedStorage:FindFirstChild("CarryState") :: RemoteEvent?
	if not self._carryStateRemote then
		task.spawn(function()
			self._carryStateRemote = ReplicatedStorage:WaitForChild("CarryState", 10) :: RemoteEvent?
			if self._carryStateRemote then
				self:_setupCarryStateHandler()
			end
		end)
	else
		self:_setupCarryStateHandler()
	end
end

function CarryManager:_setupCarryRemoteHandler()
	if not self._carryRemote then return end

	-- Listen for carry events from server (for animations)
	table.insert(self._connections, self._carryRemote.OnClientEvent:Connect(function(carrier: Model, target: Model, isPickingUp: boolean)
		self:_handleRemoteCarry(carrier, target, isPickingUp)
	end))
end

function CarryManager:_setupCarryStateHandler()
	if not self._carryStateRemote then return end

	-- Listen for when WE are being picked up or dropped
	table.insert(self._connections, self._carryStateRemote.OnClientEvent:Connect(function(isBeingCarried: boolean, _carrier: Model?)
		if isBeingCarried then
			self:_onBeingCarried()
		else
			self:_onBeingDropped()
		end
	end))
end

-- Called when this player is being picked up by someone
function CarryManager:_onBeingCarried()
	print("[CarryManager] I am being carried - disabling controls")
	self._isBeingCarried = true

	-- Disable shiftlock using the centralized utility
	ShiftlockDisabler.disable("carry")

	-- Disable reset button
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)

	print("[CarryManager] Shiftlock and controls fully disabled")
end

-- Called when this player is being dropped
function CarryManager:_onBeingDropped()
	print("[CarryManager] I have been dropped - re-enabling controls")
	self._isBeingCarried = false

	-- Re-enable shiftlock using the centralized utility
	ShiftlockDisabler.enable("carry")

	-- Re-enable reset button
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", true)
	end)

	print("[CarryManager] Controls fully restored")
end

function CarryManager:_handleRemoteCarry(carrier: Model, target: Model, isPickingUp: boolean)
	local myCharacter = self._player.Character

	-- Handle animations for carrier (if it's us)
	if carrier == myCharacter then
		if isPickingUp then
			self._isCarrying = true
			self._carriedTarget = target
			self:_playCarryingAnimation(carrier)
			self:_playCarriedAnimation(target)
		else
			self._isCarrying = false
			self._carriedTarget = nil
			self:_stopCarryAnimations()
		end
		return
	end

	-- Handle animations for remote players
	if isPickingUp then
		self:_playRemoteCarryAnimations(carrier, target)
	else
		self:_stopRemoteCarryAnimations(carrier, target)
	end
end

function CarryManager:_playCarryingAnimation(carrier: Model)
	local humanoid = carrier:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local carryAnim = Instance.new("Animation")
			carryAnim.AnimationId = CARRYING_ANIMATION
			self._carryingAnimTrack = animator:LoadAnimation(carryAnim)
			self._carryingAnimTrack.Priority = Enum.AnimationPriority.Action4
			self._carryingAnimTrack.Looped = true
			self._carryingAnimTrack:Play(0.2)
			print("[CarryManager] Playing carrying animation")
		end
	end
end

function CarryManager:_playCarriedAnimation(target: Model)
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?
	if targetHumanoid then
		local targetAnimator = targetHumanoid:FindFirstChildOfClass("Animator")
		if targetAnimator then
			local carriedAnim = Instance.new("Animation")
			carriedAnim.AnimationId = CARRIED_ANIMATION
			self._carriedAnimTrack = targetAnimator:LoadAnimation(carriedAnim)
			self._carriedAnimTrack.Priority = Enum.AnimationPriority.Action4
			self._carriedAnimTrack.Looped = true
			self._carriedAnimTrack:Play(0.2)
			print("[CarryManager] Playing carried animation on target")
		end
	end
end

function CarryManager:_stopCarryAnimations()
	if self._carryingAnimTrack and self._carryingAnimTrack.IsPlaying then
		self._carryingAnimTrack:Stop(0.2)
	end
	self._carryingAnimTrack = nil

	if self._carriedAnimTrack and self._carriedAnimTrack.IsPlaying then
		self._carriedAnimTrack:Stop(0.2)
	end
	self._carriedAnimTrack = nil
end

function CarryManager:_playRemoteCarryAnimations(carrier: Model, target: Model)
	-- Play carrying animation on carrier
	local carrierHumanoid = carrier:FindFirstChild("Humanoid") :: Humanoid?
	if carrierHumanoid then
		local animator = carrierHumanoid:FindFirstChildOfClass("Animator")
		if animator then
			local carryAnim = Instance.new("Animation")
			carryAnim.AnimationId = CARRYING_ANIMATION
			local track = animator:LoadAnimation(carryAnim)
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = true
			track:Play(0.2)
		end
	end

	-- Play carried animation on target
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?
	if targetHumanoid then
		local animator = targetHumanoid:FindFirstChildOfClass("Animator")
		if animator then
			local carriedAnim = Instance.new("Animation")
			carriedAnim.AnimationId = CARRIED_ANIMATION
			local track = animator:LoadAnimation(carriedAnim)
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = true
			track:Play(0.2)
		end
	end
end

function CarryManager:_stopRemoteCarryAnimations(carrier: Model, target: Model)
	local function stopCarryAnimations(character: Model)
		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in animator:GetPlayingAnimationTracks() do
					if track.Priority == Enum.AnimationPriority.Action4 then
						track:Stop(0.2)
					end
				end
			end
		end
	end

	stopCarryAnimations(carrier)
	stopCarryAnimations(target)
end

-- Find nearest knocked player
function CarryManager:_findNearestKnockedTarget(): Model?
	local character = self._player.Character
	if not character then return nil end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return nil end

	local myPosition = rootPart.Position
	local nearestTarget: Model? = nil
	local nearestDistance = CARRY_RANGE + 1

	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid") :: Humanoid?
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart") :: BasePart?

			if targetHumanoid and targetRootPart then
				local isKnocked = targetHumanoid.PlatformStand
				local isMarked = potentialTarget:GetAttribute("MarkedForExecution") == true
				local isCarried = potentialTarget:GetAttribute("BeingCarried") == true

				if isKnocked and not isMarked and not isCarried then
					local distance = (targetRootPart.Position - myPosition).Magnitude
					if distance <= CARRY_RANGE and distance < nearestDistance then
						nearestTarget = potentialTarget
						nearestDistance = distance
					end
				end
			end
		end
	end

	return nearestTarget
end

-- Main action - pick up or drop
function CarryManager:performCarry()
	-- Can't carry if we're being carried
	if self._isBeingCarried then
		print("[CarryManager] Cannot carry while being carried")
		return
	end

	if self._isCarrying then
		self:_dropTarget()
	else
		self:_pickUpTarget()
	end
end

function CarryManager:_pickUpTarget()
	local target = self:_findNearestKnockedTarget()
	if not target then
		print("[CarryManager] No target to pick up")
		return
	end

	-- Request server to handle the pickup
	-- Animations will be played when we receive the broadcast back
	if self._carryRemote then
		self._carryRemote:FireServer(target, true)
	end

	print(`[CarryManager] Requesting to pick up {target.Name}`)
end

function CarryManager:_dropTarget()
	if not self._isCarrying then return end

	-- Request server to drop
	if self._carryRemote and self._carriedTarget then
		self._carryRemote:FireServer(self._carriedTarget, false)
	end

	print(`[CarryManager] Requesting to drop {if self._carriedTarget then self._carriedTarget.Name else "target"}`)
end

function CarryManager:isCarrying(): boolean
	return self._isCarrying
end

function CarryManager:isBeingCarried(): boolean
	return self._isBeingCarried
end

function CarryManager:destroy()
	if self._isCarrying then
		self:_dropTarget()
	end

	if self._isBeingCarried then
		self:_onBeingDropped()
	end

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return CarryManager
