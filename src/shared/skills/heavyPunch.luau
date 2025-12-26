--!strict
-- Heavy Punch Skill
-- A slower, more powerful fist attack with windup
-- Triggered by pressing R when using fists Test

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)
local CombatConfig = require(ReplicatedStorage.Shared.config.combatConfig)

-- SFXManager lazy-loaded on client only (for volume control)
local SFXManager = nil
local function getSFXManager()
	if SFXManager == nil and RunService:IsClient() then
		SFXManager = require(ReplicatedStorage.Client.managers.sfxManager)
	end
	return SFXManager
end

-- Pre-cache status effects at module load
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
local Parrying = require(ReplicatedStorage.Shared.statusEffects.parrying)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking)
local Iframes = require(ReplicatedStorage.Shared.statusEffects.iframes)
local Autoparry = require(ReplicatedStorage.Shared.statusEffects.autoparry)
local Parried = require(ReplicatedStorage.Shared.statusEffects.parried)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)

-- Pre-cache skill references
local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Block = require(ReplicatedStorage.Shared.skills.block)

-- Posture system (lazy loaded)
local PostureManager = nil
local function getPostureManager()
	if not PostureManager then
		PostureManager = require(ReplicatedStorage.Shared.managers.postureManager)
	end
	return PostureManager
end

local HeavyPunch = WCS.RegisterSkill("HeavyPunch")

-- WCS Client Prediction Configuration
HeavyPunch.CheckClientState = false
HeavyPunch.CheckOthersActive = false

-- Configuration (from central combatConfig)
local WeaponConfig = CombatConfig.Weapons.fists
local HeavyConfig = CombatConfig.HeavyAttacks
local SkillConfig = HeavyConfig.HeavyPunch

local HEAVY_DAMAGE = math.floor(WeaponConfig.Damage * HeavyConfig.DamageMultiplier)
local HEAVY_RANGE = SkillConfig.Range
local HEAVY_COOLDOWN = HeavyConfig.Cooldown

-- Hitbox configuration
local HIT_ANGLE_THRESHOLD = CombatConfig.Hitbox.HitAngleThreshold

-- Timing configuration
local WINDUP_DURATION = HeavyConfig.WindupDuration
local DAMAGE_DELAY = HeavyConfig.DamageDelay

-- Knockback configuration
local KNOCKBACK_POWER = SkillConfig.KnockbackPower
local KNOCKBACK_DURATION = HeavyConfig.KnockbackDuration

-- Endlag after crit completes (cannot attack during this time)
local ENDLAG_DURATION = 0.3

-- Animation ID for heavy punch
local HEAVY_ANIMATION_ID = "rbxassetid://105621431802545"

-- Animation IDs that should be stopped
local MOVEMENT_ANIMATION_IDS = {
	["rbxassetid://104453488066690"] = true,
}

local WALK_ANIM_SPEED_DURING_HEAVY = 0.3 -- Slows walk animation to match slowed movement

function HeavyPunch:OnConstructServer()
	self.hitTargets = {}
	self.attackingEffect = nil
	self.attackInvalidated = false -- Flag for trade prevention animation cleanup
end

function HeavyPunch:OnConstructClient()
	self.loadedAnimation = nil
	self.animationReady = false
	self.attackInvalidated = false -- Flag for trade prevention animation cleanup

	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = HEAVY_ANIMATION_ID
			self.loadedAnimation = animator:LoadAnimation(animation)
			self.animationReady = true

			task.spawn(function()
				ContentProvider:PreloadAsync({ animation })
				print("[HeavyPunch] Client: Animation preloaded")
			end)
		end
	end
end

