local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Punch = WCS.RegisteredSkills.Skill.new("Punch")

Punch.Cooldown = 0.5

function Punch:OnStartServer()
	print("Punch activated on server")
end

function Punch:OnStartClient()
	print("Punch activated on client")
end

return Punch
