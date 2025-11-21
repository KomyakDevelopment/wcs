--!strict
-- BlockStunned Status Effect
-- Applied for 0.1s after blocking an attack
-- Brief recovery period before you can act again

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local BlockStunned = WCS.RegisterStatusEffect("BlockStunned")

function BlockStunned:OnStartServer()
	print("[BlockStunned] Server: Block recovery active (0.1s)")
end

function BlockStunned:OnStartClient()
	print("[BlockStunned] Client: Block recovery - Brief stun")
end

function BlockStunned:OnEndServer()
	print("[BlockStunned] Server: Block recovery ended")
end

function BlockStunned:OnEndClient()
	print("[BlockStunned] Client: Block recovery ended - Can act now")
end

return BlockStunned
