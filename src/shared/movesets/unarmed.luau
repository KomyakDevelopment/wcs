local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Punch = require(ReplicatedStorage.Shared.skills.punch)
local Block = require(ReplicatedStorage.Shared.skills.block)
local HeavyPunch = require(ReplicatedStorage.Shared.skills.heavyPunch)
local Grip = require(ReplicatedStorage.Shared.skills.grip)

-- Unarmed moveset contains combat skills
-- Double jump is handled by DoubleJumpManager (independent of WCS)
return WCS.CreateMoveset("Unarmed", { Dodge, Punch, Block, HeavyPunch, Grip })
