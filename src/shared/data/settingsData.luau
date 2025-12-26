--!strict
-- Settings Data Module
-- Handles saving and loading player settings via DataStore
-- Uses dirty-flag pattern with throttled saves to respect DataStore limits

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local SETTINGS_DATASTORE_NAME = "PlayerSettings_v1"
local SETTINGS_CACHE_KEY = "_SettingsCache"

-- Throttle configuration (Roblox allows ~60 requests/min per key, we stay well under)
local MIN_SAVE_INTERVAL = 6 -- Minimum seconds between saves per player
local AUTO_SAVE_INTERVAL = 30 -- Auto-save dirty settings every 30 seconds

-- Default settings
local DEFAULT_SETTINGS = {
	-- Volume settings (0-1)
	masterVolume = 1.0,
	musicVolume = 0.5,
	sfxVolume = 1.0,

	-- Feature toggles
	dynamicFOV = true,
}

export type PlayerSettings = typeof(DEFAULT_SETTINGS)

-- Per-player save state tracking (server only)
type PlayerSaveState = {
	lastSaveTime: number,
	isDirty: boolean,
	pendingSave: thread?,
}

local SettingsData = {}

-- Track save state per player (userId -> state)
local playerSaveStates: { [number]: PlayerSaveState } = {}

-- Get DataStore (only on server)
local settingsStore: DataStore? = nil
if RunService:IsServer() then
	local success, store = pcall(function()
		return DataStoreService:GetDataStore(SETTINGS_DATASTORE_NAME)
	end)
	if success then
		settingsStore = store
	else
		warn("[SettingsData] Failed to get DataStore:", store)
	end
end

-- Get or create save state for a player
local function getSaveState(player: Player): PlayerSaveState
	local userId = player.UserId
	if not playerSaveStates[userId] then
		playerSaveStates[userId] = {
			lastSaveTime = 0,
			isDirty = false,
			pendingSave = nil,
		}
	end
	return playerSaveStates[userId]
end

-- Clean up save state when player leaves
local function cleanupSaveState(player: Player)
	local userId = player.UserId
	local state = playerSaveStates[userId]
	if state and state.pendingSave then
		task.cancel(state.pendingSave)
	end
	playerSaveStates[userId] = nil
end

-- Get default settings (returns a copy)
function SettingsData.getDefaults(): PlayerSettings
	return table.clone(DEFAULT_SETTINGS) :: PlayerSettings
end

-- Load settings for a player (server only)
function SettingsData.load(player: Player): PlayerSettings
	if not RunService:IsServer() then
		warn("[SettingsData] load() can only be called on server")
		return SettingsData.getDefaults()
	end

	-- Initialize save state
	getSaveState(player)

	-- Check cache first
	local cached = player:GetAttribute(SETTINGS_CACHE_KEY)
	if cached then
		local success, decoded = pcall(function()
			return HttpService:JSONDecode(cached)
		end)
		if success and decoded then
			return SettingsData._mergeWithDefaults(decoded)
		end
	end

	-- Load from DataStore
	if settingsStore then
		local success, data = pcall(function()
			return settingsStore:GetAsync("player_" .. player.UserId)
		end)

		if success and data then
			local settings = SettingsData._mergeWithDefaults(data)
			-- Cache it
			SettingsData._cacheSettings(player, settings)
			print(`[SettingsData] Loaded settings for {player.Name}`)
			return settings
		elseif not success then
			warn(`[SettingsData] Failed to load settings for {player.Name}: {data}`)
		end
	end

	-- Return defaults if no saved data
	local defaults = SettingsData.getDefaults()
	SettingsData._cacheSettings(player, defaults)
	print(`[SettingsData] Using default settings for {player.Name}`)
	return defaults
end

-- Internal: Actually save to DataStore (bypasses throttling)
function SettingsData._saveToDataStore(player: Player, settings: PlayerSettings): boolean
	if not settingsStore then
		return false
	end

	local success, err = pcall(function()
		settingsStore:SetAsync("player_" .. player.UserId, settings)
	end)

	if success then
		local state = getSaveState(player)
		state.lastSaveTime = os.clock()
		state.isDirty = false
		print(`[SettingsData] Saved settings for {player.Name}`)
		return true
	else
		warn(`[SettingsData] Failed to save settings for {player.Name}: {err}`)
		return false
	end
end