function HeavyPunch:OnStartServer()
	-- Check equipment manager
	if not self.Character.EquipmentManager then
		return
	end

	if not self.Character.EquipmentManager:hasWeaponEquipped() then
		return
	end

	-- Check blocking status effects (includes Attacking to prevent move stacking)
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Guardbroken,
			Dashing,
			Blocking,
			Parrying,
			Attacking, -- Prevent stacking with M1
			Knockdown, -- Can't attack while knocked down
		})
	then
		return
	end

	print("[HeavyPunch] Server: Heavy punch activated!")

	self:ApplyCooldown(HEAVY_COOLDOWN)

	-- Apply HeavyAttacking status with configurable slowdown via SetHumanoidData
	-- This uses WCS's managed humanoid data system for reliable slowdown
	if self.attackingEffect then
		self.attackingEffect:Stop()
	end

	-- Get slowdown multiplier from config (per-skill configurable)
	local slowMultiplier = SkillConfig.SlowMultiplier or HeavyConfig.DefaultSlowMultiplier or 0.1

	self.attackingEffect = HeavyAttacking.new(self.Character)
	if self.attackingEffect then
		-- Pass slowdown via metadata
		self.attackingEffect:SetMetadata({ SlowMultiplier = slowMultiplier })
		self.attackingEffect:Start(DAMAGE_DELAY + ENDLAG_DURATION)
	end

	-- Broadcast parry flash AFTER windup (so parry window timing is correct)
	task.delay(WINDUP_DURATION, function()
		local parryFlashRemote = ReplicatedStorage:FindFirstChild("PlayParryFlashVFX")
		if parryFlashRemote then
			parryFlashRemote:FireAllClients(self.Character.Instance, 4) -- Use phase 4 style
		end
	end)

	-- Broadcast crit VFX to all clients
	local critVFXRemote = ReplicatedStorage:FindFirstChild("PlayCritVFX")
	if critVFXRemote then
		critVFXRemote:FireAllClients(self.Character.Instance, "heavyPunch")
	end

	-- Delayed hitbox detection
	task.delay(DAMAGE_DELAY, function()
		self:_detectHit()
	end)
end

function HeavyPunch:_stopMovementAnimations()
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

	self.originalWalkAnimSpeeds = self.originalWalkAnimSpeeds or {}

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation then
			local animId = track.Animation.AnimationId
			if MOVEMENT_ANIMATION_IDS[animId] then
				track:Stop(0.1)
			end
		end

		if track.Priority == Enum.AnimationPriority.Core or track.Priority == Enum.AnimationPriority.Movement then
			if not self.originalWalkAnimSpeeds[track] then
				self.originalWalkAnimSpeeds[track] = track.Speed
			end
			track:AdjustSpeed(WALK_ANIM_SPEED_DURING_HEAVY)
		end
	end
end

function HeavyPunch:_restoreMovementAnimations()
	if not RunService:IsClient() then
		return
	end

	if not self.originalWalkAnimSpeeds then
		return
	end

	for track, originalSpeed in pairs(self.originalWalkAnimSpeeds) do
		if track and track.IsPlaying then
			track:AdjustSpeed(originalSpeed)
		end
	end

	self.originalWalkAnimSpeeds = {}
end

function HeavyPunch:OnStartClient()
	-- Check if player is wall running (direct attribute check - status effect is client-side only)
	local character = self.Character.Instance
	if character:GetAttribute("IsWallRunning") then
		print("[HeavyPunch] Client: Blocked - Player is wall running")
		return
	end

	-- Check blocking status effects (server is authoritative, don't check Attacking here
	-- since this skill creates Attacking and it may replicate before OnStartClient runs)
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Dashing,
			Blocking,
			Parrying,
			Guardbroken,
			Knockdown, -- Can't attack while knocked down
		})
	then
		return
	end

	-- Stop any M1 (punch) animations that might be lingering
	local Punch = require(ReplicatedStorage.Shared.skills.punch)
	local punchSkill = self.Character:GetSkillFromConstructor(Punch)
	if punchSkill then
		-- Stop current animation track if playing
		if punchSkill.currentTrack and punchSkill.currentTrack.IsPlaying then
			punchSkill.currentTrack:Stop(0.05)
		end
		-- Also stop any loaded animations that might be playing
		if punchSkill.loadedAnimations then
			for _, track in pairs(punchSkill.loadedAnimations) do
				if track and track.IsPlaying then
					track:Stop(0.05)
				end
			end
		end
	end

	-- NOTE: Movement slowdown is handled server-side via HeavyAttacking status effect
	-- DO NOT set humanoid.WalkSpeed here - it conflicts with SetHumanoidData

	-- Play animation
	if self.loadedAnimation then
		self.loadedAnimation:Play(0.05)
		self.loadedAnimation.Priority = Enum.AnimationPriority.Action4
	end

	self:_stopMovementAnimations()

	-- Stop rollcancel animation if playing
	local dodgeSkill = self.Character:GetSkillFromConstructor(Dodge)
	if dodgeSkill and dodgeSkill.rollCancelTrack and dodgeSkill.rollCancelTrack.IsPlaying then
		dodgeSkill.rollCancelTrack:Stop(0.05)
		dodgeSkill.rollCancelTrack = nil
	end

	-- Apply VFX and SFX
	self:_applyHeavyVFX()
	self:_playHeavySFX()

	print("[HeavyPunch] Client: Playing heavy punch animation")
