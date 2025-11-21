local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local SoftHitstun = WCS.RegisterStatusEffect("SoftHitstun")

-- Movement reduction: player moves at 20% of their normal speed
local SPEED_MULTIPLIER = 0.375

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

function SoftHitstun:OnStartClient()
	-- Cancel any active M1 attacks (stops animation and skill)
	if self.Character and self.Character.Moveset then
		local punchSkill = self.Character.Moveset:GetSkillFromConstructor("Punch")
		if punchSkill and punchSkill:IsActive() then
			punchSkill:End()
			print("[SoftHitstun] Client: Cancelled active punch skill")
		end
	end

	-- TODO: Add visual effects (yellow outline, slight stagger animation)
	print("[SoftHitstun] Client effect started")
end

function SoftHitstun:OnEndClient()
	print("[SoftHitstun] Client effect ended")
end

return SoftHitstun
