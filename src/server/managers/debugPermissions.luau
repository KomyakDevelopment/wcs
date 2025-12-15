--!strict
-- Debug Permissions Manager (Server)
-- Handles whitelist validation for debug commands
-- SECURITY: Whitelist is server-side only, never sent to clients

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugPermissions = {}

-- WHITELIST: Only these players can access debug commands
-- This table is SERVER-SIDE ONLY and cannot be accessed by clients
local AUTHORIZED_USERS = {
	["97vsc"] = true,
	["vvvjuniper"] = true,
	["CandiedRX1"] = true,
}

-- Remote for debug requests (created on init)
local debugRemote: RemoteFunction?

function DebugPermissions.init()
	-- Create remote for debug permission checks
	local remote = Instance.new("RemoteFunction")
	remote.Name = "DebugPermissionCheck"
	remote.Parent = ReplicatedStorage
	debugRemote = remote

	-- Handle permission check requests
	remote.OnServerInvoke = function(player: Player, commandType: string)
		return DebugPermissions.isAuthorized(player, commandType)
	end

	print("[DebugPermissions] Initialized")
end

function DebugPermissions.isAuthorized(player: Player, _commandType: string?): boolean
	-- Check if player's username is in the whitelist
	return AUTHORIZED_USERS[player.Name] == true
end

-- Get authorized status without exposing the list
function DebugPermissions.getAuthorizedPlayers(): { Player }
	local authorized = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if DebugPermissions.isAuthorized(player) then
			table.insert(authorized, player)
		end
	end
	return authorized
end

return DebugPermissions
