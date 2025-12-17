--!strict
-- Server Info UI Manager (Client)
-- Updates the TopInfo UI with server info, player character info, ping bars, etc.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local ServerInfoUIManager = {}
ServerInfoUIManager.__index = ServerInfoUIManager

-- Ping bar image IDs
local PING_BARS = {
	good = "rbxassetid://113713955347155", -- 90ms or below
	medium = "rbxassetid://122198032475940", -- 90-139ms
	bad = "rbxassetid://77231381845479", -- 140ms or above
}

-- Ping thresholds
local PING_GOOD_THRESHOLD = 90
local PING_MEDIUM_THRESHOLD = 140

function ServerInfoUIManager.new()
	local self = setmetatable({}, ServerInfoUIManager)

	self._player = Players.LocalPlayer
	self._serverInfoRemote = nil :: RemoteFunction?
	self._connections = {} :: { RBXScriptConnection }
	self._serverInfo = nil :: {
		name: string,
		region: string,
		uptimeSeconds: number,
		buildSha: string,
		buildDate: string,
		loreYear: number,
	}?
	self._serverStartTime = 0 -- Local tracking for uptime display

	self:_setup()

	return self
end

function ServerInfoUIManager:_setup()
	task.spawn(function()
		-- Wait for remote
		self._serverInfoRemote = ReplicatedStorage:WaitForChild("GetServerInfo", 10) :: RemoteFunction?
		if not self._serverInfoRemote then
			warn("[ServerInfoUIManager] GetServerInfo remote not found")
			return
		end

		-- Get initial server info
		local success, info = pcall(function()
			return self._serverInfoRemote:InvokeServer()
		end)

		if success and info then
			self._serverInfo = info
			self._serverStartTime = os.time() - info.uptimeSeconds

			-- Initial UI update
			self:_updateAllLabels()

			-- Start periodic updates
			self:_startUpdateLoop()
		else
			warn("[ServerInfoUIManager] Failed to get server info")
		end
	end)
end

function ServerInfoUIManager:_getTopInfo(): GuiObject?
	local playerGui = self._player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end

	local main = playerGui:FindFirstChild("Main")
	if not main then return nil end

	local topInfo = main:FindFirstChild("TopInfo")
	if not topInfo then return nil end

	local top = topInfo:FindFirstChild("Top")
	return top :: GuiObject?
end

function ServerInfoUIManager:_updateAllLabels()
	local top = self:_getTopInfo()
	if not top then return end

	self:_updateServerTitle(top)
	self:_updateServerLocation(top)
	self:_updateServerUptime(top)
	self:_updatePlaceInfo(top)
	self:_updateCharacterInfo(top)
end

-- 1. Server Title (random name)
function ServerInfoUIManager:_updateServerTitle(top: GuiObject)
	local serverSection = top:FindFirstChild("1_server")
	if not serverSection then return end

	local titleLabel = serverSection:FindFirstChild("1_title")
	if titleLabel and titleLabel:IsA("TextLabel") and self._serverInfo then
		titleLabel.Text = self._serverInfo.name
	end
end

-- 2. Server Location + Ping Bars
function ServerInfoUIManager:_updateServerLocation(top: GuiObject)
	local serverSection = top:FindFirstChild("1_server")
	if not serverSection then return end

	local locationSection = serverSection:FindFirstChild("2_location")
	if not locationSection then return end

	-- Update location text
	local locationText = locationSection:FindFirstChild("1_Text")
	if locationText and locationText:IsA("TextLabel") and self._serverInfo then
		locationText.Text = self._serverInfo.region
	end

	-- Update ping bars based on current ping
	local barsImage = locationSection:FindFirstChild("Bars")
	if barsImage and barsImage:IsA("ImageLabel") then
		local ping = self._player:GetNetworkPing() * 1000

		if ping <= PING_GOOD_THRESHOLD then
			barsImage.Image = PING_BARS.good
		elseif ping <= PING_MEDIUM_THRESHOLD then
			barsImage.Image = PING_BARS.medium
		else
			barsImage.Image = PING_BARS.bad
		end
	end
