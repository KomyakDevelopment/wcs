--!strict
-- Heavy Slam Skill
-- A powerful two-hit critical attack for heavy weapons (kubikiribocho)
-- Triggered by pressing R when using a heavy weapon

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
local BlockStunned = require(ReplicatedStorage.Shared.statusEffects.blockStunned)
local WallRunning = require(ReplicatedStorage.Shared.statusEffects.wallRunning)
local Daze = require(ReplicatedStorage.Shared.statusEffects.daze)

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

local HeavySlam = WCS.RegisterSkill("HeavySlam")

-- WCS Client Prediction Configuration
HeavySlam.CheckClientState = false
HeavySlam.CheckOthersActive = false

-- Configuration (from central combatConfig)
local HeavyConfig = CombatConfig.HeavyAttacks
local HEAVY_COOLDOWN = HeavyConfig.Cooldown

-- Hitbox configuration
local HIT_ANGLE_THRESHOLD = CombatConfig.Hitbox.HitAngleThreshold

-- Timing configuration for 2-hit slam
local WINDUP_DURATION = HeavyConfig.WindupDuration
local HIT1_TIMING = 0.73 -- First hit timing
local HIT2_TIMING = 1.82 -- Second hit timing
local HIT1_DAMAGE = 3 -- First hit damage
local HIT2_DAMAGE = 18 -- Second hit damage

-- Endlag after crit completes
local ENDLAG_DURATION = 0.3

-- Animation ID for heavy slam (kubikiribocho critical)
local HEAVY_ANIMATION_ID = "rbxassetid://99528458324912"

-- Animation IDs that should be stopped
local MOVEMENT_ANIMATION_IDS = {
	["rbxassetid://104453488066690"] = true,
}

local WALK_ANIM_SPEED_DURING_HEAVY = 0.3

-- Default weapon for fallback
local DEFAULT_WEAPON = "kubikiribocho"

-- Helper to get weapon config dynamically
local function getWeaponConfig(weaponType: string)
	return CombatConfig.Weapons[weaponType] or CombatConfig.Weapons[DEFAULT_WEAPON]
end

function HeavySlam:OnConstructServer()
	self.hitTargetsHit1 = {} -- Targets hit by first swing
	self.hitTargetsHit2 = {} -- Targets hit by second swing
	self.attackingEffect = nil
	self.attackInvalidated = false
	self.currentWeaponType = DEFAULT_WEAPON
end

function HeavySlam:OnConstructClient()
	self.loadedAnimation = nil
	self.animationReady = false
	self.attackInvalidated = false

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
				print("[HeavySlam] Client: Animation preloaded")
			end)
		end
	end
end

function HeavySlam:OnStartServer()
	-- Check equipment manager
	if not self.Character.EquipmentManager then
		return
	end

	if not self.Character.EquipmentManager:hasWeaponEquipped() then
		return
	end

	-- Check if weapon is in hand (not just on back)
	if not self.Character.EquipmentManager:isWeaponInHand() then
		print("[HeavySlam] Blocked - Weapon not in hand")
		return
	end

	-- Check blocking status effects
	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Guardbroken,
			Dashing,
			Blocking,
			Parrying,
			Attacking,
			Knockdown,
			WallRunning,
		})
	then
		return
	end

	-- Get weapon type and config
	self.currentWeaponType = self:_getCurrentWeaponType()

	print(`[HeavySlam] Server: Heavy slam activated with {self.currentWeaponType}!`)

	self:ApplyCooldown(HEAVY_COOLDOWN)

	-- Apply HeavyAttacking status
	if self.attackingEffect then
		self.attackingEffect:Stop()
	end

	local slowMultiplier = HeavyConfig.DefaultSlowMultiplier or 0.1

	self.attackingEffect = HeavyAttacking.new(self.Character)
	if self.attackingEffect then
		self.attackingEffect:SetMetadata({ SlowMultiplier = slowMultiplier })
		self.attackingEffect:Start(HIT2_TIMING + ENDLAG_DURATION)
	end

	-- Broadcast parry flash AFTER windup
	task.delay(WINDUP_DURATION, function()
		local parryFlashRemote = ReplicatedStorage:FindFirstChild("PlayParryFlashVFX")
		if parryFlashRemote then
			parryFlashRemote:FireAllClients(self.Character.Instance, 4)
		end
	end)

	-- Broadcast crit VFX
	local critVFXRemote = ReplicatedStorage:FindFirstChild("PlayCritVFX")
	if critVFXRemote then
		critVFXRemote:FireAllClients(self.Character.Instance, "heavySlam")
	end

	-- First hit detection
	task.delay(HIT1_TIMING, function()
		self:_detectHit(1, HIT1_DAMAGE)
	end)

	-- Second hit detection
	task.delay(HIT2_TIMING, function()
		self:_detectHit(2, HIT2_DAMAGE)
	end)
