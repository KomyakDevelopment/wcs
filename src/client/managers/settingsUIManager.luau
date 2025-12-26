--!strict
-- Settings UI Manager (Client)
-- Creates and manages the settings menu with volume sliders and feature toggles

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local MusicManager = require(ReplicatedStorage.Client.managers.musicManager)
local SFXManager = require(ReplicatedStorage.Client.managers.sfxManager)
local SettingsData = require(ReplicatedStorage.Shared.data.settingsData)

local SettingsUIManager = {}
SettingsUIManager.__index = SettingsUIManager

-- Debounce configuration
local SAVE_DEBOUNCE_TIME = 0.5 -- Only save after 0.5s of no changes

-- UI Configuration (matching debug panel styling)
local UI_CONFIG = {
	menuWidth = 320,
	menuHeight = 400,
	padding = 12,
	sliderHeight = 44,
	toggleHeight = 38,
	sectionSpacing = 16,
	cornerRadius = 6,
	titleHeight = 32,
	rowHeight = 28,

	-- Colors (matching debug panels)
	backgroundColor = Color3.fromRGB(20, 20, 25),
	backgroundTransparency = 0.15,
	strokeColor = Color3.fromRGB(60, 60, 70),
	sliderTrackColor = Color3.fromRGB(40, 40, 50),
	sliderFillColor = Color3.fromRGB(100, 255, 100), -- Green like debug values
	toggleOffColor = Color3.fromRGB(50, 50, 60),
	toggleOnColor = Color3.fromRGB(100, 255, 100), -- Green like debug values
	textColor = Color3.fromRGB(255, 255, 255),
	labelColor = Color3.fromRGB(180, 180, 180),
	valueColor = Color3.fromRGB(100, 255, 100),

	-- Fonts (matching debug panels)
	titleFont = Enum.Font.GothamBold,
	textFont = Enum.Font.Code,
	textSize = 14,
	titleSize = 16,
}

export type SettingsUIManager = typeof(setmetatable(
	{} :: {
		_player: Player,
		_screenGui: ScreenGui?,
		_mainFrame: Frame?,
		_isOpen: boolean,
		_settings: SettingsData.PlayerSettings,

		-- Callbacks for when settings change
		_onSettingChanged: ((key: string, value: any) -> ())?,

		-- References to UI elements for updating
		_sliders: { [string]: { track: Frame, fill: Frame, value: TextLabel } },
		_toggles: { [string]: { button: Frame, indicator: Frame } },

		-- Manager references
		_dynamicFOVManager: any?,

		-- Debouncing for saves
		_pendingChanges: { [string]: any },
		_saveDebounceThread: thread?,
		_lastSaveTime: number,
	},
	SettingsUIManager
))

function SettingsUIManager.new(): SettingsUIManager
	local self = setmetatable({}, SettingsUIManager) :: SettingsUIManager

	self._player = Players.LocalPlayer
	self._screenGui = nil
	self._mainFrame = nil
	self._isOpen = false
	self._settings = SettingsData.getDefaults()

	self._onSettingChanged = nil
	self._sliders = {}
	self._toggles = {}
	self._dynamicFOVManager = nil

	-- Debouncing state
	self._pendingChanges = {}
	self._saveDebounceThread = nil
	self._lastSaveTime = 0

	self:_initialize()

	return self
end

function SettingsUIManager:_initialize()
	-- Load settings from cache
	local cached = SettingsData.getCached(self._player)
	if cached then
		self._settings = cached
	end

	-- Apply audio settings immediately on load (before UI is created)
	-- This ensures the player's preferences are applied as soon as possible
	self:_applyAudioSettings()

	-- Create UI
	self:_createUI()

	-- Listen for /settings chat command
	self._player.Chatted:Connect(function(message)
		local lowerMsg = string.lower(message)
		if lowerMsg == "/settings" or lowerMsg == "/options" then
			self:open()
		end
	end)

	-- Listen for settings cache changes (from server)
	self._player:GetAttributeChangedSignal("_SettingsCache"):Connect(function()
		local newSettings = SettingsData.getCached(self._player)
		if newSettings then
			self._settings = newSettings
			self:_updateUIFromSettings()
		end
	end)

	print("[SettingsUIManager] Initialized")
end

