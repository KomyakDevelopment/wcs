--!strict
-- Dashing Status Effect
-- Marks the character as dashing/dodging to block attacks and other actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Dashing = WCS.RegisterStatusEffect("Dashing")

-- This status effect is applied during dodges to prevent attacks, blocks, and other actions
-- The actual velocity is handled by the Dodge skill itself

function Dashing:OnStartClient()
	print("[Dashing] Client: Dashing status active")
end

function Dashing:OnStartServer()
	print("[Dashing] Server: Dashing status active")
end

function Dashing:OnEndServer()
	print("[Dashing] Server: Dashing status ended")
end

function Dashing:OnEndClient()
	print("[Dashing] Client: Dashing status ended")
end

return Dashing
