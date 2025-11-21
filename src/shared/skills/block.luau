--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Block = WCS.RegisterSkill("Block")

-- Configuration
local BLOCK_STARTUP_TIME = 0.05 -- Windup before block becomes active
local PARRY_WINDOW_DURATION = 0.2 -- Perfect parry window at start of block

-- Animation IDs
local PARRY_TRANSITION_ANIM = "rbxassetid://137500197245035"
local BLOCK_ANIM = "rbxassetid://115856435443170"
local BLOCK_HIT_ANIM = "rbxassetid://127830278063869"

function Block:OnConstructServer()
	self.blockActive = false
	self.blockingEffect = nil
	self.parryingEffect = nil
	self.startupComplete = false
end

function Block:OnConstructClient()
	self.loadedAnimations = {}
	self.currentAnimTrack = nil
	self.blockActive = false
	self.blockHitRemote = nil

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
	-- Check if player has equipment manager
	if not self.Character.EquipmentManager then
		warn("[Block] No equipment manager found")
		return
	end

	-- Check if player has a weapon equipped
	if not self.Character.EquipmentManager:hasWeaponEquipped() then
		print("[Block] Blocked - No weapon equipped")
		return
	end

	-- Check if player is in hitstun or dashing
	local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
	local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
	local BlockStunned = require(ReplicatedStorage.Shared.statusEffects.blockStunned)

	if self.Character:HasStatusEffects({ Dashing, SoftHitstun, TrueHitstun, Stun, BlockStunned }) then
		print("[Block] Server: Blocked - Player is in hitstun/stun/dashing/block recovery")
		return
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
		local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
		self.blockingEffect = Blocking.new(self.Character)
		if self.blockingEffect then
			self.blockingEffect:Start(-1) -- Infinite duration until cancelled
			print("[Block] Server: Applied Blocking status")
		end

		-- Apply Parrying status effect for parry window
		local Parrying = require(ReplicatedStorage.Shared.statusEffects.parrying)
		self.parryingEffect = Parrying.new(self.Character)
		if self.parryingEffect then
			self.parryingEffect:Start(PARRY_WINDOW_DURATION)
			print(`[Block] Server: Applied Parrying status ({PARRY_WINDOW_DURATION}s)`)
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
	-- Check if player has any status effects that prevent blocking
	local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
	local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
	local BlockStunned = require(ReplicatedStorage.Shared.statusEffects.blockStunned)

	if self.Character:HasStatusEffects({ SoftHitstun, TrueHitstun, Stun, Dashing, BlockStunned }) then
		print("[Block] Client: Blocked - Player is in hitstun/stun/dashing/block recovery")
		return
	end

	self.blockActive = true

	-- Play parry transition animation first
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
	print("[Block] Server: Block ended")

	self.blockActive = false
	self.startupComplete = false

	-- End Blocking status
	if self.blockingEffect then
		self.blockingEffect:End()
		self.blockingEffect = nil
		print("[Block] Server: Ended Blocking status")
	end

	-- End Parrying status if still active
	if self.parryingEffect then
		self.parryingEffect:End()
		self.parryingEffect = nil
		print("[Block] Server: Ended Parrying status")
	end
end

function Block:OnEndClient()
	print("[Block] Client: Block ended")

	self.blockActive = false

	-- Stop animation
	if self.currentAnimTrack then
		self.currentAnimTrack:Stop(0.1)
		self.currentAnimTrack = nil
	end
end

return Block
