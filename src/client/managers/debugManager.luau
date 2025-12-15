--!strict
-- Debug Manager (Client)
-- Handles debug commands: /speeddebug, /netdebug, /performancedebug, /alldebug
-- Only works for whitelisted users (validated server-side)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TextChatService = game:GetService("TextChatService")

local DebugManager = {}
DebugManager.__index = DebugManager

-- Panel configuration
local PANEL_WIDTH = 280
local PANEL_PADDING = 10
local ROW_HEIGHT = 18
local TITLE_HEIGHT = 24
local FONT = Enum.Font.Code
local TEXT_SIZE = 14
local PANEL_GAP = 12 -- Gap between panels
local CONTAINER_MARGIN = 10 -- Margin from screen edge

-- Averaging configuration
local SAMPLE_COUNT = 30 -- Number of samples to average (at 60fps = 0.5 seconds)
local UPDATE_INTERVAL = 3 -- Update display every N frames (reduces UI overhead)

function DebugManager.new()
	local self = setmetatable({}, DebugManager)

	self._player = Players.LocalPlayer
	self._isAuthorized = false
	self._panels = {} :: { [string]: Frame }
	self._labels = {} :: { [string]: { [string]: TextLabel } }
	self._connections = {} :: { RBXScriptConnection }
	self._screenGui = nil :: ScreenGui?
	self._container = nil :: Frame?
	self._permissionRemote = nil :: RemoteFunction?

	-- Panel visibility states
	self._speedVisible = false
	self._networkVisible = false
	self._performanceVisible = false

	-- Sample buffers for averaging
	self._samples = {
		fps = {} :: { number },
		ping = {} :: { number },
		velocity = {} :: { number },
		horizontalSpeed = {} :: { number },
		velocityX = {} :: { number },
		velocityY = {} :: { number },
		velocityZ = {} :: { number },
		dataReceive = {} :: { number },
		dataSend = {} :: { number },
		memory = {} :: { number },
	}
	self._frameCounter = 0
	self._lastFrameTime = tick()

	self:_setup()

	return self
end

-- Helper to add sample and compute rolling average
function DebugManager:_addSample(key: string, value: number): number
	local buffer = self._samples[key]
	if not buffer then
		self._samples[key] = {}
		buffer = self._samples[key]
	end

	table.insert(buffer, value)
	if #buffer > SAMPLE_COUNT then
		table.remove(buffer, 1)
	end

	-- Compute average
	local sum = 0
	for _, v in ipairs(buffer) do
		sum = sum + v
	end
	return sum / #buffer
end

function DebugManager:_setup()
	-- Wait for permission remote
	task.spawn(function()
		self._permissionRemote = ReplicatedStorage:WaitForChild("DebugPermissionCheck", 10) :: RemoteFunction?
		if self._permissionRemote then
			-- Check if we're authorized
			local success, result = pcall(function()
				return self._permissionRemote:InvokeServer("debug")
			end)
			if success and result then
				self._isAuthorized = true
				self:_createUI()
				self:_setupChatCommands()
				print("[DebugManager] Authorized - debug commands enabled")
			else
				print("[DebugManager] Not authorized for debug commands")
			end
		end
	end)
end

function DebugManager:_createUI()
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DebugPanels"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = self._player:WaitForChild("PlayerGui")
	self._screenGui = screenGui

	-- Create container frame (anchored center-right)
	local container = Instance.new("Frame")
	container.Name = "PanelContainer"
	container.Size = UDim2.fromOffset(PANEL_WIDTH, 0) -- Height auto-calculated
	container.AnchorPoint = Vector2.new(1, 0.5) -- Anchor to right-center
	container.Position = UDim2.new(1, -CONTAINER_MARGIN, 0.5, 0) -- Center vertically on right side
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = screenGui
	self._container = container

	-- Add UIListLayout for even spacing
	local listLayout = Instance.new("UIListLayout")
	listLayout.Name = "Layout"
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, PANEL_GAP)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Parent = container

	-- Create panels (all hidden initially)
	self:_createSpeedPanel()
	self:_createNetworkPanel()
	self:_createPerformancePanel()
end

