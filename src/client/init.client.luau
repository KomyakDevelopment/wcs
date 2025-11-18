local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.WCS)

local Client = WCS.CreateClient()

Client:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Client:RegisterDirectory(ReplicatedStorage.Shared.skills)
Client:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Client:Start()
