--!strict
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)
local CombatConfig = require(ReplicatedStorage.Shared.config.combatConfig)

-- Pre-cache status effects and skills at module load (avoid require() in hot paths)
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
local Parrying = require(ReplicatedStorage.Shared.statusEffects.parrying)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local Iframes = require(ReplicatedStorage.Shared.statusEffects.iframes)
local Autoparry = require(ReplicatedStorage.Shared.statusEffects.autoparry)
local Parried = require(ReplicatedStorage.Shared.statusEffects.parried)
local BlockStunned = require(ReplicatedStorage.Shared.statusEffects.blockStunned)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
local Shakyblock = require(ReplicatedStorage.Shared.statusEffects.shakyblock)
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
local HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking)

-- Pre-cache skill references at module load (avoid require() in OnStartClient/OnStartServer)
local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Block = require(ReplicatedStorage.Shared.skills.block)

-- Posture system (lazy loaded to avoid circular dependencies)
local PostureManager = nil
local function getPostureManager()
	if not PostureManager then
		PostureManager = require(ReplicatedStorage.Shared.managers.postureManager)
	end
	return PostureManager
end

local Slash = WCS.RegisterSkill("Slash")

-- WCS Client Prediction Configuration
-- These settings make the skill feel responsive by not waiting for server validation
Slash.CheckClientState = false -- Don't wait for server to validate before playing client effects
Slash.CheckOthersActive = false -- Don't check if other skills are active (we handle this manually)

-- Configuration (from central combatConfig)
local ComboConfig = CombatConfig.Combo

-- Hitbox configuration
local HIT_ANGLE_THRESHOLD = CombatConfig.Hitbox.HitAngleThreshold
local BLOCK_ANGLE_THRESHOLD = CombatConfig.Hitbox.BlockAngleThreshold

-- Combo system configuration
local COMBO_RESET_TIME = ComboConfig.ResetTime
local MAX_COMBO_PHASE = ComboConfig.MaxPhase

-- Default weapon config (kunai) for fallback
local DEFAULT_WEAPON = "kunai"

-- Animation IDs for each combo phase per weapon
local COMBO_ANIMATIONS = {
	kunai = {
		[1] = "rbxassetid://91619051516074",
		[2] = "rbxassetid://131141876861809",
		[3] = "rbxassetid://122892720764576",
		[4] = "rbxassetid://114181766170631", -- Flourish
	},
	uchigatana = {
		[1] = "rbxassetid://87386532163101",
		[2] = "rbxassetid://91663977468313",
		[3] = "rbxassetid://96383704992301",
		[4] = "rbxassetid://114181766170631", -- Flourish
	},
	kusanagi = {
		[1] = "rbxassetid://87386532163101",
		[2] = "rbxassetid://91663977468313",
		[3] = "rbxassetid://96383704992301",
		[4] = "rbxassetid://114181766170631", -- Flourish
	},
}

-- Helper to get weapon config dynamically
local function getWeaponConfig(weaponType: string)
	return CombatConfig.Weapons[weaponType] or CombatConfig.Weapons[DEFAULT_WEAPON]
end

-- Damage delays are now fetched dynamically per weapon via getWeaponConfig()

function Slash:OnConstructServer()
	-- Setup server-side skill data
	self.hitTargets = {}
	self.comboPhase = 1
	self.comboResetTimer = nil
	self.currentAttackPhase = 1 -- Track which phase is currently executing
	self.currentWeaponType = DEFAULT_WEAPON -- Current weapon for this attack
	self.attackingEffect = nil
	self.attackInvalidated = false -- Flag for trade prevention animation cleanup
end

function Slash:OnConstructClient()
	-- Setup client-side skill data
	self.comboPhase = 1
	self.comboResetTimer = nil
	self.loadedAnimations = {} -- Now keyed by weapon type: { kunai = { [1] = track, ... }, uchigatana = { ... } }
	self.animationsReady = false
	self.attackInvalidated = false -- Flag for trade prevention animation cleanup
	self.hitstunMonitor = nil :: RBXScriptConnection? -- Monitor for hitstun during attack

	-- Preload combo animations for ALL weapons
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animsToPreload = {}

			-- Load animations for each weapon type
			for weaponType, phases in pairs(COMBO_ANIMATIONS) do
				self.loadedAnimations[weaponType] = {}
				for phase, animId in pairs(phases) do
					local animation = Instance.new("Animation")
					animation.AnimationId = animId
					table.insert(animsToPreload, animation)
					-- Load into animator
					self.loadedAnimations[weaponType][phase] = animator:LoadAnimation(animation)
				end
			end

			-- Mark as ready immediately (LoadAnimation is synchronous)
			self.animationsReady = true

			-- Preload in background via ContentProvider for smoother first play
			task.spawn(function()
				ContentProvider:PreloadAsync(animsToPreload)
				print("[Slash] Client: Animations preloaded via ContentProvider for all weapons")
			end)
		end
	end
end

