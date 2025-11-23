--!strict
-- Posture Manager (Singleton)
-- Server-authoritative posture system
-- Handles posture damage, recovery, and guardbreak

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local WCS = require(ReplicatedStorage.Packages.wcs)

-- Lazy load to avoid circular dependencies
local Guardbroken = nil
local Blocking = nil
local Block = nil

local function getGuardbroken()
	if not Guardbroken then
		Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
	end
	return Guardbroken
end

local function getBlocking()
	if not Blocking then
		Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
	end
	return Blocking
end

local function getBlock()
	if not Block then
		Block = require(ReplicatedStorage.Shared.skills.block)
	end
	return Block
end

-- Configuration
local DEFAULT_MAX_POSTURE = 100
local RECOVERY_DELAY = 1.0 -- Seconds before recovery starts
local RECOVERY_RATE = 0.02 -- 2% of max per second
local RECOVERY_RATE_BLOCKING = 0.01 -- 1% while blocking (50% slower)
local GUARDBREAK_DURATION = 1.5

-- Posture damage values (placeholders until stats system)
local BLOCK_POSTURE_DAMAGE = 15 -- Per blocked M1
local PARRY_POSTURE_REWARD = 20 -- Defender gains on successful parry (negative = reduction)
local PARRIED_POSTURE_DAMAGE = 30 -- Attacker loses when parried (capped at 99%)

export type PostureData = {
	current: number,
	max: number,
	lastActionTime: number,
	wcsCharacter: any, -- WCS Character reference
}

-- Per-character posture data (keyed by character Instance)
local postureData: { [Model]: PostureData } = {}

-- Singleton instance
local PostureManager = {}
local initialized = false

-- Initialize the manager (called automatically on server)
local function initialize()
	if initialized then
		return
	end
	initialized = true

	-- Only run on server
	if not RunService:IsServer() then
		return
	end

	-- Setup player lifecycle hooks
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			PostureManager.initializeCharacter(player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			PostureManager.initializeCharacter(character)
		end)
	end

	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			PostureManager.initializeCharacter(character)
		end)
	end)

	-- Cleanup on player leaving
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			PostureManager.cleanupCharacter(player.Character)
		end
	end)

	-- Start recovery loop
	RunService.Heartbeat:Connect(function(dt)
		PostureManager._updateRecovery(dt)
	end)

	print("[PostureManager] Initialized (singleton) - Recovery loop started")
end

-- Initialize posture for a character (call AFTER WCS character is created)
function PostureManager.initializeCharacter(character: Model, wcsCharacter: any?)
	-- Skip if already initialized
	if postureData[character] then
		return
	end

	-- If WCS character not provided, try to get it
	local wcsChar = wcsCharacter
	if not wcsChar then
		wcsChar = WCS.Character.GetCharacterFromInstance(character)
	end

	if not wcsChar then
		warn(`[PostureManager] WCS Character not found for {character.Name}`)
		return
	end

	-- Initialize posture data
	postureData[character] = {
		current = 0,
		max = DEFAULT_MAX_POSTURE,
		lastActionTime = 0,
		wcsCharacter = wcsChar,
	}

	-- Set attributes for client UI
	character:SetAttribute("Posture", 0)
	character:SetAttribute("MaxPosture", DEFAULT_MAX_POSTURE)

	print(`[PostureManager] Initialized posture for {character.Name}`)
end

-- Cleanup posture data for a character
function PostureManager.cleanupCharacter(character: Model)
	postureData[character] = nil
	print(`[PostureManager] Cleaned up posture for {character.Name}`)
end

-- Add posture damage (for blocking hits)
function PostureManager.addPosture(character: Model, amount: number)
	local data = postureData[character]
	if not data then
		warn(`[PostureManager] No posture data for {character.Name}`)
		return
	end

	data.current = math.min(data.max, data.current + amount)
	data.lastActionTime = tick()

	-- Update attribute for client UI
	character:SetAttribute("Posture", data.current)

	print(`[PostureManager] {character.Name} posture: {data.current}/{data.max} (+{amount})`)

	-- Check for guardbreak
	if data.current >= data.max then
		PostureManager._triggerGuardbreak(character, data)
	end
end

-- Add posture damage capped at 99% (for getting parried - can never guardbreak from parry alone)
function PostureManager.addPostureCapped(character: Model, amount: number)
	local data = postureData[character]
	if not data then
		warn(`[PostureManager] No posture data for {character.Name}`)
		return
	end

	-- Cap at 99% of max posture
	local maxAllowed = data.max * 0.99
	local newPosture = math.min(maxAllowed, data.current + amount)

	data.current = newPosture
	data.lastActionTime = tick()

	-- Update attribute for client UI
	character:SetAttribute("Posture", data.current)

	print(`[PostureManager] {character.Name} posture (capped): {data.current}/{data.max} (+{amount})`)
