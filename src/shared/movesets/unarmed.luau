local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Unarmed = WCS.Moveset.new("Unarmed")

Unarmed.Skills = {
	"Punch",
}

return Unarmed