end

function HeavySlam:_stopMovementAnimations()
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

function HeavySlam:_restoreMovementAnimations()
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

function HeavySlam:OnStartClient()
	if self.loadedAnimation and self.loadedAnimation.IsPlaying then
		return
	end

	-- Check if player is wall running
	local character = self.Character.Instance
	if character:GetAttribute("IsWallRunning") then
		print("[HeavySlam] Client: Blocked - Player is wall running")
		return
	end

	if
		self.Character:HasStatusEffects({
			SoftHitstun,
			TrueHitstun,
			Stun,
			Dashing,
			Blocking,
			Parrying,
			Guardbroken,
			Knockdown,
		})
	then
		return
	end

	-- Stop any M1 (slash) animations
	local Slash = require(ReplicatedStorage.Shared.skills.slash)
	local slashSkill = self.Character:GetSkillFromConstructor(Slash)
	if slashSkill then
		if slashSkill.currentTrack and slashSkill.currentTrack.IsPlaying then
			slashSkill.currentTrack:Stop(0.05)
		end
		if slashSkill.loadedAnimations then
			for _, weaponAnims in pairs(slashSkill.loadedAnimations) do
				for _, track in pairs(weaponAnims) do
					if track and track.IsPlaying then
						track:Stop(0.05)
					end
				end
			end
		end
	end

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
	self:_applyWeaponTrail()
	self:_playHeavySFX()
	self:_applyHeavyVFX()

	print("[HeavySlam] Client: Playing heavy slam animation")
end

function HeavySlam:_getClientWeaponType(): string
	local characterInstance = self.Character.Instance
	for _, child in ipairs(characterInstance:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "_Equipped") then
			local weaponName = string.gsub(child.Name, "_Equipped", "")
			return string.lower(weaponName)
		end
	end
	return "kubikiribocho"
end

function HeavySlam:_getCurrentWeaponType(): string
	if self.Character.EquipmentManager then
		local equipped = self.Character.EquipmentManager:getEquipped()
		if equipped then
			return equipped
		end
	end
	return "kubikiribocho"
end

function HeavySlam:_detectHit(hitNumber: number, damage: number)
	if not RunService:IsServer() then
		return
	end

	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoidRootPart then
		return
	end

	local weaponConfig = getWeaponConfig(self.currentWeaponType)
	local HEAVY_RANGE = weaponConfig.Range

	local lookDirection = humanoidRootPart.CFrame.LookVector
	local origin = humanoidRootPart.Position - (lookDirection * 2)
	local hitTargets = {}

	-- Get the appropriate hit tracking table
	local hitTrackingTable = if hitNumber == 1 then self.hitTargetsHit1 else self.hitTargetsHit2

	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid")
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart")

			if targetHumanoid and targetHumanoid.Health > 0 and targetRootPart then
				local directionToTarget = (targetRootPart.Position - origin).Unit
				local dotProduct = lookDirection:Dot(directionToTarget)

				if dotProduct > HIT_ANGLE_THRESHOLD then
					local normalizedDot = (dotProduct - HIT_ANGLE_THRESHOLD) / (1.0 - HIT_ANGLE_THRESHOLD)
					local rangeMultiplier = 0.831 + (0.169 * (normalizedDot * normalizedDot))
					local effectiveRange = HEAVY_RANGE * rangeMultiplier

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
		local hitResult = self:_hitTarget(targetData.model, targetData.humanoid, hitNumber, damage, hitTrackingTable)
		if hitResult then
			table.insert(actualHits, targetData)
		end
	end

	if #actualHits > 0 then
		local hitEffectsRemote = ReplicatedStorage:FindFirstChild("PlayHitEffects")
		local gotHitAnimRemote = ReplicatedStorage:FindFirstChild("PlayGotHitAnimation")
		if hitEffectsRemote then
			local weaponType = self:_getCurrentWeaponType()
			for _, targetData in ipairs(actualHits) do
				hitEffectsRemote:FireAllClients(targetData.model, weaponType)
				-- Fire got-hit animation on the target
				if gotHitAnimRemote then
					gotHitAnimRemote:FireAllClients(targetData.model)
				end
			end
		end
	end
end

