--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Punch = WCS.RegisterSkill("Punch")

-- Configuration
local PUNCH_DAMAGE = 10
local PUNCH_RANGE = 8
local PUNCH_COOLDOWN = 0.5

-- Hitstun duration for unarmed attacks
local SOFT_HITSTUN_DURATION = 1.3
local FLOURISH_SELF_HITSTUN_DURATION = 0.5 -- Recovery time after landing flourish

-- Combo system configuration
local COMBO_RESET_TIME = 2.0 -- Time before combo resets to phase 1
local MAX_COMBO_PHASE = 4 -- Total combo phases (1, 2, 3, flourish)

-- Knockback configuration for flourish
local FLOURISH_KNOCKBACK_POWER = 55
local FLOURISH_KNOCKBACK_DURATION = 0.18

-- Animation IDs for each combo phase
local COMBO_ANIMATIONS = {
	[1] = "rbxassetid://71780482128433",
	[2] = "rbxassetid://122171966838136",
	[3] = "rbxassetid://102972252804338",
	[4] = "rbxassetid://122171966838136", -- Flourish uses 2_m1 temporarily
}

-- Damage delays for each combo phase (in seconds)
-- Adjust these to match when the fist actually hits in each animation
local DAMAGE_DELAYS = {
	[1] = 0.3, -- First M1 damage delay
	[2] = 0.3, -- Second M1 damage delay
	[3] = 0.3, -- Third M1 damage delay
	[4] = 0.3, -- Flourish damage delay
}

function Punch:OnConstructServer()
	-- Setup server-side skill data
	self.hitTargets = {}
	self.comboPhase = 1
	self.comboResetTimer = nil
	self.currentAttackPhase = 1 -- Track which phase is currently executing
end

function Punch:OnConstructClient()
	-- Setup client-side skill data
	self.comboPhase = 1
	self.comboResetTimer = nil
	self.loadedAnimations = {}

	-- Preload all combo animations
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for phase, animId in pairs(COMBO_ANIMATIONS) do
				local animation = Instance.new("Animation")
				animation.AnimationId = animId
				self.loadedAnimations[phase] = animator:LoadAnimation(animation)
			end
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

	-- Check if player is in hitstun or dashing
	local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
	if self.Character.IsInHitstun or self.Character:HasStatusEffects({ Dashing }) then
		print("[Punch] Blocked - Player is in hitstun or dashing")
		return
	end

	-- Store the current attack phase before advancing
	self.currentAttackPhase = self.comboPhase

	print(`[Punch] Server: Punch activated - Phase {self.currentAttackPhase}`)

	-- Apply cooldown
	self:ApplyCooldown(PUNCH_COOLDOWN)

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

