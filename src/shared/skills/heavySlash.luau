--!strict
-- Heavy Slash Skill
-- A slower, more powerful weapon attack with windup
-- Triggered by pressing R when using a weapon (kunai, etc.)

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)
local CombatConfig = require(ReplicatedStorage.Shared.config.combatConfig)

-- Pre-cache status effects at module load
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

local HeavySlash = WCS.RegisterSkill("HeavySlash")

-- WCS Client Prediction Configuration
HeavySlash.CheckClientState = false
HeavySlash.CheckOthersActive = false

-- Configuration (from central combatConfig)
local WeaponConfig = CombatConfig.Weapons.kunai
local HeavyConfig = CombatConfig.HeavyAttacks
local SkillConfig = HeavyConfig.HeavySlash

local HEAVY_DAMAGE = math.floor(WeaponConfig.Damage * 0.8)
local HEAVY_RANGE = SkillConfig.Range
local HEAVY_COOLDOWN = HeavyConfig.Cooldown

-- Hitbox configuration
local HIT_ANGLE_THRESHOLD = CombatConfig.Hitbox.HitAngleThreshold

-- Timing configuration
local WINDUP_DURATION = HeavyConfig.WindupDuration
-- Two-slash timing (times from animation start)
local SLASH_1_TIMING = 0.60 -- First slash
local SLASH_2_TIMING = 0.83 -- Second slash

-- Endlag after crit completes (cannot attack during this time)
local ENDLAG_DURATION = 0.3

-- Animation ID for heavy slash (placeholder - replace with actual heavy slash anim)
local HEAVY_ANIMATION_ID = "rbxassetid://136860865307002" -- Using flourish for now

-- Animation IDs that should be stopped
local MOVEMENT_ANIMATION_IDS = {
	["rbxassetid://104453488066690"] = true,
}

local WALK_ANIM_SPEED_DURING_HEAVY = 0.3

function HeavySlash:OnConstructServer()
	self.hitTargets = {}
	self.attackingEffect = nil
end

function HeavySlash:OnConstructClient()
	self.loadedAnimation = nil
	self.animationReady = false

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
				print("[HeavySlash] Client: Animation preloaded")
			end)
		end
	end
end

function HeavySlash:OnStartServer()
	-- Check equipment manager
	if not self.Character.EquipmentManager then
		return
	end

	if not self.Character.EquipmentManager:hasWeaponEquipped() then
		return
	end

	-- Check if weapon is in hand (not just on back)
	if not self.Character.EquipmentManager:isWeaponInHand() then
		print("[HeavySlash] Blocked - Weapon not in hand")
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

	print("[HeavySlash] Server: Heavy slash activated!")

	self:ApplyCooldown(HEAVY_COOLDOWN)

	-- Apply Attacking status (includes endlag after second slash)
	if self.attackingEffect then
		self.attackingEffect:Stop()
	end
	self.attackingEffect = Attacking.new(self.Character)
	if self.attackingEffect then
		self.attackingEffect:Start(SLASH_2_TIMING + ENDLAG_DURATION)
	end

	-- Broadcast parry flash AFTER windup (so parry window timing is correct)
	task.delay(WINDUP_DURATION, function()
		local parryFlashRemote = ReplicatedStorage:FindFirstChild("PlayParryFlashVFX")
		if parryFlashRemote then
			parryFlashRemote:FireAllClients(self.Character.Instance, 4) -- Use phase 4 style
		end
	end)

	-- First slash hit detection
	task.delay(SLASH_1_TIMING, function()
		self:_detectHit()
	end)

	-- Second slash hit detection (reset hitTargets so same target can be hit twice)
	task.delay(SLASH_2_TIMING, function()
		self.hitTargets = {} -- Reset so second slash can hit same targets
		self:_detectHit()
	end)
end

function HeavySlash:_stopMovementAnimations()
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

function HeavySlash:_restoreMovementAnimations()
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

function HeavySlash:OnStartClient()
	-- Include Attacking to prevent move stacking on client
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

	-- Stop any M1 (slash) animations that might be lingering
	local Slash = require(ReplicatedStorage.Shared.skills.slash)
	local slashSkill = self.Character:GetSkillFromConstructor(Slash)
	if slashSkill then
		-- Stop current animation track if playing
		if slashSkill.currentTrack and slashSkill.currentTrack.IsPlaying then
			slashSkill.currentTrack:Stop(0.05)
		end
		-- Also stop any loaded animations that might be playing
		if slashSkill.loadedAnimations then
			for _, track in pairs(slashSkill.loadedAnimations) do
				if track and track.IsPlaying then
					track:Stop(0.05)
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

	print("[HeavySlash] Client: Playing heavy slash animation")
end

-- Get the current weapon type from equipped weapon model
function HeavySlash:_getClientWeaponType(): string
	local characterInstance = self.Character.Instance
	for _, child in ipairs(characterInstance:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "_Equipped") then
			local weaponName = string.gsub(child.Name, "_Equipped", "")
			return weaponName
		end
	end
	return "Kunai" -- Default
end

-- Get the current weapon type on server
function HeavySlash:_getCurrentWeaponType(): string
	if self.Character.EquipmentManager then
		local equipped = self.Character.EquipmentManager:getEquipped()
		if equipped then
			return equipped
		end
	end
	return "kunai"
end

