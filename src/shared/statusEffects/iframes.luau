--!strict
-- Iframes (Invincibility Frames) Status Effect
-- Grants temporary invincibility during dodges to prevent damage

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Iframes = WCS.RegisterStatusEffect("Iframes")

-- This status effect makes the character invincible during dodge iframes window
-- Damage checks should verify if target has this status effect before applying damage

function Iframes:OnStartClient()
	print("[Iframes] Client: Invincibility active")
end

function Iframes:OnStartServer()
	print("[Iframes] Server: Invincibility active")
end

function Iframes:OnEndServer()
	print("[Iframes] Server: Invincibility ended")
end

function Iframes:OnEndClient()
	print("[Iframes] Client: Invincibility ended")
end

return Iframes
