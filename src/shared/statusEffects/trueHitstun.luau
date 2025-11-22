local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local WCS = require(ReplicatedStorage.Packages.wcs)

local TrueHitstun = WCS.RegisterStatusEffect("TrueHitstun")

-- Movement reduction: player moves at 32.5% of their normal speed (50% less punishing)
local SPEED_MULTIPLIER = 0.325

function TrueHitstun:OnConstructServer()
	-- Store reference to this status effect on the character
	-- This allows us to stop previous instances
	if self.Character._ActiveTrueHitstun then
		-- Stop the previous true hitstun
		self.Character._ActiveTrueHitstun:Stop()
	end
	self.Character._ActiveTrueHitstun = self
end

function TrueHitstun:OnStartServer()
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
		Type = "TrueHitstun",
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

	print(`[TrueHitstun] Applied to {character.Instance.Name} - Speed: {hitstunSpeed}`)
end

function TrueHitstun:OnEndServer()
	-- Only clear flag if this is the active hitstun
	if self.Character._ActiveTrueHitstun == self then
		self.Character.IsInHitstun = false
		self.Character._ActiveTrueHitstun = nil
	end

	-- Clear metadata
	self:SetMetadata({
		Active = false,
		Type = nil,
	})

	print(`[TrueHitstun] Ended on {self.Character.Instance.Name}`)
end

-- Walk animation speed during hitstun
local WALK_ANIM_SPEED_DURING_HITSTUN = 0.5 -- 50% speed

function TrueHitstun:OnStartClient()
	-- Slow down walk animations
	self:_slowWalkAnimations()

	print("[TrueHitstun] Client effect started")
end

function TrueHitstun:OnEndClient()
	-- Restore walk animation speeds
	self:_restoreWalkAnimations()

	print("[TrueHitstun] Client effect ended")
end

-- Slow down walk/movement animations during hitstun
function TrueHitstun:_slowWalkAnimations()
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
function TrueHitstun:_restoreWalkAnimations()
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

return TrueHitstun
