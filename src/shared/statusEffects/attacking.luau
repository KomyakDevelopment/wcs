-- Attacking Status Effect
-- Applied during M1 attacks to prevent dodging mid-combo
-- Short duration to avoid feeling clunky

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Attacking = WCS.RegisterStatusEffect("Attacking")

-- Movement reduction during attacks (20% slower = 80% of normal speed)
local ATTACK_SPEED_MULTIPLIER = 0.8

function Attacking:OnStartClient()
	print("[Attacking] Client: Attack in progress - Dodge blocked")
end

function Attacking:OnStartServer()
	print("[Attacking] Server: Attack in progress")

	local humanoid = self.Character.Instance:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		-- Apply 20% movement slowdown during attack
		local reducedSpeed = humanoid.WalkSpeed * ATTACK_SPEED_MULTIPLIER
		self:SetHumanoidData({
			WalkSpeed = { reducedSpeed, "Set" },
			JumpPower = { 0, "Set" },
			JumpHeight = { 0, "Set" },
		})
	end
end

function Attacking:OnEndServer()
	print("[Attacking] Server: Attack finished")
	-- WCS automatically restores humanoid data when status ends
end

function Attacking:OnEndClient()
	print("[Attacking] Client: Attack finished - Dodge available")
end

return Attacking
