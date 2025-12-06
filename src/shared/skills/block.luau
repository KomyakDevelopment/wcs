--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)

-- Pre-cache status effects and skills at module load (avoid require() in hot paths)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local BlockStunned = require(ReplicatedStorage.Shared.statusEffects.blockStunned)
local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
local Parrying = require(ReplicatedStorage.Shared.statusEffects.parrying)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local Shakyblock = require(ReplicatedStorage.Shared.statusEffects.shakyblock)
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)

local Block = WCS.RegisterSkill("Block")

-- WCS Client Prediction Configuration
-- These settings make the skill feel responsive by not waiting for server validation
Block.CheckClientState = false -- Don't wait for server to validate before playing client effects
Block.CheckOthersActive = false -- Don't check if other skills are active (we handle this manually)

-- Configuration
local BLOCK_STARTUP_TIME = 0.03 -- Windup before block becomes active
local PARRY_WINDOW_DURATION = 0.2975 -- Perfect parry window at start of block (0.2 * 1.35)
local BLOCK_COOLDOWN = 0.5 -- Cooldown after releasing block to prevent spam parrying

-- Animation IDs
local PARRY_TRANSITION_ANIM = "rbxassetid://137500197245035"
local BLOCK_ANIM = "rbxassetid://115856435443170"
local BLOCK_HIT_ANIM = "rbxassetid://127830278063869"

-- Failed parry animations (uses gotparried/stagger anims for visual feedback when parry window ends)
local FAILED_PARRY_ANIMATION_IDS = {
	"rbxassetid://120994424404934",
	"rbxassetid://121143763249322",
	"rbxassetid://131265897792522",
}

function Block:OnConstructServer()
	self.blockActive = false
	self.blockingEffect = nil
	self.parryingEffect = nil
	self.startupComplete = false
	self.lastBlockEndTime = 0 -- Track when block was last released for parry cooldown
	self.parryOnCooldown = false -- Track if parry is on cooldown (block still allowed)
	self._currentBlockToken = nil -- Token to detect stale delayed tasks
end

