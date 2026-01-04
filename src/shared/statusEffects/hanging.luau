--!strict
-- Hanging Status Effect
-- Applied when player is hanging from a ledge
-- Prevents attacking and can be checked by other systems

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Hanging = WCS.RegisterStatusEffect("Hanging")

Hanging.DisplayName = "Hanging"

function Hanging:OnStartServer()
	print(`[Hanging] Server: {self.Character.Instance.Name} started hanging`)
end

function Hanging:OnStartClient()
	-- Visual feedback handled by LedgeHangManager
end

function Hanging:OnEndServer()
	print(`[Hanging] Server: {self.Character.Instance.Name} stopped hanging`)
end

function Hanging:OnEndClient()
	-- Cleanup handled by LedgeHangManager
end

return Hanging