function SettingsUIManager:_createUI()
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SettingsUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 100
	screenGui.Enabled = false
	screenGui.Parent = self._player:WaitForChild("PlayerGui")
	self._screenGui = screenGui

	-- Create main menu frame (positioned on right side, slides in)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromOffset(UI_CONFIG.menuWidth, UI_CONFIG.menuHeight)
	-- Start off-screen to the right
	mainFrame.Position = UDim2.new(1, UI_CONFIG.menuWidth + 20, 0.5, 0)
	mainFrame.AnchorPoint = Vector2.new(1, 0.5)
	mainFrame.BackgroundColor3 = UI_CONFIG.backgroundColor
	mainFrame.BackgroundTransparency = UI_CONFIG.backgroundTransparency
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	self._mainFrame = mainFrame

	-- Corner rounding (matching debug panels)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UI_CONFIG.cornerRadius)
	corner.Parent = mainFrame

	-- Border stroke (matching debug panels)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI_CONFIG.strokeColor
	stroke.Thickness = 1
	stroke.Parent = mainFrame

	-- Create header title
	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Size = UDim2.new(1, -UI_CONFIG.padding * 2, 0, UI_CONFIG.titleHeight)
	headerTitle.Position = UDim2.fromOffset(UI_CONFIG.padding, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "Settings"
	headerTitle.TextColor3 = UI_CONFIG.textColor
	headerTitle.TextSize = UI_CONFIG.titleSize
	headerTitle.Font = UI_CONFIG.titleFont
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Parent = mainFrame

	-- Close button (X)
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(24, 24)
	closeButton.Position = UDim2.new(1, -UI_CONFIG.padding - 24, 0, 4)
	closeButton.BackgroundTransparency = 1
	closeButton.Text = "×"
	closeButton.TextColor3 = UI_CONFIG.labelColor
	closeButton.TextSize = 20
	closeButton.Font = UI_CONFIG.titleFont
	closeButton.Parent = mainFrame

	closeButton.MouseButton1Click:Connect(function()
		self:close()
	end)

	-- Create content scroll frame
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -UI_CONFIG.padding * 2, 1, -UI_CONFIG.titleHeight - UI_CONFIG.padding)
	content.Position = UDim2.fromOffset(UI_CONFIG.padding, UI_CONFIG.titleHeight)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 3
	content.ScrollBarImageColor3 = UI_CONFIG.strokeColor
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = mainFrame

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.Parent = content

	-- Create sections
	self:_createSectionLabel(content, "Volume", 1)
	self:_createSlider(content, "masterVolume", "Master", 2)
	self:_createSlider(content, "musicVolume", "Music", 3)
	self:_createSlider(content, "sfxVolume", "SFX", 4)

	self:_createSectionLabel(content, "Features", 5)
	self:_createToggle(content, "dynamicFOV", "Dynamic FOV", "Speed-based FOV", 6)

	-- Update UI from current settings
	self:_updateUIFromSettings()
end

function SettingsUIManager:_createSectionLabel(parent: ScrollingFrame, text: string, order: number)
	local label = Instance.new("TextLabel")
	label.Name = "Section_" .. text
	label.Size = UDim2.new(1, 0, 0, UI_CONFIG.rowHeight)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = UI_CONFIG.labelColor
	label.TextSize = UI_CONFIG.textSize
	label.Font = UI_CONFIG.titleFont
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, UI_CONFIG.sectionSpacing)
	padding.Parent = label
end