function Block:OnConstructClient()
	self.loadedAnimations = {}
	self.currentAnimTrack = nil
	self.failedParryTrack = nil -- Track failed parry animation separately for proper cleanup
	self.blockActive = false
	self.blockHitRemote = nil
	self.parryStartTime = nil
	self.lastBlockEndTime = 0 -- Track when block was last released for parry cooldown
	self.parryOnCooldown = false -- Track if parry is on cooldown (block still allowed)
	self.parrySucceeded = false -- Track if a successful parry happened during parry window
	self._clientBlockToken = nil -- Token to detect stale delayed tasks

	-- Preload animations
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			-- Parry transition animation
			local parryTransAnim = Instance.new("Animation")
			parryTransAnim.AnimationId = PARRY_TRANSITION_ANIM
			self.loadedAnimations.ParryTransition = animator:LoadAnimation(parryTransAnim)

			-- Block hold animation
			local blockAnim = Instance.new("Animation")
			blockAnim.AnimationId = BLOCK_ANIM
			self.loadedAnimations.Block = animator:LoadAnimation(blockAnim)

			-- Block hit animation
			local blockHitAnim = Instance.new("Animation")
			blockHitAnim.AnimationId = BLOCK_HIT_ANIM
			self.loadedAnimations.BlockHit = animator:LoadAnimation(blockHitAnim)

			-- Failed parry animation (random selection, preload one)
			local failedParryAnim = Instance.new("Animation")
			failedParryAnim.AnimationId = FAILED_PARRY_ANIMATION_IDS[math.random(1, #FAILED_PARRY_ANIMATION_IDS)]
			self.loadedAnimations.FailedParry = animator:LoadAnimation(failedParryAnim)

			print("[Block] Client: Preloaded animations")
		end
	end

	-- Setup block hit remote listener
	local blockHitRemote = ReplicatedStorage:WaitForChild("PlayBlockHitAnimation") :: RemoteEvent
	self.blockHitRemote = blockHitRemote.OnClientEvent:Connect(function(targetCharacter)
		if targetCharacter == self.Character.Instance then
			self:_playBlockHitAnimation()
		end
	end)
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

	-- Check if parry is on cooldown or shakyblock is active (block is still allowed, just no parry window)
	local currentTime = tick()
	local hasShakyblock = self.Character:HasStatusEffects({ Shakyblock })

	if currentTime - self.lastBlockEndTime < BLOCK_COOLDOWN then
		local remainingCooldown = BLOCK_COOLDOWN - (currentTime - self.lastBlockEndTime)
		self.parryOnCooldown = true
		print(`[Block] Server: Parry on cooldown ({string.format("%.2f", remainingCooldown)}s remaining) - Block only`)
	elseif hasShakyblock then
		self.parryOnCooldown = true
		print(`[Block] Server: Shakyblock active - Parrying disabled, block only`)
	else
		self.parryOnCooldown = false
	end

	-- Check if player is in hitstun, dashing, attacking, or guardbroken
	-- SoftHitstun prevents blocking (player must wait for hitstun to end before blocking)
	if self.Character:HasStatusEffects({ Dashing, SoftHitstun, TrueHitstun, Stun, BlockStunned, Guardbroken, Attacking, Knockdown }) then
		print("[Block] Server: Blocked - Player is in hitstun/stun/dashing/block recovery/guardbroken/attacking/knocked down")
		return
	end

	-- Check if player is sprinting (can't block while sprinting)
	-- SprintManager sets IsSprinting attribute on character
	if self.Character.Instance:GetAttribute("IsSprinting") == true then
		print("[Block] Server: Blocked - Player is sprinting")
		return
	end

	print("[Block] Server: Block started - Startup phase")

	self.blockActive = true

	-- Store a unique token for this block instance to detect stale delayed tasks
	local blockToken = {}
	self._currentBlockToken = blockToken

	-- Apply startup delay before block becomes active
	task.delay(BLOCK_STARTUP_TIME, function()
		if not self.blockActive then
			return -- Block was cancelled during startup
		end

		-- Check if this delayed task is from the current block instance
		if self._currentBlockToken ~= blockToken then
			return -- Stale task from previous block
		end

		self.startupComplete = true
		print("[Block] Server: Startup complete - Parry window starting")

		-- Apply ONLY Parrying status effect during parry window (only if not on cooldown)
		-- Blocking status comes later after failed parry window
		if not self.parryOnCooldown then
			-- End any existing parrying effect first (prevents leaked effects)
			if self.parryingEffect then
				self.parryingEffect:End()
				self.parryingEffect = nil
			end

			self.parryingEffect = Parrying.new(self.Character)
			if self.parryingEffect then
				self.parryingEffect:Start(PARRY_WINDOW_DURATION)
				print(`[Block] Server: Applied Parrying status ({PARRY_WINDOW_DURATION}s)`)
			end
		else
			print("[Block] Server: Skipping parry window - On cooldown")
		end
	end)

	-- Apply Blocking status immediately after parry window expires (no gap!)
	-- If parry is on cooldown, skip the parry window and start blocking right after startup
	-- This ensures continuous protection with no vulnerability window
	local wasOnCooldown = self.parryOnCooldown -- Capture for delayed callback
	local blockingStartDelay
	if wasOnCooldown then
		-- No parry window - start blocking immediately after startup
		blockingStartDelay = BLOCK_STARTUP_TIME
	else
		-- Normal flow - start blocking when parry window ends
		blockingStartDelay = BLOCK_STARTUP_TIME + PARRY_WINDOW_DURATION
	end

	task.delay(blockingStartDelay, function()
		if not self.blockActive then
			return -- Block was cancelled before blocking phase
		end

		-- Check if this delayed task is from the current block instance
		-- If not, it's a stale task from a previous block and should be ignored
		if self._currentBlockToken ~= blockToken then
			return -- Stale task from previous block
		end

		-- End any existing blocking effect first (prevents leaked effects)
		if self.blockingEffect then
			self.blockingEffect:End()
			self.blockingEffect = nil
		end

		-- Apply Blocking status effect (infinite duration until cancelled)
		self.blockingEffect = Blocking.new(self.Character)
		if self.blockingEffect then
			self.blockingEffect:Start(-1)
			if wasOnCooldown then
				print("[Block] Server: Applied Blocking status (no parry - on cooldown)")
			else
				print("[Block] Server: Applied Blocking status (parry window ended)")
			end
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
	-- Check if parry is on cooldown or shakyblock is active (block is still allowed, just no parry window)
	local currentTime = tick()
	local hasShakyblock = self.Character:HasStatusEffects({ Shakyblock })

	if currentTime - self.lastBlockEndTime < BLOCK_COOLDOWN then
		local remainingCooldown = BLOCK_COOLDOWN - (currentTime - self.lastBlockEndTime)
		self.parryOnCooldown = true
		print(`[Block] Client: Parry on cooldown ({string.format("%.2f", remainingCooldown)}s remaining) - Block only`)
	elseif hasShakyblock then
		self.parryOnCooldown = true
		print(`[Block] Client: Shakyblock active - Parrying disabled, block only`)
	else
		self.parryOnCooldown = false
	end

	-- Check if player has any status effects that prevent blocking
	-- SoftHitstun prevents blocking (player must wait for hitstun to end before blocking)
	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Dashing, BlockStunned, Guardbroken, Attacking, Knockdown }) then
		print("[Block] Client: Blocked - Player is in hitstun/stun/dashing/block recovery/guardbroken/attacking/knocked down")
		-- Play failed parry animation for visual feedback (shows player tried to parry but couldn't)
		self:_playFailedParryAnimation()
		return
	end

	-- Check if player is sprinting (can't block while sprinting)
	-- SprintManager sets IsSprinting attribute on character
	if self.Character.Instance:GetAttribute("IsSprinting") == true then
		print("[Block] Client: Blocked - Player is sprinting")
		-- Play failed parry animation for visual feedback
		self:_playFailedParryAnimation()
		return
	end

	self.blockActive = true
	self.parrySucceeded = false -- Reset parry success flag

	-- Store a unique token for this block instance
	local clientBlockToken = {}
	self._clientBlockToken = clientBlockToken

	-- Store when the parry window starts (after startup delay) - only if not on cooldown
	if not self.parryOnCooldown then
		task.delay(BLOCK_STARTUP_TIME, function()
			if not self.blockActive or self._clientBlockToken ~= clientBlockToken then
				return
			end
			self.parryStartTime = tick()
			print(`[Block] Client: Parry window started at {self.parryStartTime}`)
		end)

		-- Schedule failed parry -> block transition when parry window ends
		task.delay(BLOCK_STARTUP_TIME + PARRY_WINDOW_DURATION, function()
			if not self.blockActive or self._clientBlockToken ~= clientBlockToken then
				return
			end

			-- Play failed parry animation (brief stagger) then transition to block hold
			local failedParryTrack = self.loadedAnimations.FailedParry
			local blockTrack = self.loadedAnimations.Block

			if failedParryTrack then
				-- Stop current animation
				if self.currentAnimTrack then
					self.currentAnimTrack:Stop(0.05)
				end

				-- Play failed parry stagger animation and track it separately
				self.failedParryTrack = failedParryTrack
				self.currentAnimTrack = failedParryTrack
				failedParryTrack.Looped = false
				failedParryTrack.Priority = Enum.AnimationPriority.Action2
				failedParryTrack:Play(0.05)
				print("[Block] Client: Playing failed parry animation (parry window ended)")

				-- Transition to block hold after brief stagger
				task.delay(0.25, function()
					if not self.blockActive or self._clientBlockToken ~= clientBlockToken then
						-- Block ended during transition - stop failed parry anim
						if self.failedParryTrack and self.failedParryTrack.IsPlaying then
							self.failedParryTrack:Stop(0.1)
						end
						self.failedParryTrack = nil
						return
					end

					-- Stop failed parry animation explicitly before transitioning
					if self.failedParryTrack and self.failedParryTrack.IsPlaying then
						self.failedParryTrack:Stop(0.1)
					end
					self.failedParryTrack = nil

					if blockTrack then
						self.currentAnimTrack = blockTrack
						blockTrack:Play(0.1)
						blockTrack.Looped = true
						print("[Block] Client: Transitioned to block hold (after failed parry)")
					end
				end)
			elseif blockTrack then
				-- Fallback: just play block hold if failed parry anim not loaded
				self.currentAnimTrack = blockTrack
				blockTrack:Play(0.1)
				blockTrack.Looped = true
				print("[Block] Client: Playing block hold animation (parry window ended)")
			end
		end)
	else
		self.parryStartTime = nil -- No parry window when on cooldown

		-- On cooldown: go directly to block hold after startup
		task.delay(BLOCK_STARTUP_TIME, function()
			if not self.blockActive or self._clientBlockToken ~= clientBlockToken then
				return
			end

			local blockTrack = self.loadedAnimations.Block
			if blockTrack then
				if self.currentAnimTrack then
					self.currentAnimTrack:Stop(0.1)
				end
				self.currentAnimTrack = blockTrack
				blockTrack:Play(0.1)
				blockTrack.Looped = true
				print("[Block] Client: Playing block hold animation (no parry - on cooldown)")
			end
		end)
	end

	-- Play parry transition animation at start
	local parryTransTrack = self.loadedAnimations.ParryTransition
	if parryTransTrack then
		self.currentAnimTrack = parryTransTrack
		parryTransTrack:Play(0.05)
		print("[Block] Client: Playing parry transition animation")
	else
		warn("[Block] Client: Parry transition animation not loaded")
	end
end

-- Play a brief animation when player tries to parry but can't (failed parry feedback)
function Block:_playFailedParryAnimation()
	local parryTransTrack = self.loadedAnimations.ParryTransition
	if parryTransTrack then
		-- Play at faster speed for a quick "failed" feeling
		parryTransTrack:Play(0.05)
		parryTransTrack:AdjustSpeed(1.5)
		print("[Block] Client: Playing failed parry animation")

		-- Stop the animation after a short duration (don't let it complete fully)
		task.delay(0.2, function()
			if parryTransTrack and parryTransTrack.IsPlaying then
				parryTransTrack:Stop(0.1)
			end
		end)
	end
end

function Block:OnEndServer()
	print("[Block] Server: Block released - Lingering parry frames")

	self.blockActive = false
	self.startupComplete = false
	self._currentBlockToken = nil -- Invalidate any pending delayed tasks

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
	self._clientBlockToken = nil -- Invalidate any pending delayed tasks

	-- Set cooldown timer
	self.lastBlockEndTime = tick()
	print(`[Block] Client: Cooldown started ({BLOCK_COOLDOWN}s)`)

	-- Stop failed parry animation if it's still playing
	if self.failedParryTrack and self.failedParryTrack.IsPlaying then
		self.failedParryTrack:Stop(0.1)
		print("[Block] Client: Stopped failed parry animation on block end")
	end
	self.failedParryTrack = nil

	-- Handle animation stopping based on whether we had a parry window
	if self.currentAnimTrack then
		if self.parryStartTime then
			-- Had a parry window - let lingering parry frames finish
			local elapsedTime = tick() - self.parryStartTime
			local parryTimeRemaining = math.max(0, PARRY_WINDOW_DURATION - elapsedTime)
			print(`[Block] Client: Parry time remaining: {parryTimeRemaining}s`)

			-- Wait for parry frames to expire before stopping animation
			local animToStop = self.currentAnimTrack
			task.delay(parryTimeRemaining, function()
				if animToStop and animToStop.IsPlaying then
					animToStop:Stop(0.1)
					print("[Block] Client: Stopped block animation after parry window expired")
				end
			end)
			self.currentAnimTrack = nil
		elseif not self.parryOnCooldown then
			-- Parry window hasn't started yet but we're not on cooldown - wait full duration
			local parryTimeRemaining = PARRY_WINDOW_DURATION + BLOCK_STARTUP_TIME
			print(`[Block] Client: Parry hasn't started, waiting full duration: {parryTimeRemaining}s`)

			local animToStop = self.currentAnimTrack
			task.delay(parryTimeRemaining, function()
				if animToStop and animToStop.IsPlaying then
					animToStop:Stop(0.1)
					print("[Block] Client: Stopped block animation after parry window expired")
				end
			end)
			self.currentAnimTrack = nil
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
