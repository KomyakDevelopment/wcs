--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)

-- Client-side combat state for prediction (only require on client)
local LocalCombatState = nil
if RunService:IsClient() then
	LocalCombatState = require(ReplicatedStorage.Shared.state.localCombatState)
end

-- Pre-cache status effects and skills at module load (avoid require() in hot paths)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local BlockStunned = require(ReplicatedStorage.Shared.statusEffects.blockStunned)
local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
local Parrying = require(ReplicatedStorage.Shared.statusEffects.parrying)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
local WallRunning = require(ReplicatedStorage.Shared.statusEffects.wallRunning)
local Sprint = require(ReplicatedStorage.Shared.skills.sprint)

local Block = WCS.RegisterSkill("Block")

-- WCS Client Prediction Configuration
-- These settings make the skill feel responsive by not waiting for server validation
Block.CheckClientState = false -- Don't wait for server to validate before playing client effects
Block.CheckOthersActive = false -- Don't check if other skills are active (we handle this manually)

-- Configuration
local BLOCK_STARTUP_TIME = 0.03 -- Windup before block becomes active
local PARRY_WINDOW_DURATION = 0.2975 -- Perfect parry window at start of block (0.2 * 1.35)
local BLOCK_COOLDOWN = 0.5 -- Cooldown after releasing block to prevent spam parrying

-- Animation IDs (defaults for fists/unarmed)
local DEFAULT_PARRY_ANIM = "rbxassetid://137500197245035"
local DEFAULT_BLOCK_ANIM = "rbxassetid://115856435443170"
local BLOCK_HIT_ANIM = "rbxassetid://127830278063869"

-- Weapon-specific block/parry animations
local WEAPON_BLOCK_ANIMS = {
	kunai = {
		block = "rbxassetid://116055719354049",
		parry = "rbxassetid://101039289396724",
	},
	uchigatana = {
		block = "rbxassetid://122601128387564",
		parry = "rbxassetid://111224605676234",
	},
	kusanagi = {
		block = "rbxassetid://122601128387564",
		parry = "rbxassetid://111224605676234",
	},
	kubikiribocho = {
		block = "rbxassetid://122601128387564",
		parry = "rbxassetid://111224605676234",
	},
}

function Block:OnConstructServer()
	self.blockActive = false
	self.blockingEffect = nil
	self.parryingEffect = nil
	self.startupComplete = false
	self.lastBlockEndTime = 0 -- Track when block was last released for parry cooldown
	self.parryOnCooldown = false -- Track if parry is on cooldown (block still allowed)
end

function Block:OnConstructClient()
	self.loadedAnimations = {}
	self.currentAnimTrack = nil
	self.blockActive = false
	self.blockHitRemote = nil
	self.parryStartTime = nil
	self.lastBlockEndTime = 0 -- Track when block was last released for parry cooldown
	self.parryOnCooldown = false -- Track if parry is on cooldown (block still allowed)
	self.currentWeaponType = nil -- Track current weapon for animation switching

	-- Preload default animations (will be swapped when weapon changes)
	self:_loadAnimationsForWeapon(nil)

	-- Setup block hit remote listener
	local blockHitRemote = ReplicatedStorage:WaitForChild("PlayBlockHitAnimation") :: RemoteEvent
	self.blockHitRemote = blockHitRemote.OnClientEvent:Connect(function(targetCharacter)
		if targetCharacter == self.Character.Instance then
			self:_playBlockHitAnimation()
		end
	end)
end

-- Get currently equipped weapon type
function Block:_getEquippedWeaponType(): string?
	local characterInstance = self.Character.Instance
	for _, child in ipairs(characterInstance:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "_Equipped") then
			local weaponName = string.gsub(child.Name, "_Equipped", "")
			return string.lower(weaponName)
		end
	end
	return nil
end

-- Load animations for a specific weapon type
function Block:_loadAnimationsForWeapon(weaponType: string?)
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	-- Get weapon-specific animations or use defaults
	local weaponAnims = weaponType and WEAPON_BLOCK_ANIMS[weaponType]
	local parryAnimId = weaponAnims and weaponAnims.parry or DEFAULT_PARRY_ANIM
	local blockAnimId = weaponAnims and weaponAnims.block or DEFAULT_BLOCK_ANIM

	-- Parry transition animation
	local parryTransAnim = Instance.new("Animation")
	parryTransAnim.AnimationId = parryAnimId
	self.loadedAnimations.ParryTransition = animator:LoadAnimation(parryTransAnim)

	-- Block hold animation
	local blockAnim = Instance.new("Animation")
	blockAnim.AnimationId = blockAnimId
	self.loadedAnimations.Block = animator:LoadAnimation(blockAnim)

	-- Block hit animation (universal)
	local blockHitAnim = Instance.new("Animation")
	blockHitAnim.AnimationId = BLOCK_HIT_ANIM
	self.loadedAnimations.BlockHit = animator:LoadAnimation(blockHitAnim)

	self.currentWeaponType = weaponType
	print(`[Block] Client: Loaded animations for weapon: {weaponType or "default"}`)