function DebugManager:_createPanel(name: string, title: string, layoutOrder: number, rows: { string }): Frame
	local panelHeight = TITLE_HEIGHT + (#rows * ROW_HEIGHT) + PANEL_PADDING * 2

	local panel = Instance.new("Frame")
	panel.Name = name .. "Panel"
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, panelHeight)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.LayoutOrder = layoutOrder
	panel.Parent = self._container

	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = panel

	-- Border stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 70)
	stroke.Thickness = 1
	stroke.Parent = panel

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -PANEL_PADDING * 2, 0, TITLE_HEIGHT)
	titleLabel.Position = UDim2.fromOffset(PANEL_PADDING, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = title
	titleLabel.Parent = panel

	-- Create row labels
	self._labels[name] = {}
	for i, rowName in ipairs(rows) do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = rowName
		rowFrame.Size = UDim2.new(1, -PANEL_PADDING * 2, 0, ROW_HEIGHT)
		rowFrame.Position = UDim2.fromOffset(PANEL_PADDING, TITLE_HEIGHT + (i - 1) * ROW_HEIGHT)
		rowFrame.BackgroundTransparency = 1
		rowFrame.Parent = panel

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Size = UDim2.fromScale(0.55, 1)
		nameLabel.Position = UDim2.fromScale(0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.TextSize = TEXT_SIZE
		nameLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = rowName
		nameLabel.Parent = rowFrame

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.Size = UDim2.fromScale(0.45, 1)
		valueLabel.Position = UDim2.fromScale(0.55, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = FONT
		valueLabel.TextSize = TEXT_SIZE
		valueLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.Text = "—"
		valueLabel.Parent = rowFrame

		self._labels[name][rowName] = valueLabel
	end

	self._panels[name] = panel
	return panel
end

function DebugManager:_createSpeedPanel()
	local rows = {
		"Velocity (total)",
		"Velocity X",
		"Velocity Y",
		"Velocity Z",
		"Horizontal Speed",
		"Walk Speed",
		"Jump Power",
		"Move Direction",
		"Humanoid State",
	}
	self:_createPanel("speed", "SPEED DEBUG", 1, rows)
end

function DebugManager:_createNetworkPanel()
	local rows = {
		"Ping (ms)",
		"Data Receive (KB/s)",
		"Data Send (KB/s)",
		"Server Tick Rate",
	}
	self:_createPanel("network", "NETWORK DEBUG", 2, rows)
end

function DebugManager:_createPerformancePanel()
	local rows = {
		"FPS",
		"Frame Time (ms)",
		"Memory (MB)",
		"Instance Count",
	}
	self:_createPanel("performance", "PERFORMANCE DEBUG", 3, rows)
end

function DebugManager:_setupChatCommands()
	-- Create TextChatCommands (these don't show in chat or bubble)
	local commands = {
		{ name = "SpeedDebug", primaryAlias = "/speeddebug", handler = function() self:toggleSpeedPanel() end },
		{ name = "NetDebug", primaryAlias = "/netdebug", handler = function() self:toggleNetworkPanel() end },
		{ name = "PerformanceDebug", primaryAlias = "/performancedebug", handler = function() self:togglePerformancePanel() end },
		{ name = "AllDebug", primaryAlias = "/alldebug", handler = function() self:toggleAllPanels() end },
	}

	-- Wait for TextChatCommands folder
	task.spawn(function()
		local textChatCommands = TextChatService:WaitForChild("TextChatCommands", 10)
		if not textChatCommands then
			warn("[DebugManager] TextChatCommands not found, falling back to legacy chat")
			self:_setupLegacyChatCommands()
			return
		end

		for _, cmdInfo in ipairs(commands) do
			local command = Instance.new("TextChatCommand")
			command.Name = cmdInfo.name
			command.PrimaryAlias = cmdInfo.primaryAlias
			command.Parent = textChatCommands

			command.Triggered:Connect(function(originTextSource, _unfilteredText)
				if originTextSource.UserId == self._player.UserId then
					cmdInfo.handler()
				end
			end)
		end

		print("[DebugManager] Chat commands registered")
	end)
end

function DebugManager:_setupLegacyChatCommands()
	-- Fallback for legacy chat system
	local debugCommands = {
		["/speeddebug"] = function() self:toggleSpeedPanel() end,
		["/netdebug"] = function() self:toggleNetworkPanel() end,
		["/performancedebug"] = function() self:togglePerformancePanel() end,
		["/alldebug"] = function() self:toggleAllPanels() end,
	}

	self._player.Chatted:Connect(function(message)
		local lowerMsg = string.lower(message)
		local handler = debugCommands[lowerMsg]
		if handler then
			handler()
		end
	end)
end

function DebugManager:toggleSpeedPanel()
	if not self._isAuthorized then return end
	self._speedVisible = not self._speedVisible
	if self._panels.speed then
		self._panels.speed.Visible = self._speedVisible
	end
	self:_updateConnections()
	print(`[DebugManager] Speed panel: {self._speedVisible and "ON" or "OFF"}`)
end

function DebugManager:toggleNetworkPanel()
	if not self._isAuthorized then return end
	self._networkVisible = not self._networkVisible
	if self._panels.network then
		self._panels.network.Visible = self._networkVisible
	end
	self:_updateConnections()
	print(`[DebugManager] Network panel: {self._networkVisible and "ON" or "OFF"}`)
end

function DebugManager:togglePerformancePanel()
	if not self._isAuthorized then return end
	self._performanceVisible = not self._performanceVisible
	if self._panels.performance then
		self._panels.performance.Visible = self._performanceVisible
	end
	self:_updateConnections()
	print(`[DebugManager] Performance panel: {self._performanceVisible and "ON" or "OFF"}`)
end

function DebugManager:toggleAllPanels()
	if not self._isAuthorized then return end

	-- If any panel is visible, turn all off. Otherwise, turn all on.
	local anyVisible = self._speedVisible or self._networkVisible or self._performanceVisible
	local newState = not anyVisible

	self._speedVisible = newState
	self._networkVisible = newState
	self._performanceVisible = newState

	if self._panels.speed then
		self._panels.speed.Visible = newState
	end
	if self._panels.network then
		self._panels.network.Visible = newState
	end
	if self._panels.performance then
		self._panels.performance.Visible = newState
	end

	self:_updateConnections()
	print(`[DebugManager] All panels: {newState and "ON" or "OFF"}`)
end

function DebugManager:_updateConnections()
	-- Disconnect existing connections
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}

	-- Only update if at least one panel is visible
	if not (self._speedVisible or self._networkVisible or self._performanceVisible) then
		return
	end

	-- Create update loop
	local conn = RunService.Heartbeat:Connect(function()
		self:_collectSamples()

		-- Only update UI every N frames for performance
		self._frameCounter = self._frameCounter + 1
		if self._frameCounter >= UPDATE_INTERVAL then
			self._frameCounter = 0
			self:_updatePanels()
		end
	end)
	table.insert(self._connections, conn)
end

function DebugManager:_collectSamples()
	local now = tick()
	local deltaTime = now - self._lastFrameTime
	self._lastFrameTime = now

	-- FPS sample
	if deltaTime > 0 then
		self:_addSample("fps", 1 / deltaTime)
	end

	-- Ping sample
	local ping = self._player:GetNetworkPing() * 1000
	self:_addSample("ping", ping)

	-- Velocity samples
	local character = self._player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local velocity = hrp.AssemblyLinearVelocity
			local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
			self:_addSample("velocity", velocity.Magnitude)
			self:_addSample("horizontalSpeed", horizontalVel.Magnitude)
			self:_addSample("velocityX", velocity.X)
			self:_addSample("velocityY", velocity.Y)
			self:_addSample("velocityZ", velocity.Z)
		end
	end

	-- Memory sample
	local memoryMB = Stats:GetTotalMemoryUsageMb()
	self:_addSample("memory", memoryMB)

	-- Network data samples (using Stats service)
	local recvKbps = Stats.DataReceiveKbps
	local sendKbps = Stats.DataSendKbps
	self:_addSample("dataReceive", recvKbps)
	self:_addSample("dataSend", sendKbps)
end

function DebugManager:_updatePanels()
	if self._speedVisible then
		self:_updateSpeedPanel()
	end
	if self._networkVisible then
		self:_updateNetworkPanel()
	end
	if self._performanceVisible then
		self:_updatePerformancePanel()
	end
end

function DebugManager:_getAverage(key: string): number
	local buffer = self._samples[key]
	if not buffer or #buffer == 0 then
		return 0
	end

	local sum = 0
	for _, v in ipairs(buffer) do
		sum = sum + v
	end
	return sum / #buffer
end

function DebugManager:_updateSpeedPanel()
	local labels = self._labels.speed
	if not labels then return end

	local character = self._player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?

	-- Use averaged values
	labels["Velocity (total)"].Text = string.format("%.1f", self:_getAverage("velocity"))
	labels["Velocity X"].Text = string.format("%.1f", self:_getAverage("velocityX"))
	labels["Velocity Y"].Text = string.format("%.1f", self:_getAverage("velocityY"))
	labels["Velocity Z"].Text = string.format("%.1f", self:_getAverage("velocityZ"))
	labels["Horizontal Speed"].Text = string.format("%.1f", self:_getAverage("horizontalSpeed"))

	if humanoid then
		labels["Walk Speed"].Text = string.format("%.0f", humanoid.WalkSpeed)
		labels["Jump Power"].Text = string.format("%.0f", humanoid.JumpPower)

		local moveDir = humanoid.MoveDirection
		labels["Move Direction"].Text = string.format("%.1f, %.1f", moveDir.X, moveDir.Z)
		labels["Humanoid State"].Text = humanoid:GetState().Name
	end
end

function DebugManager:_updateNetworkPanel()
	local labels = self._labels.network
	if not labels then return end

	-- Use averaged values
	labels["Ping (ms)"].Text = string.format("%.0f", self:_getAverage("ping"))
	labels["Data Receive (KB/s)"].Text = string.format("%.1f", self:_getAverage("dataReceive"))
	labels["Data Send (KB/s)"].Text = string.format("%.1f", self:_getAverage("dataSend"))

	-- Server tick rate (Roblox servers run at 60Hz)
	labels["Server Tick Rate"].Text = "60 Hz"
end

function DebugManager:_updatePerformancePanel()
	local labels = self._labels.performance
	if not labels then return end

	-- Use averaged FPS
	local avgFps = self:_getAverage("fps")
	labels["FPS"].Text = string.format("%.0f", math.min(avgFps, 999))
	labels["Frame Time (ms)"].Text = string.format("%.2f", avgFps > 0 and (1000 / avgFps) or 0)

	-- Use averaged memory
	labels["Memory (MB)"].Text = string.format("%.0f", self:_getAverage("memory"))

	-- Instance count
	local instanceCount = Stats.InstanceCount
	labels["Instance Count"].Text = string.format("%d", instanceCount)
end

function DebugManager:destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}

	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
end

return DebugManager
