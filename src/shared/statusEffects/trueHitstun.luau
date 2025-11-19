local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local TrueHitstun = WCS.RegisterStatusEffect("TrueHitstun")

-- Movement reduction: player moves at 15% of their normal speed
local SPEED_MULTIPLIER = 0.15

function TrueHitstun:OnStartServer()
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

	print(`[TrueHitstun] Applied to {character.Instance.Name} - Speed: {hitstunSpeed}`)
end

function TrueHitstun:OnEndServer()
	-- Clear hitstun flag when effect ends
	self.Character.IsInHitstun = false

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
