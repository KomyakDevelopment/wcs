local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Jump = require(ReplicatedStorage.Shared.skills.jump)

-- Base moveset contains permanent skills available regardless of weapon state
return WCS.CreateMoveset("Base", { Dodge, Jump })