function SettingsUIManager:_createSlider(parent: ScrollingFrame, key: string, label: string, order: number)
	local container = Instance.new("Frame")
	container.Name = "Slider_" .. key
	container.Size = UDim2.new(1, 0, 0, UI_CONFIG.sliderHeight)
	container.BackgroundTransparency = 1
	container.LayoutOrder = order
	container.Parent = parent

	-- Label (matching debug panel style)
	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.Size = UDim2.new(0.5, 0, 0, 18)
	labelText.BackgroundTransparency = 1
	labelText.Text = label
	labelText.TextColor3 = UI_CONFIG.labelColor
	labelText.TextSize = UI_CONFIG.textSize
	labelText.Font = UI_CONFIG.textFont
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Parent = container

	-- Value display (green like debug values)
	local valueText = Instance.new("TextLabel")
	valueText.Name = "Value"
	valueText.Size = UDim2.new(0.5, 0, 0, 18)
	valueText.Position = UDim2.fromScale(0.5, 0)
	valueText.BackgroundTransparency = 1
	valueText.Text = "100%"
	valueText.TextColor3 = UI_CONFIG.valueColor
	valueText.TextSize = UI_CONFIG.textSize
	valueText.Font = UI_CONFIG.textFont
	valueText.TextXAlignment = Enum.TextXAlignment.Right
	valueText.Parent = container

	-- Slider track
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.fromOffset(0, 24)
	track.BackgroundColor3 = UI_CONFIG.sliderTrackColor
	track.BorderSizePixel = 0
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 3)
	trackCorner.Parent = track

	-- Slider fill
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = UI_CONFIG.sliderFillColor
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	-- Store references
	self._sliders[key] = {
		track = track,
		fill = fill,
		value = valueText,
	}

	-- Make slider interactive
	local dragging = false

	local function updateSlider(inputPosition: Vector2)
		local trackAbsPos = track.AbsolutePosition
		local trackAbsSize = track.AbsoluteSize
		local relativeX = math.clamp((inputPosition.X - trackAbsPos.X) / trackAbsSize.X, 0, 1)

		fill.Size = UDim2.fromScale(relativeX, 1)
		valueText.Text = math.floor(relativeX * 100) .. "%"

		-- Update setting
		self._settings[key] = relativeX
		self:_onSettingUpdated(key, relativeX)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateSlider(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateSlider(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

function SettingsUIManager:_createToggle(parent: ScrollingFrame, key: string, label: string, description: string, order: number)
	local container = Instance.new("Frame")
	container.Name = "Toggle_" .. key
	container.Size = UDim2.new(1, 0, 0, UI_CONFIG.toggleHeight)
	container.BackgroundTransparency = 1
	container.LayoutOrder = order
	container.Parent = parent

	-- Label (matching debug panel style)
	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.Size = UDim2.new(0.55, 0, 0, 18)
	labelText.BackgroundTransparency = 1
	labelText.Text = label
	labelText.TextColor3 = UI_CONFIG.labelColor
	labelText.TextSize = UI_CONFIG.textSize
	labelText.Font = UI_CONFIG.textFont
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Parent = container

	-- Description (subtle, same line)
	local descText = Instance.new("TextLabel")
	descText.Name = "Description"
	descText.Size = UDim2.new(0.45, -44, 0, 18)
	descText.Position = UDim2.fromScale(0.55, 0)
	descText.BackgroundTransparency = 1
	descText.Text = description
	descText.TextColor3 = UI_CONFIG.strokeColor
	descText.TextSize = UI_CONFIG.textSize - 2
	descText.Font = UI_CONFIG.textFont
	descText.TextXAlignment = Enum.TextXAlignment.Left
	descText.TextTruncate = Enum.TextTruncate.AtEnd
	descText.Parent = container

	-- Toggle button (smaller, cleaner)
	local toggleButton = Instance.new("Frame")
	toggleButton.Name = "ToggleButton"
	toggleButton.Size = UDim2.fromOffset(40, 20)
	toggleButton.Position = UDim2.new(1, -40, 0.5, 0)
	toggleButton.AnchorPoint = Vector2.new(0, 0.5)
	toggleButton.BackgroundColor3 = UI_CONFIG.toggleOffColor
	toggleButton.BorderSizePixel = 0
	toggleButton.Parent = container

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 10)
	toggleCorner.Parent = toggleButton

	-- Toggle indicator (the circle)
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.Size = UDim2.fromOffset(16, 16)
	indicator.Position = UDim2.fromOffset(2, 2)
	indicator.BackgroundColor3 = Color3.new(1, 1, 1)
	indicator.BorderSizePixel = 0
	indicator.Parent = toggleButton

	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.CornerRadius = UDim.new(0, 8)
	indicatorCorner.Parent = indicator

	-- Store references
	self._toggles[key] = {
		button = toggleButton,
		indicator = indicator,
	}

	-- Make toggle interactive
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickArea"
	clickButton.Size = UDim2.fromScale(1, 1)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.Parent = toggleButton

	clickButton.MouseButton1Click:Connect(function()
		local newValue = not self._settings[key]
		self._settings[key] = newValue
		self:_updateToggleVisual(key, newValue)
		self:_onSettingUpdated(key, newValue)
	end)
end

function SettingsUIManager:_updateUIFromSettings()
	-- Update sliders
	for key, slider in self._sliders do
		local value = self._settings[key] or 0
		slider.fill.Size = UDim2.fromScale(value, 1)
		slider.value.Text = math.floor(value * 100) .. "%"
	end

	-- Update toggles
	for key, _ in self._toggles do
		local value = self._settings[key] or false
		self:_updateToggleVisual(key, value)
	end
end

function SettingsUIManager:_updateToggleVisual(key: string, enabled: boolean)
	local toggle = self._toggles[key]
	if not toggle then
		return
	end

	local targetColor = enabled and UI_CONFIG.toggleOnColor or UI_CONFIG.toggleOffColor
	-- Toggle is 40x20 with 16x16 indicator, so positions are 2 (off) or 22 (on)
	local targetPos = enabled and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2)

	TweenService:Create(toggle.button, TweenInfo.new(0.15), { BackgroundColor3 = targetColor }):Play()
	TweenService:Create(toggle.indicator, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Position = targetPos }):Play()