function Punch:OnStartClient()
	-- Check if player has any hitstun status effects active or is dashing
	local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
	local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)

	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Dashing }) then
		print("[Punch] Client: Blocked - Player is in hitstun/stun/dashing")
		return
	end

	-- Reset combo timer on client
	if self.comboResetTimer then
		task.cancel(self.comboResetTimer)
	end

	-- Play animation for current combo phase
	local animTrack = self.loadedAnimations[self.comboPhase]
	if animTrack then
		animTrack:Play()
		print(`[Punch] Client: Playing combo phase {self.comboPhase} animation`)
	else
		warn(`[Punch] No animation loaded for phase {self.comboPhase}`)
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
		print("[Punch] Client: Combo reset to phase 1")
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
	local origin = humanoidRootPart.Position
	local lookDirection = humanoidRootPart.CFrame.LookVector
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

					-- If dot product > 0.5, target is roughly in front (within ~60 degrees)
					if dotProduct > 0.5 then
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
		local Iframes = require(ReplicatedStorage.Shared.statusEffects.iframes)
		if targetWCSCharacter:HasStatusEffects({ Iframes }) then
			print(`[Punch] Target {targetModel.Name} has iframes - No damage`)
			return false
		end

		-- Check for parry (Parrying or Autoparry status)
		local Parrying = require(ReplicatedStorage.Shared.statusEffects.parrying)
		local Autoparry = require(ReplicatedStorage.Shared.statusEffects.autoparry)
		local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)

		if targetWCSCharacter:HasStatusEffects({ Parrying, Autoparry }) then
			print(`[Punch] Target {targetModel.Name} PARRIED the attack!`)
			self:_handleParry(targetWCSCharacter)
			return false
		end

		-- Check for block (Blocking status but NOT parrying)
		if targetWCSCharacter:HasStatusEffects({ Blocking }) then
			print(`[Punch] Target {targetModel.Name} blocked the attack`)
			self:_handleBlock(targetWCSCharacter)
			return false
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
		local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
		local hitstun = SoftHitstun.new(targetWCSCharacter)
		if hitstun then
			-- Start with duration per WCS docs (will refresh if already active)
			hitstun:Start(SOFT_HITSTUN_DURATION)
			print(`[Punch] Applied SoftHitstun ({SOFT_HITSTUN_DURATION}s) to {targetModel.Name}`)
		else
			warn(`[Punch] Failed to create SoftHitstun for {targetModel.Name}`)
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
			local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
			local selfHitstun = SoftHitstun.new(self.Character)

			if selfHitstun then
				selfHitstun:Start(FLOURISH_SELF_HITSTUN_DURATION)
				print(`[Punch] Applied self-hitstun ({FLOURISH_SELF_HITSTUN_DURATION}s) to attacker for flourish recovery`)
			else
				warn("[Punch] Failed to create self-hitstun for flourish recovery")
			end
		end
	end

	-- Return true to indicate this was a real hit (not blocked/parried)
	return true
end

-- Handle successful parry
function Punch:_handleParry(defenderWCSCharacter)
	-- Apply Autoparry status to defender for 0.4s
	local Autoparry = require(ReplicatedStorage.Shared.statusEffects.autoparry)
	local autoparryEffect = Autoparry.new(defenderWCSCharacter)
	if autoparryEffect then
		autoparryEffect:Start(0.4)
		print(`[Punch] Applied Autoparry (0.4s) to {defenderWCSCharacter.Instance.Name}`)
	end

	-- Apply TrueHitstun to attacker (0.8s punishment for getting parried)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	local trueHitstunEffect = TrueHitstun.new(self.Character)
	if trueHitstunEffect then
		trueHitstunEffect:Start(0.8)
		print(`[Punch] Applied TrueHitstun (0.8s) to attacker {self.Character.Instance.Name} - Got parried`)
	end

	-- Apply Parried status to attacker for visual/audio feedback
	local Parried = require(ReplicatedStorage.Shared.statusEffects.parried)
	local parriedEffect = Parried.new(self.Character)
	if parriedEffect then
		parriedEffect:Start(0.8)
		print(`[Punch] Applied Parried status (0.8s) to attacker {self.Character.Instance.Name}`)
	end

	-- Fire parry flash VFX event (when attack is parried)
	local parryFlashRemote = ReplicatedStorage:FindFirstChild("PlayParryFlashVFX")
	if parryFlashRemote then
		parryFlashRemote:FireAllClients(defenderWCSCharacter.Instance)
	end

	-- Fire parry VFX event (full parry effect)
	local parryVFXRemote = ReplicatedStorage:FindFirstChild("PlayParryVFX")
	if parryVFXRemote then
		parryVFXRemote:FireAllClients(defenderWCSCharacter.Instance)
	end

	-- TODO: Apply posture changes (defender -30%, attacker +30%)
	print("[Punch] TODO: Apply posture changes for parry")
end

-- Handle successful block (not a parry)
function Punch:_handleBlock(defenderWCSCharacter)
	-- Apply BlockStunned status to defender for 0.1s
	local BlockStunned = require(ReplicatedStorage.Shared.statusEffects.blockStunned)
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

function Punch:OnEndServer()
	-- Clear hit targets when skill ends
	self.hitTargets = {}
end

return Punch
