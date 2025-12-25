--!strict
-- Momentum UI
-- Simple percentage display in the bottom left corner
-- Shows momentum buildup during actions like wall running

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MomentumUI = {}
MomentumUI.__index = MomentumUI

-- Configuration
local CONFIG = {
	-- Position (bottom left with some padding)
	POSITION = UDim2.new(0, 20, 1, -60),
	SIZE = UDim2.new(0, 80, 0, 30),

	-- Appearance
	BACKGROUND_COLOR = Color3.fromRGB(20, 20, 20),
	BACKGROUND_TRANSPARENCY = 0.5,
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	TEXT_COLOR_FULL = Color3.fromRGB(100, 255, 100), -- Green when at 100%
	FONT = Enum.Font.GothamBold,
	TEXT_SIZE = 16,
	CORNER_RADIUS = UDim.new(0, 6),

	-- Animation
	FADE_TIME = 0.2,
	COLOR_TWEEN_TIME = 0.15,
}

export type MomentumUI = typeof(setmetatable(
	{} :: {
		_player: Player,
		_screenGui: ScreenGui?,
		_container: Frame?,
		_label: TextLabel?,
		_isVisible: boolean,
		_currentMomentum: number,
	},
	MomentumUI
))

function MomentumUI.new(): MomentumUI
	local self = setmetatable({}, MomentumUI) :: MomentumUI

	self._player = Players.LocalPlayer
	self._screenGui = nil
	self._container = nil
	self._label = nil
	self._isVisible = false
	self._currentMomentum = 0

	self:_setup()

	return self
end

function MomentumUI:_setup()
	local playerGui = self._player:WaitForChild("PlayerGui")

	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MomentumUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 5
	screenGui.Parent = playerGui
	self._screenGui = screenGui

	-- Create container frame
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = CONFIG.SIZE
	container.Position = CONFIG.POSITION
	container.AnchorPoint = Vector2.new(0, 1)
	container.BackgroundColor3 = CONFIG.BACKGROUND_COLOR
	container.BackgroundTransparency = 1 -- Start hidden
	container.BorderSizePixel = 0
	container.Parent = screenGui
	self._container = container

	-- Add corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = CONFIG.CORNER_RADIUS
	corner.Parent = container

	-- Create percentage label
	local label = Instance.new("TextLabel")
	label.Name = "PercentLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = CONFIG.TEXT_COLOR
	label.TextTransparency = 1 -- Start hidden
	label.Font = CONFIG.FONT
	label.TextSize = CONFIG.TEXT_SIZE
	label.Text = "0%"
	label.Parent = container
	self._label = label

	print("[MomentumUI] Created")
end

-- Update the displayed momentum percentage
function MomentumUI:setMomentum(momentum: number)
	self._currentMomentum = momentum

	if not self._label then
		return
	end

	-- Update text
	self._label.Text = `{math.floor(momentum)}%`

	-- Change color when at 100%
	local targetColor = if momentum >= 100 then CONFIG.TEXT_COLOR_FULL else CONFIG.TEXT_COLOR

	local colorTween = TweenService:Create(
		self._label,
		TweenInfo.new(CONFIG.COLOR_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextColor3 = targetColor }
	)
	colorTween:Play()
end

-- Show the UI with fade in
function MomentumUI:show()
	if self._isVisible then
		return
	end

	self._isVisible = true

	if not self._container or not self._label then
		return
	end

	-- Fade in
	local containerTween = TweenService:Create(
		self._container,
		TweenInfo.new(CONFIG.FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = CONFIG.BACKGROUND_TRANSPARENCY }
	)

	local labelTween = TweenService:Create(
		self._label,
		TweenInfo.new(CONFIG.FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0 }
	)

	containerTween:Play()
	labelTween:Play()
end

-- Hide the UI with fade out
function MomentumUI:hide()
	if not self._isVisible then
		return
	end

	self._isVisible = false

	if not self._container or not self._label then
		return
	end

	-- Fade out
	local containerTween = TweenService:Create(
		self._container,
		TweenInfo.new(CONFIG.FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)

	local labelTween = TweenService:Create(
		self._label,
		TweenInfo.new(CONFIG.FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1 }
	)

	containerTween:Play()
	labelTween:Play()
end

-- Check if UI is currently visible
function MomentumUI:isVisible(): boolean
	return self._isVisible
end

function MomentumUI:destroy()
	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
end

return MomentumUI