end

-- 3. Server Uptime (0d 0h 0m format)
function ServerInfoUIManager:_updateServerUptime(top: GuiObject)
	local serverSection = top:FindFirstChild("1_server")
	if not serverSection then return end

	local uptimeLabel = serverSection:FindFirstChild("3_uptime")
	if uptimeLabel and uptimeLabel:IsA("TextLabel") then
		local uptimeSeconds = os.time() - self._serverStartTime

		local days = math.floor(uptimeSeconds / 86400)
		local hours = math.floor((uptimeSeconds % 86400) / 3600)
		local minutes = math.floor((uptimeSeconds % 3600) / 60)

		uptimeLabel.Text = `{days}d {hours}h {minutes}m`
	end
end

-- 4. Place Info (title, build, year)
function ServerInfoUIManager:_updatePlaceInfo(top: GuiObject)
	local placeSection = top:FindFirstChild("2_place")
	if not placeSection then return end

	-- 4a. Place Title - TODO: Link to location system later
	-- local titleLabel = placeSection:FindFirstChild("1_title")
	-- if titleLabel and titleLabel:IsA("TextLabel") then
	-- 	titleLabel.Text = "Current Location" -- Will be updated by location system
	-- end

	-- 4b. Build ID (SHA_YYMMDD)
	local buildLabel = placeSection:FindFirstChild("2_Buid") -- Note: typo in original path
	if buildLabel and buildLabel:IsA("TextLabel") and self._serverInfo then
		buildLabel.Text = `{self._serverInfo.buildSha}_{self._serverInfo.buildDate}`
	end

	-- 4c. Lore Year - TODO: Implement dynamic year system
	local yearLabel = placeSection:FindFirstChild("3_year")
	if yearLabel and yearLabel:IsA("TextLabel") and self._serverInfo then
		yearLabel.Text = tostring(self._serverInfo.loreYear)
	end
end

-- 5. Character Info (name, UUID)
function ServerInfoUIManager:_updateCharacterInfo(top: GuiObject)
	local charSection = top:FindFirstChild("3_character")
	if not charSection then return end

	-- 5a. Character Name - TODO: Get from character creation system
	-- For now, use placeholder from Player attributes
	local nameLabel = charSection:FindFirstChild("1_name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		local firstName = self._player:GetAttribute("FirstName") or "Naruto"
		local lastName = self._player:GetAttribute("LastName") or "Uzumaki"
		nameLabel.Text = `{firstName} {lastName}`
	end

	-- 5b. Character UUID (consistent per player, same as death UI)
	local uuidLabel = charSection:FindFirstChild("2_uuid")
	if uuidLabel and uuidLabel:IsA("TextLabel") then
		local uuid = self._player:GetAttribute("CharacterUUID")
		if uuid then
			uuidLabel.Text = tostring(uuid)
		else
			-- Wait for UUID to be assigned by server
			task.spawn(function()
				local attempts = 0
				while attempts < 50 and not self._player:GetAttribute("CharacterUUID") do
					task.wait(0.1)
					attempts = attempts + 1
				end

				local finalUuid = self._player:GetAttribute("CharacterUUID")
				if finalUuid and uuidLabel and uuidLabel.Parent then
					uuidLabel.Text = tostring(finalUuid)
				end
			end)
		end
	end
end

function ServerInfoUIManager:_startUpdateLoop()
	-- Update uptime and ping bars periodically
	local conn = RunService.Heartbeat:Connect(function()
		-- Throttle to once per second
		if not self._lastUpdate or (os.clock() - self._lastUpdate) >= 1 then
			self._lastUpdate = os.clock()

			local top = self:_getTopInfo()
			if top then
				self:_updateServerUptime(top)
				self:_updateServerLocation(top) -- Updates ping bars
			end
		end
	end)
	table.insert(self._connections, conn)
end

function ServerInfoUIManager:destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
end

return ServerInfoUIManager
