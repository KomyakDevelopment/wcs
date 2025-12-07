--!strict
-- Carry Manager (Server)
-- Handles server-side carry mechanics using position updates (NOT welds)
-- Welds cause physics issues - position updates are more reliable

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarryManager = {}
CarryManager.__index = CarryManager

-- Configuration
local CARRY_RANGE = 10 -- Slightly larger than client for lag tolerance
local CARRY_SPEED_MULTIPLIER = 0.7
local COMBAT_TAG_REFRESH_INTERVAL = 5 -- Refresh combat tag every 5 seconds during carry

-- Carry offset (relative to carrier's HumanoidRootPart)
local CARRY_OFFSET = CFrame.new(0, 0.5, 1.2) * CFrame.Angles(math.rad(-15), math.rad(180), 0)

function CarryManager.new()
	local self = setmetatable({}, CarryManager)

	self._carryRemote = nil :: RemoteEvent?
	self._carryStateRemote = nil :: RemoteEvent? -- For notifying carried player's client
	self._carriedPlayers = {} :: { [Model]: Model } -- target -> carrier
	self._originalWalkSpeeds = {} :: { [Player]: number }
	self._originalCollisionGroups = {} :: { [Model]: { [BasePart]: string } }
	self._connections = {} :: { RBXScriptConnection }
	self._heartbeatConnection = nil :: RBXScriptConnection?
	self._combatTagTimers = {} :: { [Model]: number } -- target -> last tag time

	self:_setup()

	print("[CarryManager Server] Initialized (Position-based)")
	return self
end

function CarryManager:_setup()
	-- Create carry remote
	self._carryRemote = ReplicatedStorage:FindFirstChild("PlayerCarry") :: RemoteEvent?
	if not self._carryRemote then
		self._carryRemote = Instance.new("RemoteEvent")
		self._carryRemote.Name = "PlayerCarry"
		self._carryRemote.Parent = ReplicatedStorage
	end

	-- Create carry state remote (to notify carried player's client)
	self._carryStateRemote = ReplicatedStorage:FindFirstChild("CarryState") :: RemoteEvent?
	if not self._carryStateRemote then
		self._carryStateRemote = Instance.new("RemoteEvent")
		self._carryStateRemote.Name = "CarryState"
		self._carryStateRemote.Parent = ReplicatedStorage
	end

	-- Handle carry requests from clients
	self._carryRemote.OnServerEvent:Connect(function(player: Player, target: Model, isPickingUp: boolean)
		if isPickingUp then
			self:_handlePickUp(player, target)
		else
			self:_handleDrop(player, target)
		end
	end)

	-- Clean up when players leave
	table.insert(self._connections, Players.PlayerRemoving:Connect(function(player)
		self:_handlePlayerLeave(player)
	end))

	-- Start heartbeat for position updates
	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_updateCarriedPositions()
	end)
end

-- Update all carried players' positions every frame
function CarryManager:_updateCarriedPositions()
	local now = tick()

	for target, carrier in pairs(self._carriedPlayers) do
		local carrierRoot = carrier:FindFirstChild("HumanoidRootPart") :: BasePart?
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?

		if carrierRoot and targetRoot and target.Parent and carrier.Parent then
			-- Position target relative to carrier
			targetRoot.CFrame = carrierRoot.CFrame * CARRY_OFFSET

			-- Clear velocities to prevent physics interference
			targetRoot.AssemblyLinearVelocity = Vector3.zero
			targetRoot.AssemblyAngularVelocity = Vector3.zero

			-- Refresh combat tag periodically
			local lastTagTime = self._combatTagTimers[target] or 0
			if now - lastTagTime >= COMBAT_TAG_REFRESH_INTERVAL then
				self._combatTagTimers[target] = now
				self:_refreshCombatTags(carrier, target)
			end
		else
			-- Carrier or target no longer valid, clean up
			self:_forceDropTarget(target)
		end
	end
end

-- Refresh combat tags for both carrier and target
function CarryManager:_refreshCombatTags(carrier: Model, target: Model)
	if not _G.CombatTagManager then return end

	local carrierPlayer = Players:GetPlayerFromCharacter(carrier)
	local targetPlayer = Players:GetPlayerFromCharacter(target)

	if carrierPlayer then
		_G.CombatTagManager:tagPlayer(carrierPlayer, nil)
	end
	if targetPlayer then
		_G.CombatTagManager:tagPlayer(targetPlayer, carrierPlayer)
	end
end

function CarryManager:_handlePickUp(player: Player, target: Model)
	local character = player.Character
	if not character then return end

	local carrierRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carrierHumanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?

	if not carrierRoot or not targetRoot or not carrierHumanoid or not targetHumanoid then
		warn("[CarryManager Server] Missing required parts for carry")
		return
	end

	-- Validate range
	local distance = (carrierRoot.Position - targetRoot.Position).Magnitude
	if distance > CARRY_RANGE then
		warn(`[CarryManager Server] Target too far: {distance}`)
		return
	end

	-- Validate target is knocked down
	if not targetHumanoid.PlatformStand then
		warn("[CarryManager Server] Target is not knocked down")
		return
	end

	-- Check if target is already being carried
	if self._carriedPlayers[target] then
		warn("[CarryManager Server] Target is already being carried")
		return
	end

	-- Check if target is marked for execution
	if target:GetAttribute("MarkedForExecution") then
		warn("[CarryManager Server] Target is marked for execution")
		return
	end

	-- Check if carrier is already carrying someone
	for existingTarget, existingCarrier in pairs(self._carriedPlayers) do
		if existingCarrier == character then
			warn("[CarryManager Server] Carrier is already carrying someone")
			return
		end
	end

	-- Store original walk speed
	self._originalWalkSpeeds[player] = carrierHumanoid.WalkSpeed

	-- Slow down carrier
	carrierHumanoid.WalkSpeed = self._originalWalkSpeeds[player] * CARRY_SPEED_MULTIPLIER

	-- Mark target as being carried
	target:SetAttribute("BeingCarried", true)
	target:SetAttribute("CarriedBy", character.Name)

	-- Clear all velocities on target
	for _, part in target:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- Disable ragdoll on target
	local ragdollTrigger = target:FindFirstChild("RagdollTrigger") :: BoolValue?
	if ragdollTrigger then
		ragdollTrigger.Value = false
	end

	-- Fully immobilize target
	targetHumanoid.PlatformStand = true
	targetHumanoid.WalkSpeed = 0
	targetHumanoid.JumpPower = 0
	targetHumanoid.JumpHeight = 0
	targetHumanoid.AutoRotate = false

	-- Set network ownership of target to server for reliable positioning
	for _, part in target:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetNetworkOwner(nil) -- Server owns it
		end
	end

	-- Position target initially
	targetRoot.CFrame = carrierRoot.CFrame * CARRY_OFFSET

	-- Set collision groups to prevent collision between carrier and target
	self._originalCollisionGroups[target] = {}
	for _, part in target:GetDescendants() do
		if part:IsA("BasePart") then
			self._originalCollisionGroups[target][part] = part.CollisionGroup
			part.CollisionGroup = "Players"
		end
	end

	-- Pause knockdown timer via DeathManager
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if targetPlayer and _G.DeathManager then
		_G.DeathManager:pauseKnockdown(targetPlayer)
	end

	-- Apply initial combat tag
	self._combatTagTimers[target] = tick()
	self:_refreshCombatTags(character, target)

	-- Store reference
	self._carriedPlayers[target] = character

	-- Notify carried player's client to disable controls
	if targetPlayer and self._carryStateRemote then
		self._carryStateRemote:FireClient(targetPlayer, true, character)
	end

	-- Broadcast to all clients for animations
	self._carryRemote:FireAllClients(character, target, true)

	print(`[CarryManager Server] {player.Name} picked up {target.Name}`)
end

function CarryManager:_handleDrop(player: Player, target: Model)
	local character = player.Character
	if not character then return end

	-- Verify this player is carrying the target
	if self._carriedPlayers[target] ~= character then
		warn("[CarryManager Server] Player is not carrying this target")
		return
	end

	self:_dropTarget(target, character)
end

-- Internal drop function (can be called from multiple places)
function CarryManager:_dropTarget(target: Model, carrier: Model)
	local carrierRoot = carrier:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?

	local carrierPlayer = Players:GetPlayerFromCharacter(carrier)
	local targetPlayer = Players:GetPlayerFromCharacter(target)

	-- Restore carrier walk speed
	if carrierPlayer then
		local carrierHumanoid = carrier:FindFirstChild("Humanoid") :: Humanoid?
		if carrierHumanoid and self._originalWalkSpeeds[carrierPlayer] then
			carrierHumanoid.WalkSpeed = self._originalWalkSpeeds[carrierPlayer]
		end
		self._originalWalkSpeeds[carrierPlayer] = nil
	end

	-- Clear carried attributes
	target:SetAttribute("BeingCarried", nil)
	target:SetAttribute("CarriedBy", nil)

	-- Position target in front of carrier
	if carrierRoot and targetRoot then
		local dropPosition = carrierRoot.Position + carrierRoot.CFrame.LookVector * 3
		targetRoot.CFrame = CFrame.new(dropPosition) * CFrame.Angles(0, 0, math.rad(90))
	end

	-- Clear velocities
	if targetRoot then
		targetRoot.AssemblyLinearVelocity = Vector3.zero
		targetRoot.AssemblyAngularVelocity = Vector3.zero
	end

	-- Return network ownership to target player
	if targetPlayer then
		for _, part in target:GetDescendants() do
			if part:IsA("BasePart") then
				pcall(function()
					part:SetNetworkOwner(targetPlayer)
				end)
			end
		end
	end

	-- Restore AutoRotate
	if targetHumanoid then
		targetHumanoid.AutoRotate = true
	end

	-- Re-enable ragdoll on target
	local ragdollTrigger = target:FindFirstChild("RagdollTrigger") :: BoolValue?
	if ragdollTrigger then
		ragdollTrigger.Value = true
	end

	-- Restore collision groups
	if self._originalCollisionGroups[target] then
		for part, group in pairs(self._originalCollisionGroups[target]) do
			if part and part.Parent then
				part.CollisionGroup = group
			end
		end
		self._originalCollisionGroups[target] = nil
	end

	-- Resume knockdown timer via DeathManager
	if targetPlayer and _G.DeathManager then
		_G.DeathManager:resumeKnockdown(targetPlayer)
	end

	-- Clear combat tag timer
	self._combatTagTimers[target] = nil

	-- Clear reference
	self._carriedPlayers[target] = nil

	-- Notify carried player's client to re-enable controls
	if targetPlayer and self._carryStateRemote then
		self._carryStateRemote:FireClient(targetPlayer, false, nil)
	end

	-- Broadcast to all clients
	self._carryRemote:FireAllClients(carrier, target, false)

	print(`[CarryManager Server] Dropped {target.Name}`)
end

-- Force drop a target (used when carrier/target becomes invalid)
function CarryManager:_forceDropTarget(target: Model)
	local carrier = self._carriedPlayers[target]
	if not carrier then return end

	local targetPlayer = Players:GetPlayerFromCharacter(target)

	-- Clear attributes
	target:SetAttribute("BeingCarried", nil)
	target:SetAttribute("CarriedBy", nil)

	-- Restore collision groups
	if self._originalCollisionGroups[target] then
		for part, group in pairs(self._originalCollisionGroups[target]) do
			if part and part.Parent then
				part.CollisionGroup = group
			end
		end
		self._originalCollisionGroups[target] = nil
	end

	-- Re-enable ragdoll
	local ragdollTrigger = target:FindFirstChild("RagdollTrigger") :: BoolValue?
	if ragdollTrigger then
		ragdollTrigger.Value = true
	end

	-- Resume knockdown timer
	if targetPlayer and _G.DeathManager then
		_G.DeathManager:resumeKnockdown(targetPlayer)
	end

	-- Notify carried player's client
	if targetPlayer and self._carryStateRemote then
		self._carryStateRemote:FireClient(targetPlayer, false, nil)
	end

	-- Clear references
	self._combatTagTimers[target] = nil
	self._carriedPlayers[target] = nil

	print(`[CarryManager Server] Force dropped {target.Name}`)
end

function CarryManager:_handlePlayerLeave(player: Player)
	local character = player.Character
	if not character then return end

	-- Drop any target this player was carrying
	for target, carrier in pairs(self._carriedPlayers) do
		if carrier == character then
			self:_forceDropTarget(target)
		end
	end

	-- If this player was being carried, clean up
	if character:GetAttribute("BeingCarried") then
		for target, carrier in pairs(self._carriedPlayers) do
			if target == character then
				local carrierPlayer = Players:GetPlayerFromCharacter(carrier)
				if carrierPlayer then
					local carrierHumanoid = carrier:FindFirstChild("Humanoid") :: Humanoid?
					if carrierHumanoid and self._originalWalkSpeeds[carrierPlayer] then
						carrierHumanoid.WalkSpeed = self._originalWalkSpeeds[carrierPlayer]
					end
					self._originalWalkSpeeds[carrierPlayer] = nil
				end
				self._carriedPlayers[target] = nil
				self._combatTagTimers[target] = nil
			end
		end
	end

	self._originalWalkSpeeds[player] = nil
end

function CarryManager:destroy()
	-- Drop all carried players
	for target, _ in pairs(self._carriedPlayers) do
		self:_forceDropTarget(target)
	end

	self._carriedPlayers = {}
	self._originalWalkSpeeds = {}
	self._originalCollisionGroups = {}
	self._combatTagTimers = {}

	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return CarryManager
