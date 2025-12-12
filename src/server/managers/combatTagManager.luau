--!strict
-- CombatTagManager
-- Tracks players in combat to prevent combat logging
-- Supports multiple attackers per player - displays the tag with most time remaining
-- Includes "mb" and "sorry" chat commands to remove combat tags

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Configuration
local COMBAT_TAG_DURATION = 30 -- seconds

-- Types
-- Each player can have multiple tags from different attackers
-- Maps: victim -> { attacker -> expiresAt }
type AttackerTags = { [Player]: number }

local CombatTagManager = {}
CombatTagManager.__index = CombatTagManager

-- Singleton instance
local instance: CombatTagManager? = nil

export type CombatTagManager = typeof(setmetatable({} :: {
	_taggedPlayers: { [Player]: AttackerTags },
	_pausedPlayers: { [Player]: boolean }, -- Players with paused combat tags
	_connections: { RBXScriptConnection },
	_updateRemote: RemoteEvent?,
}, CombatTagManager))

function CombatTagManager.new(): CombatTagManager
	if instance then
		return instance
	end

	local self = setmetatable({
		_taggedPlayers = {} :: { [Player]: AttackerTags },
		_pausedPlayers = {} :: { [Player]: boolean },
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

	-- Setup chat commands
	self:_setupChatCommands()
end

-- Setup chat command listeners for mb/sorry
function CombatTagManager:_setupChatCommands()
	Players.PlayerAdded:Connect(function(player)
		self:_connectPlayerChat(player)
	end)

	-- Connect existing players
	for _, player in ipairs(Players:GetPlayers()) do
		self:_connectPlayerChat(player)
	end
end

function CombatTagManager:_connectPlayerChat(player: Player)
	player.Chatted:Connect(function(message)
		self:_handleChatCommand(player, message)
	end)
end

function CombatTagManager:_handleChatCommand(speaker: Player, message: string)
	-- Normalize message to lowercase for case-insensitive matching
	local lowerMessage = string.lower(message)

	-- Check for "mb all" or "sorry all"
	if lowerMessage == "mb all" or lowerMessage == "sorry all" then
		self:removeTagsFromAttacker(speaker)
		print(`[CombatTagManager] {speaker.Name} used '{message}' - removed all their combat tags`)
		return
	end

	-- Check for "mb <name>" or "sorry <name>"
	local mbTarget = string.match(lowerMessage, "^mb%s+(.+)$")
	local sorryTarget = string.match(lowerMessage, "^sorry%s+(.+)$")
	local targetName = mbTarget or sorryTarget

	if targetName and targetName ~= "all" then
		-- Find player by first name (case-insensitive)
		local targetPlayer = self:_findPlayerByFirstName(targetName)

		if targetPlayer then
			self:removeTagFromPlayer(targetPlayer, speaker)
			print(`[CombatTagManager] {speaker.Name} used '{message}' - removed combat tag from {targetPlayer.Name}`)
		else
			-- Player not found - could send a message but for now just ignore
			print(`[CombatTagManager] {speaker.Name} tried '{message}' but no player found with name '{targetName}'`)
		end
	end
end

-- Find a player by their character's first name (case-insensitive)
function CombatTagManager:_findPlayerByFirstName(name: string): Player?
	local lowerName = string.lower(name)

	for _, player in ipairs(Players:GetPlayers()) do
		-- Check display name first
		if string.lower(player.DisplayName) == lowerName then
			return player
		end

		-- Check username
		if string.lower(player.Name) == lowerName then
			return player
		end

		-- Check character name if different
		if player.Character and string.lower(player.Character.Name) == lowerName then
			return player
		end
	end

	return nil
end

-- Tag a player as in combat
function CombatTagManager:tagPlayer(player: Player, attacker: Player?)
	local now = os.clock()
	local expiresAt = now + COMBAT_TAG_DURATION

	-- Initialize tag table for this player if needed
	if not self._taggedPlayers[player] then
		self._taggedPlayers[player] = {}
	end

	-- Add or update the tag from this attacker
	if attacker then
		self._taggedPlayers[player][attacker] = expiresAt
	end

	-- Notify client with the longest remaining time
	self:_updateClientTag(player)

	print(`[CombatTagManager] {player.Name} tagged by {attacker and attacker.Name or "unknown"}`)
end

-- Remove a specific attacker's tag from a player
function CombatTagManager:removeTagFromPlayer(player: Player, attacker: Player)
	local tags = self._taggedPlayers[player]
	if not tags then
		return
	end

	if tags[attacker] then
		tags[attacker] = nil
		print(`[CombatTagManager] Removed {attacker.Name}'s tag from {player.Name}`)

		-- Check if player has any remaining tags
		local hasRemainingTags = false
		for _ in pairs(tags) do
			hasRemainingTags = true
			break
		end

		if not hasRemainingTags then
			self._taggedPlayers[player] = nil
			self._pausedPlayers[player] = nil
		end

		-- Update client
		self:_updateClientTag(player)
	end
end

-- Remove all tags from a specific attacker (for all players they tagged)
function CombatTagManager:removeTagsFromAttacker(attacker: Player)
	for player, tags in pairs(self._taggedPlayers) do
		if tags[attacker] then
			tags[attacker] = nil

			-- Check if player has any remaining tags
			local hasRemainingTags = false
			for _ in pairs(tags) do
				hasRemainingTags = true
				break
			end

			if not hasRemainingTags then
				self._taggedPlayers[player] = nil
				self._pausedPlayers[player] = nil
			end

			-- Update client
			self:_updateClientTag(player)
		end
	end
end

-- Get the longest remaining tag time and its attacker
function CombatTagManager:_getLongestTag(player: Player): (number, Player?)
	local tags = self._taggedPlayers[player]
	if not tags then
		return 0, nil
	end

	local now = os.clock()
	local longestTime = 0
	local longestAttacker: Player? = nil

	for attacker, expiresAt in pairs(tags) do
		local remaining = expiresAt - now
		if remaining > longestTime then
			longestTime = remaining
			longestAttacker = attacker
		end
	end

	return math.max(0, longestTime), longestAttacker
end

-- Update the client with their current tag status
function CombatTagManager:_updateClientTag(player: Player)
	if not self._updateRemote or not player.Parent then
		return
	end

	local remaining, _ = self:_getLongestTag(player)

	if remaining > 0 then
		self._updateRemote:FireClient(player, true, math.ceil(remaining))
	else
		self._updateRemote:FireClient(player, false, 0)
	end
end

-- Check if a player is tagged
function CombatTagManager:isTagged(player: Player): boolean
	local remaining, _ = self:_getLongestTag(player)
	return remaining > 0
end

-- Get time remaining on tag (longest one)
function CombatTagManager:getTimeRemaining(player: Player): number
	local remaining, _ = self:_getLongestTag(player)
	return remaining
end

-- Get last attacker (the one with longest remaining tag)
function CombatTagManager:getLastAttacker(player: Player): Player?
	local _, attacker = self:_getLongestTag(player)
	return attacker
end

-- Clear all combat tags for a player (called on death)
function CombatTagManager:clearTag(player: Player)
	if not self._taggedPlayers[player] then
		return
	end

	self._taggedPlayers[player] = nil
	self._pausedPlayers[player] = nil
	print(`[CombatTagManager] {player.Name}'s combat tag cleared`)

	-- Notify client
	if self._updateRemote and player.Parent then
		self._updateRemote:FireClient(player, false, 0)
	end
end

-- Clear combat tags for all players who were tagged by a specific attacker
-- Called when the attacker dies - their victims are no longer in combat with them
function CombatTagManager:clearTagsFromAttacker(attacker: Player)
	self:removeTagsFromAttacker(attacker)
	print(`[CombatTagManager] All tags from {attacker.Name} cleared (attacker died)`)
end

-- Pause combat tag countdown (used during carry - tag stays at max)
function CombatTagManager:pauseTag(player: Player)
	if not self._taggedPlayers[player] then
		-- Tag them first if not tagged
		self:tagPlayer(player, nil)
	end

	self._pausedPlayers[player] = true

	-- Update client to show full duration (paused at max)
	if self._updateRemote and player.Parent then
		self._updateRemote:FireClient(player, true, COMBAT_TAG_DURATION)
	end

	print(`[CombatTagManager] {player.Name}'s combat tag PAUSED (will stay at max)`)
end

-- Resume combat tag countdown
function CombatTagManager:resumeTag(player: Player)
	if not self._pausedPlayers[player] then
		return
	end

	self._pausedPlayers[player] = nil

	-- Reset all tags to full duration when resuming
	local tags = self._taggedPlayers[player]
	if tags then
		local now = os.clock()
		for attacker in pairs(tags) do
			tags[attacker] = now + COMBAT_TAG_DURATION
		end
	end

	print(`[CombatTagManager] {player.Name}'s combat tag RESUMED (counting down again)`)
end

-- Check if tag is paused
function CombatTagManager:isTagPaused(player: Player): boolean
	return self._pausedPlayers[player] == true
end

-- Called when a player leaves
function CombatTagManager:_onPlayerRemoving(player: Player)
	local tags = self._taggedPlayers[player]

	if tags then
		local remaining, attacker = self:_getLongestTag(player)

		if remaining > 0 then
			-- Player combat logged!
			if attacker and attacker.Parent then
				-- Award kill to attacker with longest tag
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
	end

	-- Clean up - also remove this player as an attacker from all other players
	self._taggedPlayers[player] = nil
	self._pausedPlayers[player] = nil

	-- Remove this player as an attacker from everyone else
	for otherPlayer, otherTags in pairs(self._taggedPlayers) do
		if otherTags[player] then
			otherTags[player] = nil

			-- Check if other player has remaining tags
			local hasRemainingTags = false
			for _ in pairs(otherTags) do
				hasRemainingTags = true
				break
			end

			if not hasRemainingTags then
				self._taggedPlayers[otherPlayer] = nil
				self._pausedPlayers[otherPlayer] = nil
			end

			self:_updateClientTag(otherPlayer)
		end
	end
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
	for player, tags in pairs(self._taggedPlayers) do
		if not player.Parent then
			-- Player left, clean up
			self._taggedPlayers[player] = nil
			self._pausedPlayers[player] = nil
		elseif self._pausedPlayers[player] then
			-- Tag is paused - refresh all tag expiries
			for attacker in pairs(tags) do
				tags[attacker] = now + COMBAT_TAG_DURATION
			end
			if self._updateRemote then
				self._updateRemote:FireClient(player, true, COMBAT_TAG_DURATION)
			end
		else
			-- Clean up expired tags
			local hasValidTags = false
			for attacker, expiresAt in pairs(tags) do
				if now >= expiresAt then
					tags[attacker] = nil
				else
					hasValidTags = true
				end
			end

			if not hasValidTags then
				-- All tags expired
				self._taggedPlayers[player] = nil
				self._pausedPlayers[player] = nil
				print(`[CombatTagManager] {player.Name} is no longer in combat`)

				if self._updateRemote then
					self._updateRemote:FireClient(player, false, 0)
				end
			else
				-- Update client with remaining time
				local remaining, _ = self:_getLongestTag(player)
				if self._updateRemote then
					self._updateRemote:FireClient(player, true, math.ceil(remaining))
				end
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
	self._pausedPlayers = {}
	instance = nil
end

return CombatTagManager
