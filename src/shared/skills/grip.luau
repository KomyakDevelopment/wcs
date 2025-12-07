--!strict
-- Grip Skill (Simplified)
-- Allows players to execute knocked down enemies
-- Press B to start grip, press B again to cancel

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)

-- Pre-cache status effects
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)

local Grip = WCS.RegisterSkill("Grip")

-- Configuration
local GRIP_RANGE = 8
local GRIP_DURATION = 2.5
local GRIP_COOLDOWN = 2.0

-- Animation IDs
local GRIP_ATTACKER_ANIMATION = "rbxassetid://130414330071752"
local GRIP_VICTIM_ANIMATION = "rbxassetid://78865882601929"

-- WCS Configuration
Grip.CheckClientState = false
Grip.CheckOthersActive = false

-- ============================================================================
-- SERVER
-- ============================================================================

function Grip:OnConstructServer()
	self.targetCharacter = nil
	self.isGripping = false
	self.damageConnection = nil :: RBXScriptConnection?
	self.gripThread = nil :: thread?
end

function Grip:OnStartServer()
	print("[Grip] Server: OnStartServer called")

	-- If already gripping, this is a cancel request
	if self.isGripping then
		print("[Grip] Server: Cancel requested (already gripping)")
		self:_serverCancelGrip()
		return
	end

	-- Check for blocking status effects
	if self.Character:HasStatusEffects({
		SoftHitstun, TrueHitstun, Stun, Dashing,
		Blocking, Attacking, Guardbroken, Knockdown
	}) then
		print("[Grip] Server: Blocked by status effect")
		return
	end

	-- Find target
	local target = self:_findNearestKnockedTarget()
	if not target then
		print("[Grip] Server: No valid target found")
		return
	end

	-- Start the grip
	self:_serverStartGrip(target)
end

function Grip:_serverStartGrip(target: Model)
	self.targetCharacter = target
	self.isGripping = true

	print(`[Grip] Server: Starting grip on {target.Name}`)

	-- Immobilize attacker
	local attackerHumanoid = self.Character.Instance:FindFirstChild("Humanoid") :: Humanoid?
	if attackerHumanoid then
		self.originalWalkSpeed = attackerHumanoid.WalkSpeed
		self.originalJumpPower = attackerHumanoid.JumpPower
		self.originalHealth = attackerHumanoid.Health
		attackerHumanoid.WalkSpeed = 0
		attackerHumanoid.JumpPower = 0
	end

	-- Disable victim ragdoll for animation
	local ragdollTrigger = target:FindFirstChild("RagdollTrigger") :: BoolValue?
	if ragdollTrigger then
		ragdollTrigger.Value = false
	end

	-- Mark target for execution
	target:SetAttribute("MarkedForExecution", true)
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if targetPlayer and _G.DeathManager then
		_G.DeathManager:markForExecution(targetPlayer)
	end

	-- Apply combat tags
	local attackerPlayer = Players:GetPlayerFromCharacter(self.Character.Instance)
	if _G.CombatTagManager then
		if attackerPlayer then _G.CombatTagManager:tagPlayer(attackerPlayer, nil) end
		if targetPlayer then _G.CombatTagManager:tagPlayer(targetPlayer, attackerPlayer) end
	end

	-- Setup damage listener
	if attackerHumanoid then
		if self.damageConnection then self.damageConnection:Disconnect() end
		self.damageConnection = attackerHumanoid.HealthChanged:Connect(function(newHealth)
			if self.isGripping and newHealth < (self.originalHealth or 100) then
				print("[Grip] Server: Attacker took damage, cancelling")
				self:_serverCancelGrip()
			end
			self.originalHealth = newHealth
		end)
	end

	-- Broadcast to clients
	local gripStartRemote = ReplicatedStorage:FindFirstChild("GripStart") :: RemoteEvent?
	if not gripStartRemote then
		gripStartRemote = Instance.new("RemoteEvent")
		gripStartRemote.Name = "GripStart"
		gripStartRemote.Parent = ReplicatedStorage
	end
	gripStartRemote:FireAllClients(self.Character.Instance, target)

	-- Apply cooldown
	self:ApplyCooldown(GRIP_COOLDOWN)

	-- Schedule execution
	self.gripThread = task.delay(GRIP_DURATION, function()
		if self.isGripping and self.targetCharacter == target then
			self:_serverExecuteTarget(target)
		end
	end)
