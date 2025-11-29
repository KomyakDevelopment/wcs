--!strict
-- Hotbar UI
-- Simple 2-slot weapon hotbar with decorative frame style

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HotbarUI = {}
HotbarUI.__index = HotbarUI

-- Style constants
local SLOT_SIZE = 70
local SLOT_SIZE_SELECTED = 78
local SLOT_PADDING = 10
local CORNER_SIZE = 12
local CORNER_THICKNESS = 2
local BG_COLOR = Color3.fromRGB(15, 15, 15)
local BORDER_COLOR = Color3.fromRGB(60, 60, 60)
local CORNER_COLOR = Color3.fromRGB(80, 80, 80)
local SELECTED_COLOR = Color3.fromRGB(255, 255, 255)
local TEXT_COLOR = Color3.fromRGB(180, 180, 180)

-- Animation settings
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function HotbarUI.new()
	local self = setmetatable({}, HotbarUI)

	self.selectedSlot = nil
	self.slots = {} -- UI elements (by visual position)
	self.slotData = {} -- Track what weapon is in each slot
	self.onSlotClicked = nil -- Callback for slot clicks: function(slotNumber)

	-- Initialize slot data (slot 1 = fists, slot 2 = kunai by default)
	self.slotData[1] = { weaponId = "fists", displayName = "Fists" }
	self.slotData[2] = { weaponId = "kunai", displayName = "Kunai" }

	self:_createUI()

	return self
end

function HotbarUI:_createUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Create ScreenGui (starts disabled - enabled by MenuManager after continue)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HotbarUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	self.screenGui = screenGui

	-- Create container frame at bottom left
	local totalWidth = (2 * SLOT_SIZE_SELECTED) + SLOT_PADDING + 20
	local container = Instance.new("Frame")
	container.Name = "HotbarContainer"
	container.Size = UDim2.new(0, totalWidth, 0, SLOT_SIZE_SELECTED + 10)
	container.Position = UDim2.new(0, 20, 1, -SLOT_SIZE_SELECTED - 25)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	-- Create horizontal layout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, SLOT_PADDING)
	layout.Parent = container

	-- Create slots
	for i = 1, 2 do
		local slot = self:_createSlot(i)
		slot.Parent = container
		self.slots[i] = slot
	end

	self.container = container
end

-- Create a corner accent (L-shaped bracket)
local function createCorner(parent: Frame, position: string)
	local corner = Instance.new("Frame")
	corner.Name = "Corner_" .. position
	corner.BackgroundTransparency = 1
	corner.Size = UDim2.new(0, CORNER_SIZE, 0, CORNER_SIZE)

	-- Horizontal bar of the L
	local hBar = Instance.new("Frame")
	hBar.Name = "HBar"
	hBar.BackgroundColor3 = CORNER_COLOR
	hBar.BorderSizePixel = 0
	hBar.Size = UDim2.new(0, CORNER_SIZE, 0, CORNER_THICKNESS)
	hBar.Parent = corner

	-- Vertical bar of the L
	local vBar = Instance.new("Frame")
	vBar.Name = "VBar"
	vBar.BackgroundColor3 = CORNER_COLOR
	vBar.BorderSizePixel = 0
	vBar.Size = UDim2.new(0, CORNER_THICKNESS, 0, CORNER_SIZE)
	vBar.Parent = corner

	-- Position based on which corner
	if position == "TopLeft" then
		corner.Position = UDim2.new(0, 0, 0, 0)
		hBar.Position = UDim2.new(0, 0, 0, 0)
		vBar.Position = UDim2.new(0, 0, 0, 0)
	elseif position == "TopRight" then
		corner.Position = UDim2.new(1, -CORNER_SIZE, 0, 0)
		hBar.Position = UDim2.new(0, 0, 0, 0)
		vBar.Position = UDim2.new(1, -CORNER_THICKNESS, 0, 0)
	elseif position == "BottomLeft" then
		corner.Position = UDim2.new(0, 0, 1, -CORNER_SIZE)
		hBar.Position = UDim2.new(0, 0, 1, -CORNER_THICKNESS)
		vBar.Position = UDim2.new(0, 0, 0, 0)
	elseif position == "BottomRight" then
		corner.Position = UDim2.new(1, -CORNER_SIZE, 1, -CORNER_SIZE)
		hBar.Position = UDim2.new(0, 0, 1, -CORNER_THICKNESS)
		vBar.Position = UDim2.new(1, -CORNER_THICKNESS, 0, 0)
	end

	corner.Parent = parent
	return corner
end

