--!strict
local ContentProvider = game:GetService("ContentProvider")
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

local Punch = WCS.RegisterSkill("Punch")

-- WCS Client Prediction Configuration
-- These settings make the skill feel responsive by not waiting for server validation
Punch.CheckClientState = false -- Don't wait for server to validate before playing client effects
Punch.CheckOthersActive = false -- Don't check if other skills are active (we handle this manually)

-- Configuration (from central combatConfig)
local WeaponConfig = CombatConfig.Weapons.fists
local ComboConfig = CombatConfig.Combo

local PUNCH_DAMAGE = WeaponConfig.Damage
local PUNCH_RANGE = WeaponConfig.Range
local PUNCH_COOLDOWN = WeaponConfig.Cooldown

-- Hitbox configuration
local HIT_ANGLE_THRESHOLD = CombatConfig.Hitbox.HitAngleThreshold
local BLOCK_ANGLE_THRESHOLD = CombatConfig.Hitbox.BlockAngleThreshold

-- Hitstun duration for unarmed attacks
local SOFT_HITSTUN_DURATION = WeaponConfig.HitstunDuration
local FLOURISH_SELF_HITSTUN_DURATION = WeaponConfig.FlourishSelfHitstun

-- Combo system configuration
local COMBO_RESET_TIME = ComboConfig.ResetTime
local MAX_COMBO_PHASE = ComboConfig.MaxPhase

-- Knockback configuration for flourish
local FLOURISH_KNOCKBACK_POWER = WeaponConfig.FlourishKnockbackPower
local FLOURISH_KNOCKBACK_DURATION = WeaponConfig.FlourishKnockbackDuration

-- Animation IDs for each combo phase
local COMBO_ANIMATIONS = {
	[1] = "rbxassetid://71814602910988",
	[2] = "rbxassetid://83691540313756",
	[3] = "rbxassetid://118980540226262",
	[4] = "rbxassetid://128565870055276", -- Flourish uses 2_m1 temporarily
}

-- Damage delays for each combo phase (in seconds)
-- Synced to when the fist/foot connects in each animation
local DAMAGE_DELAYS = WeaponConfig.DamageDelays

function Punch:OnConstructServer()
	-- Setup server-side skill data
	self.hitTargets = {}
	self.comboPhase = 1
	self.comboResetTimer = nil
	self.currentAttackPhase = 1 -- Track which phase is currently executing
	self.attackingEffect = nil
	self.attackInvalidated = false -- Flag for trade prevention animation cleanup
end

function Punch:OnConstructClient()
	-- Setup client-side skill data
	self.comboPhase = 1
	self.comboResetTimer = nil
	self.loadedAnimations = {}
	self.animationsReady = false
	self.attackInvalidated = false -- Flag for trade prevention animation cleanup

	-- Preload all combo animations
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			-- Create animation instances first
			local animationInstances = {}
			for phase, animId in pairs(COMBO_ANIMATIONS) do
				local animation = Instance.new("Animation")
				animation.AnimationId = animId
				animationInstances[phase] = animation
				-- Load into animator
				self.loadedAnimations[phase] = animator:LoadAnimation(animation)
			end

			-- Mark as ready immediately (LoadAnimation is synchronous)
			self.animationsReady = true

			-- Preload in background via ContentProvider for smoother first play
			task.spawn(function()
				local animsToPreload = {}
				for _, anim in pairs(animationInstances) do
					table.insert(animsToPreload, anim)
				end
				ContentProvider:PreloadAsync(animsToPreload)
				print("[Punch] Client: Animations preloaded via ContentProvider")
			end)
		end
	end
end

