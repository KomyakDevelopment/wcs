local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Stun = WCS.RegisteredStatusEffects.StatusEffect.new("Stun")

Stun.Duration = 2

function Stun:OnStartServer()
	print("Character stunned")
end

function Stun:OnStartClient()
	print("Stun effect displayed")
end

return Stun
