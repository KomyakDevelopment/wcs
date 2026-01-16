--!strict
-- Loading Manager (Client)
-- Waits for server to be ready (remotes, assets, character)
-- Visual loading screen is handled by ReplicatedFirst

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

-- Required remote events that must exist before game starts
local REQUIRED_REMOTES = {
	"EquipWeapon",
	"PlayHitEffects",
	"PlayParryFlashVFX",
	"PlayParryVFX",
	"PlayBlockHitVFX",
	"PlayBlockHitAnimation",
	"PlayParriedAnimation",
	"PlayGotHitAnimation", -- Got-hit reaction animations
	"PlayerDeath",
	"PlayRollCancel",
	"PlayGuardbreak",
	"PlayerExecuted", -- Execution system
	"ConfirmExecution", -- Execution confirmation
	"RequestRespawn", -- Respawn request
	"RequestSpawn", -- Initial spawn request (after continue)
	"PlayCritVFX", -- Crit attack VFX (heavy punch, heavy slash)
}

-- Assets to preload (animation IDs, sounds, etc.)
local PRELOAD_ASSETS = {
	-- Add animation IDs here as needed
	-- "rbxassetid://123456789",
}

local TIMEOUT = 30 -- Max seconds to wait before giving up

local LoadingManager = {}
LoadingManager.__index = LoadingManager

function LoadingManager.new()
	local self = setmetatable({}, LoadingManager)

	self.player = Players.LocalPlayer
	self.isReady = false

	print("[LoadingManager] Initialized - waiting for server resources")
	return self
end

-- Wait for all required remotes to exist
function LoadingManager:waitForRemotes(): boolean
	print("[LoadingManager] Waiting for server remotes...")

	local startTime = tick()

	for _, remoteName in ipairs(REQUIRED_REMOTES) do
		local remote = ReplicatedStorage:WaitForChild(remoteName, TIMEOUT)
		if not remote then
			warn(`[LoadingManager] Timeout waiting for remote: {remoteName}`)
			return false
		end

		-- Check timeout
		if tick() - startTime > TIMEOUT then
			warn("[LoadingManager] Overall timeout reached")
			return false
		end
	end

	print("[LoadingManager] All remotes found")
	return true
end

-- Preload assets
function LoadingManager:preloadAssets()
	if #PRELOAD_ASSETS == 0 then
		return
	end

	print(`[LoadingManager] Preloading {#PRELOAD_ASSETS} assets...`)

	local assets = {}
	for _, assetId in ipairs(PRELOAD_ASSETS) do
		table.insert(assets, assetId)
	end

	ContentProvider:PreloadAsync(assets)
	print("[LoadingManager] Asset preloading complete")
end

-- Wait for character to be ready
function LoadingManager:waitForCharacter(): boolean
	print("[LoadingManager] Waiting for character...")

	local character = self.player.Character or self.player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid then
		warn("[LoadingManager] Character humanoid not found")
		return false
	end

	print("[LoadingManager] Character ready")
	return true
end

-- Main loading sequence
function LoadingManager:load(): boolean
	-- Wait for remotes
	if not self:waitForRemotes() then
		return false
	end

	-- Preload assets
	self:preloadAssets()

	-- Wait for character
	if not self:waitForCharacter() then
		return false
	end

	self.isReady = true
	print("[LoadingManager] Loading complete - ready to play")
	return true
end

-- No-op: Visual loading screen is handled by ReplicatedFirst
function LoadingManager:fadeOut()
	-- Kept for API compatibility
end

-- Clean up
function LoadingManager:destroy()
	-- No resources to clean up
end

return LoadingManager
