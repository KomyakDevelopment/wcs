local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.WCS)

local Client = WCS.CreateClient()

Client:RegisterDirectory(ReplicatedStorage.movesets)
Client:RegisterDirectory(ReplicatedStorage.skills)
Client:RegisterDirectory(ReplicatedStorage.statusEffects)

Client:Start()
