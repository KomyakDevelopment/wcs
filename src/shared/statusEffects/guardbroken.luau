--!strict
-- Guardbroken Status Effect
-- Applied when a character's posture is broken
-- Similar to TrueHitstun but with 0 movement speed

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Guardbroken = WCS.RegisterStatusEffect("Guardbroken")

-- Configuration
local GUARDBROKEN_ANIMATION_ID = "rbxassetid://120994424404934"

function Guardbroken:OnConstructServer()
	-- Store reference to prevent duplicate guardbreaks
	if self.Character._ActiveGuardbroken then
		self.Character._ActiveGuardbroken:Stop()
	end
	self.Character._ActiveGuardbroken = self
end

function Guardbroken:OnStartServer()
	local character = self.Character
	local humanoid = character.Instance:FindFirstChild("Humanoid")

	if not humanoid then
		return
	end

	-- Set flag on WCS Character
	character.IsGuardbroken = true

	-- Replicate state to clients via metadata
	self:SetMetadata({
		Active = true,
		Type = "Guardbroken",
	})

	-- Apply complete movement lock (0 speed, unlike TrueHitstun which allows some movement)
	self:SetHumanoidData({
		WalkSpeed = { 0, "Set" },
		JumpPower = { 0, "Set" },
		JumpHeight = { 0, "Set" },
	})

	-- Fire guardbreak effects to all clients (VFX + SFX)
	local guardbreakRemote = ReplicatedStorage:FindFirstChild("PlayGuardbreak")
	if guardbreakRemote then
		guardbreakRemote:FireAllClients(character.Instance)
	end

	print(`[Guardbroken] Applied to {character.Instance.Name}`)
end

function Guardbroken:OnEndServer()
	-- Only clear flag if this is the active guardbroken
	if self.Character._ActiveGuardbroken == self then
		self.Character.IsGuardbroken = false
		self.Character._ActiveGuardbroken = nil
	end

	-- Clear metadata
	self:SetMetadata({
		Active = false,
		Type = nil,
	})

	print(`[Guardbroken] Ended on {self.Character.Instance.Name}`)
end

function Guardbroken:OnStartClient()
	-- Play guardbroken animation
	self:_playGuardbrokenAnimation()

	-- Stop all movement animations
	self:_freezeMovementAnimations()

	-- Note: VFX and SFX are handled by guardbreakManager via PlayGuardbreak remote
	-- This ensures all players see/hear the effects, not just the guardbroken player

	print("[Guardbroken] Client effect started")
end

function Guardbroken:OnEndClient()
	-- Stop the animation
	if self.animTrack then
		self.animTrack:Stop(0.2)
		self.animTrack = nil
	end

	-- Restore movement animations
	self:_restoreMovementAnimations()

	print("[Guardbroken] Client effect ended")
end

-- Play the guardbroken stagger animation
function Guardbroken:_playGuardbrokenAnimation()
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

	-- Stop all Action priority animations first
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local priority = track.Priority
		if
			priority == Enum.AnimationPriority.Action
			or priority == Enum.AnimationPriority.Action2
			or priority == Enum.AnimationPriority.Action3
			or priority == Enum.AnimationPriority.Action4
		then
			track:AdjustSpeed(0)
			track:AdjustWeight(0, 0.1)
			track:Stop(0.1)
		end
	end

	-- Create and play guardbroken animation
	local animation = Instance.new("Animation")
	animation.AnimationId = GUARDBROKEN_ANIMATION_ID
	self.animTrack = animator:LoadAnimation(animation)

	self.animTrack.Looped = false
	self.animTrack.Priority = Enum.AnimationPriority.Action4
	self.animTrack:Play(0.1)
	self.animTrack:AdjustWeight(1, 0.1)
end

-- Freeze movement animations during guardbroken
function Guardbroken:_freezeMovementAnimations()
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

	-- Store original speeds for restoration
	self.originalMovementAnimSpeeds = {}

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Priority == Enum.AnimationPriority.Core or track.Priority == Enum.AnimationPriority.Movement then
			self.originalMovementAnimSpeeds[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
end

-- Restore movement animation speeds after guardbroken
function Guardbroken:_restoreMovementAnimations()
	if not RunService:IsClient() then
		return
	end

	if not self.originalMovementAnimSpeeds then
		return
	end

	for track, originalSpeed in pairs(self.originalMovementAnimSpeeds) do
		if track and track.IsPlaying then
			track:AdjustSpeed(originalSpeed)
		end
	end

	self.originalMovementAnimSpeeds = nil
end

-- Play blockbreak VFX particle effect
function Guardbroken:_playBlockbreakVFX()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Get blockbreak VFX template
	local blockbreakVFXPart = ReplicatedStorage.Assets.VFX.General_Combat.blockbreak
	if not blockbreakVFXPart then
		warn("[Guardbroken] Blockbreak VFX part not found")
		return
	end

	local vfxAttachment = blockbreakVFXPart:FindFirstChild("Attachment")
	if not vfxAttachment then
		warn("[Guardbroken] Blockbreak VFX attachment not found")
		return
	end

	-- Clone attachment to player's root part
	local attachmentClone = vfxAttachment:Clone()
	attachmentClone.Parent = rootPart

	-- Emit particles
	for _, child in ipairs(attachmentClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			child:Emit(child:GetAttribute("EmitCount") or child.Rate)
		end
	end

	-- Clean up after particles finish
	task.delay(3, function()
		if attachmentClone and attachmentClone.Parent then
			attachmentClone:Destroy()
		end
	end)

	print("[Guardbroken] Playing blockbreak VFX")
end

-- Play guardbreak SFX
function Guardbroken:_playGuardbreakSFX()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Get guardbreak SFX folder
	local guardbreakSFXFolder = ReplicatedStorage.Assets.SFX.General_Combat.guardbreak
	if not guardbreakSFXFolder then
		warn("[Guardbroken] Guardbreak SFX folder not found")
		return
	end

	-- Get all Sound instances from folder
	local sounds = {}
	for _, child in ipairs(guardbreakSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[Guardbroken] No guardbreak sounds found in folder")
		return
	end

	-- Select random sound
	local randomSound = sounds[math.random(1, #sounds)]

	-- Clone and play the sound
	local soundClone = randomSound:Clone()
	soundClone.Parent = rootPart
	soundClone:Play()

	-- Clean up after sound finishes
	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)

	print(`[Guardbroken] Playing guardbreak SFX: {randomSound.Name}`)
end

return Guardbroken