function Punch:OnStartServer()
	-- Check if player has equipment manager
	if not self.Character.EquipmentManager then
		warn("[Punch] No equipment manager found")
		return
	end

	-- Check if player has a weapon equipped
	if not self.Character.EquipmentManager:hasWeaponEquipped() then
		print("[Punch] Blocked - No weapon equipped")
		return
	end

	-- Check if player is in hitstun, guardbroken, dashing, blocking/parrying, knocked down, or already attacking
	-- Attacking check prevents move stacking with heavy attacks
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Guardbroken,
			Dashing,
			Blocking,
			Parrying,
			Attacking, -- Prevents stacking M1 with heavy attack
			Knockdown, -- Can't attack while knocked down
		})
	then
		print("[Punch] Blocked - Player is in hitstun, guardbroken, dashing, blocking/parrying, knocked down, or attacking")
		return
	end

	-- Store the current attack phase before advancing
	self.currentAttackPhase = self.comboPhase

	print(`[Punch] Server: Punch activated - Phase {self.currentAttackPhase}`)

	-- Apply cooldown
	self:ApplyCooldown(PUNCH_COOLDOWN)

	-- Apply Attacking status effect FIRST (prevents dodging and slows movement during attack)
	-- This MUST be applied before parry flash remote so clients can validate the status
	if self.attackingEffect then
		self.attackingEffect:Stop()
	end
	self.attackingEffect = Attacking.new(self.Character)
	if self.attackingEffect then
		-- Duration matches the damage delay (when attack animation is active)
		local attackDuration = DAMAGE_DELAYS[self.currentAttackPhase] or 0.45
		self.attackingEffect:Start(attackDuration)
		print(`[Punch] Applied Attacking status for {attackDuration}s`)
	end

	-- Broadcast parry flash VFX to all clients (shows timing indicator for defenders)
	-- NOTE: This is sent AFTER Attacking status is applied so clients can validate
	local parryFlashRemote = ReplicatedStorage:FindFirstChild("PlayParryFlashVFX")
	if parryFlashRemote then
		parryFlashRemote:FireAllClients(self.Character.Instance, self.currentAttackPhase)
		print(`[Punch] Server: Broadcasting parry flash VFX for phase {self.currentAttackPhase}`)
	end

	-- Perform hitbox detection with delay based on animation timing
	local damageDelay = DAMAGE_DELAYS[self.currentAttackPhase] or 0.1
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
		print("[Punch] Combo reset to phase 1")
	end)
end

-- Animation IDs that should be stopped when punching (movement animations)
local MOVEMENT_ANIMATION_IDS = {
	["rbxassetid://104453488066690"] = true, -- Sprint animation
}

-- Walking animation speed multiplier during punch
local WALK_ANIM_SPEED_DURING_PUNCH = 0.5 -- 50% speed

-- Stop sprint and slow walking animations during punch
function Punch:_stopMovementAnimations()
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
			track:AdjustSpeed(WALK_ANIM_SPEED_DURING_PUNCH)
		end
	end
end

-- Restore walking animation speeds after punch
function Punch:_restoreMovementAnimations()
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

function Punch:OnStartClient()
	-- Check if player has any hitstun status effects active, is guardbroken, dashing, blocking/parrying, knocked down, or attacking
	-- Attacking check prevents move stacking with heavy attacks
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Dashing,
			Blocking,
			Parrying,
			Guardbroken,
			Attacking,
			Knockdown, -- Can't attack while knocked down
		})
	then
		return
	end

	-- Store current phase before advancing
	local currentPhase = self.comboPhase

	-- PRIORITY: Play animation FIRST for immediate visual feedback
	local animTrack = self.loadedAnimations[currentPhase]
	if animTrack then
		animTrack:Play(0.05)
		animTrack.Priority = Enum.AnimationPriority.Action4
	end

	-- Reset combo timer
	if self.comboResetTimer then
		task.cancel(self.comboResetTimer)
	end

	-- Stop any other punch animations that might be playing
	for phase, track in pairs(self.loadedAnimations) do
		if track and track.IsPlaying and phase ~= currentPhase then
			track:Stop(0.05)
		end
	end

	-- Stop movement animations (after punch anim starts)
	self:_stopMovementAnimations()

	-- Stop rollcancel animation if playing
	local dodgeSkill = self.Character:GetSkillFromConstructor(Dodge)
	if dodgeSkill and dodgeSkill.rollCancelTrack and dodgeSkill.rollCancelTrack.IsPlaying then
		dodgeSkill.rollCancelTrack:Stop(0.05)
		dodgeSkill.rollCancelTrack = nil
	end

	-- Apply VFX and SFX
	if animTrack then
		self:_applyFistsTrail(animTrack, currentPhase)
		self:_playSwingSFX(animTrack)
	end

	-- Client-side prediction: check for nearby targets with iframes and play rollcancel immediately
	self:_predictRollCancel()

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
function Punch:_detectHit()
	if not RunService:IsServer() then
		return
	end

	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoidRootPart then
		warn("[Punch] HumanoidRootPart not found")
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
				-- Check if target is in range
				local distance = (targetRootPart.Position - origin).Magnitude

				if distance <= PUNCH_RANGE then
					-- Check if target is in front of attacker
					local directionToTarget = (targetRootPart.Position - origin).Unit
					local dotProduct = lookDirection:Dot(directionToTarget)

					-- Check if target is within attack cone
					if dotProduct > HIT_ANGLE_THRESHOLD then
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
			-- Fire effects for each target that was hit
			for _, targetData in ipairs(actualHits) do
				hitEffectsRemote:FireAllClients(targetData.model, "fists")
			end
		end
	end
