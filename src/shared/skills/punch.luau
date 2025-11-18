local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Punch = WCS.RegisterSkill({
	Name = "Punch",
	Cooldown = 0.5,

	OnStartServer = function(self)
		print("Punch activated on server")
	end,

	OnStartClient = function(self)
		print("Punch activated on client")
	end,
})

return Punch