function HotbarUI:_createSlot(slotNumber: number)
	local data = self.slotData[slotNumber]

	-- Use TextButton for clickability
	local slot = Instance.new("TextButton")
	slot.Name = `Slot{slotNumber}`
	slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
	slot.BackgroundColor3 = BG_COLOR
	slot.BorderSizePixel = 0
	slot.Text = ""
	slot.AutoButtonColor = false

	-- Click handler
	slot.MouseButton1Click:Connect(function()
		if self.onSlotClicked then
			self.onSlotClicked(slotNumber)
		end
	end)

	-- Subtle hover effect
	slot.MouseEnter:Connect(function()
		slot.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	end)

	slot.MouseLeave:Connect(function()
		slot.BackgroundColor3 = BG_COLOR
	end)

	-- Rounded corners for the slot itself
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = slot

	-- Subtle border on main slot (follows rounded corners)
	local border = Instance.new("UIStroke")
	border.Name = "Border"
	border.Color = BORDER_COLOR
	border.Thickness = 1
	border.Parent = slot

	-- Selection frame (sharp corners, no UICorner)
	local selectionFrame = Instance.new("Frame")
	selectionFrame.Name = "SelectionFrame"
	selectionFrame.Size = UDim2.new(1, 0, 1, 0)
	selectionFrame.Position = UDim2.new(0, 0, 0, 0)
	selectionFrame.BackgroundTransparency = 1
	selectionFrame.Visible = false
	selectionFrame.Parent = slot

	-- Sharp-cornered selection stroke
	local selectionStroke = Instance.new("UIStroke")
	selectionStroke.Name = "SelectionStroke"
	selectionStroke.Color = SELECTED_COLOR
	selectionStroke.Thickness = 2
	selectionStroke.Parent = selectionFrame

	-- Create decorative corner accents
	createCorner(slot, "TopLeft")
	createCorner(slot, "TopRight")
	createCorner(slot, "BottomLeft")
	createCorner(slot, "BottomRight")

	-- Weapon name label (centered)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "WeaponName"
	nameLabel.Size = UDim2.new(1, -10, 0, 20)
	nameLabel.Position = UDim2.new(0, 5, 0.5, -10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = data.displayName
	nameLabel.TextColor3 = TEXT_COLOR
	nameLabel.TextSize = 14
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.Parent = slot

	-- Slot number in bottom left
	local numberLabel = Instance.new("TextLabel")
	numberLabel.Name = "SlotNumber"
	numberLabel.Size = UDim2.new(0, 20, 0, 20)
	numberLabel.Position = UDim2.new(0, 8, 1, -24)
	numberLabel.BackgroundTransparency = 1
	numberLabel.Text = tostring(slotNumber)
	numberLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
	numberLabel.TextSize = 12
	numberLabel.Font = Enum.Font.GothamBold
	numberLabel.Parent = slot

	return slot
end

-- Set callback for slot clicks
function HotbarUI:setOnSlotClicked(callback: (number) -> ())
	self.onSlotClicked = callback
end

-- Update slot visual states
function HotbarUI:updateSlot(slotNumber: number, state: string, _weaponInHand: boolean?)
	local slot = self.slots[slotNumber]
	if not slot then
		return
	end

	local selectionFrame = slot:FindFirstChild("SelectionFrame")

	if state == "selected" then
		-- Show selection frame and enlarge
		if selectionFrame then
			selectionFrame.Visible = true
		end
		-- Animate size increase
		local tween = TweenService:Create(slot, TWEEN_INFO, {
			Size = UDim2.new(0, SLOT_SIZE_SELECTED, 0, SLOT_SIZE_SELECTED),
		})
		tween:Play()
		self.selectedSlot = slotNumber
	elseif state == "equipped" or state == "none" then
		-- Hide selection frame and shrink back
		if selectionFrame then
			selectionFrame.Visible = false
		end
		-- Animate size decrease
		local tween = TweenService:Create(slot, TWEEN_INFO, {
			Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
		})
		tween:Play()
		if state == "none" then
			self.selectedSlot = nil
		end
	end
end

-- Check if a slot is currently selected
function HotbarUI:isSlotSelected(slotNumber: number): boolean
	return self.selectedSlot == slotNumber
end

-- Swap weapon to slot 1 when equipped
function HotbarUI:moveWeaponToFirstSlot(weaponId: string)
	-- Find which slot has this weapon
	local sourceSlot = nil
	for i, data in self.slotData do
		if data.weaponId == weaponId then
			sourceSlot = i
			break
		end
	end

	-- If weapon is already in slot 1, nothing to do
	if sourceSlot == 1 or sourceSlot == nil then
		return
	end

	-- Swap the slot data
	local temp = self.slotData[1]
	self.slotData[1] = self.slotData[sourceSlot]
	self.slotData[sourceSlot] = temp

	-- Update the UI labels
	self:_updateSlotLabels()
end

-- Update slot labels to match current slotData
function HotbarUI:_updateSlotLabels()
	for i, slot in self.slots do
		local data = self.slotData[i]
		local nameLabel = slot:FindFirstChild("WeaponName")
		if nameLabel then
			nameLabel.Text = data.displayName
		end
	end
end

-- Get weapon ID for a slot
function HotbarUI:getSlotWeapon(slotNumber: number): string?
	local data = self.slotData[slotNumber]
	if data then
		return data.weaponId
	end
	return nil
end

-- Get total number of slots
function HotbarUI.getSlotCount(): number
	return 2
end

-- Clear selection visual
function HotbarUI:clearSelection()
	if self.selectedSlot then
		self:updateSlot(self.selectedSlot, "none")
		self.selectedSlot = nil
	end
end

-- Check if mouse is over the hotbar
function HotbarUI:isMouseOverHotbar(): boolean
	local container = self.container
	if not container then
		return false
	end

	local mouse = Players.LocalPlayer:GetMouse()
	local mousePos = Vector2.new(mouse.X, mouse.Y)
	local absPos = container.AbsolutePosition
	local absSize = container.AbsoluteSize

	return mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X
		and mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y
end

-- Cleanup
function HotbarUI:destroy()
	if self.screenGui then
		self.screenGui:Destroy()
	end
end

return HotbarUI