function Slash:OnStartServer()
	-- Check if player has equipment manager
	if not self.Character.EquipmentManager then
		warn("[Slash] No equipment manager found")
		return
	end

	-- Check if player has a weapon equipped
	if not self.Character.EquipmentManager:hasWeaponEquipped() then
		print("[Slash] Blocked - No weapon equipped")
		return
	end

	-- Check if weapon is in hand (not just on back)
	if not self.Character.EquipmentManager:isWeaponInHand() then
		print("[Slash] Blocked - Weapon not in hand")
		return
	end

	-- Check if player is in hitstun, guardbroken, dashing, blocking/parrying, or already attacking
	-- Use HasStatusEffects to avoid flag race conditions between status effects
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Guardbroken,
			Dashing,
			Blocking,
			Parrying,
			Attacking, -- Prevents stacking M1 with M1
			HeavyAttacking, -- Prevents stacking M1 with heavy attack
			Knockdown, -- Can't attack while knocked down
		})
	then
		print(
			"[Slash] Blocked - Player is in hitstun, guardbroken, dashing, blocking/parrying, knocked down, or attacking"
		)
		return
	end

	-- Store the current attack phase before advancing
	self.currentAttackPhase = self.comboPhase

	-- Get weapon type and config for this attack
	self.currentWeaponType = self:_getCurrentWeaponType()
	local weaponConfig = getWeaponConfig(self.currentWeaponType)

	print(`[Slash] Server: Slash activated - Phase {self.currentAttackPhase} with {self.currentWeaponType}`)

	-- Apply cooldown
	self:ApplyCooldown(weaponConfig.Cooldown)

	-- Apply Attacking status effect FIRST (prevents dodging and slows movement during attack)
	-- This MUST be applied before parry flash remote so clients can validate the status
	if self.attackingEffect then
		self.attackingEffect:Stop()
	end
	self.attackingEffect = Attacking.new(self.Character)
	if self.attackingEffect then
		-- Duration matches the damage delay (when attack animation is active)
		local attackDuration = weaponConfig.DamageDelays[self.currentAttackPhase] or 0.4
		self.attackingEffect:Start(attackDuration)
		print(`[Slash] Applied Attacking status for {attackDuration}s`)
	end

	-- Broadcast parry flash VFX to all clients (shows timing indicator for defenders)
	-- Also sends animation ID so clients can play it locally for frame-perfect sync
	-- NOTE: This is sent AFTER Attacking status is applied so clients can validate
	local parryFlashRemote = ReplicatedStorage:FindFirstChild("PlayParryFlashVFX")
	if parryFlashRemote then
		local animId = COMBO_ANIMATIONS[self.currentWeaponType] and COMBO_ANIMATIONS[self.currentWeaponType][self.currentAttackPhase]
		parryFlashRemote:FireAllClients(self.Character.Instance, self.currentAttackPhase, animId)
		print(`[Slash] Server: Broadcasting parry flash VFX for phase {self.currentAttackPhase}, anim {animId}`)
	end

	-- Perform hitbox detection with delay based on animation timing
	local damageDelay = weaponConfig.DamageDelays[self.currentAttackPhase] or 0.1
	task.delay(damageDelay, function()
		self:_detectHit()
	end)

	-- Reset combo timer
	if self.comboResetTimer then
		task.cancel(self.comboResetTimer)
	end

	-- Advance combo phase for next attack
	if self.comboPhase < MAX_COMBO_PHASE then
		self.comboPhase = self.comboPhase + 1
	else
		self.comboPhase = 1 -- Reset to phase 1 after flourish
	end

	-- Set timer to reset combo if no input
	self.comboResetTimer = task.delay(COMBO_RESET_TIME, function()
		self.comboPhase = 1
		print("[Slash] Combo reset to phase 1")
	end)
end

-- Animation IDs that should be stopped when slashing (movement animations)
local MOVEMENT_ANIMATION_IDS = {
	["rbxassetid://104453488066690"] = true, -- Sprint animation
}

-- Walking animation speed multiplier during slash
local WALK_ANIM_SPEED_DURING_SLASH = 0.5 -- 50% speed

-- Stop sprint and slow walking animations during slash
function Slash:_stopMovementAnimations()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	-- Store original walk animation speeds for restoration later
	self.originalWalkAnimSpeeds = self.originalWalkAnimSpeeds or {}

	-- Process all playing animations
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation then
			local animId = track.Animation.AnimationId
			-- Stop sprint animation completely
			if MOVEMENT_ANIMATION_IDS[animId] then
				track:Stop(0.1)
			end
		end

		-- Slow down core movement animations (walk/run) by checking priority
		if track.Priority == Enum.AnimationPriority.Core or track.Priority == Enum.AnimationPriority.Movement then
			if not self.originalWalkAnimSpeeds[track] then
				self.originalWalkAnimSpeeds[track] = track.Speed
			end
			track:AdjustSpeed(WALK_ANIM_SPEED_DURING_SLASH)
		end
	end
end

-- Restore walking animation speeds after slash
function Slash:_restoreMovementAnimations()
	if not RunService:IsClient() then
		return
	end

	if not self.originalWalkAnimSpeeds then
		return
	end

	-- Restore original speeds for all tracked animations
	for track, originalSpeed in pairs(self.originalWalkAnimSpeeds) do
		if track and track.IsPlaying then
			track:AdjustSpeed(originalSpeed)
		end
	end

	-- Clear the stored speeds
	self.originalWalkAnimSpeeds = {}
end