end

-- Play block hit animation when getting hit while blocking
function Block:_playBlockHitAnimation()
	if not self.blockActive then
		return
	end

	local blockHitTrack = self.loadedAnimations.BlockHit
	if blockHitTrack then
		blockHitTrack:Play(0.05)
		print("[Block] Client: Playing block hit animation")

		-- Return to block hold animation after hit animation completes
		local hitAnimLength = blockHitTrack.Length
		task.delay(hitAnimLength or 0.3, function()
			if self.blockActive then
				local blockTrack = self.loadedAnimations.Block
				if blockTrack then
					blockTrack:Play(0.1)
					blockTrack.Looped = true
				end
			end
		end)
	end
end

function Block:OnStartServer()
	print("[Block] Server: OnStartServer called")

	-- Check if player has equipment manager
	if not self.Character.EquipmentManager then
		warn("[Block] Server: No equipment manager found")
		return
	end

	print("[Block] Server: Equipment manager found, checking weapon...")

	-- Check if player has a weapon equipped
	if not self.Character.EquipmentManager:hasWeaponEquipped() then
		print("[Block] Server: Blocked - No weapon equipped")
		return
	end

	print("[Block] Server: Weapon equipped, proceeding with block")

	-- Check if parry is on cooldown (block is still allowed, just no parry window)
	local currentTime = tick()
	if currentTime - self.lastBlockEndTime < BLOCK_COOLDOWN then
		local remainingCooldown = BLOCK_COOLDOWN - (currentTime - self.lastBlockEndTime)
		self.parryOnCooldown = true
		print(`[Block] Server: Parry on cooldown ({string.format("%.2f", remainingCooldown)}s remaining) - Block only`)
	else
		self.parryOnCooldown = false
	end

	-- Check if player is in hitstun or dashing or guardbroken
	-- Note: SoftHitstun is ALLOWED (can parry during soft hitstun), but TrueHitstun is NOT
	if self.Character:HasStatusEffects({ Dashing, TrueHitstun, Stun, BlockStunned, Guardbroken, Knockdown, WallRunning }) then
		print("[Block] Server: Blocked - Player is in a blocking state")
		return
	end

	-- Check if player is sprinting (can't block while sprinting)
	local sprintSkill = self.Character:GetSkillFromConstructor(Sprint)
	if sprintSkill then
		local sprintState = sprintSkill:GetState()
		if sprintState.IsActive then
			print("[Block] Server: Blocked - Player is sprinting")
			return
		end
	end

	print("[Block] Server: Block started - Startup phase")

	self.blockActive = true

	-- Apply startup delay before block becomes active
	task.delay(BLOCK_STARTUP_TIME, function()
		if not self.blockActive then
			return -- Block was cancelled during startup
		end

		self.startupComplete = true
		print("[Block] Server: Startup complete - Block now active")

		-- Apply Blocking status effect
		self.blockingEffect = Blocking.new(self.Character)
		if self.blockingEffect then
			self.blockingEffect:Start(-1) -- Infinite duration until cancelled
			print("[Block] Server: Applied Blocking status")
		end

		-- Apply Parrying status effect for parry window (only if not on cooldown)
		if not self.parryOnCooldown then
			self.parryingEffect = Parrying.new(self.Character)
			if self.parryingEffect then
				self.parryingEffect:Start(PARRY_WINDOW_DURATION)
				print(`[Block] Server: Applied Parrying status ({PARRY_WINDOW_DURATION}s)`)
			end
		else
			print("[Block] Server: Skipping parry window - On cooldown")
		end
	end)

	-- Keep skill active until block is released (hold-to-use)
	-- This loop prevents the skill from ending immediately
	while self.blockActive do
		task.wait(0.1)
	end

	print("[Block] Server: Block loop ended")
end

function Block:OnStartClient()
	-- Check if player is wall running (direct attribute check - status effect is client-side only)
	local character = self.Character.Instance
	if character:GetAttribute("IsWallRunning") then
		print("[Block] Client: Blocked - Player is wall running")
		return
	end

	-- Check if weapon has changed and reload animations if needed
	local currentWeapon = self:_getEquippedWeaponType()
	if currentWeapon ~= self.currentWeaponType then
		self:_loadAnimationsForWeapon(currentWeapon)
	end

	-- Check if parry is on cooldown (block is still allowed, just no parry window)
	local currentTime = tick()
	if currentTime - self.lastBlockEndTime < BLOCK_COOLDOWN then
		local remainingCooldown = BLOCK_COOLDOWN - (currentTime - self.lastBlockEndTime)
		self.parryOnCooldown = true
		print(`[Block] Client: Parry on cooldown ({string.format("%.2f", remainingCooldown)}s remaining) - Block only`)
	else
		self.parryOnCooldown = false
	end

	-- Check if player has any status effects that prevent blocking
	-- Note: SoftHitstun is ALLOWED (can parry during soft hitstun), but TrueHitstun is NOT
	if self.Character:HasStatusEffects({ TrueHitstun, Stun, Dashing, BlockStunned, Guardbroken, Knockdown }) then
		print("[Block] Client: Blocked - Player is in a blocking state")
		return
	end

	-- Check if player is sprinting (can't block while sprinting)
	local sprintSkill = self.Character:GetSkillFromConstructor(Sprint)
	if sprintSkill then
		local sprintState = sprintSkill:GetState()
		if sprintState.IsActive then
			print("[Block] Client: Blocked - Player is sprinting")
			return
		end
	end

	self.blockActive = true

	-- Update LocalCombatState for client-side prediction
	if LocalCombatState then
		LocalCombatState.startBlock(self.parryOnCooldown)
	end

	-- Store when the parry window starts (after startup delay) - only if not on cooldown
	if not self.parryOnCooldown then
		task.delay(BLOCK_STARTUP_TIME, function()
			self.parryStartTime = tick()
			print(`[Block] Client: Parry window started at {self.parryStartTime}`)
		end)
	else
		self.parryStartTime = nil -- No parry window when on cooldown
	end

	-- Always play parry transition animation first, then transition to block hold
	local parryTransTrack = self.loadedAnimations.ParryTransition
	if parryTransTrack then
		self.currentAnimTrack = parryTransTrack
		parryTransTrack:Play(0.05)
		print("[Block] Client: Playing parry transition animation")

		-- Wait for transition to complete, then play block hold
		local transitionLength = parryTransTrack.Length
		task.delay(transitionLength or 0.3, function()
			if not self.blockActive then
				return -- Block was cancelled
			end

			-- Play block hold animation (loops)
			local blockTrack = self.loadedAnimations.Block
			if blockTrack then
				self.currentAnimTrack = blockTrack
				blockTrack:Play(0.1)
				blockTrack.Looped = true
				print("[Block] Client: Playing block hold animation (looping)")
			end
		end)
	else
		warn("[Block] Client: Parry transition animation not loaded")
	end
end

function Block:OnEndServer()
	print("[Block] Server: Block released - Lingering parry frames")

	self.blockActive = false
	self.startupComplete = false

	-- Set cooldown timer
	self.lastBlockEndTime = tick()
	print(`[Block] Server: Cooldown started ({BLOCK_COOLDOWN}s)`)

	-- End Blocking status immediately (can't block anymore)
	if self.blockingEffect then
		self.blockingEffect:End()
		self.blockingEffect = nil
		print("[Block] Server: Ended Blocking status")
	end

	-- DON'T end Parrying status - let it finish its natural duration
	-- The parry window will continue until PARRY_WINDOW_DURATION expires
	print("[Block] Server: Parrying status continues until natural expiration")
	self.parryingEffect = nil -- Clear reference so we don't manually end it
end

function Block:OnEndClient()
	print("[Block] Client: Block released")

	self.blockActive = false

	-- Update LocalCombatState for client-side prediction
	if LocalCombatState then
		LocalCombatState.endBlock()
	end

	-- Set cooldown timer
	self.lastBlockEndTime = tick()
	print(`[Block] Client: Cooldown started ({BLOCK_COOLDOWN}s)`)

	-- Handle animation stopping based on whether we had a parry window
	if self.currentAnimTrack then
		if self.parryStartTime then
			-- Had a parry window - let lingering parry frames finish
			local elapsedTime = tick() - self.parryStartTime
			local parryTimeRemaining = math.max(0, PARRY_WINDOW_DURATION - elapsedTime)
			print(`[Block] Client: Parry time remaining: {parryTimeRemaining}s`)

			-- Wait for parry frames to expire before stopping animation
			task.delay(parryTimeRemaining, function()
				if self.currentAnimTrack then
					self.currentAnimTrack:Stop(0.1)
					self.currentAnimTrack = nil
					print("[Block] Client: Stopped block animation after parry window expired")
				end
			end)
		elseif not self.parryOnCooldown then
			-- Parry window hasn't started yet but we're not on cooldown - wait full duration
			local parryTimeRemaining = PARRY_WINDOW_DURATION + BLOCK_STARTUP_TIME
			print(`[Block] Client: Parry hasn't started, waiting full duration: {parryTimeRemaining}s`)

			task.delay(parryTimeRemaining, function()
				if self.currentAnimTrack then
					self.currentAnimTrack:Stop(0.1)
					self.currentAnimTrack = nil
					print("[Block] Client: Stopped block animation after parry window expired")
				end
			end)
		else
			-- On cooldown - no parry window, stop animation immediately
			self.currentAnimTrack:Stop(0.1)
			self.currentAnimTrack = nil
			print("[Block] Client: Stopped block animation (no parry window)")
		end
	end

	-- Reset parry start time
	self.parryStartTime = nil
end

return Block