-- Save settings for a player with throttling (server only)
function SettingsData.save(player: Player, settings: PlayerSettings): boolean
	if not RunService:IsServer() then
		warn("[SettingsData] save() can only be called on server")
		return false
	end

	-- Always cache immediately for responsiveness
	SettingsData._cacheSettings(player, settings)

	local state = getSaveState(player)
	local now = os.clock()
	local timeSinceLastSave = now - state.lastSaveTime

	-- If enough time has passed, save immediately
	if timeSinceLastSave >= MIN_SAVE_INTERVAL then
		return SettingsData._saveToDataStore(player, settings)
	end

	-- Otherwise, mark dirty and schedule a save
	state.isDirty = true

	-- Cancel any existing pending save
	if state.pendingSave then
		task.cancel(state.pendingSave)
	end

	-- Schedule save after the minimum interval
	local delay = MIN_SAVE_INTERVAL - timeSinceLastSave
	state.pendingSave = task.delay(delay, function()
		-- Re-check player is still in game
		if player.Parent then
			local currentSettings = SettingsData.getCached(player)
			if currentSettings then
				SettingsData._saveToDataStore(player, currentSettings)
			end
		end
		state.pendingSave = nil
	end)

	return true -- Queued for save
end

-- Update multiple settings at once (server only) - used by batched client updates
function SettingsData.updateSettings(player: Player, changes: { [string]: any }): boolean
	if not RunService:IsServer() then
		warn("[SettingsData] updateSettings() can only be called on server")
		return false
	end

	local settings = SettingsData.load(player)
	local hasValidChanges = false

	for key, value in changes do
		if DEFAULT_SETTINGS[key] ~= nil and type(value) == type(DEFAULT_SETTINGS[key]) then
			(settings :: any)[key] = value
			hasValidChanges = true
		else
			warn(`[SettingsData] Invalid setting: {key}`)
		end
	end

	if hasValidChanges then
		return SettingsData.save(player, settings)
	end

	return false
end

-- Force save immediately (for player leaving) - bypasses throttling
function SettingsData.forceSave(player: Player): boolean
	if not RunService:IsServer() then
		return false
	end

	local state = playerSaveStates[player.UserId]

	-- Cancel any pending save
	if state and state.pendingSave then
		task.cancel(state.pendingSave)
		state.pendingSave = nil
	end

	-- Only save if dirty or never saved
	if state and (state.isDirty or state.lastSaveTime == 0) then
		local settings = SettingsData.getCached(player)
		if settings then
			return SettingsData._saveToDataStore(player, settings)
		end
	end

	return true -- Nothing to save
end

-- Clean up when player leaves (call from server init)
function SettingsData.onPlayerRemoving(player: Player)
	-- Force save any pending changes
	SettingsData.forceSave(player)
	-- Clean up state
	cleanupSaveState(player)
end

-- Get cached settings (can be called from client via attribute)
function SettingsData.getCached(player: Player): PlayerSettings?
	local cached = player:GetAttribute(SETTINGS_CACHE_KEY)
	if cached then
		local success, decoded = pcall(function()
			return HttpService:JSONDecode(cached)
		end)
		if success and decoded then
			return SettingsData._mergeWithDefaults(decoded)
		end
	end
	return nil
end

-- Merge loaded data with defaults (ensures all keys exist)
function SettingsData._mergeWithDefaults(data: any): PlayerSettings
	local merged = SettingsData.getDefaults()
	if type(data) == "table" then
		for key, defaultValue in DEFAULT_SETTINGS do
			if data[key] ~= nil and type(data[key]) == type(defaultValue) then
				(merged :: any)[key] = data[key]
			end
		end
	end
	return merged
end

-- Cache settings as player attribute (for client access)
function SettingsData._cacheSettings(player: Player, settings: PlayerSettings)
	local success, encoded = pcall(function()
		return HttpService:JSONEncode(settings)
	end)
	if success then
		player:SetAttribute(SETTINGS_CACHE_KEY, encoded)
	end
end

-- Start auto-save loop (call once from server init)
function SettingsData.startAutoSave()
	if not RunService:IsServer() then
		return
	end

	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)

			-- Save all dirty player settings
			for userId, state in playerSaveStates do
				if state.isDirty then
					local player = game:GetService("Players"):GetPlayerByUserId(userId)
					if player then
						local settings = SettingsData.getCached(player)
						if settings then
							SettingsData._saveToDataStore(player, settings)
						end
					end
				end
			end
		end
	end)

	print("[SettingsData] Auto-save loop started")
end

return SettingsData