end

function Grip:_serverCancelGrip()
	if not self.isGripping then return end

	print("[Grip] Server: Cancelling grip")
	self.isGripping = false

	-- Cancel scheduled execution
	if self.gripThread then
		task.cancel(self.gripThread)
		self.gripThread = nil
	end

	-- Disconnect damage listener
	if self.damageConnection then
		self.damageConnection:Disconnect()
		self.damageConnection = nil
	end

	-- Restore attacker
	local attackerHumanoid = self.Character.Instance:FindFirstChild("Humanoid") :: Humanoid?
	if attackerHumanoid then
		attackerHumanoid.WalkSpeed = self.originalWalkSpeed or 16
		attackerHumanoid.JumpPower = self.originalJumpPower or 50
	end

	-- Restore target
	if self.targetCharacter then
		-- Re-enable ragdoll
		local ragdollTrigger = self.targetCharacter:FindFirstChild("RagdollTrigger") :: BoolValue?
		if ragdollTrigger then
			ragdollTrigger.Value = true
		end

		-- Clear execution marker
		self.targetCharacter:SetAttribute("MarkedForExecution", nil)

		-- Restore knockdown state
		local targetPlayer = Players:GetPlayerFromCharacter(self.targetCharacter)
		if targetPlayer and _G.DeathManager then
			_G.DeathManager:cancelExecution(targetPlayer)
		end

		-- Broadcast cancel
		local cancelRemote = ReplicatedStorage:FindFirstChild("GripCancelBroadcast") :: RemoteEvent?
		if not cancelRemote then
			cancelRemote = Instance.new("RemoteEvent")
			cancelRemote.Name = "GripCancelBroadcast"
			cancelRemote.Parent = ReplicatedStorage
		end
		cancelRemote:FireAllClients(self.Character.Instance, self.targetCharacter)

		print(`[Grip] Server: Released {self.targetCharacter.Name}`)
	end

	self.targetCharacter = nil
end

function Grip:_serverExecuteTarget(target: Model)
	if not self.isGripping then return end

	print(`[Grip] Server: Executing {target.Name}`)
	self.isGripping = false
	self.gripThread = nil

	-- Disconnect damage listener
	if self.damageConnection then
		self.damageConnection:Disconnect()
		self.damageConnection = nil
	end

	-- Restore attacker movement
	local attackerHumanoid = self.Character.Instance:FindFirstChild("Humanoid") :: Humanoid?
	if attackerHumanoid then
		attackerHumanoid.WalkSpeed = self.originalWalkSpeed or 16
		attackerHumanoid.JumpPower = self.originalJumpPower or 50
	end

	-- Fire execution event FIRST (for animations/effects)
	local executeRemote = ReplicatedStorage:FindFirstChild("PlayerExecuted") :: RemoteEvent?
	if executeRemote then
		executeRemote:FireAllClients(target, self.Character.Instance)
	end

	-- Actually kill the target via DeathManager
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if targetPlayer and _G.DeathManager then
		-- Prepare removes all knockdown protection so HP can go to 0
		_G.DeathManager:prepareForExecution(targetPlayer)
	end

	-- Kill the target
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?
	if targetHumanoid then
		targetHumanoid.BreakJointsOnDeath = true
		targetHumanoid.Health = 0
		print(`[Grip] Server: Killed {target.Name}`)
	end

	-- Respawn after delay
	if targetPlayer then
		task.delay(2.0, function()
			if targetPlayer and targetPlayer.Parent then
				targetPlayer:LoadCharacter()
				print(`[Grip] Server: Respawned {targetPlayer.Name}`)
			end
		end)
	end

	self.targetCharacter = nil
end