end

function HeavyPunch:_detectHit()
	if not RunService:IsServer() then
		return
	end

	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoidRootPart then
		return
	end

	local lookDirection = humanoidRootPart.CFrame.LookVector
	local origin = humanoidRootPart.Position - (lookDirection * 2)
	local hitTargets = {}

	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid")
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart")

			if targetHumanoid and targetHumanoid.Health > 0 and targetRootPart then
				-- Calculate direction and angle to target
				local directionToTarget = (targetRootPart.Position - origin).Unit
				local dotProduct = lookDirection:Dot(directionToTarget)

				-- Check if target is within attack cone angle
				if dotProduct > HIT_ANGLE_THRESHOLD then
					-- Calculate range falloff based on angle
					-- At center (dot = 1.0): 100% range
					-- At edge (dot = HIT_ANGLE_THRESHOLD): ~83% range
					local normalizedDot = (dotProduct - HIT_ANGLE_THRESHOLD) / (1.0 - HIT_ANGLE_THRESHOLD)
					-- Use squared falloff for more dramatic reduction at edges
					local rangeMultiplier = 0.831 + (0.169 * (normalizedDot * normalizedDot))
					local effectiveRange = HEAVY_RANGE * rangeMultiplier

					-- Check if target is within effective range
					local distance = (targetRootPart.Position - origin).Magnitude
					if distance <= effectiveRange then
						table.insert(hitTargets, { model = potentialTarget, humanoid = targetHumanoid })
					end
				end
			end
		end
	end

	local actualHits = {}
	for _, targetData in ipairs(hitTargets) do
		local hitResult = self:_hitTarget(targetData.model, targetData.humanoid)
		if hitResult then
			table.insert(actualHits, targetData)
		end
	end

	-- Fire hit effects
	if #actualHits > 0 then
		local hitEffectsRemote = ReplicatedStorage:FindFirstChild("PlayHitEffects")
		if hitEffectsRemote then
			hitEffectsRemote:FireAllClients(actualHits[1].model, "fists")
		end
	end
end

