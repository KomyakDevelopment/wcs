--!strict
-- Hotbar UI
-- Uses existing UI template at Main.NGUI.ScreenGui.hotbar_container.1_temp
-- Clones template for additional slots, supports up to 10 slots (keys 1-9, 0)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- Selection tween configuration
local SELECTION_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COLOR_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SELECTION_SCALE_INCREASE = 1.15 -- 15% larger when selected (Y axis)
local SELECTED_STROKE_COLOR = Color3.fromRGB(61, 61, 61)
local DEFAULT_STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local HotbarUI = {}
HotbarUI.__index = HotbarUI

-- Maximum slots and default keybinds
local MAX_SLOTS = 10
local DEFAULT_KEYBINDS = {
	[1] = Enum.KeyCode.One,
	[2] = Enum.KeyCode.Two,
	[3] = Enum.KeyCode.Three,
	[4] = Enum.KeyCode.Four,
	[5] = Enum.KeyCode.Five,
	[6] = Enum.KeyCode.Six,
	[7] = Enum.KeyCode.Seven,
	[8] = Enum.KeyCode.Eight,
	[9] = Enum.KeyCode.Nine,
	[10] = Enum.KeyCode.Zero,
}

-- Keybind display names
local KEYBIND_DISPLAY = {
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
	[Enum.KeyCode.Zero] = "0",
}

export type SlotData = {
	weaponId: string,
	displayName: string,
	isConsumable: boolean?,
	quantity: number?,
}

function HotbarUI.new()
	local self = setmetatable({}, HotbarUI)

	self.player = Players.LocalPlayer
	self.selectedSlot = nil :: number?
	self.slots = {} :: { [number]: Frame } -- UI elements by slot number
	self.slotData = {} :: { [number]: SlotData } -- Weapon data per slot
	self.keybinds = table.clone(DEFAULT_KEYBINDS) :: { [number]: Enum.KeyCode }
	self.onSlotClicked = nil :: ((number) -> ())? -- Callback for slot clicks
	self.hotbarContainer = nil :: Frame?
	self.template = nil :: Frame?
	self.inputConnection = nil :: RBXScriptConnection?
	self.slotOriginalSizes = {} :: { [number]: UDim2 } -- Store original sizes for tween reset

	-- Initialize with all weapons for testing
	self.slotData[1] = { weaponId = "fists", displayName = "Fists" }
	self.slotData[2] = { weaponId = "kunai", displayName = "Kunai" }
	self.slotData[3] = { weaponId = "uchigatana", displayName = "Uchigatana" }
	self.slotData[4] = { weaponId = "kusanagi", displayName = "Kusanagi" }

	self:_setup()

	return self
end

function HotbarUI:_setup()
	local playerGui = self.player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main", 5)
	if not mainGui then
		warn("[HotbarUI] Main GUI not found")
		return
	end

	-- Path: Main.NGUI.ScreenGui.hotbar_container
	local ngui = mainGui:FindFirstChild("NGUI")
	if not ngui then
		warn("[HotbarUI] NGUI not found in Main")
		return
	end

	local screenGui = ngui:FindFirstChild("ScreenGui")
	if not screenGui then
		warn("[HotbarUI] ScreenGui not found in NGUI")
		return
	end

	local hotbarContainer = screenGui:FindFirstChild("hotbar_container")
	if not hotbarContainer then
		warn("[HotbarUI] hotbar_container not found")
		return
	end

	self.hotbarContainer = hotbarContainer

	-- Find the template (1_temp)
	local template = hotbarContainer:FindFirstChild("1_temp")
	if not template then
		warn("[HotbarUI] 1_temp template not found in hotbar_container")
		return
	end

	self.template = template
	self.slots[1] = template

	-- Store original size and make visible
	self.slotOriginalSizes[1] = template.Size
	template.Visible = true

	-- Initialize the first slot with default data
	self:_updateSlotUI(1)

	-- Create slots for all pre-initialized items (slots 2+)
	for slotNumber, _ in pairs(self.slotData) do
		if slotNumber > 1 then
			self:_createSlot(slotNumber)
			self:_updateSlotUI(slotNumber)
		end
	end

	-- Setup input handling for keybinds
	self:_setupInputHandling()

	print("[HotbarUI] Initialized with template system")
end

function HotbarUI:_setupInputHandling()
	-- Listen for key presses to select slots
	self.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		-- Check if this key matches any of our keybinds
		for slotNumber, keyCode in pairs(self.keybinds) do
			if input.KeyCode == keyCode then
				-- Only trigger if slot exists (has data)
				if self.slotData[slotNumber] then
					if self.onSlotClicked then
						self.onSlotClicked(slotNumber)
					end
				end
				break
			end
		end
	end)
end

