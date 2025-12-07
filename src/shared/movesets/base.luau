local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Grip = require(ReplicatedStorage.Shared.skills.grip)

-- Base moveset contains core movement skills
-- Jump is only available with weapons equipped (Unarmed moveset)
-- Grip allows executing knocked players
-- Carry is handled by CarryManager (not a WCS skill)
return WCS.CreateMoveset("Base", { Dodge, Grip })
