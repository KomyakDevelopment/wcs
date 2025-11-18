local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Server = WCS.CreateServer()

Server:RegisterDirectory(ReplicatedStorage.movesets)
Server:RegisterDirectory(ReplicatedStorage.skills)
Server:RegisterDirectory(ReplicatedStorage.statusEffects)

Server:Start()