function HeavyPunch:_hitTarget(targetModel: Model, targetHumanoid: Humanoid)
	-- TRADE PREVENTION: Check if attacker got hit first (has hitstun)
	-- This is the key to preventing trading - first hit wins
	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Parried }) then
		print(`[HeavyPunch] Attack invalidated - {self.Character.Instance.Name} was hit first (has hitstun)`)
		-- Set flag so OnEndClient knows to force stop animations (status might not have replicated yet)
		self.attackInvalidated = true
		-- End the skill immediately to stop animations
		self:End()
		return false
	end

	if self.hitTargets[targetModel] then
		return false
	end

	-- Check if target is marked for execution (complete iframes)
	if targetModel:GetAttribute("MarkedForExecution") == true then
		print(`[HeavyPunch] Target {targetModel.Name} is marked for execution - No damage`)
		return false
	end

	local targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	if targetWCSCharacter then
		-- Check for iframes
		if targetWCSCharacter:HasStatusEffects({ Iframes }) then
			print(`[HeavyPunch] Target {targetModel.Name} has iframes`)

			local targetDodgeSkill = targetWCSCharacter:GetSkillFromConstructor(Dodge)
			if targetDodgeSkill then
				local dodgeState = targetDodgeSkill:GetState()
				if dodgeState.IsActive then
					targetDodgeSkill:End()
				end
			end

			local rollCancelRemote = ReplicatedStorage:FindFirstChild("PlayRollCancel")
			if rollCancelRemote then
				rollCancelRemote:FireAllClients(targetModel)
			end

			self:_cancelAttackMomentum()
			return false
		end

		-- Check for parry (heavy attacks can still be parried)
		if targetWCSCharacter:HasStatusEffects({ Parrying, Autoparry }) then
			print(`[HeavyPunch] Target {targetModel.Name} PARRIED!`)
			self:_handleParry(targetWCSCharacter)
			return false
		end

		-- Check if target is blocking (we'll use this to determine guardbreak vs knockback)
		-- Heavy attacks go through blocks but have different effects
	end

	-- Check if target was blocking BEFORE we hit them
	local wasBlocking = targetWCSCharacter and targetWCSCharacter:HasStatusEffects({ Blocking })

	self.hitTargets[targetModel] = true

	print(`[HeavyPunch] Heavy hit on: {targetModel.Name}! (was blocking: {wasBlocking})`)

	targetHumanoid:TakeDamage(HEAVY_DAMAGE)

	-- Combat tag the target (PvP only)
	if _G.CombatTagManager then
		local attackerPlayer = Players:GetPlayerFromCharacter(self.Character.Instance)
		local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
		if attackerPlayer and targetPlayer then
			_G.CombatTagManager:tagPlayer(targetPlayer, attackerPlayer)
		end
	end

	if not targetWCSCharacter then
		targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	end

	if targetWCSCharacter then
		-- Apply soft hitstun (0.2s longer than M1 for fist crit)
		local critHitstunDuration = WeaponConfig.HitstunDuration + 0.2
		local hitstun = SoftHitstun.new(targetWCSCharacter)
		if hitstun then
			hitstun:Start(critHitstunDuration)
			print(`[HeavyPunch] Applied SoftHitstun ({critHitstunDuration}s) to {targetModel.Name}`)
		end

		-- Cancel target's attacks
		local Punch = require(ReplicatedStorage.Shared.skills.punch)
		local targetPunchSkill = targetWCSCharacter:GetSkillFromConstructor(Punch)
		if targetPunchSkill then
			local punchState = targetPunchSkill:GetState()
			if punchState.IsActive then
				targetPunchSkill:End()
			end
		end

		if wasBlocking then
			-- TARGET WAS BLOCKING: Guardbreak (combo starter), no knockback
			-- End block skill first
			local targetBlockSkill = targetWCSCharacter:GetSkillFromConstructor(Block)
			if targetBlockSkill then
				local blockState = targetBlockSkill:GetState()
				if blockState.IsActive then
					targetBlockSkill:End()
				end
			end

			-- Apply guardbreak
			local guardbrokenEffect = Guardbroken.new(targetWCSCharacter)
			if guardbrokenEffect then
				guardbrokenEffect:Start(HeavyConfig.GuardbreakDuration)
				print(`[HeavyPunch] Broke {targetModel.Name}'s block! Guardbroken for combo.`)
			end
		else
			-- TARGET WAS NOT BLOCKING: Knockback (spacing tool), no guardbreak
			local targetRootPart = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
			local attackerRootPart = self.Character.Instance:FindFirstChild("HumanoidRootPart") :: BasePart?
			local knockbackTargetHumanoid = targetModel:FindFirstChild("Humanoid") :: Humanoid?

			-- Skip knockback if target is knocked down (ragdolled)
			if knockbackTargetHumanoid and knockbackTargetHumanoid.PlatformStand then
				print(`[HeavyPunch] Skipping knockback - {targetModel.Name} is knocked down`)
			elseif targetRootPart and attackerRootPart then
				local knockbackDirection = (targetRootPart.Position - attackerRootPart.Position).Unit
				local knockbackVelocity =
					Vector3.new(knockbackDirection.X * KNOCKBACK_POWER, 5, knockbackDirection.Z * KNOCKBACK_POWER)

				local bodyVelocity = Instance.new("BodyVelocity")
				bodyVelocity.MaxForce = Vector3.new(50000, 5000, 50000)
				bodyVelocity.Velocity = knockbackVelocity
				bodyVelocity.Parent = targetRootPart

				game:GetService("Debris"):AddItem(bodyVelocity, KNOCKBACK_DURATION)
				print(`[HeavyPunch] Knocked back {targetModel.Name}!`)
			end
		end
	end

	return true
end

function HeavyPunch:_handleParry(defenderWCSCharacter)
	local blockSkill = defenderWCSCharacter:GetSkillFromConstructor(Block)
	if blockSkill then
		local blockState = blockSkill:GetState()
		if blockState.IsActive then
			blockSkill:End()
		end
		blockSkill.lastBlockEndTime = 0
		blockSkill.parryOnCooldown = false
	end

	local autoparryEffect = Autoparry.new(defenderWCSCharacter)
	if autoparryEffect then
		autoparryEffect:Start(CombatConfig.StatusDurations.Autoparry)
	end

	local softHitstunEffect = SoftHitstun.new(self.Character)
	if softHitstunEffect then
		softHitstunEffect:Start(CombatConfig.StatusDurations.HeavyParriedHitstun)
	end

	if self.attackingEffect then
		self.attackingEffect:Stop()
		self.attackingEffect = nil
	end

	local parriedEffect = Parried.new(self.Character)
	if parriedEffect then
		parriedEffect:Start(CombatConfig.StatusDurations.HeavyParriedHitstun)
	end

	local parryVFXRemote = ReplicatedStorage:FindFirstChild("PlayParryVFX")
	if parryVFXRemote then
		parryVFXRemote:FireAllClients(defenderWCSCharacter.Instance)
	end

	local parriedAnimRemote = ReplicatedStorage:FindFirstChild("PlayParriedAnimation")
	if parriedAnimRemote then
		parriedAnimRemote:FireAllClients(self.Character.Instance)
	end

	local postureManager = getPostureManager()
	postureManager.addPostureCapped(self.Character.Instance, postureManager.getParriedPostureDamage())
	postureManager.removePosture(defenderWCSCharacter.Instance, postureManager.getParryPostureReward())
end

function HeavyPunch:_applyHeavyVFX()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	-- Get VFX folder from Criticals
	local vfxFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Weapon_Classes")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes:FindFirstChild("Criticals")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals:FindFirstChild("Light_Weapons")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals.Light_Weapons:FindFirstChild("heavyPunch")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals.Light_Weapons.heavyPunch:FindFirstChild("vfx")

	if not vfxFolder then
		warn("[HeavyPunch] VFX folder not found at Assets.VFX.Weapon_Classes.Criticals.Light_Weapons.heavyPunch.vfx")
		return
	end

	local animLength = self.loadedAnimation and self.loadedAnimation.Length or 0.7
	local clonedAttachments = {} -- Track all cloned attachments for cleanup

	-- Process VFX_attachment (particles on HumanoidRootPart)
	local vfxAttachment = vfxFolder:FindFirstChild("VFX_attachment")
	if vfxAttachment and vfxAttachment:IsA("Attachment") then
		local attachmentClone = vfxAttachment:Clone()
		attachmentClone.Parent = humanoidRootPart
		table.insert(clonedAttachments, attachmentClone)

		-- Process all particle emitters - emit based on their attributes
		for _, emitter in ipairs(attachmentClone:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				-- Keep disabled - we'll manually emit
				emitter.Enabled = false

				-- Read attributes for timing
				local emitDelay = emitter:GetAttribute("EmitDelay") or 0
				local emitCount = emitter:GetAttribute("EmitCount") or emitter.Rate

				-- Emit at the specified delay time
				if emitDelay > 0 then
					task.delay(emitDelay, function()
						if emitter and emitter.Parent then
							emitter:Emit(emitCount)
						end
					end)
				else
					-- Emit immediately if no delay
					emitter:Emit(emitCount)
				end
			end
		end
	end

	-- Process limb-based folders (e.g., "Left Leg", "Right Arm", etc.)
	for _, child in ipairs(vfxFolder:GetChildren()) do
		if child:IsA("Folder") then
			local limbName = child.Name
			local limbPart = character:FindFirstChild(limbName)

			if limbPart then
				-- Get the first Attachment child from the folder
				local attachmentTemplate = child:FindFirstChildOfClass("Attachment")
				if attachmentTemplate then
					local attachmentClone = attachmentTemplate:Clone()
					attachmentClone.Parent = limbPart
					table.insert(clonedAttachments, attachmentClone)

					-- Process trails with start/end timing attributes
					for _, trailChild in ipairs(attachmentClone:GetChildren()) do
						if trailChild:IsA("Trail") then
							local startTime = trailChild:GetAttribute("start")
							local endTime = trailChild:GetAttribute("end")

							-- Start disabled
							trailChild.Enabled = false

							-- Enable at start time
							if startTime and startTime > 0 then
								task.delay(startTime, function()
									if trailChild and trailChild.Parent then
										trailChild.Enabled = true
									end
								end)
							else
								-- No start time means enable immediately
								trailChild.Enabled = true
							end

							-- Disable at end time
							if endTime and endTime > 0 then
								task.delay(endTime, function()
									if trailChild and trailChild.Parent then
										trailChild.Enabled = false
									end
								end)
							end
						end
					end
				end
			end
		end
	end

	-- Cleanup all cloned attachments after animation
	task.delay(animLength + 0.5, function()
		for _, attachment in ipairs(clonedAttachments) do
			if attachment and attachment.Parent then
				attachment:Destroy()
			end
		end
	end)
end

function HeavyPunch:_playHeavySFX()
	if not RunService:IsClient() then
		return
	end

	local animLength = self.loadedAnimation and self.loadedAnimation.Length or 0.7
	local sfxDelay = animLength * 0.35 -- Later in the animation due to windup

	task.delay(sfxDelay, function()
		local swingSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
			and ReplicatedStorage.Assets:FindFirstChild("SFX")
			and ReplicatedStorage.Assets.SFX:FindFirstChild("Weapon_Classes")
			and ReplicatedStorage.Assets.SFX.Weapon_Classes:FindFirstChild("Light_Weapons")
			and ReplicatedStorage.Assets.SFX.Weapon_Classes.Light_Weapons:FindFirstChild("Fists")
			and ReplicatedStorage.Assets.SFX.Weapon_Classes.Light_Weapons.Fists:FindFirstChild("swings")

		if not swingSFXFolder then
			return
		end

		local sounds = {}
		for _, child in ipairs(swingSFXFolder:GetChildren()) do
			if child:IsA("Sound") then
				table.insert(sounds, child)
			end
		end

		if #sounds == 0 then
			return
		end

		local randomSound = sounds[math.random(1, #sounds)]

		local character = self.Character.Instance
		if not character then
			return
		end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		local soundClone = randomSound:Clone()
		-- Route through SFX volume control
		local sfxManager = getSFXManager()
		if sfxManager then
			soundClone.SoundGroup = sfxManager.getSoundGroup()
		end
		soundClone.Parent = rootPart
		soundClone:Play()

		task.delay(soundClone.TimeLength + 0.1, function()
			if soundClone and soundClone.Parent then
				soundClone:Destroy()
			end
		end)
	end)
end

function HeavyPunch:_cancelAttackMomentum()
	if not RunService:IsServer() then
		return
	end

	local character = self.Character.Instance
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	for _, child in ipairs(rootPart:GetChildren()) do
		if child:IsA("BodyVelocity") or child:IsA("BodyPosition") or child:IsA("BodyGyro") then
			child:Destroy()
		end
	end

	if rootPart:IsA("BasePart") then
		rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
	end

	if self.attackingEffect then
		self.attackingEffect:Stop()
		self.attackingEffect = nil
	end
end

function HeavyPunch:OnEndServer()
	self.hitTargets = {}
	-- WalkSpeed restoration is handled automatically by HeavyAttacking status via SetHumanoidData
end

function HeavyPunch:OnEndClient()
	self:_restoreMovementAnimations()

	-- NOTE: Movement speed restoration is handled server-side via HeavyAttacking status effect
	-- DO NOT restore humanoid.WalkSpeed here - it conflicts with SetHumanoidData

	-- Also check attackInvalidated flag (trade prevention - status might not have replicated yet)
	local interrupted = self.attackInvalidated or self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Parried })

	if interrupted then
		if self.loadedAnimation and self.loadedAnimation.IsPlaying then
			self.loadedAnimation:Stop(0.05)
			print("[HeavyPunch] Client: Stopped animation due to interrupt")
		end
	end

	-- Reset the flag for next attack
	self.attackInvalidated = false
end

return HeavyPunch