end

function SettingsUIManager:_onSettingUpdated(key: string, value: any)
	-- Apply setting immediately on client for responsiveness
	self:_applySettingLocally(key, value)

	-- Queue the change for debounced save
	self._pendingChanges[key] = value

	-- Cancel existing debounce thread if any
	if self._saveDebounceThread then
		task.cancel(self._saveDebounceThread)
		self._saveDebounceThread = nil
	end

	-- Start new debounce timer
	self._saveDebounceThread = task.delay(SAVE_DEBOUNCE_TIME, function()
		self:_flushPendingChanges()
	end)

	-- Call callback if set
	if self._onSettingChanged then
		self._onSettingChanged(key, value)
	end
end

-- Flush all pending changes to server in a single batch
function SettingsUIManager:_flushPendingChanges()
	if next(self._pendingChanges) == nil then
		return -- No pending changes
	end

	-- Send all pending changes to server
	local remote = ReplicatedStorage:FindFirstChild("UpdateSettings") :: RemoteEvent?
	if remote then
		-- Send a copy and clear pending
		local changesToSend = table.clone(self._pendingChanges)
		self._pendingChanges = {}
		self._saveDebounceThread = nil

		remote:FireServer(changesToSend)
	end
end

function SettingsUIManager:_applySettingLocally(key: string, value: any)
	if key == "masterVolume" then
		-- Master volume affects both music and SFX
		MusicManager.setMasterVolume(value)
		SFXManager.setMasterVolume(value)
	elseif key == "musicVolume" then
		-- Music volume (independent slider, master is applied internally)
		MusicManager.setVolume(value)
	elseif key == "sfxVolume" then
		-- SFX volume (independent slider, master is applied internally)
		SFXManager.setVolume(value)
	elseif key == "dynamicFOV" then
		-- Dynamic FOV toggle
		if self._dynamicFOVManager then
			self._dynamicFOVManager:setEnabled(value)
		end
	end
end

-- Apply audio settings only (can be called before managers are linked)
function SettingsUIManager:_applyAudioSettings()
	-- Apply master volume first (affects both music and SFX)
	MusicManager.setMasterVolume(self._settings.masterVolume)
	SFXManager.setMasterVolume(self._settings.masterVolume)

	-- Apply individual volumes
	MusicManager.setVolume(self._settings.musicVolume)
	SFXManager.setVolume(self._settings.sfxVolume)

	print("[SettingsUIManager] Applied audio settings on load")
end

function SettingsUIManager:setDynamicFOVManager(manager: any)
	self._dynamicFOVManager = manager

	-- Apply current setting immediately
	if manager and self._settings.dynamicFOV ~= nil then
		manager:setEnabled(self._settings.dynamicFOV)
	end
end

function SettingsUIManager:open()
	if self._screenGui then
		self._screenGui.Enabled = true
		self._isOpen = true

		-- Slide in from the right
		if self._mainFrame then
			-- Start off-screen to the right
			self._mainFrame.Position = UDim2.new(1, UI_CONFIG.menuWidth + 20, 0.5, 0)
			TweenService:Create(
				self._mainFrame,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(1, -20, 0.5, 0) }
			):Play()
		end
	end
end

function SettingsUIManager:close()
	if self._screenGui and self._mainFrame then
		self._isOpen = false

		-- Flush any pending changes immediately when closing
		if self._saveDebounceThread then
			task.cancel(self._saveDebounceThread)
			self._saveDebounceThread = nil
		end
		self:_flushPendingChanges()

		-- Slide out to the right
		local tween = TweenService:Create(
			self._mainFrame,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(1, UI_CONFIG.menuWidth + 20, 0.5, 0) }
		)
		tween:Play()
		tween.Completed:Connect(function()
			if not self._isOpen and self._screenGui then
				self._screenGui.Enabled = false
			end
		end)
	end
end

function SettingsUIManager:toggle()
	if self._isOpen then
		self:close()
	else
		self:open()
	end
end

function SettingsUIManager:isOpen(): boolean
	return self._isOpen
end

function SettingsUIManager:setOnSettingChanged(callback: (key: string, value: any) -> ())
	self._onSettingChanged = callback
end

function SettingsUIManager:getSettings(): SettingsData.PlayerSettings
	return self._settings
end

function SettingsUIManager:destroy()
	-- Flush any pending changes before destroying
	if self._saveDebounceThread then
		task.cancel(self._saveDebounceThread)
		self._saveDebounceThread = nil
	end
	self:_flushPendingChanges()

	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
end

return SettingsUIManager
