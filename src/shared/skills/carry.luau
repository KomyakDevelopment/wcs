--!strict
-- Carry Skill
-- Allows players to pick up and carry knocked down players
-- Press keybind to pick up, press again to drop

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)

-- Pre-cache status effects
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)
local Dashing = require(ReplicatedStorage.Shared.statusEffects.dashing)
local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)

local Carry = WCS.RegisterSkill("Carry")

-- Configuration
local CARRY_RANGE = 8 -- Distance to pick up target
local CARRY_SPEED_MULTIPLIER = 0.7 -- Slower movement while carrying

-- Animation IDs
local CARRYING_ANIMATION = "rbxassetid://76405414110055" -- Player carrying animation
local CARRIED_ANIMATION = "rbxassetid://132103454609128" -- Victim being carried animation

-- WCS Configuration
Carry.CheckClientState = false
Carry.CheckOthersActive = false

function Carry:OnConstructServer()
	self.carriedCharacter = nil :: Model?
	self.carryWeld = nil :: WeldConstraint?
	self.originalWalkSpeed = 16
	self.isCarrying = false
end

function Carry:OnConstructClient()
	self.loadedAnimations = {}
	self.carryingAnimTrack = nil :: AnimationTrack?
	self.carriedAnimTrack = nil :: AnimationTrack?
	self.carriedCharacter = nil :: Model?
	self.isCarrying = false

	-- Preload carrying animation
	local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local carryAnim = Instance.new("Animation")
			carryAnim.AnimationId = CARRYING_ANIMATION
			self.loadedAnimations.Carrying = animator:LoadAnimation(carryAnim)
			print("[Carry] Client: Preloaded carrying animation")
		end
	end
end

-- Find nearest knocked down player within range (same as grip)
function Carry:_findNearestKnockedTarget(): Model?
	local character = self.Character.Instance
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return nil
	end

	local myPosition = rootPart.Position
	local nearestTarget = nil :: Model?
	local nearestDistance = CARRY_RANGE + 1

	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid") :: Humanoid?
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart") :: BasePart?

			if targetHumanoid and targetRootPart then
				-- Check if target is knocked down (PlatformStand = true means ragdolled)
				if targetHumanoid.PlatformStand then
					-- Skip if already being carried by someone
					if potentialTarget:GetAttribute("BeingCarried") then
						continue
					end

					-- Skip if marked for execution
					if RunService:IsServer() and _G.DeathManager then
						local targetPlayer = Players:GetPlayerFromCharacter(potentialTarget)
						if targetPlayer and _G.DeathManager:isMarkedForExecution(targetPlayer) then
							continue
						end
					end

					local distance = (targetRootPart.Position - myPosition).Magnitude
					if distance <= CARRY_RANGE and distance < nearestDistance then
						nearestTarget = potentialTarget
						nearestDistance = distance
					end
				end
			end
		end
	end

	return nearestTarget
end

function Carry:OnStartServer()
	print("[Carry] Server: OnStartServer called")

	-- If already carrying, drop the target
	if self.isCarrying and self.carriedCharacter then
		print("[Carry] Server: Dropping carried player")
		self:_dropTarget()
		return
	end

	-- Check if player is in any status that prevents carrying
	local hasBlockingStatus = self.Character:HasStatusEffects({
		SoftHitstun, TrueHitstun, Stun, Dashing,
		Blocking, Attacking, Guardbroken, Knockdown
	})

	if hasBlockingStatus then
		print("[Carry] Server: Blocked - Player has preventing status effect")
		return
	end

	-- Check if player is wall running (direct attribute check)
	local character = self.Character.Instance
	if character:GetAttribute("IsWallRunning") then
		print("[Carry] Server: Blocked - Player is wall running")
		return
	end

	-- Find target
	local target = self:_findNearestKnockedTarget()
	if not target then
		print("[Carry] Server: No valid target found within range")
		return
	end

	print(`[Carry] Server: Found target {target.Name}, picking up`)
	self:_pickUpTarget(target)
end

