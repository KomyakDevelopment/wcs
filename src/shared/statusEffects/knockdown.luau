--!strict
-- Knockdown Status Effect
-- Applied while player is knocked down (ragdolled)
-- Prevents ALL actions - no attacking, blocking, dodging, etc.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Knockdown = WCS.RegisterStatusEffect("Knockdown")

function Knockdown:OnStartServer()
	print("[Knockdown] Server: Player is knocked down - All actions blocked")
end

function Knockdown:OnStartClient()
	print("[Knockdown] Client: Player is knocked down - All actions blocked")
end

function Knockdown:OnEndServer()
	print("[Knockdown] Server: Player recovered from knockdown")
end

function Knockdown:OnEndClient()
	print("[Knockdown] Client: Player recovered from knockdown")
end

return Knockdown
