--!strict
-- Death Manager (Server)
-- Handles death lifecycle, lives, cleanup, and respawn
-- Deepwoken-style death: ragdoll, fade, then respawn

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local CharacterData = require(ReplicatedStorage.Shared.data.characterData)

-- Lazy load to avoid circular dependencies
local PostureManager = nil
local Iframes = nil

local function getPostureManager()
	if not PostureManager then
		PostureManager = require(ReplicatedStorage.Shared.managers.postureManager)
	end
	return PostureManager
end

local function getIframes()
	if not Iframes then
		Iframes = require(ReplicatedStorage.Shared.statusEffects.iframes)
	end
	return Iframes
end

-- Configuration
local RESPAWN_DELAY = 3.0 -- Seconds before respawn
local DEATH_IFRAMES_DURATION = 5.0 -- Iframes during death sequence (longer than respawn to be safe)

-- Remote events
local deathRemote: RemoteEvent = nil

local DeathManager = {}
DeathManager.__index = DeathManager

function DeathManager.new()
	local self = setmetatable({}, DeathManager)

	self._connections = {} :: { RBXScriptConnection }
	self._dyingPlayers = {} :: { [Player]: boolean } -- Track players currently in death sequence

	self:_setup()

	print("[DeathManager] Initialized")
	return self
end

function DeathManager:_setup()
	-- Get remote event (created in init.server.luau)
	deathRemote = ReplicatedStorage:FindFirstChild("PlayerDeath") :: RemoteEvent
	if not deathRemote then
		warn("[DeathManager] PlayerDeath remote not found - create it in init.server.luau")
	end

	-- Initialize character data for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		CharacterData.initialize(player)
		if player.Character then
			self:_setupCharacter(player, player.Character)
		end
	end

	-- Handle new players
	table.insert(
		self._connections,
		Players.PlayerAdded:Connect(function(player)
			CharacterData.initialize(player)
			player.CharacterAdded:Connect(function(character)
				self:_setupCharacter(player, character)
			end)
		end)
	)

	-- Handle existing players' future characters
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(
			self._connections,
			player.CharacterAdded:Connect(function(character)
				self:_setupCharacter(player, character)
			end)
		)
	end
end

function DeathManager:_setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		warn(`[DeathManager] Humanoid not found for {player.Name}`)
		return
	end

	-- Disable BreakJointsOnDeath for custom death handling
	humanoid.BreakJointsOnDeath = false

	-- Listen for death
	humanoid.Died:Connect(function()
		self:_handleDeath(player, character, humanoid)
	end)
end

function DeathManager:_handleDeath(player: Player, character: Model, humanoid: Humanoid)
	-- Prevent double-handling
	if self._dyingPlayers[player] then
		return
	end
	self._dyingPlayers[player] = true

	print(`[DeathManager] {player.Name} died`)

	-- Get WCS character for cleanup and iframes
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)

	-- Apply iframes during death sequence (prevents any lingering damage)
	if wcsCharacter then
		local IframesEffect = getIframes()
		local iframesInstance = IframesEffect.new(wcsCharacter)
		if iframesInstance then
			iframesInstance:Start(DEATH_IFRAMES_DURATION)
		end
	end

	-- Decrement lives
	local remainingLives = CharacterData.decrementLives(player)

	-- Fire death event to client (for ragdoll/fade effects)
	deathRemote:FireClient(player, {
		remainingLives = remainingLives,
		respawnDelay = RESPAWN_DELAY,
	})

	-- Fire to all clients for spectator view (optional)
	deathRemote:FireAllClients({
		playerName = player.Name,
		character = character,
		isLocalDeath = false,
	})

	-- Cleanup (posture, status effects, etc.)
	self:_cleanup(player, character, wcsCharacter)

	-- Handle respawn or permadeath
	if remainingLives > 0 then
		-- Wait for death sequence, then respawn
		task.delay(RESPAWN_DELAY, function()
			self._dyingPlayers[player] = nil

			-- Respawn the player
			if player and player.Parent then
				player:LoadCharacter()
				print(`[DeathManager] {player.Name} respawned with {remainingLives} lives remaining`)
			end
		end)
	else
		-- Permadeath - character wiped
		print(`[DeathManager] {player.Name} has no lives remaining - PERMADEATH`)
		CharacterData.wipeCharacter(player)

		-- For now, kick with message (later: character creation screen)
		task.delay(RESPAWN_DELAY + 1, function()
			self._dyingPlayers[player] = nil

			if player and player.Parent then
				player:Kick("Your character has died permanently. Create a new character to continue.")
			end
		end)
	end
end

function DeathManager:_cleanup(player: Player, character: Model, wcsCharacter: any)
	-- Reset posture
	local postureManager = getPostureManager()
	if postureManager then
		postureManager.cleanupCharacter(character)
	end

	-- End all active skills
	if wcsCharacter then
		-- Get all skills and end them
		local skills = wcsCharacter:GetAllActiveSkills()
		if skills then
			for _, skill in ipairs(skills) do
				skill:End()
			end
		end

		-- Clear status effects (except iframes we just applied)
		local statusEffects = wcsCharacter:GetAllStatusEffects()
		if statusEffects then
			for _, effect in ipairs(statusEffects) do
				-- Don't remove iframes during death
				if effect.Name ~= "Iframes" then
					effect:End()
				end
			end
		end
	end

	-- Cleanup equipment manager
	if wcsCharacter and wcsCharacter.EquipmentManager then
		wcsCharacter.EquipmentManager:destroy()
		wcsCharacter.EquipmentManager = nil
	end

	print(`[DeathManager] Cleanup complete for {player.Name}`)
end

function DeathManager:destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}

	if deathRemote then
		deathRemote:Destroy()
	end
end

return DeathManager
