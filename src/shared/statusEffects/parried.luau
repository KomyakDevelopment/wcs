--!strict
-- Parried Status Effect
-- Applied to attacker for 0.8s when their attack gets parried
-- This is a soft hitstun that locks them out of actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Parried = WCS.RegisterStatusEffect("Parried")

function Parried:OnStartServer()
	print("[Parried] Server: Attacker got parried - Stunned (0.8s)")
end

function Parried:OnStartClient()
	print("[Parried] Client: You got parried - Punish window active!")
end

function Parried:OnEndServer()
	print("[Parried] Server: Parried stun ended")
end

function Parried:OnEndClient()
	print("[Parried] Client: Parried stun ended - Can act now")
end

return Parried
