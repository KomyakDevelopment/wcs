local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Punch = require(ReplicatedStorage.Shared.skills.punch)
local Block = require(ReplicatedStorage.Shared.skills.block)

-- Unarmed moveset contains all combat skills including Dodge
-- When equipped, this replaces the Base moveset entirely
return WCS.CreateMoveset("Unarmed", { Dodge, Punch, Block })