function HeavySlash:_detectHit()
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
				local distance = (targetRootPart.Position - origin).Magnitude

				if distance <= HEAVY_RANGE then
					local directionToTarget = (targetRootPart.Position - origin).Unit
					local dotProduct = lookDirection:Dot(directionToTarget)

					if dotProduct > HIT_ANGLE_THRESHOLD then
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

	-- Fire hit effects with weapon type
	if #actualHits > 0 then
		local hitEffectsRemote = ReplicatedStorage:FindFirstChild("PlayHitEffects")
		if hitEffectsRemote then
			local weaponType = self:_getCurrentWeaponType()
			hitEffectsRemote:FireAllClients(actualHits[1].model, weaponType)
		end
	end
end

function HeavySlash:_hitTarget(targetModel: Model, targetHumanoid: Humanoid)
	if self.hitTargets[targetModel] then
		return false
	end

	-- Check if target is marked for execution (complete iframes)
	if targetModel:GetAttribute("MarkedForExecution") == true then
		print(`[HeavySlash] Target {targetModel.Name} is marked for execution - No damage`)
		return false
	end

	local targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	if targetWCSCharacter then
		-- Check for iframes
		if targetWCSCharacter:HasStatusEffects({ Iframes }) then
			print(`[HeavySlash] Target {targetModel.Name} has iframes`)

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
			print(`[HeavySlash] Target {targetModel.Name} PARRIED!`)
			self:_handleParry(targetWCSCharacter)
			return false
		end

		-- Check if target is blocking (we'll use this to determine guardbreak vs knockback)
		-- Heavy attacks go through blocks but have different effects
	end

	-- Check if target was blocking BEFORE we hit them
	local wasBlocking = targetWCSCharacter and targetWCSCharacter:HasStatusEffects({ Blocking })

	self.hitTargets[targetModel] = true

	print(`[HeavySlash] Heavy hit on: {targetModel.Name}! (was blocking: {wasBlocking})`)

	targetHumanoid:TakeDamage(HEAVY_DAMAGE)

	if not targetWCSCharacter then
		targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	end

	if targetWCSCharacter then
		-- Cancel target's attacks
		local Slash = require(ReplicatedStorage.Shared.skills.slash)
		local targetSlashSkill = targetWCSCharacter:GetSkillFromConstructor(Slash)
		if targetSlashSkill then
			local slashState = targetSlashSkill:GetState()
			if slashState.IsActive then
				targetSlashSkill:End()
			end
		end

		-- No knockback or guardbreak - pure damage skill
	end

	return true
end

function HeavySlash:_handleParry(defenderWCSCharacter)
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

function HeavySlash:_applyWeaponTrail()
	if not RunService:IsClient() then
		return
	end

	-- Find the weapon model
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

	-- Find the Grip part in the weapon model
	local gripPart = weaponModel:FindFirstChild("Grip")
	if not gripPart then
		return
	end

	-- Get trail attachments
	local trail0 = gripPart:FindFirstChild("trail0")
	if not trail0 then
		return
	end

	local trail1 = trail0:FindFirstChild("trail1") or gripPart:FindFirstChild("trail1")
	if not trail1 then
		return
	end

	-- Find the Trail object
	local trail = gripPart:FindFirstChildOfClass("Trail") or trail0:FindFirstChildOfClass("Trail")
	if trail then
		trail.Enabled = true

		local animLength = self.loadedAnimation and self.loadedAnimation.Length or 0.7
		task.delay(animLength * 0.8, function()
			if trail and trail.Parent then
				trail.Enabled = false
			end
		end)
	end
end

function HeavySlash:_playHeavySFX()
	if not RunService:IsClient() then
		return
	end

	local animLength = self.loadedAnimation and self.loadedAnimation.Length or 0.7
	local sfxDelay = animLength * 0.35 -- Later in the animation due to windup

	task.delay(sfxDelay, function()
		local weaponType = self:_getClientWeaponType()

		local swingSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
			and ReplicatedStorage.Assets:FindFirstChild("SFX")
			and ReplicatedStorage.Assets.SFX:FindFirstChild("Weapon_Classes")
			and ReplicatedStorage.Assets.SFX.Weapon_Classes:FindFirstChild("Light_Weapons")
			and ReplicatedStorage.Assets.SFX.Weapon_Classes.Light_Weapons:FindFirstChild(weaponType)
			and ReplicatedStorage.Assets.SFX.Weapon_Classes.Light_Weapons[weaponType]:FindFirstChild("swings")

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
		soundClone.Parent = rootPart
		soundClone:Play()

		task.delay(soundClone.TimeLength + 0.1, function()
			if soundClone and soundClone.Parent then
				soundClone:Destroy()
			end
		end)
	end)
end

function HeavySlash:_cancelAttackMomentum()
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

	local stunEffect = Stun.new(self.Character)
	if stunEffect then
		stunEffect:Start(CombatConfig.StatusDurations.RollcancelStun)
	end
end

function HeavySlash:OnEndServer()
	self.hitTargets = {}
end

function HeavySlash:OnEndClient()
	self:_restoreMovementAnimations()

	local interrupted = self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Parried })

	if interrupted then
		if self.loadedAnimation and self.loadedAnimation.IsPlaying then
			self.loadedAnimation:Stop(0.05)
		end
	end
end

return HeavySlash