-- Update a slot's UI elements to match its data
function HotbarUI:_updateSlotUI(slotNumber: number)
	local slot = self.slots[slotNumber]
	local data = self.slotData[slotNumber]

	if not slot then
		return
	end

	-- Update keybind label
	local keybindLabel = slot:FindFirstChild("keybind")
	if keybindLabel and keybindLabel:IsA("TextLabel") then
		local keyCode = self.keybinds[slotNumber]
		keybindLabel.Text = KEYBIND_DISPLAY[keyCode] or tostring(slotNumber)
	end

	-- Update name label
	local nameLabel = slot:FindFirstChild("name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = data and data.displayName or ""
	end

	-- Update count label for consumables
	local countLabel = slot:FindFirstChild("count")
	if countLabel and countLabel:IsA("TextLabel") then
		if data and data.isConsumable and data.quantity then
			countLabel.Visible = true
			countLabel.Text = `x{data.quantity}`
		else
			countLabel.Visible = false
			countLabel.Text = ""
		end
	end
end

-- Add an item to the hotbar (finds next available slot or uses specified slot)
-- For consumables, pass isConsumable=true and quantity
function HotbarUI:addItem(
	weaponId: string,
	displayName: string,
	slotNumber: number?,
	isConsumable: boolean?,
	quantity: number?
): number?
	local targetSlot = slotNumber

	-- If no slot specified, find next empty slot
	if not targetSlot then
		for i = 1, MAX_SLOTS do
			if not self.slotData[i] then
				targetSlot = i
				break
			end
		end
	end

	if not targetSlot or targetSlot > MAX_SLOTS then
		warn("[HotbarUI] No available slots")
		return nil
	end

	-- Set the data
	self.slotData[targetSlot] = {
		weaponId = weaponId,
		displayName = displayName,
		isConsumable = isConsumable,
		quantity = quantity,
	}

	-- Create slot UI if needed (slot 1 uses existing template, others are clones)
	if not self.slots[targetSlot] then
		self:_createSlot(targetSlot)
	end

	-- Update the UI
	self:_updateSlotUI(targetSlot)

	print(`[HotbarUI] Added {displayName} to slot {targetSlot}`)
	return targetSlot
end

-- Update quantity for a consumable item
function HotbarUI:updateQuantity(slotNumber: number, newQuantity: number)
	local data = self.slotData[slotNumber]
	if not data then
		return
	end

	data.quantity = newQuantity

	-- If quantity is 0 or less, remove the item
	if newQuantity <= 0 then
		self:removeItem(slotNumber)
		return
	end

	-- Update the UI
	self:_updateSlotUI(slotNumber)
end

-- Get quantity for a slot (returns nil if not a consumable)
function HotbarUI:getQuantity(slotNumber: number): number?
	local data = self.slotData[slotNumber]
	if data and data.isConsumable then
		return data.quantity
	end
	return nil
end

-- Create a new slot by cloning the template
function HotbarUI:_createSlot(slotNumber: number)
	if not self.template or not self.hotbarContainer then
		return
	end

	if self.slots[slotNumber] then
		return -- Already exists
	end

	local newSlot = self.template:Clone()
	newSlot.Name = `{slotNumber}_temp`
	newSlot.Parent = self.hotbarContainer
	newSlot.Visible = true

	self.slots[slotNumber] = newSlot
	self.slotOriginalSizes[slotNumber] = newSlot.Size

	-- Setup click handler if it's a button
	if newSlot:IsA("TextButton") or newSlot:IsA("ImageButton") then
		newSlot.MouseButton1Click:Connect(function()
			if self.onSlotClicked then
				self.onSlotClicked(slotNumber)
			end
		end)
	else
		-- If it's a frame, look for a button child or make it clickable
		local button = newSlot:FindFirstChildWhichIsA("TextButton") or newSlot:FindFirstChildWhichIsA("ImageButton")
		if button then
			button.MouseButton1Click:Connect(function()
				if self.onSlotClicked then
					self.onSlotClicked(slotNumber)
				end
			end)
		end
	end
end

-- Remove an item from a slot
function HotbarUI:removeItem(slotNumber: number)
	if not self.slotData[slotNumber] then
		return
	end

	self.slotData[slotNumber] = nil

	-- Don't destroy slot 1 (the template), just clear its data
	if slotNumber == 1 then
		self:_updateSlotUI(1)
	else
		-- Destroy the cloned slot
		local slot = self.slots[slotNumber]
		if slot then
			slot:Destroy()
			self.slots[slotNumber] = nil
		end
	end
end

-- Set callback for slot clicks
function HotbarUI:setOnSlotClicked(callback: (number) -> ())
	self.onSlotClicked = callback
end

-- Update slot visual state (selected/none)
function HotbarUI:updateSlot(slotNumber: number, state: string)
	local slot = self.slots[slotNumber]
	if not slot then
		return
	end

	local originalSize: UDim2? = self.slotOriginalSizes[slotNumber]
	if not originalSize then
		return
	end

	-- Look for selection indicator or modify appearance
	local selectionFrame = slot:FindFirstChild("selection") or slot:FindFirstChild("SelectionFrame")

	-- Find the name label's UIStroke for color tweening
	local nameLabel = slot:FindFirstChild("name")
	local nameStroke = nameLabel and nameLabel:FindFirstChild("UIStroke")

	if state == "selected" then
		if selectionFrame then
			selectionFrame.Visible = true
		end
		self.selectedSlot = slotNumber

		-- Tween to 15% larger on Y axis
		local selectedSize = UDim2.new(
			(originalSize :: UDim2).X.Scale,
			(originalSize :: UDim2).X.Offset,
			(originalSize :: UDim2).Y.Scale * SELECTION_SCALE_INCREASE,
			(originalSize :: UDim2).Y.Offset
		)
		local sizeTween = TweenService:Create(slot, SELECTION_TWEEN_INFO, { Size = selectedSize })
		sizeTween:Play()

		-- Tween stroke color to selected color
		if nameStroke then
			local colorTween = TweenService:Create(nameStroke, COLOR_TWEEN_INFO, { Color = SELECTED_STROKE_COLOR })
			colorTween:Play()
		end
	else
		if selectionFrame then
			selectionFrame.Visible = false
		end
		if self.selectedSlot == slotNumber then
			self.selectedSlot = nil
		end

		-- Tween back to original size
		local sizeTween = TweenService:Create(slot, SELECTION_TWEEN_INFO, { Size = originalSize })
		sizeTween:Play()

		-- Tween stroke color back to default
		if nameStroke then
			local colorTween = TweenService:Create(nameStroke, COLOR_TWEEN_INFO, { Color = DEFAULT_STROKE_COLOR })
			colorTween:Play()
		end
	end
end

-- Check if a slot is currently selected
function HotbarUI:isSlotSelected(slotNumber: number): boolean
	return self.selectedSlot == slotNumber
end

-- Get weapon ID for a slot
function HotbarUI:getSlotWeapon(slotNumber: number): string?
	local data = self.slotData[slotNumber]
	return data and data.weaponId
end

-- Get total number of active slots
function HotbarUI:getSlotCount(): number
	local count = 0
	for _ in pairs(self.slotData) do
		count = count + 1
	end
	return count
end

-- Get maximum possible slots
function HotbarUI.getMaxSlots(): number
	return MAX_SLOTS
end

-- Swap weapons between slots
function HotbarUI:swapSlots(slot1: number, slot2: number)
	local data1 = self.slotData[slot1]
	local data2 = self.slotData[slot2]

	self.slotData[slot1] = data2
	self.slotData[slot2] = data1

	-- Ensure both slots have UI elements
	if data2 and not self.slots[slot1] then
		self:_createSlot(slot1)
	end
	if data1 and not self.slots[slot2] then
		self:_createSlot(slot2)
	end

	self:_updateSlotUI(slot1)
	self:_updateSlotUI(slot2)
end

-- Move weapon to first slot (for equip behavior)
function HotbarUI:moveWeaponToFirstSlot(weaponId: string)
	-- Find which slot has this weapon
	local sourceSlot = nil
	for i, data in pairs(self.slotData) do
		if data.weaponId == weaponId then
			sourceSlot = i
			break
		end
	end

	if not sourceSlot or sourceSlot == 1 then
		return
	end

	self:swapSlots(1, sourceSlot)
end

-- Set keybind for a slot
function HotbarUI:setKeybind(slotNumber: number, keyCode: Enum.KeyCode)
	if slotNumber < 1 or slotNumber > MAX_SLOTS then
		return
	end

	self.keybinds[slotNumber] = keyCode

	-- Update the UI to show new keybind
	self:_updateSlotUI(slotNumber)
end

-- Get keybind for a slot
function HotbarUI:getKeybind(slotNumber: number): Enum.KeyCode?
	return self.keybinds[slotNumber]
end

-- Clear selection visual
function HotbarUI:clearSelection()
	if self.selectedSlot then
		self:updateSlot(self.selectedSlot, "none")
	end
end

-- Check if mouse is over the hotbar
function HotbarUI:isMouseOverHotbar(): boolean
	local container = self.hotbarContainer
	if not container then
		return false
	end

	local mouse = self.player:GetMouse()
	local mousePos = Vector2.new(mouse.X, mouse.Y)
	local absPos = container.AbsolutePosition
	local absSize = container.AbsoluteSize

	return mousePos.X >= absPos.X
		and mousePos.X <= absPos.X + absSize.X
		and mousePos.Y >= absPos.Y
		and mousePos.Y <= absPos.Y + absSize.Y
end

-- Cleanup
function HotbarUI:destroy()
	if self.inputConnection then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end

	-- Destroy cloned slots (not the template)
	for slotNumber, slot in pairs(self.slots) do
		if slotNumber > 1 and slot then
			slot:Destroy()
		end
	end

	self.slots = {}
	self.slotData = {}
end

return HotbarUI