function Grip:_findNearestKnockedTarget(): Model?
	local character = self.Character.Instance
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return nil end

	local myPosition = rootPart.Position
	local nearestTarget: Model? = nil
	local nearestDistance = GRIP_RANGE + 1

	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid") :: Humanoid?
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart") :: BasePart?

			if targetHumanoid and targetRootPart and targetHumanoid.PlatformStand then
				-- Skip if being carried
				if potentialTarget:GetAttribute("BeingCarried") then continue end

				-- Skip if already marked for execution
				if RunService:IsServer() and _G.DeathManager then
					local targetPlayer = Players:GetPlayerFromCharacter(potentialTarget)
					if targetPlayer and _G.DeathManager:isMarkedForExecution(targetPlayer) then
						continue
					end
				end

				local distance = (targetRootPart.Position - myPosition).Magnitude
				if distance <= GRIP_RANGE and distance < nearestDistance then
					nearestTarget = potentialTarget
					nearestDistance = distance
				end
			end
		end
	end

	return nearestTarget
end

function Grip:OnEndServer()
	-- Clean up if skill ends unexpectedly
	if self.isGripping then
		self:_serverCancelGrip()
	end
end

-- ============================================================================
-- CLIENT
-- ============================================================================

function Grip:OnConstructClient()
	self.isGripActive = false
	self.targetCharacter = nil
	self._connections = {} :: { RBXScriptConnection }

	-- Listen for grip events
	task.spawn(function()
		local gripStartRemote = ReplicatedStorage:WaitForChild("GripStart", 10) :: RemoteEvent?
		if gripStartRemote then
			table.insert(self._connections, gripStartRemote.OnClientEvent:Connect(function(attacker: Model, victim: Model)
				self:_clientOnGripStart(attacker, victim)
			end))
		end

		local gripCancelRemote = ReplicatedStorage:WaitForChild("GripCancelBroadcast", 10) :: RemoteEvent?
		if gripCancelRemote then
			table.insert(self._connections, gripCancelRemote.OnClientEvent:Connect(function(attacker: Model, victim: Model)
				self:_clientOnGripCancel(attacker, victim)
			end))
		end

		local executedRemote = ReplicatedStorage:WaitForChild("PlayerExecuted", 10) :: RemoteEvent?
		if executedRemote then
			table.insert(self._connections, executedRemote.OnClientEvent:Connect(function(executed: Model, _killer: Model?)
				self:_clientOnExecuted(executed)
			end))
		end
	end)
end

function Grip:_clientOnGripStart(attacker: Model, victim: Model)
	local myCharacter = self.Character.Instance

	if attacker == myCharacter then
		self.isGripActive = true
		self.targetCharacter = victim
		print("[Grip] Client: I am gripping, state set")
	end

	-- Note: Animations handled by gripEffectsManager
end

function Grip:_clientOnGripCancel(attacker: Model, _victim: Model)
	local myCharacter = self.Character.Instance

	if attacker == myCharacter then
		self.isGripActive = false
		self.targetCharacter = nil
		print("[Grip] Client: Grip cancelled, state reset")
	end
end

function Grip:_clientOnExecuted(executed: Model)
	if self.isGripActive and self.targetCharacter == executed then
		self.isGripActive = false
		self.targetCharacter = nil
		print("[Grip] Client: Target executed, state reset")
	end
end

function Grip:OnStartClient()
	-- Check for blocking status
	if self.Character:HasStatusEffects({
		SoftHitstun, TrueHitstun, Stun, Dashing,
		Blocking, Attacking, Guardbroken, Knockdown
	}) then
		return
	end

	-- If grip is active, this start is a cancel request (handled on server)
	if self.isGripActive then
		print("[Grip] Client: Sending cancel request")
		return
	end

	-- Check if there's a valid target
	local target = self:_findNearestKnockedTarget()
	if not target then
		print("[Grip] Client: No target found")
		return
	end

	print(`[Grip] Client: Found target {target.Name}`)
end

function Grip:OnEndClient()
	-- Don't reset state here - it's managed by event broadcasts
end

-- Public method for interaction manager
function Grip:IsGripActive(): boolean
	return self.isGripActive
end

return Grip
