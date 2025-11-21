--!strict
-- Attacking Status Effect
-- Applied during M1 attacks to prevent dodging mid-combo
-- Short duration to avoid feeling clunky

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Attacking = WCS.RegisterStatusEffect("Attacking")

function Attacking:OnStartClient()
	print("[Attacking] Client: Attack in progress - Dodge blocked")
end

function Attacking:OnStartServer()
	print("[Attacking] Server: Attack in progress")
end

function Attacking:OnEndServer()
	print("[Attacking] Server: Attack finished")
end

function Attacking:OnEndClient()
	print("[Attacking] Client: Attack finished - Dodge available")
end

return Attacking
