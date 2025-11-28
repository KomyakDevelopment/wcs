local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Grip = require(ReplicatedStorage.Shared.skills.grip)

-- Base moveset contains core movement skills
-- Jump is only available with weapons equipped (Unarmed moveset)
-- Grip allows executing knocked players
return WCS.CreateMoveset("Base", { Dodge, Grip })