function Slash:OnStartClient()
	-- Check if player has any hitstun status effects active, is guardbroken, dashing, blocking/parrying, or attacking
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Dashing,
			Blocking,
			Parrying,
			Guardbroken,
			Attacking, -- Prevents stacking M1 with M1
			HeavyAttacking, -- Prevents stacking M1 with heavy attack
			Knockdown, -- Can't attack while knocked down
		})
	then
		return
	end

	-- Store current phase before advancing
	local currentPhase = self.comboPhase

	-- Get current weapon type for animation lookup
	local clientWeaponType = self:_getClientWeaponType()
	local weaponAnims = self.loadedAnimations[clientWeaponType] or self.loadedAnimations[DEFAULT_WEAPON]

	-- PRIORITY: Play animation FIRST for immediate visual feedback
	local animTrack = weaponAnims and weaponAnims[currentPhase]
	if animTrack then
		animTrack:Play(0.05)
		animTrack.Priority = Enum.AnimationPriority.Action4
	end

	-- Reset combo timer
	if self.comboResetTimer then
		task.cancel(self.comboResetTimer)
	end

	-- Stop any other slash animations that might be playing (for current weapon)
	if weaponAnims then
		for phase, track in pairs(weaponAnims) do
			if track and track.IsPlaying and phase ~= currentPhase then
				track:Stop(0.05)
			end
		end
	end

	-- Stop movement animations (after slash anim starts)
	self:_stopMovementAnimations()

	-- Stop rollcancel animation if playing
	local dodgeSkill = self.Character:GetSkillFromConstructor(Dodge)
	if dodgeSkill and dodgeSkill.rollCancelTrack and dodgeSkill.rollCancelTrack.IsPlaying then
		dodgeSkill.rollCancelTrack:Stop(0.05)
		dodgeSkill.rollCancelTrack = nil
	end

	-- Apply VFX and SFX
	if animTrack then
		self:_applyWeaponTrail(animTrack, currentPhase)
		self:_playSwingSFX(animTrack)
	end

	-- Client-side prediction: check for nearby targets with iframes and play rollcancel immediately
	self:_predictRollCancel()

	-- Start hitstun monitoring (for M1 trade animation cancellation)
	-- This actively monitors for hitstun and cancels animation immediately when detected
	if self.hitstunMonitor then
		self.hitstunMonitor:Disconnect()
	end
	self.hitstunMonitor = RunService.Heartbeat:Connect(function()
		-- Check if we got hit (have hitstun)
		if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Parried }) then
			-- Stop all slash animations immediately
			for _, track in pairs(self.loadedAnimations) do
				if track and track.IsPlaying then
					track:Stop(0.05)
				end
			end
			-- Set flag and disconnect
			self.attackInvalidated = true
			if self.hitstunMonitor then
				self.hitstunMonitor:Disconnect()
				self.hitstunMonitor = nil
			end
			print("[Slash] Client: Animation cancelled - Got hit during attack")
		end
	end)

	-- Advance combo phase
	if self.comboPhase < MAX_COMBO_PHASE then
		self.comboPhase = self.comboPhase + 1
	else
		self.comboPhase = 1
	end

	-- Set timer to reset combo
	self.comboResetTimer = task.delay(COMBO_RESET_TIME, function()
		self.comboPhase = 1
	end)
end

-- Server-only hitbox detection
function Slash:_detectHit()
	if not RunService:IsServer() then
		return
	end

	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoidRootPart then
		warn("[Slash] HumanoidRootPart not found")
		return
	end

	-- Get all potential targets in range
	-- Origin is slightly behind the player so targets standing inside you still get hit
	local lookDirection = humanoidRootPart.CFrame.LookVector
	local origin = humanoidRootPart.Position - (lookDirection * 2)
	local hitTargets = {}

	-- Find all characters in workspace
	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid")
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart")

			if targetHumanoid and targetHumanoid.Health > 0 and targetRootPart then
				-- Skip if target is being carried by the attacker
				-- (don't hit the person you're holding)
				local carriedBy = potentialTarget:GetAttribute("CarriedBy")
				if carriedBy == character.Name then
					continue
				end

				-- Calculate direction and angle to target
				local directionToTarget = (targetRootPart.Position - origin).Unit
				local dotProduct = lookDirection:Dot(directionToTarget)
				local weaponConfig = getWeaponConfig(self.currentWeaponType or DEFAULT_WEAPON)

				-- Check if target is within attack cone angle
				if dotProduct > HIT_ANGLE_THRESHOLD then
					-- Calculate range falloff based on angle
					-- At center (dot = 1.0): 100% range
					-- At edge (dot = HIT_ANGLE_THRESHOLD): ~83% range
					local normalizedDot = (dotProduct - HIT_ANGLE_THRESHOLD) / (1.0 - HIT_ANGLE_THRESHOLD)
					-- Use squared falloff for more dramatic reduction at edges
					local rangeMultiplier = 0.831 + (0.169 * (normalizedDot * normalizedDot))
					local effectiveRange = weaponConfig.Range * rangeMultiplier

					-- Check if target is within effective range
					local distance = (targetRootPart.Position - origin).Magnitude
					if distance <= effectiveRange then
						table.insert(hitTargets, { model = potentialTarget, humanoid = targetHumanoid })
					end
				end
			end
		end
	end

	-- Process all hit targets and collect actual hits (not blocked/parried)
	local actualHits = {}
	for _, targetData in ipairs(hitTargets) do
		local hitResult = self:_hitTarget(targetData.model, targetData.humanoid)
		-- hitResult will be true if it was a real hit, false if blocked/parried/iframed
		if hitResult then
			table.insert(actualHits, targetData)
		end
	end

	-- Fire hit effects for EACH target that was actually hit (not blocked/parried)
	if #actualHits > 0 then
		local hitEffectsRemote = ReplicatedStorage:FindFirstChild("PlayHitEffects")
		if hitEffectsRemote then
			-- Flourish (phase 4) uses kick, so use fists hit effects instead of weapon
			local weaponType = if self.currentAttackPhase == MAX_COMBO_PHASE
				then "fists"
				else self:_getCurrentWeaponType()
			-- Fire effects for each target that was hit
			for _, targetData in ipairs(actualHits) do
				hitEffectsRemote:FireAllClients(targetData.model, weaponType)
			end
		end
	end
