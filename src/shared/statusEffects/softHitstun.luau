local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local WCS = require(ReplicatedStorage.Packages.wcs)

local SoftHitstun = WCS.RegisterStatusEffect("SoftHitstun")

-- Movement reduction: player moves at reduced speed (40% less slowdown than before)
local SPEED_MULTIPLIER = 0.625

function SoftHitstun:OnConstructServer()
	-- Store reference to this status effect on the character
	-- This allows us to stop previous instances
	if self.Character._ActiveSoftHitstun then
		-- Stop the previous soft hitstun
		self.Character._ActiveSoftHitstun:Stop()
	end
	self.Character._ActiveSoftHitstun = self
end

function SoftHitstun:OnStartServer()
	local character = self.Character
	local humanoid = character.Instance:FindFirstChild("Humanoid")

	if not humanoid then
		return
	end

	-- Set flag on WCS Character to indicate hitstun is active
	character.IsInHitstun = true

	-- Replicate state to clients via metadata
	self:SetMetadata({
		Active = true,
		Type = "SoftHitstun",
	})

	-- Get current walkspeed and calculate hitstun speed
	local originalSpeed = humanoid.WalkSpeed
	local hitstunSpeed = originalSpeed * SPEED_MULTIPLIER

	-- Apply movement reduction using WCS SetHumanoidData
	self:SetHumanoidData({
		WalkSpeed = { hitstunSpeed, "Set" },
		JumpPower = { 0, "Set" },
		JumpHeight = { 0, "Set" },
	})

	print(`[SoftHitstun] Applied to {character.Instance.Name} - Speed: {hitstunSpeed}`)
end

function SoftHitstun:OnEndServer()
	-- Only clear flag if this is the active hitstun
	if self.Character._ActiveSoftHitstun == self then
		self.Character.IsInHitstun = false
		self.Character._ActiveSoftHitstun = nil
	end

	-- Clear metadata
	self:SetMetadata({
		Active = false,
		Type = nil,
	})

	print(`[SoftHitstun] Ended on {self.Character.Instance.Name}`)
end

-- Walk animation speed during hitstun
local WALK_ANIM_SPEED_DURING_HITSTUN = 0.5 -- 50% speed

function SoftHitstun:OnStartClient()
	-- Cancel any active M1 attacks (stops animation and skill)
	if self.Character and self.Character.Moveset then
		local punchSkill = self.Character.Moveset:GetSkillFromConstructor("Punch")
		if punchSkill and punchSkill:IsActive() then
			punchSkill:End()
			print("[SoftHitstun] Client: Cancelled active punch skill")
		end
	end

	-- Slow down walk animations
	self:_slowWalkAnimations()

	print("[SoftHitstun] Client effect started")
end

function SoftHitstun:OnEndClient()
	-- Restore walk animation speeds
	self:_restoreWalkAnimations()

	print("[SoftHitstun] Client effect ended")
end

-- Slow down walk/movement animations during hitstun
function SoftHitstun:_slowWalkAnimations()
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
	self.originalWalkAnimSpeeds = {}

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		-- Slow down core movement animations (walk/run)
		if track.Priority == Enum.AnimationPriority.Core or track.Priority == Enum.AnimationPriority.Movement then
			self.originalWalkAnimSpeeds[track] = track.Speed
			track:AdjustSpeed(WALK_ANIM_SPEED_DURING_HITSTUN)
		end
	end
end

-- Restore walk animation speeds after hitstun
function SoftHitstun:_restoreWalkAnimations()
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

	self.originalWalkAnimSpeeds = nil
end

return SoftHitstun
