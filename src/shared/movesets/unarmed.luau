local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Punch = require(ReplicatedStorage.Shared.skills.punch)
local Block = require(ReplicatedStorage.Shared.skills.block)

-- Unarmed moveset contains weapon-required skills (Punch, Block)
-- Dodge is in the Base moveset which is always available
return WCS.CreateMoveset("Unarmed", { Punch, Block })
