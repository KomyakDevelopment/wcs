local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Slash = require(ReplicatedStorage.Shared.skills.slash)
local Block = require(ReplicatedStorage.Shared.skills.block)
local HeavySlash = require(ReplicatedStorage.Shared.skills.heavySlash)
local HeavySwing = require(ReplicatedStorage.Shared.skills.heavySwing)
local Grip = require(ReplicatedStorage.Shared.skills.grip)

-- Armed moveset contains weapon-based combat skills
-- Uses Slash instead of Punch for melee attacks
-- Includes both HeavySlash (light weapons) and HeavySwing (medium weapons)
return WCS.CreateMoveset("Armed", { Dodge, Slash, Block, HeavySlash, HeavySwing, Grip })
