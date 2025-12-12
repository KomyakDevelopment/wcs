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
Grip.Duration = 10 -- Long duration, we end it manually when grip completes/cancels

-- ============================================================================
-- SERVER
-- ============================================================================

function Grip:OnConstructServer()
	self.targetCharacter = nil
	self.isGripping = false
	self.damageConnection = nil :: RBXScriptConnection?
	self.gripThread = nil :: thread?
	self.gripStartTime = 0 -- Track when grip started to prevent accidental cancel
	self.lastGripAttempt = 0 -- Debounce for rapid grip attempts
end

-- Minimum time before grip can be cancelled (prevents double-input issues)
local MIN_GRIP_TIME_BEFORE_CANCEL = 0.5
local GRIP_DEBOUNCE = 0.3 -- Minimum time between grip attempts

function Grip:OnStartServer()
	local now = os.clock()

	-- CRITICAL: Debounce to prevent double-processing from input buffering or WCS issues
	if now - self.lastGripAttempt < GRIP_DEBOUNCE then
		print(`[Grip] Server: Debounced - too soon since last attempt ({now - self.lastGripAttempt}s)`)
		return
	end
	self.lastGripAttempt = now

	print("[Grip] Server: OnStartServer called")

	-- If already gripping, this is a cancel request - but only if grip has been active for a bit
	if self.isGripping then
		local timeSinceStart = now - self.gripStartTime
		if timeSinceStart < MIN_GRIP_TIME_BEFORE_CANCEL then
			print(`[Grip] Server: Cancel ignored - grip just started ({timeSinceStart}s ago)`)
			return
		end
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
	self.gripStartTime = os.clock() -- Track start time to prevent accidental quick-cancel

	print(`[Grip] Server: Starting grip on {target.Name}`)

	-- Immobilize attacker completely (no movement, no rotation)
	local attackerHumanoid = self.Character.Instance:FindFirstChild("Humanoid") :: Humanoid?
	if attackerHumanoid then
		self.originalWalkSpeed = attackerHumanoid.WalkSpeed
		self.originalJumpPower = attackerHumanoid.JumpPower
		self.originalAutoRotate = attackerHumanoid.AutoRotate
		self.originalHealth = attackerHumanoid.Health
		attackerHumanoid.WalkSpeed = 0
		attackerHumanoid.JumpPower = 0
		attackerHumanoid.AutoRotate = false
	end

	-- Move attacker to victim's position for the grip animation (do this FIRST, before any state changes)
	local attackerRootPart = self.Character.Instance:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetRootPart = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if attackerRootPart and targetRootPart then
		-- Position attacker at victim's location, only copying Y rotation (yaw), not full orientation
		-- (victim might be ragdolled/lying down, we don't want to copy that tilt)
		local targetPos = targetRootPart.Position
		local _, yRot, _ = targetRootPart.CFrame:ToEulerAnglesYXZ()
		attackerRootPart.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, yRot, 0)
	end

	-- Disable victim ragdoll for animation (after a delay to let fade complete)
	task.delay(0.5, function()
		if not self.isGripping then return end -- Check grip wasn't cancelled

		local ragdollTrigger = target:FindFirstChild("RagdollTrigger") :: BoolValue?
		if ragdollTrigger then
			ragdollTrigger.Value = false
		end

		-- Stand up the victim for the grip animation
		local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?
		if targetHumanoid then
			targetHumanoid.PlatformStand = false
		end
	end)

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

	-- Setup damage listener with delay to avoid false positives during initialization
	if attackerHumanoid then
		if self.damageConnection then self.damageConnection:Disconnect() end

		-- Use a flag to delay damage checking - prevents false triggers from health changes during setup
		local damageCheckActive = false
		task.delay(0.15, function()
			if self.isGripping then
				-- Capture health baseline AFTER the delay for accuracy
				self.originalHealth = attackerHumanoid.Health
				damageCheckActive = true
				print(`[Grip] Server: Damage detection now active, baseline HP: {self.originalHealth}`)
			end
		end)

		self.damageConnection = attackerHumanoid.HealthChanged:Connect(function(newHealth)
			if not damageCheckActive then return end -- Skip until delay passes
			if self.isGripping and newHealth < (self.originalHealth or 100) then
				print(`[Grip] Server: Attacker took damage ({self.originalHealth} -> {newHealth}), cancelling`)
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

	-- Note: Cooldown is applied when grip ends (cancel or execute), not here
	-- This ensures no cooldown if grip fails during setup

	-- Schedule execution
	self.gripThread = task.delay(GRIP_DURATION, function()
		if self.isGripping and self.targetCharacter == target then
			self:_serverExecuteTarget(target)
		end
	end)
end

function Grip:_serverCancelGrip()
	if not self.isGripping then
		print("[Grip] Server: _serverCancelGrip called but isGripping is false, ignoring")
		return
	end

	local timeSinceStart = os.clock() - self.gripStartTime
	print(`[Grip] Server: Cancelling grip (was active for {timeSinceStart}s)`)
	self.isGripping = false

	-- Apply cooldown now that grip actually started and is ending
	self:ApplyCooldown(GRIP_COOLDOWN)

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
		attackerHumanoid.AutoRotate = if self.originalAutoRotate ~= nil then self.originalAutoRotate else true
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

	-- End the skill
	self:End()
end

function Grip:_serverExecuteTarget(target: Model)
	if not self.isGripping then return end

	print(`[Grip] Server: Executing {target.Name}`)
	self.isGripping = false
	self.gripThread = nil

	-- Apply cooldown now that grip completed
	self:ApplyCooldown(GRIP_COOLDOWN)

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
		attackerHumanoid.AutoRotate = if self.originalAutoRotate ~= nil then self.originalAutoRotate else true
	end

	-- Fire execution event FIRST (for animations/effects)
	local executeRemote = ReplicatedStorage:FindFirstChild("PlayerExecuted") :: RemoteEvent?
	if executeRemote then
		executeRemote:FireAllClients(target, self.Character.Instance)
	end

	-- DON'T call prepareForExecution here - it sets PlatformStand=false and disables ragdoll
	-- which causes the character to briefly stand up. We want to keep them incapacitated.
	-- prepareForExecution will be called when the player clicks continue (via ConfirmExecution remote)

	-- Keep the target incapacitated
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?
	if targetHumanoid then
		-- Keep them fully incapacitated - they stay down until they click continue
		targetHumanoid.WalkSpeed = 0
		targetHumanoid.JumpPower = 0
		targetHumanoid.PlatformStand = true

		-- Enable ragdoll to keep them down
		local ragdollTrigger = target:FindFirstChild("RagdollTrigger") :: BoolValue?
		if ragdollTrigger then
			ragdollTrigger.Value = true
		end

		-- DON'T set health to 0 - this triggers death state which causes standing up
		-- Instead just keep them incapacitated. The client will fire ConfirmExecution
		-- when they click continue, which will handle the actual respawn.
		print(`[Grip] Server: Incapacitated {target.Name} - waiting for continue button`)

		-- Mark them as executed so they can't be interacted with
		target:SetAttribute("Executed", true)

		-- Keep them frozen indefinitely until respawn (client controls when via ConfirmExecution remote)
		task.spawn(function()
			while target and target.Parent and target:GetAttribute("Executed") do
				if targetHumanoid and targetHumanoid.Parent then
					targetHumanoid.WalkSpeed = 0
					targetHumanoid.JumpPower = 0
					targetHumanoid.PlatformStand = true
				end
				task.wait(0.1)
			end
		end)
	end

	-- DON'T auto-respawn - the client's ExecutionEffectsManager will fire ConfirmExecution
	-- when the player clicks continue, and the server handler will respawn them

	self.targetCharacter = nil

	-- End the skill
	self:End()
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
	print(`[Grip] Server: OnEndServer called, isGripping={self.isGripping}`)

	-- Clean up if skill ends unexpectedly
	-- BUT only if we've been gripping for a bit (prevents WCS immediate end issues)
	if self.isGripping then
		local timeSinceStart = os.clock() - self.gripStartTime
		if timeSinceStart < 0.1 then
			-- Grip JUST started, WCS is ending it prematurely - this is a bug we need to handle
			print(`[Grip] Server: OnEndServer called too soon ({timeSinceStart}s), ignoring WCS end`)
			-- Don't cancel, let the grip continue - the skill ending doesn't mean we should cancel
			return
		end
		self:_serverCancelGrip()
	end
end

-- ============================================================================
-- CLIENT
-- ============================================================================

function Grip:OnConstructClient()
	self.isGripActive = false
	self.targetCharacter = nil

	-- IMPORTANT: Clean up any existing connections before creating new ones
	-- This prevents duplicate listeners if the skill is reconstructed
	if self._connections then
		for _, conn in ipairs(self._connections) do
			conn:Disconnect()
		end
	end
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