function Carry:_pickUpTarget(target: Model)
	local character = self.Character.Instance
	local carrierRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carrierHumanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?

	if not carrierRoot or not targetRoot or not carrierHumanoid or not targetHumanoid then
		warn("[Carry] Server: Missing required parts")
		return
	end

	self.carriedCharacter = target
	self.isCarrying = true

	-- Mark target as being carried
	target:SetAttribute("BeingCarried", true)
	target:SetAttribute("CarriedBy", character.Name)

	-- Store original walk speed
	self.originalWalkSpeed = carrierHumanoid.WalkSpeed

	-- Slow down carrier
	carrierHumanoid.WalkSpeed = self.originalWalkSpeed * CARRY_SPEED_MULTIPLIER

	-- Disable ragdoll trigger on target so they stay limp but welded
	local ragdollTrigger = target:FindFirstChild("RagdollTrigger") :: BoolValue?
	if ragdollTrigger then
		ragdollTrigger.Value = false
	end

	-- Keep target in platformstand so they don't try to walk
	targetHumanoid.PlatformStand = true

	-- Position target on carrier's back/shoulder
	targetRoot.CFrame = carrierRoot.CFrame * CFrame.new(0, 0.5, -1) * CFrame.Angles(0, 0, math.rad(90))

	-- Create weld to attach target to carrier
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = carrierRoot
	weld.Part1 = targetRoot
	weld.Parent = carrierRoot
	self.carryWeld = weld

	-- Fire event to clients for animations
	local carryRemote = ReplicatedStorage:FindFirstChild("PlayerCarry") :: RemoteEvent?
	if not carryRemote then
		carryRemote = Instance.new("RemoteEvent")
		carryRemote.Name = "PlayerCarry"
		carryRemote.Parent = ReplicatedStorage
	end
	carryRemote:FireAllClients(character, target, true) -- true = picking up

	print(`[Carry] Server: {character.Name} is now carrying {target.Name}`)
end

function Carry:_dropTarget()
	if not self.carriedCharacter then
		return
	end

	local character = self.Character.Instance
	local carrierHumanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	local target = self.carriedCharacter
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Remove weld
	if self.carryWeld then
		self.carryWeld:Destroy()
		self.carryWeld = nil
	end

	-- Restore carrier walk speed
	if carrierHumanoid then
		carrierHumanoid.WalkSpeed = self.originalWalkSpeed
	end

	-- Clear carried attributes
	target:SetAttribute("BeingCarried", nil)
	target:SetAttribute("CarriedBy", nil)

	-- Re-enable ragdoll on target (they're still knocked down)
	local ragdollTrigger = target:FindFirstChild("RagdollTrigger") :: BoolValue?
	if ragdollTrigger then
		ragdollTrigger.Value = true
	end

	-- Position target in front of carrier
	local carrierRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if carrierRoot and targetRoot then
		local dropPosition = carrierRoot.Position + carrierRoot.CFrame.LookVector * 3
		targetRoot.CFrame = CFrame.new(dropPosition)
	end

	-- Fire event to clients
	local carryRemote = ReplicatedStorage:FindFirstChild("PlayerCarry") :: RemoteEvent?
	if carryRemote then
		carryRemote:FireAllClients(character, target, false) -- false = dropping
	end

	print(`[Carry] Server: {character.Name} dropped {target.Name}`)

	self.carriedCharacter = nil
	self.isCarrying = false
end

function Carry:OnStartClient()
	-- If already carrying, this will trigger drop on server
	if self.isCarrying then
		print("[Carry] Client: Requesting drop")
		return
	end

	-- Check for preventing status effects
	if self.Character:HasStatusEffects({
		SoftHitstun, TrueHitstun, Stun, Dashing,
		Blocking, Attacking, Guardbroken, Knockdown
	}) then
		return
	end

	-- Find target for visual feedback
	local target = self:_findNearestKnockedTarget()
	if not target then
		return
	end

	self.carriedCharacter = target
	self.isCarrying = true

	-- Play carrying animation on self
	local carryTrack = self.loadedAnimations.Carrying
	if carryTrack then
		self.carryingAnimTrack = carryTrack
		carryTrack.Priority = Enum.AnimationPriority.Action
		carryTrack.Looped = true
		carryTrack:Play(0.2)
		print("[Carry] Client: Playing carrying animation")
	end

	-- Play carried animation on target
	local targetHumanoid = target:FindFirstChild("Humanoid") :: Humanoid?
	if targetHumanoid then
		local targetAnimator = targetHumanoid:FindFirstChildOfClass("Animator")
		if targetAnimator then
			local carriedAnim = Instance.new("Animation")
			carriedAnim.AnimationId = CARRIED_ANIMATION
			local carriedTrack = targetAnimator:LoadAnimation(carriedAnim)
			carriedTrack.Priority = Enum.AnimationPriority.Action
			carriedTrack.Looped = true
			carriedTrack:Play(0.2)
			self.carriedAnimTrack = carriedTrack
			print("[Carry] Client: Playing carried animation on target")
		end
	end
end

function Carry:OnEndServer()
	-- Drop target if still carrying when skill ends
	if self.isCarrying and self.carriedCharacter then
		self:_dropTarget()
	end
end

function Carry:OnEndClient()
	-- Stop carrying animation
	if self.carryingAnimTrack and self.carryingAnimTrack.IsPlaying then
		self.carryingAnimTrack:Stop(0.2)
	end
	self.carryingAnimTrack = nil

	-- Stop carried animation
	if self.carriedAnimTrack and self.carriedAnimTrack.IsPlaying then
		self.carriedAnimTrack:Stop(0.2)
	end
	self.carriedAnimTrack = nil

	self.carriedCharacter = nil
	self.isCarrying = false
end

return Carry
