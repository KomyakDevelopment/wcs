local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Punch = require(ReplicatedStorage.Shared.skills.punch)

return WCS.CreateMoveset("Unarmed", { Punch })
