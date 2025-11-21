local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Punch = require(ReplicatedStorage.Shared.skills.punch)
local Dodge = require(ReplicatedStorage.Shared.skills.dodge)

return WCS.CreateMoveset("Unarmed", { Punch, Dodge })
