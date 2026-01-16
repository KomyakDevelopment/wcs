--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)
local CombatConfig = require(ReplicatedStorage.Shared.config.combatConfig)

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

-- Configuration (from central combatConfig)
local ParryConfig = CombatConfig.Parry
local BLOCK_STARTUP_TIME = ParryConfig.StartupTime -- Brief delay before parry window starts
local PARRY_WINDOW_DURATION = ParryConfig.WindowDuration -- Perfect parry window at start of block
local BLOCK_COOLDOWN = ParryConfig.Cooldown -- Cooldown after releasing block

-- Safety mechanisms to prevent stuck Blocking status
local MAX_BLOCK_DURATION = 30 -- Maximum time a block can be held (safety valve)
local CLIENT_BLOCKING_TIMEOUT = 10 -- Force-end Blocking on client if stuck for this long

-- Animation IDs (defaults for fists/unarmed)
local DEFAULT_PARRY_ANIM = "rbxassetid://137500197245035"
local DEFAULT_BLOCK_ANIM = "rbxassetid://115856435443170"
local BLOCK_HIT_ANIM = "rbxassetid://127830278063869"

-- Weapon-specific block/parry animations
local WEAPON_BLOCK_ANIMS = {
	kunai = {
		block = "rbxassetid://129722547154685",
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
	bostaff = {
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
	self.blockStartTime = 0 -- Track when block started for safety timeout
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
	self.safetyCheckConnection = nil -- Safety mechanism connection
	self.blockStartTime = 0 -- Track when block started for animation timing

	-- Preload default animations (will be swapped when weapon changes)
	self:_loadAnimationsForWeapon(nil)

	-- Setup block hit remote listener
	local blockHitRemote = ReplicatedStorage:WaitForChild("PlayBlockHitAnimation") :: RemoteEvent
	self.blockHitRemote = blockHitRemote.OnClientEvent:Connect(function(targetCharacter)
		if targetCharacter == self.Character.Instance then
			self:_playBlockHitAnimation()
		end
	end)

	-- Safety mechanism 3: Client-side stuck Blocking detection
	-- Periodically check if Blocking status exists but Block skill is not active
	-- Note: Client can't directly end server-owned status effects, but can clean up local state
	local lastBlockingDetectedTime = 0
	local checkCounter = 0
	self.safetyCheckConnection = RunService.Heartbeat:Connect(function()
		-- Only check every ~0.5 seconds to reduce overhead (30 frames at 60fps)
		checkCounter = checkCounter + 1
		if checkCounter < 30 then
			return
		end
		checkCounter = 0

		-- Check if we have Blocking status effect
		local hasBlocking = self.Character:HasStatusEffects({ Blocking })

		if hasBlocking and not self.blockActive then
			-- Blocking status exists but skill is not active - potential stuck state
			if lastBlockingDetectedTime == 0 then
				lastBlockingDetectedTime = tick()
				print("[Block] Client: SAFETY - Detected Blocking without active Block skill")
			elseif tick() - lastBlockingDetectedTime > CLIENT_BLOCKING_TIMEOUT then
				-- Blocking has been stuck for too long, clean up local state
				warn(`[Block] Client: SAFETY - Blocking stuck for {CLIENT_BLOCKING_TIMEOUT}s, cleaning up local state`)

				-- Clear LocalCombatState to allow M1s on client side
				-- Server-side safety will eventually clean up the actual status effect
				if LocalCombatState then
					LocalCombatState.endBlock()
					print("[Block] Client: SAFETY - Cleared LocalCombatState blocking")
				end

				-- Stop any lingering animations
				if self.currentAnimTrack then
					self.currentAnimTrack:Stop(0.12)
					self.currentAnimTrack = nil
					print("[Block] Client: SAFETY - Stopped lingering block animation")
				end

				lastBlockingDetectedTime = 0
			end
		else
			-- Either no Blocking or Block skill is active - reset timer
			lastBlockingDetectedTime = 0
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
	self.blockStartTime = tick() -- Track when block started for safety timeout

	local character = self.Character.Instance

	-- Set IsBlocking attribute immediately for fast replication
	character:SetAttribute("IsBlocking", true)

	-- Apply startup delay before block becomes active
	task.delay(BLOCK_STARTUP_TIME, function()
		self.startupComplete = true
		print("[Block] Server: Startup complete - Block now active")

		-- Apply Blocking status effect ONLY if still holding block
		-- (movement slow requires actively blocking)
		if self.blockActive then
			self.blockingEffect = Blocking.new(self.Character)
			if self.blockingEffect then
				self.blockingEffect:Start(-1) -- Infinite duration until cancelled
				print("[Block] Server: Applied Blocking status")
			end
		end

		-- ALWAYS apply parry window after startup, regardless of whether block is still held
		-- This gives "lingering parry frames" - tap F to get the full parry window
		if not self.parryOnCooldown then
			-- Use synchronized server time for parry timestamp
			local parryStartTime = workspace:GetServerTimeNow()

			-- Set parry attributes for INSTANT replication (authoritative from server)
			character:SetAttribute("IsParrying", true)
			character:SetAttribute("ParryStartTime", parryStartTime)
			character:SetAttribute("ParryWindowEnd", parryStartTime + PARRY_WINDOW_DURATION)

			-- Also apply WCS status effect (for backwards compatibility)
			self.parryingEffect = Parrying.new(self.Character)
			if self.parryingEffect then
				self.parryingEffect:Start(PARRY_WINDOW_DURATION)
				print(`[Block] Server: Applied Parrying status ({PARRY_WINDOW_DURATION}s)`)
			end

			-- Clear parry attributes when window expires
			task.delay(PARRY_WINDOW_DURATION, function()
				if character:GetAttribute("ParryStartTime") == parryStartTime then
					character:SetAttribute("IsParrying", nil)
					character:SetAttribute("ParryStartTime", nil)
					character:SetAttribute("ParryWindowEnd", nil)
					print("[Block] Server: Parry window expired - attributes cleared")
				end
			end)
		else
			print("[Block] Server: Skipping parry window - On cooldown")
		end
	end)

	-- Keep skill active until block is released (hold-to-use)
	-- This loop prevents the skill from ending immediately
	-- Safety checks prevent the block from getting stuck if input release is lost
	while self.blockActive do
		-- Safety check 1: Max block duration timeout
		local blockDuration = tick() - self.blockStartTime
		if blockDuration > MAX_BLOCK_DURATION then
			warn(`[Block] Server: SAFETY - Max block duration ({MAX_BLOCK_DURATION}s) exceeded, forcing end`)
			self.blockActive = false
			break
		end

		-- Safety check 2: Verify character and humanoid are still valid
		local charInstance = self.Character.Instance
		if not charInstance or not charInstance.Parent then
			warn("[Block] Server: SAFETY - Character no longer valid, forcing end")
			self.blockActive = false
			break
		end

		local humanoid = charInstance:FindFirstChild("Humanoid") :: Humanoid?
		if not humanoid or humanoid.Health <= 0 then
			warn("[Block] Server: SAFETY - Humanoid dead or missing, forcing end")
			self.blockActive = false
			break
		end

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
	self.blockStartTime = tick() -- Track when block started for animation timing

	-- Update LocalCombatState for client-side prediction
	if LocalCombatState then
		LocalCombatState.startBlock(self.parryOnCooldown)
	end

	-- Set IsBlocking attribute immediately for fast replication
	character:SetAttribute("IsBlocking", true)

	-- ALWAYS apply parry window after startup, regardless of whether block is still held
	-- This gives "lingering parry frames" - tap F to get the full parry window
	if not self.parryOnCooldown then
		task.delay(BLOCK_STARTUP_TIME, function()
			-- Use synchronized server time for parry timestamp
			-- This ensures all clients see the same timing
			local parryStartTime = workspace:GetServerTimeNow()
			self.parryStartTime = parryStartTime

			-- Set parry attributes for INSTANT replication to all clients
			-- These attributes are checked during hit detection instead of status effects
			character:SetAttribute("IsParrying", true)
			character:SetAttribute("ParryStartTime", parryStartTime)
			character:SetAttribute("ParryWindowEnd", parryStartTime + PARRY_WINDOW_DURATION)

			print(`[Block] Client: Parry window started at {parryStartTime} (ends at {parryStartTime + PARRY_WINDOW_DURATION})`)

			-- Clear parry attributes when window expires
			task.delay(PARRY_WINDOW_DURATION, function()
				-- Only clear if this is still the same parry (check timestamp)
				if character:GetAttribute("ParryStartTime") == parryStartTime then
					character:SetAttribute("IsParrying", nil)
					character:SetAttribute("ParryStartTime", nil)
					character:SetAttribute("ParryWindowEnd", nil)
					print("[Block] Client: Parry window expired - attributes cleared")
				end
			end)
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

	-- Clear IsBlocking attribute (but NOT parry attributes - let those expire naturally)
	local character = self.Character.Instance
	character:SetAttribute("IsBlocking", nil)

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

	-- Clear IsBlocking attribute (but NOT parry attributes - let those expire naturally)
	local character = self.Character.Instance
	character:SetAttribute("IsBlocking", nil)

	-- Update LocalCombatState for client-side prediction
	if LocalCombatState then
		LocalCombatState.endBlock()
	end

	-- Set cooldown timer
	self.lastBlockEndTime = tick()
	print(`[Block] Client: Cooldown started ({BLOCK_COOLDOWN}s)`)

	-- Handle animation - keep playing through the full parry window duration
	-- Since we now give lingering parry frames, animation should match
	if self.currentAnimTrack then
		-- Capture track reference to prevent issues if player blocks again quickly
		local trackToStop = self.currentAnimTrack
		self.currentAnimTrack = nil -- Clear immediately so new blocks can use it

		if not self.parryOnCooldown and self.blockStartTime > 0 then
			-- Calculate when parry window ends based on block start time
			-- Parry window: starts at blockStartTime + STARTUP, ends at blockStartTime + STARTUP + DURATION
			local parryEndTime = self.blockStartTime + BLOCK_STARTUP_TIME + PARRY_WINDOW_DURATION
			local parryTimeRemaining = math.max(0, parryEndTime - tick())
			print(`[Block] Client: Parry time remaining: {parryTimeRemaining}s (animation persists)`)

			-- Keep animation playing until parry window fully expires
			if parryTimeRemaining > 0 then
				task.delay(parryTimeRemaining, function()
					if trackToStop and trackToStop.IsPlaying then
						trackToStop:Stop(0.15) -- Slightly slower fade for smoother exit
						print("[Block] Client: Stopped block animation after parry window expired")
					end
				end)
			else
				-- Parry window already expired, stop now
				trackToStop:Stop(0.1)
				print("[Block] Client: Stopped block animation (parry window already expired)")
			end
		else
			-- On cooldown or no valid start time - no parry window, stop animation immediately
			trackToStop:Stop(0.1)
			print("[Block] Client: Stopped block animation (no parry window)")
		end
	end

	-- Reset parry start time
	self.parryStartTime = nil
end

return Block
