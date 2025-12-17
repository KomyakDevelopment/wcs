--!strict
-- Server Info Manager (Server)
-- Handles server name generation, uptime tracking, and server info distribution

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local ServerInfoManager = {}

-- Server name word lists
local FIRST_NAMES = {
	"Hidden", "Tidal", "Scandalous", "Sandstruck", "Crimson",
	"Shadow", "Thunder", "Frozen", "Blazing", "Silent",
	"Ancient", "Mystic", "Savage", "Eternal", "Phantom",
	"Storm", "Iron", "Golden", "Hollow", "Cursed",
	"Radiant", "Vengeful", "Lost", "Forsaken", "Burning",
}

local SECOND_NAMES = {
	"Uzumaki", "Wave", "Orochi", "Plains", "Valley",
	"Mountain", "Forest", "Temple", "Village", "Shrine",
	"Harbor", "Fortress", "Cavern", "Summit", "Depths",
	"Sands", "Blade", "Phoenix", "Dragon", "Serpent",
	"Spirit", "Dawn", "Dusk", "Eclipse", "Horizon",
}

-- Server state (initialized once when server starts)
local serverName: string = ""
local serverStartTime: number = 0
local serverRegion: string = "Unknown"
local serverInfoRemote: RemoteFunction? = nil

-- Build info (set manually or via build script)
-- TODO: Replace with actual git SHA during build process
local BUILD_SHA = "dev"
local BUILD_DATE = os.date("!%y%m%d") -- Current date as fallback

-- In-game lore year (placeholder - set starting year here)
local LORE_START_YEAR = 1200
local LORE_CURRENT_YEAR = LORE_START_YEAR -- Will be dynamic later

function ServerInfoManager.init()
	-- Generate random server name (once per server lifetime)
	local firstName = FIRST_NAMES[math.random(1, #FIRST_NAMES)]
	local secondName = SECOND_NAMES[math.random(1, #SECOND_NAMES)]
	serverName = firstName .. " " .. secondName

	-- Record server start time
	serverStartTime = os.time()

	-- Detect server region via IP geolocation
	-- Requires HttpService to be enabled in Game Settings > Security
	ServerInfoManager._detectRegion()

	-- Create remote for clients to request server info
	local remote = Instance.new("RemoteFunction")
	remote.Name = "GetServerInfo"
	remote.Parent = ReplicatedStorage

	remote.OnServerInvoke = function(_player)
		return ServerInfoManager.getServerInfo()
	end

	-- Generate UUIDs for players when they join
	Players.PlayerAdded:Connect(function(player)
		ServerInfoManager._assignPlayerUUID(player)
	end)

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		ServerInfoManager._assignPlayerUUID(player)
	end

	print(`[ServerInfoManager] Initialized - Server: "{serverName}"`)
end

function ServerInfoManager._detectRegion()
	-- Fetch actual server location using IP geolocation
	-- Requires HttpService to be enabled in Game Settings > Security
	task.spawn(function()
		-- Step 1: Get server's IP address
		local ipSuccess, ipResponse = pcall(function()
			return HttpService:GetAsync("https://ipconfig.io/json")
		end)

		if not ipSuccess or not ipResponse then
			warn("[ServerInfoManager] Failed to get server IP")
			serverRegion = "Unknown"
			return
		end

		local ipData = HttpService:JSONDecode(ipResponse)
		local serverIP = ipData and ipData.ip

		if not serverIP then
			warn("[ServerInfoManager] No IP in response")
			serverRegion = "Unknown"
			return
		end

		-- Step 2: Get location from IP
		local locSuccess, locResponse = pcall(function()
			return HttpService:GetAsync("https://ipapi.co/" .. serverIP .. "/json/")
		end)

		if not locSuccess or not locResponse then
			warn("[ServerInfoManager] Failed to get location for IP")
			serverRegion = "Unknown"
			return
		end

		local locData = HttpService:JSONDecode(locResponse)

		if locData and locData.region and locData.country_code then
			serverRegion = `{locData.region}, {locData.country_code}`
			print(`[ServerInfoManager] Server location: {serverRegion}`)
		else
			serverRegion = "Unknown"
		end
	end)
end

function ServerInfoManager._assignPlayerUUID(player: Player)
	-- Check if player already has a UUID
	if player:GetAttribute("CharacterUUID") then
		return
	end

	-- Generate persistent UUID for this player's character
	-- Format: {UserId}-{4 numbers}-{4 alphanumeric}
	-- Example: 7426263709-3826-a8ch

	local numbersOnly = "0123456789"
	local alphanumeric = "0123456789abcdefghijklmnopqrstuvwxyz"

	-- Use player's UserId as seed for consistency across sessions
	local rng = Random.new(player.UserId)

	-- First part: Player's UserId
	local uuid = tostring(player.UserId)

	-- Second part: 4 random numbers
	uuid = uuid .. "-"
	for _ = 1, 4 do
		local randomIndex = rng:NextInteger(1, #numbersOnly)
		uuid = uuid .. numbersOnly:sub(randomIndex, randomIndex)
	end

	-- Third part: 4 random alphanumeric
	uuid = uuid .. "-"
	for _ = 1, 4 do
		local randomIndex = rng:NextInteger(1, #alphanumeric)
		uuid = uuid .. alphanumeric:sub(randomIndex, randomIndex)
	end

	player:SetAttribute("CharacterUUID", uuid)
	print(`[ServerInfoManager] Assigned UUID to {player.Name}: {uuid}`)
end

function ServerInfoManager.getServerInfo(): {
	name: string,
	region: string,
	uptimeSeconds: number,
	buildSha: string,
	buildDate: string,
	loreYear: number,
}
	return {
		name = serverName,
		region = serverRegion,
		uptimeSeconds = os.time() - serverStartTime,
		buildSha = BUILD_SHA,
		buildDate = BUILD_DATE,
		loreYear = LORE_CURRENT_YEAR,
	}
end

function ServerInfoManager.getServerName(): string
	return serverName
end

function ServerInfoManager.getUptime(): number
	return os.time() - serverStartTime
end

function ServerInfoManager.getRegion(): string
	return serverRegion
end

return ServerInfoManager
