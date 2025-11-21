--!strict
-- Parrying Status Effect
-- Applied for 0.2s at the start of block - perfect parry window
-- Any attack received during this window results in a successful parry

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Parrying = WCS.RegisterStatusEffect("Parrying")

function Parrying:OnStartServer()
	print("[Parrying] Server: Parry window active (0.2s)")
end

function Parrying:OnStartClient()
	print("[Parrying] Client: Parry window active - Perfect timing!")
end

function Parrying:OnEndServer()
	print("[Parrying] Server: Parry window ended")
end

function Parrying:OnEndClient()
	print("[Parrying] Client: Parry window ended")
end

return Parrying
