--!strict
-- Wall Running Status Effect
-- Applied when player is actively running on a wall
-- Prevents attacking and blocking while maintaining mobility

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local WallRunning = WCS.RegisterStatusEffect("WallRunning")

-- Metadata
WallRunning.DisplayName = "Wall Running"
WallRunning.Icon = "" -- Optional icon for UI

function WallRunning:OnStartServer()
	-- Wall running state is primarily client-side
	-- Server just tracks the status for validation
	print(`[WallRunning] {self.Character.Instance.Name} started wall running`)
end

function WallRunning:OnStartClient()
	-- Visual feedback is handled by WallRunManager
	-- This just tracks the state
end

function WallRunning:OnEndServer()
	print(`[WallRunning] {self.Character.Instance.Name} stopped wall running`)
end

function WallRunning:OnEndClient()
	-- Cleanup handled by WallRunManager
end

return WallRunning
