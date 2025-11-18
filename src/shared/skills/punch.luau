local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Punch = WCS.RegisterSkill("Punch")

function Punch:OnStartServer()
	print("Punch activated on server")
	self:ApplyCooldown(0.5)
end

function Punch:OnStartClient()
	print("Punch activated on client")
end

return Punch
