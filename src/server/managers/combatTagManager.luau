--!strict
-- CombatTagManager
-- Tracks players in combat to prevent combat logging
-- When a tagged player leaves, their last attacker gets kill credit

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Configuration
local COMBAT_TAG_DURATION = 30 -- seconds

-- Types
type TagState = {
	taggedUntil: number,
	lastAttacker: Player?,
}

local CombatTagManager = {}
CombatTagManager.__index = CombatTagManager

-- Singleton instance
local instance: CombatTagManager? = nil

export type CombatTagManager = typeof(setmetatable({} :: {
	_taggedPlayers: { [Player]: TagState },
	_connections: { RBXScriptConnection },
	_updateRemote: RemoteEvent?,
}, CombatTagManager))

function CombatTagManager.new(): CombatTagManager
	if instance then
		return instance
	end

	local self = setmetatable({
		_taggedPlayers = {} :: { [Player]: TagState },
		_connections = {} :: { RBXScriptConnection },
		_updateRemote = nil :: RemoteEvent?,
	}, CombatTagManager)

	self:_setup()

	instance = self
	print("[CombatTagManager] Initialized")
	return self
end

function CombatTagManager:_setup()
	-- Get or create the remote event
	self._updateRemote = ReplicatedStorage:FindFirstChild("CombatTagUpdate") :: RemoteEvent?
	if not self._updateRemote then
		local remote = Instance.new("RemoteEvent")
		remote.Name = "CombatTagUpdate"
		remote.Parent = ReplicatedStorage
		self._updateRemote = remote
	end

	-- Handle players leaving - check for combat log
	local leavingConn = Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
	table.insert(self._connections, leavingConn)

	-- Heartbeat loop to expire tags and update clients
	local heartbeatConn = RunService.Heartbeat:Connect(function()
		self:_updateLoop()
	end)
	table.insert(self._connections, heartbeatConn)
end

-- Tag a player as in combat
function CombatTagManager:tagPlayer(player: Player, attacker: Player?)
	local now = os.clock()
	local expiresAt = now + COMBAT_TAG_DURATION

	local wasTagged = self._taggedPlayers[player] ~= nil

	self._taggedPlayers[player] = {
		taggedUntil = expiresAt,
		lastAttacker = attacker or (self._taggedPlayers[player] and self._taggedPlayers[player].lastAttacker),
	}

	-- Notify client
	if self._updateRemote then
		self._updateRemote:FireClient(player, true, COMBAT_TAG_DURATION)
	end

	if not wasTagged then
		print(`[CombatTagManager] {player.Name} is now in combat`)
	end
end

-- Check if a player is tagged
function CombatTagManager:isTagged(player: Player): boolean
	local state = self._taggedPlayers[player]
	if not state then
		return false
	end
	return os.clock() < state.taggedUntil
end

-- Get time remaining on tag
function CombatTagManager:getTimeRemaining(player: Player): number
	local state = self._taggedPlayers[player]
	if not state then
		return 0
	end
	return math.max(0, state.taggedUntil - os.clock())
end

-- Get last attacker
function CombatTagManager:getLastAttacker(player: Player): Player?
	local state = self._taggedPlayers[player]
	return state and state.lastAttacker
end

-- Called when a player leaves
function CombatTagManager:_onPlayerRemoving(player: Player)
	local state = self._taggedPlayers[player]

	if state and os.clock() < state.taggedUntil then
		-- Player combat logged!
		local attacker = state.lastAttacker

		if attacker and attacker.Parent then
			-- Award kill to attacker
			print(`[CombatTagManager] {player.Name} COMBAT LOGGED - kill awarded to {attacker.Name}`)

			-- Increment attacker's kill stat (if you have leaderstats)
			local leaderstats = attacker:FindFirstChild("leaderstats")
			if leaderstats then
				local kills = leaderstats:FindFirstChild("Kills")
				if kills and kills:IsA("IntValue") then
					kills.Value = kills.Value + 1
				end
			end

			-- Fire event for any listeners (could be used for kill feed, etc.)
			local combatLogEvent = ReplicatedStorage:FindFirstChild("PlayerCombatLogged") :: RemoteEvent?
			if combatLogEvent then
				combatLogEvent:FireAllClients(player.Name, attacker.Name)
			end
		else
			print(`[CombatTagManager] {player.Name} COMBAT LOGGED - no attacker to award`)
		end
	end

	-- Clean up
	self._taggedPlayers[player] = nil
end

-- Heartbeat update loop
local lastUpdate = 0
local UPDATE_INTERVAL = 1 -- Update clients every second

function CombatTagManager:_updateLoop()
	local now = os.clock()

	-- Only update clients periodically
	if now - lastUpdate < UPDATE_INTERVAL then
		return
	end
	lastUpdate = now

	-- Check each tagged player
	for player, state in pairs(self._taggedPlayers) do
		if not player.Parent then
			-- Player left, clean up
			self._taggedPlayers[player] = nil
		elseif now >= state.taggedUntil then
			-- Tag expired
			self._taggedPlayers[player] = nil
			print(`[CombatTagManager] {player.Name} is no longer in combat`)

			-- Notify client
			if self._updateRemote then
				self._updateRemote:FireClient(player, false, 0)
			end
		else
			-- Update client with remaining time
			local remaining = math.ceil(state.taggedUntil - now)
			if self._updateRemote then
				self._updateRemote:FireClient(player, true, remaining)
			end
		end
	end
end

function CombatTagManager:destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
	self._taggedPlayers = {}
	instance = nil
end

return CombatTagManager