function HeavySlam:_hitTarget(targetModel: Model, targetHumanoid: Humanoid, hitNumber: number, damage: number, hitTrackingTable: { [Model]: boolean })
	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Parried }) then
		print(`[HeavySlam] Attack invalidated - {self.Character.Instance.Name} was hit first`)
		self.attackInvalidated = true
		self:End()
		return false
	end

	-- Check if already hit by this specific hit
	if hitTrackingTable[targetModel] then
		return false
	end

	if targetModel:GetAttribute("MarkedForExecution") == true then
		print(`[HeavySlam] Target {targetModel.Name} is marked for execution - No damage`)
		return false
	end

	local targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	if targetWCSCharacter then
		if targetWCSCharacter:HasStatusEffects({ Iframes }) then
			print(`[HeavySlam] Target {targetModel.Name} has iframes`)

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

		if targetWCSCharacter:HasStatusEffects({ Parrying, Autoparry }) then
			print(`[HeavySlam] Target {targetModel.Name} PARRIED!`)
			self:_handleParry(targetWCSCharacter)
			return false
		end

		if targetWCSCharacter:HasStatusEffects({ Blocking }) then
			print(`[HeavySlam] Target {targetModel.Name} BLOCKED!`)
			hitTrackingTable[targetModel] = true

			local postureManager = getPostureManager()
			local postureDamage = CombatConfig.Posture.BlockDamage * CombatConfig.Posture.HeavyBlockDamageMultiplier
			postureManager.addPosture(targetModel, postureDamage)

			local blockStunnedEffect = BlockStunned.new(targetWCSCharacter)
			if blockStunnedEffect then
				blockStunnedEffect:Start(CombatConfig.StatusDurations.BlockStunned)
			end

			local blockHitAnimRemote = ReplicatedStorage:FindFirstChild("PlayBlockHitAnimation")
			if blockHitAnimRemote then
				blockHitAnimRemote:FireAllClients(targetModel)
			end

			local blockHitVFXRemote = ReplicatedStorage:FindFirstChild("PlayBlockHitVFX")
			if blockHitVFXRemote then
				blockHitVFXRemote:FireAllClients(targetModel)
			end

			return false
		end
	end

	hitTrackingTable[targetModel] = true

	print(`[HeavySlam] Hit {hitNumber} on: {targetModel.Name} for {damage} damage!`)

	targetHumanoid:TakeDamage(damage)

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
		local weaponConfig = getWeaponConfig(self.currentWeaponType)
		local hitstun = SoftHitstun.new(targetWCSCharacter)
		if hitstun then
			hitstun:Start(weaponConfig.HitstunDuration)
			print(`[HeavySlam] Applied SoftHitstun ({weaponConfig.HitstunDuration}s) to {targetModel.Name}`)
		end

		-- Apply Daze on first hit only (disables rolling, slows walkspeed)
		print(`[HeavySlam] Hit number: {hitNumber}, checking for Daze application...`)
		if hitNumber == 1 then
			print(`[HeavySlam] First hit detected, creating Daze for {targetModel.Name}`)
			local dazeEffect = Daze.new(targetWCSCharacter)
			print(`[HeavySlam] Daze.new() returned: {dazeEffect and "SUCCESS" or "NIL"}`)
			if dazeEffect then
				dazeEffect:Start(1.5) -- 1.5 second daze
				print(`[HeavySlam] Applied Daze (1.5s) to {targetModel.Name}`)
			else
				warn(`[HeavySlam] Failed to create Daze effect for {targetModel.Name}`)
			end
		else
			print(`[HeavySlam] Not first hit (hitNumber={hitNumber}), skipping Daze`)
		end

		local Slash = require(ReplicatedStorage.Shared.skills.slash)
		local targetSlashSkill = targetWCSCharacter:GetSkillFromConstructor(Slash)
		if targetSlashSkill then
			local slashState = targetSlashSkill:GetState()
			if slashState.IsActive then
				targetSlashSkill:End()
			end
		end
	end

	return true
end

function HeavySlam:_handleParry(defenderWCSCharacter)
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

