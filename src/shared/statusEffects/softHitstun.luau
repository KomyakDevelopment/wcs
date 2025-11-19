local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local SoftHitstun = WCS.RegisterStatusEffect("SoftHitstun")

-- Movement reduction: player moves at 20% of their normal speed
local SPEED_MULTIPLIER = 0.2

function SoftHitstun:OnStartServer()
	local character = self.Character
	local humanoid = character.Instance:FindFirstChild("Humanoid")

	if not humanoid then
		return
	end

	-- Set flag on WCS Character to indicate hitstun is active
	character.IsInHitstun = true

	-- Get current walkspeed and calculate hitstun speed
	local originalSpeed = humanoid.WalkSpeed
	local hitstunSpeed = originalSpeed * SPEED_MULTIPLIER

	-- Apply movement reduction using WCS SetHumanoidData
	self:SetHumanoidData({
		WalkSpeed = { hitstunSpeed, "Set" },
		JumpPower = { 0, "Set" },
	})

	print(`[SoftHitstun] Applied to {character.Instance.Name} - Speed: {hitstunSpeed}`)
end

function SoftHitstun:OnEndServer()
	-- Clear hitstun flag when effect ends
	self.Character.IsInHitstun = false

	print(`[SoftHitstun] Ended on {self.Character.Instance.Name}`)
end

function SoftHitstun:OnStartClient()
	-- TODO: Add visual effects (yellow outline, slight stagger animation)
	print("[SoftHitstun] Client effect started")
end

function SoftHitstun:OnEndClient()
	print("[SoftHitstun] Client effect ended")
end

return SoftHitstun
