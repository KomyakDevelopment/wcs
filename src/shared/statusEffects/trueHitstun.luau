local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local TrueHitstun = WCS.RegisterStatusEffect("TrueHitstun")

-- Movement reduction: player moves at 15% of their normal speed
local SPEED_MULTIPLIER = 0.15

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

function TrueHitstun:OnStartClient()
	-- TODO: Add visual effects (red outline, stun stars, etc.)
	print("[TrueHitstun] Client effect started")
end

function TrueHitstun:OnEndClient()
	print("[TrueHitstun] Client effect ended")
end

return TrueHitstun