end

-- Apply damage to a target
-- Returns true if it was a real hit, false if blocked/parried/iframed
function Punch:_hitTarget(targetModel: Model, targetHumanoid: Humanoid)
	-- TRADE PREVENTION: Check if attacker got hit first (has hitstun)
	-- This is the key to preventing M1 trading - first hit wins
	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Parried }) then
		print(`[Punch] Attack invalidated - {self.Character.Instance.Name} was hit first (has hitstun)`)
		-- Set flag so OnEndClient knows to force stop animations (status might not have replicated yet)
		self.attackInvalidated = true
		-- End the skill immediately to stop animations
		self:End()
		return false
	end

	-- Check if we already hit this target (prevent double-hitting)
	if self.hitTargets[targetModel] then
		return false
	end

	-- Check if target is marked for execution (complete iframes)
	if targetModel:GetAttribute("MarkedForExecution") == true then
		print(`[Punch] Target {targetModel.Name} is marked for execution - No damage`)
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
					print(`[Punch] Target {targetModel.Name} is in failed parry window or startup phase!`)
				end
			end
		end

		if targetWCSCharacter:HasStatusEffects({ Iframes }) then
			print(`[Punch] Target {targetModel.Name} has iframes - No damage`)

			-- End target's dodge skill (cancel the roll)
			local targetDodgeSkill = targetWCSCharacter:GetSkillFromConstructor(Dodge)
			if targetDodgeSkill then
				local dodgeState = targetDodgeSkill:GetState()
				if dodgeState.IsActive then
					targetDodgeSkill:End()
					print(`[Punch] Ended dodge skill for {targetModel.Name} - Rollcancel`)
				end
			end

			-- Fire rollcancel effect on the target (plays cancel animation/sound/VFX)
			local rollCancelRemote = ReplicatedStorage:FindFirstChild("PlayRollCancel")
			if rollCancelRemote then
				rollCancelRemote:FireAllClients(targetModel)
			end

			-- Cancel attacker's momentum and attack
			self:_cancelAttackMomentum()

			return false
		end

		-- Check for parry (Parrying or Autoparry status) - 360 degrees, no facing requirement
		if targetWCSCharacter:HasStatusEffects({ Parrying, Autoparry }) then
			print(`[Punch] Target {targetModel.Name} PARRIED the attack!`)
			self:_handleParry(targetWCSCharacter)
			return false
		end

		-- Check for block (Blocking status but NOT parrying) - requires facing attacker
		if targetWCSCharacter:HasStatusEffects({ Blocking }) then
			local defenderFacingAttacker = self:_isDefenderFacingAttacker(targetModel)
			if defenderFacingAttacker then
				print(`[Punch] Target {targetModel.Name} blocked the attack`)
				self:_handleBlock(targetWCSCharacter)
				return false
			else
				print(`[Punch] Target {targetModel.Name} tried to block but wasn't facing attacker`)
				-- Fall through to damage (but no shakyblock - they're in blocking phase)
			end
		end
	end

	self.hitTargets[targetModel] = true

	print(`[Punch] Hit target: {targetModel.Name} - Phase {self.currentAttackPhase}`)

	-- Mark damage as M1 (so knockdown system knows not to auto-execute from M1s)
	targetModel:SetAttribute("LastDamageWasM1", true)

	-- Apply damage
	targetHumanoid:TakeDamage(PUNCH_DAMAGE)

	-- Apply soft hitstun to the target (if they have WCS character)
	if not targetWCSCharacter then
		targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	end
	if targetWCSCharacter then
		local hitstun = SoftHitstun.new(targetWCSCharacter)
		if hitstun then
			-- Start with duration per WCS docs (will refresh if already active)
			hitstun:Start(SOFT_HITSTUN_DURATION)
			print(`[Punch] Applied SoftHitstun ({SOFT_HITSTUN_DURATION}s) to {targetModel.Name}`)
		else
			warn(`[Punch] Failed to create SoftHitstun for {targetModel.Name}`)
		end

		-- Apply Shakyblock if target was in failed parry window (failed parry punishment)
		if inFailedParryWindow then
			local shakyblock = Shakyblock.new(targetWCSCharacter)
			if shakyblock then
				shakyblock:Start(CombatConfig.StatusDurations.Shakyblock)
				print(`[Punch] Applied Shakyblock to {targetModel.Name} - Failed parry punishment`)
			else
				warn(`[Punch] Failed to create Shakyblock for {targetModel.Name}`)
			end
		end

		-- Cancel target's M1 if they were attacking (M1 cancellation on hit)
		local targetPunchSkill = targetWCSCharacter:GetSkillFromConstructor(Punch)
		if targetPunchSkill then
			local punchState = targetPunchSkill:GetState()
			if punchState.IsActive then
				targetPunchSkill:End()
				print(`[Punch] Cancelled {targetModel.Name}'s M1 - Got hit`)
			end
		end
	else
		warn(`[Punch] No WCS character found for {targetModel.Name}`)
	end

	-- Apply knockback for flourish (phase 4)
	if self.currentAttackPhase == MAX_COMBO_PHASE then
		local targetRootPart = targetModel:FindFirstChild("HumanoidRootPart")
		local attackerRootPart = self.Character.Instance:FindFirstChild("HumanoidRootPart")
		local knockbackTargetHumanoid = targetModel:FindFirstChild("Humanoid") :: Humanoid?

		-- Skip knockback if target is knocked down (ragdolled)
		if knockbackTargetHumanoid and knockbackTargetHumanoid.PlatformStand then
			print(`[Punch] Skipping flourish knockback - {targetModel.Name} is knocked down`)
		elseif targetRootPart and attackerRootPart then
			local knockbackDirection = (targetRootPart.Position - attackerRootPart.Position).Unit
			local knockbackVelocity = Vector3.new(
				knockbackDirection.X * FLOURISH_KNOCKBACK_POWER,
				0, -- No vertical knockback
				knockbackDirection.Z * FLOURISH_KNOCKBACK_POWER
			)

			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.MaxForce = Vector3.new(50000, 0, 50000)
			bodyVelocity.Velocity = knockbackVelocity
			bodyVelocity.Parent = targetRootPart

			game:GetService("Debris"):AddItem(bodyVelocity, FLOURISH_KNOCKBACK_DURATION)
			print(`[Punch] Applied flourish knockback to {targetModel.Name}`)

			-- Apply self-hitstun to attacker for recovery period
			local selfHitstun = SoftHitstun.new(self.Character)

			if selfHitstun then
				selfHitstun:Start(FLOURISH_SELF_HITSTUN_DURATION)
				print(
					`[Punch] Applied self-hitstun ({FLOURISH_SELF_HITSTUN_DURATION}s) to attacker for flourish recovery`
				)
			else
				warn("[Punch] Failed to create self-hitstun for flourish recovery")
			end
		end
	end

	-- Return true to indicate this was a real hit (not blocked/parried)
	return true
end

-- Check if defender is facing the attacker (for directional blocking)
-- Returns true if the defender's look direction points towards the attacker
function Punch:_isDefenderFacingAttacker(defenderModel: Model): boolean
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
function Punch:_handleParry(defenderWCSCharacter)
	-- End Block skill so defender can attack during Autoparry window (enables parry trading)
	local blockSkill = defenderWCSCharacter:GetSkillFromConstructor(Block)
	if blockSkill then
		-- End the block skill to remove Blocking/Parrying status
		local blockState = blockSkill:GetState()
		if blockState.IsActive then
			blockSkill:End()
			print(`[Punch] Ended Block skill for {defenderWCSCharacter.Instance.Name} - Parry reward`)
		end

		-- Reset parry cooldown as reward for successful parry
		blockSkill.lastBlockEndTime = 0
		blockSkill.parryOnCooldown = false
		print(`[Punch] Reset parry cooldown for {defenderWCSCharacter.Instance.Name} - Parry reward`)
	end

	-- Apply Autoparry status to defender (protects during attack window)
	local autoparryEffect = Autoparry.new(defenderWCSCharacter)
	if autoparryEffect then
		autoparryEffect:Start(CombatConfig.StatusDurations.Autoparry)
		print(`[Punch] Applied Autoparry to {defenderWCSCharacter.Instance.Name}`)
	end

	-- Apply SoftHitstun to attacker (stagger - can still parry out of it)
	local softHitstunEffect = SoftHitstun.new(self.Character)
	if softHitstunEffect then
		softHitstunEffect:Start(CombatConfig.StatusDurations.ParriedAttackerHitstun)
		print(`[Punch] Applied SoftHitstun to attacker {self.Character.Instance.Name} - Got parried`)
	end

	-- Cancel attacker's M1 (this skill) - stop the attack animation
	-- The skill will end naturally but we want immediate feedback
	if self.attackingEffect then
		self.attackingEffect:Stop()
		self.attackingEffect = nil
	end

	-- Apply Parried status to attacker for visual/audio feedback
	local parriedEffect = Parried.new(self.Character)
	if parriedEffect then
		parriedEffect:Start(CombatConfig.StatusDurations.ParriedAttackerHitstun)
		print(`[Punch] Applied Parried status to attacker {self.Character.Instance.Name}`)
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
function Punch:_handleBlock(defenderWCSCharacter)
	-- Apply posture damage to defender for blocking FIRST (to check for guardbreak)
	local postureManager = getPostureManager()
	postureManager.addPosture(defenderWCSCharacter.Instance, postureManager.getBlockPostureDamage())

	-- Check if this block resulted in a guardbreak
	if defenderWCSCharacter.IsGuardbroken then
		print(
			`[Punch] Defender {defenderWCSCharacter.Instance.Name} guardbroken - Skipping block VFX (only guardbreak VFX will play)`
		)
		-- Don't play block VFX or block stun - guardbreak handles everything
		return
	end

	-- Normal block (no guardbreak) - apply block effects
	local blockStunnedEffect = BlockStunned.new(defenderWCSCharacter)
	if blockStunnedEffect then
		blockStunnedEffect:Start(CombatConfig.StatusDurations.BlockStunned)
		print(`[Punch] Applied BlockStunned to {defenderWCSCharacter.Instance.Name}`)
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

-- Apply fists trail VFX to specific arm based on combo phase (client-only)
function Punch:_applyFistsTrail(animTrack: AnimationTrack, currentPhase: number)
	if not RunService:IsClient() then
		return
	end

	-- Flourish (phase 4) has no trail
	if currentPhase == 4 then
		return
	end

	-- Get fists trail template
	local fistsTrailPart = ReplicatedStorage.Assets.VFX.Weapon_Classes.Light_Weapons.Fists.fists_trail
	if not fistsTrailPart or not fistsTrailPart:IsA("BasePart") then
		warn("[Punch] Fists trail part not found")
		return
	end

	-- Get the attachment from the trail part
	local trailAttachment = fistsTrailPart:FindFirstChildOfClass("Attachment")
	if not trailAttachment then
		warn("[Punch] No attachment found in fists_trail part")
		return
	end

	local character = self.Character.Instance

	-- Determine which arm to use based on combo phase
	-- Phase 1: Left Arm, Phase 2: Right Arm, Phase 3: Left Arm
	local targetGrip
	local armName

	if currentPhase == 1 or currentPhase == 3 then
		-- Left arm
		local leftArm = character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftHand")
		targetGrip = leftArm and leftArm:FindFirstChild("LeftGripAttachment")
		armName = "left"
	elseif currentPhase == 2 then
		-- Right arm
		local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
		targetGrip = rightArm and rightArm:FindFirstChild("RightGripAttachment")
		armName = "right"
	end

	if not targetGrip or not targetGrip:IsA("Attachment") then
		warn(`[Punch] Could not find grip attachment for phase {currentPhase}`)
		return
	end

	-- Clone trail attachment and parent it to the grip attachment
	local trailClone = trailAttachment:Clone()
	trailClone.Name = "FistsTrail_" .. armName
	trailClone.Parent = targetGrip -- Parent to grip attachment directly
	print(`[Punch] Applied fists trail to {armName} arm grip attachment (phase {currentPhase})`)

	-- Remove trail when animation ends
	local animLength = animTrack.Length or 0.5
	task.delay(animLength, function()
		if trailClone and trailClone.Parent then
			trailClone:Destroy()
		end
		print("[Punch] Removed fists trail VFX")
	end)
end

-- Play swing SFX (client-only) - delayed to 3/4 of animation duration
function Punch:_playSwingSFX(animTrack: AnimationTrack?)
	if not RunService:IsClient() then
		return
	end

	-- Calculate delay (1/4 of animation duration - early in the swing)
	local animLength = if animTrack then animTrack.Length else 0.5
	local sfxDelay = animLength * 0.25

	-- Delay the sound to match animation timing
	task.delay(sfxDelay, function()
		-- Get swing SFX folder
		local swingSFXFolder = ReplicatedStorage.Assets.SFX.Weapon_Classes.Light_Weapons.Fists.swings
		if not swingSFXFolder then
			warn("[Punch] Swing SFX folder not found")
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
			warn("[Punch] No swing sounds found in folder")
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
			warn("[Punch] No HumanoidRootPart found")
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

		print(`[Punch] Playing swing SFX: {randomSound.Name}`)
	end)
end

function Punch:OnEndServer()
	-- Clear hit targets when skill ends
	self.hitTargets = {}
end

function Punch:OnEndClient()
	-- Restore walking animation speeds when punch ends
	self:_restoreMovementAnimations()

	-- Industry standard: Only stop animations on interrupt, let them finish naturally otherwise
	-- Check if we were interrupted by looking for hitstun status OR Parried status
	-- Also check attackInvalidated flag (trade prevention - status might not have replicated yet)
	local interrupted = self.attackInvalidated or self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Parried })

	if interrupted then
		-- Only stop animations if interrupted - use fast fade
		for _, animTrack in pairs(self.loadedAnimations) do
			if animTrack and animTrack.IsPlaying then
				animTrack:Stop(0.05)
				print("[Punch] Client: Stopped animation due to interrupt")
			end
		end
	end
	-- Otherwise let animations finish naturally - don't stop them

	-- Reset the flag for next attack
	self.attackInvalidated = false
