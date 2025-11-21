--!strict
-- Autoparry Status Effect
-- Applied for 0.4s after a successful parry
-- Automatically parries any parriable attack during this window

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Autoparry = WCS.RegisterStatusEffect("Autoparry")

function Autoparry:OnStartServer()
	print("[Autoparry] Server: Autoparry frames active (0.4s)")
end

function Autoparry:OnStartClient()
	print("[Autoparry] Client: Autoparry frames active - Free parries!")
end

function Autoparry:OnEndServer()
	print("[Autoparry] Server: Autoparry frames ended")
end

function Autoparry:OnEndClient()
	print("[Autoparry] Client: Autoparry frames ended")
end

return Autoparry
