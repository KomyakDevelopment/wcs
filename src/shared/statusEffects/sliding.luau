--!strict
-- Sliding Status Effect
-- Marks the character as sliding to block attacks and other actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Sliding = WCS.RegisterStatusEffect("Sliding")

-- This status effect is applied during slides to prevent attacks, blocks, and other actions
-- The actual velocity is handled by the Slide skill itself

function Sliding:OnStartClient()
	print("[Sliding] Client: Sliding status active")
end

function Sliding:OnStartServer()
	print("[Sliding] Server: Sliding status active")
end

function Sliding:OnEndServer()
	print("[Sliding] Server: Sliding status ended")
end

function Sliding:OnEndClient()
	print("[Sliding] Client: Sliding status ended")
end

return Sliding