end

-- Client-side prediction for rollcancel (plays sound immediately when detecting iframe targets)
function Punch:_predictRollCancel()
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

	-- Check nearby characters for iframes
	for _, otherCharacter in ipairs(workspace:GetChildren()) do
		if otherCharacter:IsA("Model") and otherCharacter ~= character then
			local otherHumanoid = otherCharacter:FindFirstChild("Humanoid")
			local otherRootPart = otherCharacter:FindFirstChild("HumanoidRootPart")

			if otherHumanoid and otherRootPart and otherHumanoid.Health > 0 then
				-- Check distance
				local distance = (otherRootPart.Position - myPosition).Magnitude
				if distance <= PUNCH_RANGE then
					-- Check angle (in front of attacker)
					local directionToTarget = (otherRootPart.Position - myPosition).Unit
					local dotProduct = myLookVector:Dot(directionToTarget)

					if dotProduct > HIT_ANGLE_THRESHOLD then
						-- Target is in range and in front - check for iframes
						local wcsCharacter = WCS.Character.GetCharacterFromInstance(otherCharacter)
						if wcsCharacter and wcsCharacter:HasStatusEffects({ Iframes }) then
							-- Play rollcancel sound immediately (client prediction)
							self:_playPredictedRollCancelSound(otherCharacter)
							print(`[Punch] Client prediction: Rollcancel on {otherCharacter.Name}`)
							return -- Only trigger once per punch
						end
					end
				end
			end
		end
	end
end

-- Play predicted rollcancel sound (client-side, before server confirmation)
function Punch:_playPredictedRollCancelSound(targetModel: Model)
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
function Punch:_cancelAttackMomentum()
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

	-- Apply very brief stun to create a punish window
	local stunEffect = Stun.new(self.Character)
	if stunEffect then
		stunEffect:Start(CombatConfig.StatusDurations.RollcancelStun)
		print(`[Punch] Applied rollcancel stun to attacker {character.Name}`)
	end

	print(`[Punch] Cancelled attack momentum for {character.Name} - Hit iframes`)
end

return Punch
