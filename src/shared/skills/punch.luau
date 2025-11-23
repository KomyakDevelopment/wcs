--!strict
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)

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

-- Pre-cache skill references at module load (avoid require() in OnStartClient/OnStartServer)
local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Block = require(ReplicatedStorage.Shared.skills.block)

local Punch = WCS.RegisterSkill("Punch")

-- WCS Client Prediction Configuration
-- These settings make the skill feel responsive by not waiting for server validation
Punch.CheckClientState = false -- Don't wait for server to validate before playing client effects
Punch.CheckOthersActive = false -- Don't check if other skills are active (we handle this manually)

-- Configuration
local PUNCH_DAMAGE = 10
local PUNCH_RANGE = 8 -- Increased for better hit registration
local PUNCH_COOLDOWN = 0.75

-- Hitbox configuration
local HIT_ANGLE_THRESHOLD = 0.3 -- Dot product threshold for hit detection (~72 degrees in front)
local BLOCK_ANGLE_THRESHOLD = 0.3 -- Must face attacker to block/parry

-- Hitstun duration for unarmed attacks
local SOFT_HITSTUN_DURATION = 0.6
local FLOURISH_SELF_HITSTUN_DURATION = 0.5 -- Recovery time after landing flourish

-- Combo system configuration
local COMBO_RESET_TIME = 2.0 -- Time before combo resets to phase 1
local MAX_COMBO_PHASE = 4 -- Total combo phases (1, 2, 3, flourish)

-- Knockback configuration for flourish
local FLOURISH_KNOCKBACK_POWER = 55
local FLOURISH_KNOCKBACK_DURATION = 0.18

-- Animation IDs for each combo phase
local COMBO_ANIMATIONS = {
	[1] = "rbxassetid://95618907841454",
	[2] = "rbxassetid://126552545189412",
	[3] = "rbxassetid://72345778790227",
	[4] = "rbxassetid://139971702607493", -- Flourish uses 2_m1 temporarily
}

-- Damage delays for each combo phase (in seconds)
-- Synced to when the fist/foot connects in each animation
local DAMAGE_DELAYS = {
	[1] = 0.41, -- First M1 - quick jab
	[2] = 0.41, -- Second M1 - cross punch
	[3] = 0.41, -- Third M1 - hook
	[4] = 0.51, -- Flourish - kick takes slightly longer
}

function Punch:OnConstructServer()
	-- Setup server-side skill data
	self.hitTargets = {}
	self.comboPhase = 1
	self.comboResetTimer = nil
	self.currentAttackPhase = 1 -- Track which phase is currently executing
	self.attackingEffect = nil
end

function Punch:OnConstructClient()
	-- Setup client-side skill data
	self.comboPhase = 1
	self.comboResetTimer = nil
	self.loadedAnimations = {}
	self.animationsReady = false

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

	-- Check if player is in hitstun, dashing, or blocking/parrying
	if self.Character.IsInHitstun or self.Character:HasStatusEffects({ Dashing, Blocking, Parrying }) then
		print("[Punch] Blocked - Player is in hitstun, dashing, or blocking/parrying")
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
	-- Check if player has any hitstun status effects active, is dashing, or is blocking/parrying
	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Dashing, Blocking, Parrying }) then
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
	end
	self:_playSwingSFX()

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

	-- Fire hit effects ONCE if any actual hits occurred (not blocked/parried)
	if #actualHits > 0 then
		local hitEffectsRemote = ReplicatedStorage:FindFirstChild("PlayHitEffects")
		if hitEffectsRemote then
			-- Send the first target for sound positioning (plays once regardless of hit count)
			hitEffectsRemote:FireAllClients(actualHits[1].model, "fists")
		end
	end
end

-- Apply damage to a target
-- Returns true if it was a real hit, false if blocked/parried/iframed
function Punch:_hitTarget(targetModel: Model, targetHumanoid: Humanoid)
	-- Check if we already hit this target (prevent double-hitting)
	if self.hitTargets[targetModel] then
		return false
	end

	-- Check if target has iframes (invincibility)
	local targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	if targetWCSCharacter then
		if targetWCSCharacter:HasStatusEffects({ Iframes }) then
			print(`[Punch] Target {targetModel.Name} has iframes - No damage`)
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
				print(`[Punch] Target {targetModel.Name} tried to block but wasn't facing attacker!`)
				-- Fall through to damage
			end
		end
	end

	self.hitTargets[targetModel] = true

	print(`[Punch] Hit target: {targetModel.Name} - Phase {self.currentAttackPhase}`)

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

		if targetRootPart and attackerRootPart then
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

	-- Apply Autoparry status to defender for 0.4s (protects during attack window)
	local autoparryEffect = Autoparry.new(defenderWCSCharacter)
	if autoparryEffect then
		autoparryEffect:Start(0.4)
		print(`[Punch] Applied Autoparry (0.4s) to {defenderWCSCharacter.Instance.Name}`)
	end

	-- Apply SoftHitstun to attacker (0.8s stagger - can still parry out of it)
	local softHitstunEffect = SoftHitstun.new(self.Character)
	if softHitstunEffect then
		softHitstunEffect:Start(0.8)
		print(`[Punch] Applied SoftHitstun (0.8s) to attacker {self.Character.Instance.Name} - Got parried`)
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
		parriedEffect:Start(0.8)
		print(`[Punch] Applied Parried status (0.8s) to attacker {self.Character.Instance.Name}`)
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

	-- TODO: Apply posture changes (defender -30%, attacker +30%)
	print("[Punch] TODO: Apply posture changes for parry")
end

-- Handle successful block (not a parry)
function Punch:_handleBlock(defenderWCSCharacter)
	-- Apply BlockStunned status to defender for 0.1s
	local blockStunnedEffect = BlockStunned.new(defenderWCSCharacter)
	if blockStunnedEffect then
		blockStunnedEffect:Start(0.1)
		print(`[Punch] Applied BlockStunned (0.1s) to {defenderWCSCharacter.Instance.Name}`)
	end

	-- Fire block hit animation event
	local blockHitAnimRemote = ReplicatedStorage:FindFirstChild("PlayBlockHitAnimation")
	if blockHitAnimRemote then
		blockHitAnimRemote:FireAllClients(defenderWCSCharacter.Instance)
	end

	-- Fire block hit VFX event
	local blockHitVFXRemote = ReplicatedStorage:FindFirstChild("PlayBlockHitVFX")
	if blockHitVFXRemote then
		blockHitVFXRemote:FireAllClients(defenderWCSCharacter.Instance)
	end

	-- TODO: Apply posture damage (defender +24%)
	print("[Punch] TODO: Apply posture damage for block")
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
	local fistsTrailPart = ReplicatedStorage.Assets.VFX.Weapon_Classes.Fists.fists_trail
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

-- Play swing SFX (client-only)
function Punch:_playSwingSFX()
	if not RunService:IsClient() then
		return
	end

	-- Get swing SFX folder
	local swingSFXFolder = ReplicatedStorage.Assets.SFX.Weapon_Classes.Fists.swings
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
	local interrupted = self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Parried })

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
end

return Punch
