local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Stun = WCS.RegisterStatusEffect("Stun")

function Stun:OnStartServer()
	print("Character stunned")
	self:SetHumanoidData({
		WalkSpeed = { 0, "Set" },
		JumpPower = { 0, "Set" },
	})
end

function Stun:OnStartClient()
	print("Stun effect displayed on client")
end

return Stun
