local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.WCS)

local Server = WCS.CreateServer()

Server:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Server:RegisterDirectory(ReplicatedStorage.Shared.skills)
Server:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Server:Start()
