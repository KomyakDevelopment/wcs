local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Stun = WCS.RegisterStatusEffect({
	Name = "Stun",
	Duration = 2,

	OnStartServer = function(self)
		print("Character stunned")
	end,

	OnStartClient = function(self)
		print("Stun effect displayed")
	end,
})

return Stun