end

-- Remove posture (reward for successful parry)
function PostureManager.removePosture(character: Model, amount: number)
	local data = postureData[character]
	if not data then
		return
	end

	data.current = math.max(0, data.current - amount)
	data.lastActionTime = tick()

	-- Update attribute for client UI
	character:SetAttribute("Posture", data.current)

	print(`[PostureManager] {character.Name} posture: {data.current}/{data.max} (-{amount})`)
end

-- Get current posture
function PostureManager.getPosture(character: Model): number
	local data = postureData[character]
	return data and data.current or 0
end

-- Get max posture
function PostureManager.getMaxPosture(character: Model): number
	local data = postureData[character]
	return data and data.max or DEFAULT_MAX_POSTURE
end

-- Check if character is guardbroken
function PostureManager.isGuardbroken(character: Model): boolean
	local data = postureData[character]
	if not data or not data.wcsCharacter then
		return false
	end

	return data.wcsCharacter.IsGuardbroken == true
end

-- Trigger guardbreak on a character
function PostureManager._triggerGuardbreak(character: Model, data: PostureData)
	if not data.wcsCharacter then
		return
	end

	-- Don't double-trigger if already guardbroken
	if data.wcsCharacter.IsGuardbroken then
		return
	end

	print(`[PostureManager] GUARDBREAK on {character.Name}!`)

	-- End Block skill if active (can't block while guardbroken)
	local BlockSkill = getBlock()
	local blockSkill = data.wcsCharacter:GetSkillFromConstructor(BlockSkill)
	if blockSkill then
		local blockState = blockSkill:GetState()
		if blockState.IsActive then
			blockSkill:End()
			print(`[PostureManager] Ended Block skill for {character.Name} - Guardbroken`)
		end
	end

	-- Apply Guardbroken status effect
	local GuardbrokenEffect = getGuardbroken()
	local guardbrokenInstance = GuardbrokenEffect.new(data.wcsCharacter)
	if guardbrokenInstance then
		guardbrokenInstance:Start(GUARDBREAK_DURATION)
	end

	-- Reset posture after guardbreak ends
	task.delay(GUARDBREAK_DURATION, function()
		if postureData[character] then
			postureData[character].current = 0
			postureData[character].lastActionTime = tick()
			character:SetAttribute("Posture", 0)
			print(`[PostureManager] {character.Name} posture reset after guardbreak`)
		end
	end)
end

-- Update posture recovery for all characters
function PostureManager._updateRecovery(dt: number)
	local currentTime = tick()

	for character, data in pairs(postureData) do
		-- Skip if character no longer exists
		if not character or not character.Parent then
			postureData[character] = nil
			continue
		end

		-- Skip if guardbroken (no recovery during guardbreak)
		if data.wcsCharacter and data.wcsCharacter.IsGuardbroken then
			continue
		end

		-- Skip if no posture to recover
		if data.current <= 0 then
			continue
		end

		-- Check if recovery delay has passed
		local timeSinceAction = currentTime - data.lastActionTime
		if timeSinceAction < RECOVERY_DELAY then
			continue
		end

		-- Determine recovery rate (slower while blocking)
		local rate = RECOVERY_RATE
		if data.wcsCharacter then
			local BlockingEffect = getBlocking()
			if data.wcsCharacter:HasStatusEffects({ BlockingEffect }) then
				rate = RECOVERY_RATE_BLOCKING
			end
		end

		-- Apply recovery
		local recovery = data.max * rate * dt
		local oldPosture = data.current
		data.current = math.max(0, data.current - recovery)

		-- Update attribute for client UI
		character:SetAttribute("Posture", data.current)

		-- Debug: Print when posture crosses integer thresholds
		if math.floor(oldPosture) ~= math.floor(data.current) then
			print(`[PostureManager] {character.Name} posture recovering: {math.floor(data.current)}/{data.max}`)
		end
	end
end

-- Get posture damage values (for external use)
function PostureManager.getBlockPostureDamage(): number
	return BLOCK_POSTURE_DAMAGE
end

function PostureManager.getParryPostureReward(): number
	return PARRY_POSTURE_REWARD
end

function PostureManager.getParriedPostureDamage(): number
	return PARRIED_POSTURE_DAMAGE
end

-- Dummy new() for backwards compatibility with init.server.luau
function PostureManager.new()
	initialize()
	return PostureManager
end

-- Auto-initialize when required on server
initialize()

return PostureManager