function HeavySlam:_applyWeaponTrail()
	if not RunService:IsClient() then
		return
	end

	local characterInstance = self.Character.Instance
	local weaponModel = nil

	for _, child in ipairs(characterInstance:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "_Equipped") then
			weaponModel = child
			break
		end
	end

	if not weaponModel then
		return
	end

	local gripPart = weaponModel:FindFirstChild("Grip")
	if not gripPart then
		return
	end

	local trail0 = gripPart:FindFirstChild("trail0")
	if not trail0 then
		return
	end

	local trail1 = trail0:FindFirstChild("trail1") or gripPart:FindFirstChild("trail1")
	if not trail1 then
		return
	end

	local trail = gripPart:FindFirstChildOfClass("Trail") or trail0:FindFirstChildOfClass("Trail")
	if trail then
		trail.Enabled = true

		local animLength = self.loadedAnimation and self.loadedAnimation.Length or 2.0
		task.delay(animLength * 0.9, function()
			if trail and trail.Parent then
				trail.Enabled = false
			end
		end)
	end
end

function HeavySlam:_playHeavySFX()
	if not RunService:IsClient() then
		return
	end

	local animLength = self.loadedAnimation and self.loadedAnimation.Length or 2.0
	local sfxDelay = animLength * 0.25

	task.delay(sfxDelay, function()
		local weaponType = self:_getClientWeaponType()
		local weaponCategory = "Heavy_Weapons"
		local weaponFolderName = string.upper(string.sub(weaponType, 1, 1)) .. string.sub(weaponType, 2)

		local swingSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
			and ReplicatedStorage.Assets:FindFirstChild("SFX")
			and ReplicatedStorage.Assets.SFX:FindFirstChild("Weapon_Classes")
			and ReplicatedStorage.Assets.SFX.Weapon_Classes:FindFirstChild(weaponCategory)
			and ReplicatedStorage.Assets.SFX.Weapon_Classes[weaponCategory]:FindFirstChild(weaponFolderName)
			and ReplicatedStorage.Assets.SFX.Weapon_Classes[weaponCategory][weaponFolderName]:FindFirstChild("swings")

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

function HeavySlam:_applyHeavyVFX()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	-- Get VFX folder for critical attack
	local vfxFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Weapon_Classes")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes:FindFirstChild("Criticals")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals:FindFirstChild("Heavy_Weapons")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals.Heavy_Weapons:FindFirstChild("heavySlam")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals.Heavy_Weapons.heavySlam:FindFirstChild("vfx")

	if not vfxFolder then
		return
	end

	local animLength = self.loadedAnimation and self.loadedAnimation.Length or 2.0
	local clonedAttachments = {}

	local vfxAttachment = vfxFolder:FindFirstChild("VFX_attachment")
	if vfxAttachment and vfxAttachment:IsA("Attachment") then
		local attachmentClone = vfxAttachment:Clone()
		attachmentClone.Parent = humanoidRootPart
		table.insert(clonedAttachments, attachmentClone)

		for _, emitter in ipairs(attachmentClone:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = false
				local emitDelay = emitter:GetAttribute("EmitDelay") or 0
				local emitCount = emitter:GetAttribute("EmitCount") or emitter.Rate
				if emitDelay > 0 then
					task.delay(emitDelay, function()
						if emitter and emitter.Parent then
							emitter:Emit(emitCount)
						end
					end)
				else
					emitter:Emit(emitCount)
				end
			end
		end

		for _, beam in ipairs(attachmentClone:GetDescendants()) do
			if beam:IsA("Beam") then
				beam.Enabled = false
				local duration = beam:GetAttribute("Duration") or 0.15

				-- First hit beam
				task.delay(HIT1_TIMING, function()
					if beam and beam.Parent then
						beam.Enabled = true
						task.delay(duration, function()
							if beam and beam.Parent then
								beam.Enabled = false
							end
						end)
					end
				end)

				-- Second hit beam
				task.delay(HIT2_TIMING, function()
					if beam and beam.Parent then
						beam.Enabled = true
						task.delay(duration, function()
							if beam and beam.Parent then
								beam.Enabled = false
							end
						end)
					end
				end)
			end
		end
	end

	task.delay(animLength + 0.5, function()
		for _, attachment in ipairs(clonedAttachments) do
			if attachment and attachment.Parent then
				attachment:Destroy()
			end
		end
	end)
end

function HeavySlam:_cancelAttackMomentum()
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

function HeavySlam:OnEndServer()
	self.hitTargetsHit1 = {}
	self.hitTargetsHit2 = {}
end

function HeavySlam:OnEndClient()
	self:_restoreMovementAnimations()

	local interrupted = self.attackInvalidated or self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Parried })

	if interrupted then
		if self.loadedAnimation and self.loadedAnimation.IsPlaying then
			self.loadedAnimation:Stop(0.05)
			print("[HeavySlam] Client: Stopped animation due to interrupt")
		end
	end

	self.attackInvalidated = false
end

return HeavySlam
