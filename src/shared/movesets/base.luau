local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = require(ReplicatedStorage.Shared.skills.dodge)

-- Base moveset contains core movement skills
-- Jump is only available with weapons equipped (Unarmed moveset)
return WCS.CreateMoveset("Base", { Dodge })
