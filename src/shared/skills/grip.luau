--!strict
-- Grip Skill
-- Allows players to execute knocked down enemies
-- Player walks up to knocked player, presses B, plays grip animation, then executes target

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

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
local GRIP_RANGE = 8 -- Distance to target
local GRIP_DURATION = 1.5 -- Time to complete the grip animation before execution
local GRIP_COOLDOWN = 2.0
local SINK_DEPTH = 5 -- How far to sink the body into the ground
local SINK_DURATION = 1.5 -- How long the sink takes
local FADE_DURATION = 1.0 -- How long the fade takes

-- Animation IDs
local GRIP_ANIMATION = "rbxassetid://71814602910988" -- Placeholder - replace with actual grip anim

-- WCS Configuration
Grip.CheckClientState = false
Grip.CheckOthersActive = false

function Grip:OnConstructServer()
	self.targetCharacter = nil
	self.executionScheduled = false -- Track if we've scheduled an execution (separate from skill state)
end

function Grip:OnConstructClient()
	self.loadedAnimations = {}
	self.currentAnimTrack = nil
	self.targetCharacter = nil

	-- Preload animation
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local gripAnim = Instance.new("Animation")
			gripAnim.AnimationId = GRIP_ANIMATION
			self.loadedAnimations.Grip = animator:LoadAnimation(gripAnim)
			print("[Grip] Client: Preloaded grip animation")
		end
	end
end

-- Find nearest knocked down player within range
function Grip:_findNearestKnockedTarget(): Model?
	local character = self.Character.Instance
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return nil
	end

	local myPosition = rootPart.Position
	local nearestTarget = nil :: Model?
	local nearestDistance = GRIP_RANGE + 1

	-- Check all characters in workspace
	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid") :: Humanoid?
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart") :: BasePart?

			if targetHumanoid and targetRootPart then
				-- Check if target is knocked down (PlatformStand = true means ragdolled)
				if targetHumanoid.PlatformStand then
					-- On server, check if target is already marked for execution
					if RunService:IsServer() and _G.DeathManager then
						local targetPlayer = Players:GetPlayerFromCharacter(potentialTarget)
						if targetPlayer and _G.DeathManager:isMarkedForExecution(targetPlayer) then
							-- Skip this target - already being executed
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
	end

	return nearestTarget
end

function Grip:OnStartServer()
	print("[Grip] Server: OnStartServer called")

	-- Check if player is in any status that prevents gripping
	local hasBlockingStatus = self.Character:HasStatusEffects({
		SoftHitstun, TrueHitstun, Stun, Dashing,
		Blocking, Attacking, Guardbroken, Knockdown
	})

	if hasBlockingStatus then
		print("[Grip] Server: Blocked - Player has preventing status effect")
		return
	end

	print("[Grip] Server: No blocking status effects, finding target...")

	-- Find target
	local target = self:_findNearestKnockedTarget()
	if not target then
		print("[Grip] Server: No valid target found within range")
		return
	end

	self.targetCharacter = target
	self.executionScheduled = true

	print(`[Grip] Server: Found target {target.Name}, starting grip`)

	-- Get target player
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	print(`[Grip] Server: Target player = {if targetPlayer then targetPlayer.Name else "nil (NPC)"}`)

	-- Immediately mark for execution - stops regen and shows 0% HP visually
	if targetPlayer then
		if _G.DeathManager then
			print("[Grip] Server: Marking target for execution via DeathManager")
			_G.DeathManager:markForExecution(targetPlayer)
		else
			warn("[Grip] Server: _G.DeathManager is nil!")
		end
	end

	-- Apply cooldown
	self:ApplyCooldown(GRIP_COOLDOWN)
	print(`[Grip] Server: Applied {GRIP_COOLDOWN}s cooldown`)

	-- Store target reference for the delayed execution (skill may end before this fires)
	local targetRef = target

	-- Wait for grip duration (animation plays on client)
	print(`[Grip] Server: Scheduling execution in {GRIP_DURATION}s`)
	task.delay(GRIP_DURATION, function()
		print("[Grip] Server: Execution delay finished, checking target validity...")

		-- Check if target still exists and is still knocked down
		if not targetRef or not targetRef.Parent then
			print("[Grip] Server: Target no longer exists (destroyed or left game)")
			return
		end

		local targetHumanoid = targetRef:FindFirstChild("Humanoid") :: Humanoid?
		if not targetHumanoid then
			print("[Grip] Server: Target humanoid not found")
			return
		end

		print(`[Grip] Server: Target PlatformStand = {targetHumanoid.PlatformStand}, Health = {targetHumanoid.Health}`)

		if not targetHumanoid.PlatformStand then
			print("[Grip] Server: Target is no longer knocked down (recovered)")
			return
		end

		-- Execute the target
		print("[Grip] Server: All checks passed, calling _executeTarget...")
		self:_executeTarget(targetRef)
	end)
end

function Grip:OnStartClient()
	-- Check for preventing status effects
	if self.Character:HasStatusEffects({
		SoftHitstun, TrueHitstun, Stun, Dashing,
		Blocking, Attacking, Guardbroken, Knockdown
	}) then
		return
	end

	-- Find target for visual feedback
	local target = self:_findNearestKnockedTarget()
	if not target then
		return
	end

	self.targetCharacter = target

	-- Play grip animation
	local gripTrack = self.loadedAnimations.Grip
	if gripTrack then
		self.currentAnimTrack = gripTrack
		gripTrack.Priority = Enum.AnimationPriority.Action4
		gripTrack:Play(0.1)
		print("[Grip] Client: Playing grip animation")
	end
end

-- Execute the target (server-only)
-- NOTE: This does NOT kill the player - it just fires the execution event
-- The player will be killed when they click "Continue" on the death screen
function Grip:_executeTarget(targetCharacter: Model)
	print("[Grip] Server: _executeTarget called")

	if not RunService:IsServer() then
		print("[Grip] Server: Not on server, returning")
		return
	end

	local targetHumanoid = targetCharacter:FindFirstChild("Humanoid") :: Humanoid?
	if not targetHumanoid then
		warn("[Grip] Server: Target humanoid not found in _executeTarget")
		return
	end

	print(`[Grip] Server: Executing {targetCharacter.Name} (waiting for continue)`)

	-- Fire execution event to all clients (for VFX/SFX/death UI)
	-- The player is NOT killed here - they click continue to actually die and respawn
	local executeRemote = ReplicatedStorage:FindFirstChild("PlayerExecuted") :: RemoteEvent?
	if executeRemote then
		print(`[Grip] Server: Firing PlayerExecuted event to all clients for {targetCharacter.Name}`)
		executeRemote:FireAllClients(targetCharacter)
		print("[Grip] Server: PlayerExecuted event fired successfully")
	else
		warn("[Grip] Server: PlayerExecuted remote event NOT FOUND in ReplicatedStorage!")
	end

	-- Player stays in execution state until they click continue
	-- The ConfirmExecution remote handler will kill and respawn them
	print(`[Grip] Server: {targetCharacter.Name} execution event fired - awaiting continue`)

	self.executionScheduled = false
end

function Grip:OnEndServer()
	-- Don't reset executionScheduled here - the task.delay handles its own cleanup
	self.targetCharacter = nil
end

function Grip:OnEndClient()
	-- Stop animation if playing
	if self.currentAnimTrack and self.currentAnimTrack.IsPlaying then
		self.currentAnimTrack:Stop(0.2)
	end
	self.currentAnimTrack = nil
	self.targetCharacter = nil
end

return Grip