end

-- Get the current weapon type from equipment manager
function Slash:_getCurrentWeaponType(): string
	if self.Character.EquipmentManager then
		local equipped = self.Character.EquipmentManager:getEquipped()
		if equipped then
			return equipped
		end
	end
	return "kunai" -- Default to kunai
end

-- Apply damage to a target
-- Returns true if it was a real hit, false if blocked/parried/iframed
function Slash:_hitTarget(targetModel: Model, targetHumanoid: Humanoid)
	-- TRADE PREVENTION: Check if attacker got hit first (has hitstun)
	-- This is the key to preventing M1 trading - first hit wins
	-- Even if both attacks were initiated, the first to land applies hitstun
	-- When the second attack's hit detection runs, the attacker will have hitstun
	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Parried }) then
		print(`[Slash] Attack invalidated - {self.Character.Instance.Name} was hit first (has hitstun)`)
		-- Set flag so OnEndClient knows to force stop animations (status might not have replicated yet)
		self.attackInvalidated = true
		-- End the skill immediately to stop animations (OnEndClient will handle cleanup)
		self:End()
		return false
	end

	-- Check if we already hit this target (prevent double-hitting)
	if self.hitTargets[targetModel] then
		return false
	end

	-- Check if target is marked for execution (complete iframes)
	if targetModel:GetAttribute("MarkedForExecution") == true then
		print(`[Slash] Target {targetModel.Name} is marked for execution - No damage`)
		return false
	end

	-- Track if target was in failed parry window or startup (for failed parry punishment)
	local inFailedParryWindow = false

	-- Check if target has iframes (invincibility)
	local targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	if targetWCSCharacter then
		-- Check if target is in failed parry window or startup phase (block skill active but no Parrying/Blocking status)
		local targetBlockSkill = targetWCSCharacter:GetSkillFromConstructor(Block)
		if targetBlockSkill then
			local blockState = targetBlockSkill:GetState()
			if blockState.IsActive then
				-- Block skill is active - check if they're in the failed parry window or startup
				local hasParryingOrBlocking = targetWCSCharacter:HasStatusEffects({ Parrying, Autoparry, Blocking })
				if not hasParryingOrBlocking then
					-- They're holding block but have no parrying/blocking status = failed parry window OR startup
					inFailedParryWindow = true
					print(`[Slash] Target {targetModel.Name} is in failed parry window or startup phase!`)
				end
			end
		end

		if targetWCSCharacter:HasStatusEffects({ Iframes }) then
			print(`[Slash] Target {targetModel.Name} has iframes - No damage`)

			-- Check if we're within the rollcancel window (first 75% of iframe duration)
			local rollcancelWindowEnd = targetModel:GetAttribute("_RollcancelWindowEnd")
			local canRollcancel = rollcancelWindowEnd and tick() < rollcancelWindowEnd

			if canRollcancel then
				-- End target's dodge skill (cancel the roll)
				local targetDodgeSkill = targetWCSCharacter:GetSkillFromConstructor(Dodge)
				if targetDodgeSkill then
					local dodgeState = targetDodgeSkill:GetState()
					if dodgeState.IsActive then
						targetDodgeSkill:End()
						print(`[Slash] Ended dodge skill for {targetModel.Name} - Rollcancel`)
					end
				end

				-- Fire rollcancel effect on the target (plays cancel animation/sound/VFX)
				local rollCancelRemote = ReplicatedStorage:FindFirstChild("PlayRollCancel")
				if rollCancelRemote then
					rollCancelRemote:FireAllClients(targetModel)
				end

				-- Cancel attacker's momentum and attack
				self:_cancelAttackMomentum()
			else
				print(`[Slash] Target {targetModel.Name} is past rollcancel window - No rollcancel`)
			end

			return false
		end

		-- Check for parry (Parrying or Autoparry status) - 360 degrees, no facing requirement
		if targetWCSCharacter:HasStatusEffects({ Parrying, Autoparry }) then
			print(`[Slash] Target {targetModel.Name} PARRIED the attack!`)
			self:_handleParry(targetWCSCharacter)
			return false
		end

		-- Check for block (Blocking status but NOT parrying) - requires facing attacker
		if targetWCSCharacter:HasStatusEffects({ Blocking }) then
			local defenderFacingAttacker = self:_isDefenderFacingAttacker(targetModel)
			if defenderFacingAttacker then
				print(`[Slash] Target {targetModel.Name} blocked the attack`)
				self:_handleBlock(targetWCSCharacter)
				return false
			else
				print(`[Slash] Target {targetModel.Name} tried to block but wasn't facing attacker`)
				-- Fall through to damage (but no shakyblock - they're in blocking phase)
			end
		end
	end

	self.hitTargets[targetModel] = true

	print(`[Slash] Hit target: {targetModel.Name} - Phase {self.currentAttackPhase}`)

	-- Get weapon config for this attack
	local weaponConfig = getWeaponConfig(self.currentWeaponType or DEFAULT_WEAPON)

	-- Mark damage as M1 (so knockdown system knows not to auto-execute from M1s)
	targetModel:SetAttribute("LastDamageWasM1", true)

	-- Apply damage
	targetHumanoid:TakeDamage(weaponConfig.Damage)

	-- Combat tag the target (PvP only)
	if _G.CombatTagManager then
		local attackerPlayer = Players:GetPlayerFromCharacter(self.Character.Instance)
		local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
		if attackerPlayer and targetPlayer then
			_G.CombatTagManager:tagPlayer(targetPlayer, attackerPlayer)
		end
	end

	-- Apply soft hitstun to the target (if they have WCS character)
	if not targetWCSCharacter then
		targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	end
	if targetWCSCharacter then
		local hitstun = SoftHitstun.new(targetWCSCharacter)
		if hitstun then
			-- Start with duration per WCS docs (will refresh if already active)
			hitstun:Start(weaponConfig.HitstunDuration)
			print(`[Slash] Applied SoftHitstun ({weaponConfig.HitstunDuration}s) to {targetModel.Name}`)
		else
			warn(`[Slash] Failed to create SoftHitstun for {targetModel.Name}`)
		end

		-- Apply Shakyblock if target was in failed parry window (failed parry punishment)
		-- Only apply if they don't already have Shakyblock (prevents double activation)
		if inFailedParryWindow and not targetWCSCharacter:HasStatusEffects({ Shakyblock }) then
			local shakyblock = Shakyblock.new(targetWCSCharacter)
			if shakyblock then
				shakyblock:Start(CombatConfig.StatusDurations.Shakyblock)
				print(`[Slash] Applied Shakyblock (0.3s) to {targetModel.Name} - Failed parry punishment`)
			else
				warn(`[Slash] Failed to create Shakyblock for {targetModel.Name}`)
			end
		end

		-- Cancel target's attack if they were attacking (attack cancellation on hit)
		local Slash_ref = require(ReplicatedStorage.Shared.skills.slash)
		local targetSlashSkill = targetWCSCharacter:GetSkillFromConstructor(Slash_ref)
		if targetSlashSkill then
			local slashState = targetSlashSkill:GetState()
			if slashState.IsActive then
				targetSlashSkill:End()
				print(`[Slash] Cancelled {targetModel.Name}'s Slash - Got hit`)
			end
		end
	else
		warn(`[Slash] No WCS character found for {targetModel.Name}`)
	end

	-- Apply knockback for flourish (phase 4)
	if self.currentAttackPhase == MAX_COMBO_PHASE then
		local targetRootPart = targetModel:FindFirstChild("HumanoidRootPart")
		local attackerRootPart = self.Character.Instance:FindFirstChild("HumanoidRootPart")
		local knockbackTargetHumanoid = targetModel:FindFirstChild("Humanoid") :: Humanoid?

		-- Skip knockback if target is knocked down (ragdolled)
		if knockbackTargetHumanoid and knockbackTargetHumanoid.PlatformStand then
			print(`[Slash] Skipping flourish knockback - {targetModel.Name} is knocked down`)
		elseif targetRootPart and attackerRootPart then
			local knockbackDirection = (targetRootPart.Position - attackerRootPart.Position).Unit
			local knockbackVelocity = Vector3.new(
				knockbackDirection.X * weaponConfig.FlourishKnockbackPower,
				0, -- No vertical knockback
				knockbackDirection.Z * weaponConfig.FlourishKnockbackPower
			)

			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.MaxForce = Vector3.new(50000, 0, 50000)
			bodyVelocity.Velocity = knockbackVelocity
			bodyVelocity.Parent = targetRootPart

			game:GetService("Debris"):AddItem(bodyVelocity, weaponConfig.FlourishKnockbackDuration)
			print(`[Slash] Applied flourish knockback to {targetModel.Name}`)

			-- Apply self-hitstun to attacker for recovery period
			local selfHitstun = SoftHitstun.new(self.Character)

			if selfHitstun then
				selfHitstun:Start(weaponConfig.FlourishSelfHitstun)
				print(
					`[Slash] Applied self-hitstun ({weaponConfig.FlourishSelfHitstun}s) to attacker for flourish recovery`
				)
			else
				warn("[Slash] Failed to create self-hitstun for flourish recovery")
			end
		end
	end

	-- Return true to indicate this was a real hit (not blocked/parried)
	return true
end

-- Check if defender is facing the attacker (for directional blocking)
-- Returns true if the defender's look direction points towards the attacker
function Slash:_isDefenderFacingAttacker(defenderModel: Model): boolean
	local attackerRootPart = self.Character.Instance:FindFirstChild("HumanoidRootPart") :: BasePart?
	local defenderRootPart = defenderModel:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not attackerRootPart or not defenderRootPart then
		return false
	end

	-- Get defender's look direction
	local defenderLookDirection = defenderRootPart.CFrame.LookVector

	-- Get direction from defender to attacker
	local directionToAttacker = (attackerRootPart.Position - defenderRootPart.Position).Unit

	-- Calculate dot product (1 = facing directly, 0 = perpendicular, -1 = facing away)
	local dotProduct = defenderLookDirection:Dot(directionToAttacker)

	-- Defender must be facing attacker within the block angle threshold
	return dotProduct > BLOCK_ANGLE_THRESHOLD
end

-- Handle successful parry
function Slash:_handleParry(defenderWCSCharacter)
	-- End Block skill so defender can attack during Autoparry window (enables parry trading)
	local blockSkill = defenderWCSCharacter:GetSkillFromConstructor(Block)
	if blockSkill then
		-- End the block skill to remove Blocking/Parrying status
		local blockState = blockSkill:GetState()
		if blockState.IsActive then
			blockSkill:End()
			print(`[Slash] Ended Block skill for {defenderWCSCharacter.Instance.Name} - Parry reward`)
		end

		-- Reset parry cooldown as reward for successful parry
		blockSkill.lastBlockEndTime = 0
		blockSkill.parryOnCooldown = false
		print(`[Slash] Reset parry cooldown for {defenderWCSCharacter.Instance.Name} - Parry reward`)
	end

	-- Apply Autoparry status to defender for 0.4s (protects during attack window)
	local autoparryEffect = Autoparry.new(defenderWCSCharacter)
	if autoparryEffect then
		autoparryEffect:Start(CombatConfig.StatusDurations.Autoparry)
		print(`[Slash] Applied Autoparry (0.4s) to {defenderWCSCharacter.Instance.Name}`)
	end

	-- Apply SoftHitstun to attacker (0.8s stagger - can still parry out of it)
	local softHitstunEffect = SoftHitstun.new(self.Character)
	if softHitstunEffect then
		softHitstunEffect:Start(CombatConfig.StatusDurations.ParriedAttackerHitstun)
		print(`[Slash] Applied SoftHitstun (0.8s) to attacker {self.Character.Instance.Name} - Got parried`)
	end

	-- Cancel attacker's attack (this skill) - stop the attack animation
	-- The skill will end naturally but we want immediate feedback
	if self.attackingEffect then
		self.attackingEffect:Stop()
		self.attackingEffect = nil
	end

	-- Apply Parried status to attacker for visual/audio feedback
	local parriedEffect = Parried.new(self.Character)
	if parriedEffect then
		parriedEffect:Start(CombatConfig.StatusDurations.ParriedAttackerHitstun)
		print(`[Slash] Applied Parried status (0.8s) to attacker {self.Character.Instance.Name}`)
	end

	-- Fire parry VFX event on DEFENDER (full parry effect on defender)
	local parryVFXRemote = ReplicatedStorage:FindFirstChild("PlayParryVFX")
	if parryVFXRemote then
		parryVFXRemote:FireAllClients(defenderWCSCharacter.Instance)
	end

	-- Fire parried animation event on ATTACKER (stagger animation when getting parried)
	local parriedAnimRemote = ReplicatedStorage:FindFirstChild("PlayParriedAnimation")
	if parriedAnimRemote then
		parriedAnimRemote:FireAllClients(self.Character.Instance)
	end

	-- Apply posture changes
	local postureManager = getPostureManager()
	-- Attacker gains posture (capped at 99% - can never guardbreak from parry alone)
	postureManager.addPostureCapped(self.Character.Instance, postureManager.getParriedPostureDamage())
	-- Defender loses posture (reward for successful parry)
	postureManager.removePosture(defenderWCSCharacter.Instance, postureManager.getParryPostureReward())
end

-- Handle successful block (not a parry)
function Slash:_handleBlock(defenderWCSCharacter)
	-- Apply posture damage to defender for blocking FIRST (to check for guardbreak)
	local postureManager = getPostureManager()
	postureManager.addPosture(defenderWCSCharacter.Instance, postureManager.getBlockPostureDamage())

	-- Check if this block resulted in a guardbreak
	if defenderWCSCharacter.IsGuardbroken then
		print(
			`[Slash] Defender {defenderWCSCharacter.Instance.Name} guardbroken - Skipping block VFX (only guardbreak VFX will play)`
		)
		-- Don't play block VFX or block stun - guardbreak handles everything
		return
	end

	-- Normal block (no guardbreak) - apply block effects
	-- Apply BlockStunned status to defender for 0.1s
	local blockStunnedEffect = BlockStunned.new(defenderWCSCharacter)
	if blockStunnedEffect then
		blockStunnedEffect:Start(CombatConfig.StatusDurations.BlockStunned)
		print(`[Slash] Applied BlockStunned (0.1s) to {defenderWCSCharacter.Instance.Name}`)
	end

	-- Fire block hit animation event
	local blockHitAnimRemote = ReplicatedStorage:FindFirstChild("PlayBlockHitAnimation")
	if blockHitAnimRemote then
		blockHitAnimRemote:FireAllClients(defenderWCSCharacter.Instance)
	end

	-- Fire block hit VFX event (only if not guardbroken)
	local blockHitVFXRemote = ReplicatedStorage:FindFirstChild("PlayBlockHitVFX")
	if blockHitVFXRemote then
		blockHitVFXRemote:FireAllClients(defenderWCSCharacter.Instance)
	end
end

-- Apply weapon trail VFX to weapon's Grip attachments (client-only)
function Slash:_applyWeaponTrail(animTrack: AnimationTrack, currentPhase: number)
	if not RunService:IsClient() then
		return
	end

	-- Flourish (phase 4) has no trail
	if currentPhase == 4 then
		return
	end

	-- Find the weapon model directly from character (it's parented there with "_Equipped" suffix)
	-- On client, EquipmentManager doesn't exist, so we search the character's children
	local characterInstance = self.Character.Instance
	local weaponModel = nil

	for _, child in ipairs(characterInstance:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "_Equipped") then
			weaponModel = child
			break
		end
	end

	if not weaponModel then
		warn("[Slash] No weapon model found for trail (looking for *_Equipped model)")
		return
	end

	-- Find trail0 attachment anywhere in the weapon model (recursive search)
	local trail0: Instance? = nil
	for _, descendant in ipairs(weaponModel:GetDescendants()) do
		if descendant.Name == "trail0" then
			trail0 = descendant
			break
		end
	end

	if not trail0 then
		warn("[Slash] Trail attachment (trail0) not found in weapon model")
		return
	end

	-- Find the Trail object inside trail0
	local trail = trail0:FindFirstChildOfClass("Trail")
	if trail then
		local animLength = animTrack.Length or 0.5

		-- Enable trail at 10% of animation (delayed start)
		task.delay(animLength * 0.1, function()
			if trail and trail.Parent then
				trail.Enabled = true
				print(`[Slash] Enabled weapon trail for phase {currentPhase}`)
			end
		end)

		-- Disable trail at 80% of animation
		task.delay(animLength * 0.8, function()
			if trail and trail.Parent then
				trail.Enabled = false
				print("[Slash] Disabled weapon trail VFX")
			end
		end)
	else
		warn("[Slash] No Trail object found in trail0")
	end
end

-- Play swing SFX (client-only) - delayed to 1/4 of animation duration
function Slash:_playSwingSFX(animTrack: AnimationTrack?)
	if not RunService:IsClient() then
		return
	end

	-- Calculate delay (1/4 of animation duration - early in the swing)
	local animLength = if animTrack then animTrack.Length else 0.5
	local sfxDelay = animLength * 0.25

	-- Delay the sound to match animation timing
	task.delay(sfxDelay, function()
		-- Get the equipped weapon type for SFX path
		local weaponType = self:_getClientWeaponType()

		-- Determine weapon category based on weapon type
		local weaponCategory = "Light_Weapons"
		if weaponType == "uchigatana" or weaponType == "kusanagi" then
			weaponCategory = "Medium_Weapons"
		end

		-- Capitalize weapon type for folder name (folders use PascalCase)
		local weaponFolderName = string.upper(string.sub(weaponType, 1, 1)) .. string.sub(weaponType, 2)

		-- Get swing SFX folder for this weapon
		local swingSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
			and ReplicatedStorage.Assets:FindFirstChild("SFX")
			and ReplicatedStorage.Assets.SFX:FindFirstChild("Weapon_Classes")
			and ReplicatedStorage.Assets.SFX.Weapon_Classes:FindFirstChild(weaponCategory)
			and ReplicatedStorage.Assets.SFX.Weapon_Classes[weaponCategory]:FindFirstChild(weaponFolderName)
			and ReplicatedStorage.Assets.SFX.Weapon_Classes[weaponCategory][weaponFolderName]:FindFirstChild("swings")

		if not swingSFXFolder then
			warn(`[Slash] Swing SFX folder not found for weapon: {weaponType}`)
			return
		end

		-- Get all Sound instances from folder
		local sounds = {}
		for _, child in ipairs(swingSFXFolder:GetChildren()) do
			if child:IsA("Sound") then
				table.insert(sounds, child)
			end
		end

		if #sounds == 0 then
			warn("[Slash] No swing sounds found in folder")
			return
		end

		-- Select random sound
		local randomSound = sounds[math.random(1, #sounds)]

		-- Find the character's HumanoidRootPart for spatial audio
		local character = self.Character.Instance
		if not character then
			return
		end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			warn("[Slash] No HumanoidRootPart found")
			return
		end

		-- Clone the sound and parent it to the root part for spatial audio
		local soundClone = randomSound:Clone()
		soundClone.Parent = rootPart

		-- Play the sound
		soundClone:Play()

		-- Clean up after sound finishes
		task.delay(soundClone.TimeLength + 0.1, function()
			if soundClone and soundClone.Parent then
				soundClone:Destroy()
			end
		end)

		print(`[Slash] Playing swing SFX: {randomSound.Name}`)
	end)
end

-- Get weapon type on client (for SFX/VFX paths)
function Slash:_getClientWeaponType(): string
	-- On client, find weapon model from character (named *_Equipped)
	local characterInstance = self.Character.Instance
	for _, child in ipairs(characterInstance:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "_Equipped") then
			-- Extract weapon name from "Kunai_Equipped" -> "kunai" (lowercase for config lookup)
			local weaponName = string.gsub(child.Name, "_Equipped", "")
			return string.lower(weaponName)
		end
	end
	return "kunai" -- Default (lowercase)
end

function Slash:OnEndServer()
	-- Clear hit targets when skill ends
	self.hitTargets = {}
end

function Slash:OnEndClient()
	-- Clean up hitstun monitor connection
	if self.hitstunMonitor then
		self.hitstunMonitor:Disconnect()
		self.hitstunMonitor = nil
	end

	-- Restore walking animation speeds when slash ends
	self:_restoreMovementAnimations()

	-- Industry standard: Only stop animations on interrupt, let them finish naturally otherwise
	-- Check if we were interrupted by looking for hitstun status OR Parried status
	-- Also check attackInvalidated flag (trade prevention - status might not have replicated yet)
	local interrupted = self.attackInvalidated or self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Parried })

	if interrupted then
		-- Only stop animations if interrupted - use fast fade
		-- loadedAnimations is now { weaponType = { phase = track } }
		for _, weaponAnims in pairs(self.loadedAnimations) do
			for _, animTrack in pairs(weaponAnims) do
				if animTrack and animTrack.IsPlaying then
					animTrack:Stop(0.05)
					print("[Slash] Client: Stopped animation due to interrupt")
				end
			end
		end
	end
	-- Otherwise let animations finish naturally - don't stop them

	-- Reset the flag for next attack
	self.attackInvalidated = false
end

-- Client-side prediction for rollcancel (plays sound immediately when detecting iframe targets)
function Slash:_predictRollCancel()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local myPosition = rootPart.Position
	local myLookVector = rootPart.CFrame.LookVector

	-- Get weapon config for range check
	local clientWeaponType = self:_getClientWeaponType()
	local weaponConfig = getWeaponConfig(clientWeaponType)

	-- Check nearby characters for iframes
	for _, otherCharacter in ipairs(workspace:GetChildren()) do
		if otherCharacter:IsA("Model") and otherCharacter ~= character then
			local otherHumanoid = otherCharacter:FindFirstChild("Humanoid")
			local otherRootPart = otherCharacter:FindFirstChild("HumanoidRootPart")

			if otherHumanoid and otherRootPart and otherHumanoid.Health > 0 then
				-- Check distance
				local distance = (otherRootPart.Position - myPosition).Magnitude
				if distance <= weaponConfig.Range then
					-- Check angle (in front of attacker)
					local directionToTarget = (otherRootPart.Position - myPosition).Unit
					local dotProduct = myLookVector:Dot(directionToTarget)

					if dotProduct > HIT_ANGLE_THRESHOLD then
						-- Target is in range and in front - check for iframes
						local wcsCharacter = WCS.Character.GetCharacterFromInstance(otherCharacter)
						if wcsCharacter and wcsCharacter:HasStatusEffects({ Iframes }) then
							-- Play rollcancel sound immediately (client prediction)
							self:_playPredictedRollCancelSound(otherCharacter)
							print(`[Slash] Client prediction: Rollcancel on {otherCharacter.Name}`)
							return -- Only trigger once per slash
						end
					end
				end
			end
		end
	end
end

-- Play predicted rollcancel sound (client-side, before server confirmation)
function Slash:_playPredictedRollCancelSound(targetModel: Model)
	-- Set debounce attribute so hitEffectsManager won't play duplicate sound
	targetModel:SetAttribute("_RollCancelTime", tick())

	local cancelSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("SFX")
		and ReplicatedStorage.Assets.SFX:FindFirstChild("Movement")
		and ReplicatedStorage.Assets.SFX.Movement:FindFirstChild("Dodges")
		and ReplicatedStorage.Assets.SFX.Movement.Dodges:FindFirstChild("Cancel")

	if not cancelSFXFolder then
		return -- Silently fail - folder might not exist yet
	end

	local sounds = {}
	for _, child in ipairs(cancelSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		return
	end

	local randomSound = sounds[math.random(1, #sounds)]
	local soundClone = randomSound:Clone()
	soundClone.Parent = targetModel:FindFirstChild("HumanoidRootPart") or targetModel
	soundClone:Play()

	-- Cleanup
	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)
end

-- Cancel attacker's momentum when hitting iframes (rollcancel punishment)
function Slash:_cancelAttackMomentum()
	if not RunService:IsServer() then
		return
	end

	local character = self.Character.Instance
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Cancel any velocity/momentum by removing BodyVelocity or similar movers
	for _, child in ipairs(rootPart:GetChildren()) do
		if child:IsA("BodyVelocity") or child:IsA("BodyPosition") or child:IsA("BodyGyro") then
			child:Destroy()
		end
	end

	-- Reset velocity to zero
	if rootPart:IsA("BasePart") then
		rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
	end

	-- End attacking status to allow dodging/movement
	if self.attackingEffect then
		self.attackingEffect:Stop()
		self.attackingEffect = nil
	end

	print(`[Slash] Cancelled attack momentum for {character.Name} - Hit iframes`)
end

return Slash
