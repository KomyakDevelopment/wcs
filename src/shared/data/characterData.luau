--!strict
-- Character Data Module
-- Stores character information using Player attributes (DataStore later)
-- Handles lives, identity, and character state

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Configuration
local DEFAULT_LIVES = 3
local MAX_LIVES = 3

export type CharacterInfo = {
	characterId: string,
	firstName: string,
	lastName: string,
	gender: string,
	village: string,
	lives: number,
}

local CharacterData = {}

-- Initialize character data for a player (server only)
function CharacterData.initialize(player: Player)
	if not RunService:IsServer() then
		warn("[CharacterData] initialize() can only be called on server")
		return
	end

	-- Set default attributes if not already set
	if player:GetAttribute("Lives") == nil then
		player:SetAttribute("Lives", DEFAULT_LIVES)
	end

	-- Stub identity data (will be set during character creation later)
	if player:GetAttribute("CharacterId") == nil then
		player:SetAttribute("CharacterId", "")
	end
	if player:GetAttribute("FirstName") == nil then
		player:SetAttribute("FirstName", "")
	end
	if player:GetAttribute("LastName") == nil then
		player:SetAttribute("LastName", "")
	end
	if player:GetAttribute("Gender") == nil then
		player:SetAttribute("Gender", "")
	end
	if player:GetAttribute("Village") == nil then
		player:SetAttribute("Village", "")
	end

	print(`[CharacterData] Initialized data for {player.Name} with {DEFAULT_LIVES} lives`)
end

-- Get current lives
function CharacterData.getLives(player: Player): number
	return player:GetAttribute("Lives") or 0
end

-- Set lives (server only)
function CharacterData.setLives(player: Player, lives: number)
	if not RunService:IsServer() then
		warn("[CharacterData] setLives() can only be called on server")
		return
	end

	lives = math.clamp(lives, 0, MAX_LIVES)
	player:SetAttribute("Lives", lives)
	print(`[CharacterData] {player.Name} lives set to {lives}`)
end

-- Decrement lives by 1, returns new lives count
function CharacterData.decrementLives(player: Player): number
	if not RunService:IsServer() then
		warn("[CharacterData] decrementLives() can only be called on server")
		return CharacterData.getLives(player)
	end

	local currentLives = CharacterData.getLives(player)
	local newLives = math.max(0, currentLives - 1)
	player:SetAttribute("Lives", newLives)
	print(`[CharacterData] {player.Name} lost a life: {currentLives} -> {newLives}`)
	return newLives
end

-- Reset lives to max (server only)
function CharacterData.resetLives(player: Player)
	if not RunService:IsServer() then
		warn("[CharacterData] resetLives() can only be called on server")
		return
	end

	player:SetAttribute("Lives", MAX_LIVES)
	print(`[CharacterData] {player.Name} lives reset to {MAX_LIVES}`)
end

-- Check if player has lives remaining
function CharacterData.hasLives(player: Player): boolean
	return CharacterData.getLives(player) > 0
end

-- Get full character info
function CharacterData.getCharacterInfo(player: Player): CharacterInfo
	return {
		characterId = player:GetAttribute("CharacterId") or "",
		firstName = player:GetAttribute("FirstName") or "",
		lastName = player:GetAttribute("LastName") or "",
		gender = player:GetAttribute("Gender") or "",
		village = player:GetAttribute("Village") or "",
		lives = CharacterData.getLives(player),
	}
end

-- Wipe character data (for permadeath)
function CharacterData.wipeCharacter(player: Player)
	if not RunService:IsServer() then
		warn("[CharacterData] wipeCharacter() can only be called on server")
		return
	end

	player:SetAttribute("CharacterId", "")
	player:SetAttribute("FirstName", "")
	player:SetAttribute("LastName", "")
	player:SetAttribute("Gender", "")
	player:SetAttribute("Village", "")
	player:SetAttribute("Lives", 0)

	print(`[CharacterData] Character data wiped for {player.Name}`)
end

-- Get max lives constant
function CharacterData.getMaxLives(): number
	return MAX_LIVES
end

return CharacterData
