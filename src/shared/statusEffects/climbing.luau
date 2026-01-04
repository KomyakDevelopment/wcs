--!strict
-- Climbing Status Effect
-- Applied when player is climbing a wall
-- Prevents attacking and can be checked by other systems

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Climbing = WCS.RegisterStatusEffect("Climbing")

Climbing.DisplayName = "Climbing"

function Climbing:OnStartServer()
	print(`[Climbing] Server: {self.Character.Instance.Name} started climbing`)
end

function Climbing:OnStartClient()
	-- Visual feedback handled by ClimbManager
end

function Climbing:OnEndServer()
	print(`[Climbing] Server: {self.Character.Instance.Name} stopped climbing`)
end

function Climbing:OnEndClient()
	-- Cleanup handled by ClimbManager
end

return Climbing
