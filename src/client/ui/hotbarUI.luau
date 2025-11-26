--!strict
-- Hotbar UI
-- Simple 2-slot weapon hotbar with click support

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HotbarUI = {}
HotbarUI.__index = HotbarUI

-- Slot definitions (fixed weapons per slot)
local SLOTS = {
	[1] = { weaponId = "fists", displayName = "Fists", icon = "" },
	[2] = { weaponId = "kunai", displayName = "Kunai", icon = "" },
}

function HotbarUI.new()
	local self = setmetatable({}, HotbarUI)

	self.selectedSlot = nil
	self.equippedSlot = nil
	self.slots = {} -- UI elements
	self.onSlotClicked = nil -- Callback for slot clicks: function(slotNumber)

	self:_createUI()

	return self
end

function HotbarUI:_createUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HotbarUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	self.screenGui = screenGui

	-- Create container frame at bottom left
	local container = Instance.new("Frame")
	container.Name = "HotbarContainer"
	container.Size = UDim2.new(0, 140, 0, 70)
	container.Position = UDim2.new(0, 20, 1, -90)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	-- Create horizontal layout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 10)
	layout.Parent = container

	-- Create slots
	for i, slotData in ipairs(SLOTS) do
		local slot = self:_createSlot(i, slotData)
		slot.Parent = container
		self.slots[i] = slot
	end

	self.container = container
end

function HotbarUI:_createSlot(slotNumber: number, slotData: { weaponId: string, displayName: string, icon: string })
	-- Use TextButton for clickability
	local slot = Instance.new("TextButton")
	slot.Name = `Slot{slotNumber}`
	slot.Size = UDim2.new(0, 60, 0, 70)
	slot.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	slot.BorderSizePixel = 0
	slot.Text = "" -- No text on the button itself
	slot.AutoButtonColor = false -- We handle hover ourselves

	-- Click handler
	slot.MouseButton1Click:Connect(function()
		if self.onSlotClicked then
			self.onSlotClicked(slotNumber)
		end
	end)

	-- Hover effects
	slot.MouseEnter:Connect(function()
		slot.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
	end)

	slot.MouseLeave:Connect(function()
		slot.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	end)

	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = slot

	-- Border/stroke for selection
	local stroke = Instance.new("UIStroke")
	stroke.Name = "SelectionStroke"
	stroke.Color = Color3.fromRGB(100, 100, 100)
	stroke.Thickness = 2
	stroke.Parent = slot

	-- Weapon name label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "WeaponName"
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Position = UDim2.new(0, 0, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = slotData.displayName
	nameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = slot

	-- Slot number label
	local numberLabel = Instance.new("TextLabel")
	numberLabel.Name = "SlotNumber"
	numberLabel.Size = UDim2.new(0, 20, 0, 20)
	numberLabel.Position = UDim2.new(0, 5, 1, -25)
	numberLabel.BackgroundTransparency = 1
	numberLabel.Text = tostring(slotNumber)
	numberLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	numberLabel.TextSize = 14
	numberLabel.Font = Enum.Font.GothamBold
	numberLabel.Parent = slot

	-- Status label (Selected/Equipped/Drawn)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0, 15)
	statusLabel.Position = UDim2.new(0, 0, 0, 25)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
	statusLabel.TextSize = 10
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Parent = slot

	return slot
end

-- Set callback for slot clicks
function HotbarUI:setOnSlotClicked(callback: (number) -> ())
	self.onSlotClicked = callback
end

-- Update slot visual states
function HotbarUI:updateSlot(slotNumber: number, state: string, weaponInHand: boolean?)
	local slot = self.slots[slotNumber]
	if not slot then
		return
	end

	local stroke = slot:FindFirstChild("SelectionStroke")
	local statusLabel = slot:FindFirstChild("StatusLabel")

	if state == "selected" then
		-- Yellow border for selected
		if stroke then
			stroke.Color = Color3.fromRGB(255, 200, 0)
			stroke.Thickness = 3
		end
		if statusLabel then
			statusLabel.Text = "Selected"
			statusLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
		end
		self.selectedSlot = slotNumber
	elseif state == "equipped" then
		-- Green border for equipped
		if stroke then
			stroke.Color = Color3.fromRGB(100, 200, 100)
			stroke.Thickness = 3
		end
		if statusLabel then
			if weaponInHand then
				statusLabel.Text = "Drawn"
				statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
			else
				statusLabel.Text = "On Back"
				statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
			end
		end
		self.equippedSlot = slotNumber
	elseif state == "none" then
		-- Default gray border
		if stroke then
			stroke.Color = Color3.fromRGB(100, 100, 100)
			stroke.Thickness = 2
		end
		if statusLabel then
			statusLabel.Text = ""
		end
	end
end

-- Clear selection visual
function HotbarUI:clearSelection()
	if self.selectedSlot then
		local slot = self.slots[self.selectedSlot]
		if slot then
			local stroke = slot:FindFirstChild("SelectionStroke")
			local statusLabel = slot:FindFirstChild("StatusLabel")

			-- If this slot is equipped, show equipped state
			if self.selectedSlot == self.equippedSlot then
				if stroke then
					stroke.Color = Color3.fromRGB(100, 200, 100)
					stroke.Thickness = 3
				end
			else
				if stroke then
					stroke.Color = Color3.fromRGB(100, 100, 100)
					stroke.Thickness = 2
				end
				if statusLabel then
					statusLabel.Text = ""
				end
			end
		end
		self.selectedSlot = nil
	end
end

-- Clear equipped visual from a slot
function HotbarUI:clearEquipped(slotNumber: number)
	local slot = self.slots[slotNumber]
	if slot then
		local stroke = slot:FindFirstChild("SelectionStroke")
		local statusLabel = slot:FindFirstChild("StatusLabel")

		if stroke then
			stroke.Color = Color3.fromRGB(100, 100, 100)
			stroke.Thickness = 2
		end
		if statusLabel then
			statusLabel.Text = ""
		end
	end

	if self.equippedSlot == slotNumber then
		self.equippedSlot = nil
	end
end

-- Get weapon ID for a slot
function HotbarUI.getSlotWeapon(slotNumber: number): string?
	local slotData = SLOTS[slotNumber]
	if slotData then
		return slotData.weaponId
	end
	return nil
end

-- Get total number of slots
function HotbarUI.getSlotCount(): number
	return #SLOTS
end

-- Cleanup
function HotbarUI:destroy()
	if self.screenGui then
		self.screenGui:Destroy()
	end
end

return HotbarUI
