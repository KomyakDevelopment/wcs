--!strict
-- Equipment Controller (Client)
-- Handles weapon selection, equip/unequip logic with fixed 2-slot hotbar

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HotbarUI = require(ReplicatedStorage.Client.ui.hotbarUI)

local EquipmentController = {}
EquipmentController.__index = EquipmentController

-- Remote events for equip requests (will be created by server)
local EquipRemote: RemoteEvent
local ToggleWeaponInHandRemote: RemoteEvent

-- Fixed slot definitions (slot 1 = fists, slot 2 = kunai)
local SLOT_WEAPONS = {
	[1] = "fists",
	[2] = "kunai",
}

-- Track which weapons are physical (have a model that needs to be in hand)
local PHYSICAL_WEAPONS = {
	kunai = true,
}

function EquipmentController.new()
	local self = setmetatable({}, EquipmentController)

	-- Wait for remote events
	EquipRemote = ReplicatedStorage:WaitForChild("EquipWeapon") :: RemoteEvent
	ToggleWeaponInHandRemote = ReplicatedStorage:WaitForChild("ToggleWeaponInHand") :: RemoteEvent

	-- Track selected slot and equipped state
	self.selectedSlot = nil :: number? -- Currently selected hotbar slot (waiting for confirm)
	self.equippedSlot = nil :: number? -- Currently equipped slot
	self.equipped = nil :: string? -- Currently equipped weapon ID
	self.weaponInHand = false -- Is weapon in hand (for physical weapons)

	-- Create hotbar UI
	self.hotbarUI = HotbarUI.new()

	-- Connect click callback - clicking a slot is same as pressing its key
	self.hotbarUI:setOnSlotClicked(function(slotNumber)
		self:selectSlot(slotNumber)
	end)

	-- Reset equipment state on respawn (new character has no weapon equipped)
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function()
		self.equipped = nil
		self.selectedSlot = nil
		self.equippedSlot = nil
		self.weaponInHand = false

		-- Reset UI
		for i = 1, HotbarUI.getSlotCount() do
			self.hotbarUI:updateSlot(i, "none")
		end

		print("[EquipmentController] Reset equipment state on respawn")
	end)

	return self
end

-- Select a hotbar slot
-- If slot is already equipped: toggle draw/sheath for physical weapons
-- If slot is different: select it for equipping via M1
function EquipmentController:selectSlot(slotNumber: number)
	local slotWeapon = SLOT_WEAPONS[slotNumber]

	if not slotWeapon then
		print(`[EquipmentController] Slot {slotNumber} is empty`)
		return
	end

	-- Check if this slot is already equipped
	if self.equippedSlot == slotNumber then
		-- Same weapon equipped - toggle draw/sheath for physical weapons
		if PHYSICAL_WEAPONS[slotWeapon] then
			self:toggleWeaponInHand()
			-- Update UI to show drawn/sheathed state
			self.hotbarUI:updateSlot(slotNumber, "equipped", self.weaponInHand)
			return
		end
		-- Non-physical weapons (fists) - already equipped, nothing to do
		print(`[EquipmentController] {slotWeapon} already equipped`)
		return
	end

	-- Different slot - clear previous selection and select this one
	if self.selectedSlot and self.selectedSlot ~= slotNumber then
		-- Clear old selection visual (unless it's the equipped slot)
		if self.selectedSlot ~= self.equippedSlot then
			self.hotbarUI:updateSlot(self.selectedSlot, "none")
		else
			self.hotbarUI:updateSlot(self.selectedSlot, "equipped", self.weaponInHand)
		end
	end

	self.selectedSlot = slotNumber
	self.hotbarUI:updateSlot(slotNumber, "selected")

	print(`[EquipmentController] Selected slot {slotNumber} ({slotWeapon})`)
end

-- Confirm action: equip weapon from selected slot
function EquipmentController:confirmAction()
	if not EquipRemote then
		warn("[EquipmentController] EquipWeapon remote not found")
		return
	end

	if not self.selectedSlot then
		return -- No slot selected, nothing to confirm
	end

	local weaponId = SLOT_WEAPONS[self.selectedSlot]
	if not weaponId then
		self.selectedSlot = nil
		return
	end

	-- Clear old equipped slot visual
	if self.equippedSlot and self.equippedSlot ~= self.selectedSlot then
		self.hotbarUI:updateSlot(self.equippedSlot, "none")
	end

	-- Equip the weapon from the selected slot
	print(`[EquipmentController] Equipping from slot {self.selectedSlot}: {weaponId}`)
	EquipRemote:FireServer(weaponId)
	self.equipped = weaponId
	self.equippedSlot = self.selectedSlot

	-- Physical weapons start on back (not in hand)
	-- Fists are always "in hand"
	if PHYSICAL_WEAPONS[weaponId] then
		self.weaponInHand = false
	else
		self.weaponInHand = true
	end

	-- Update UI to show equipped state
	self.hotbarUI:updateSlot(self.equippedSlot, "equipped", self.weaponInHand)

	self.selectedSlot = nil -- Clear selection after equipping
end

-- Get currently selected slot
function EquipmentController:getSelectedSlot(): number?
	return self.selectedSlot
end

-- Get currently equipped weapon
function EquipmentController:getEquipped(): string?
	return self.equipped
end

-- Check if weapon is in hand (for physical weapons)
function EquipmentController:isWeaponInHand(): boolean
	return self.weaponInHand
end

-- Get weapon assigned to a slot
function EquipmentController:getSlotWeapon(slotNumber: number): string?
	return SLOT_WEAPONS[slotNumber]
end

-- Toggle weapon in hand (for physical weapons)
-- Called when pressing the same slot key again after equipping
function EquipmentController:toggleWeaponInHand()
	if not self.equipped then
		return
	end

	if not ToggleWeaponInHandRemote then
		warn("[EquipmentController] ToggleWeaponInHand remote not found")
		return
	end

	-- Send toggle request to server
	ToggleWeaponInHandRemote:FireServer()

	-- Optimistically update local state
	self.weaponInHand = not self.weaponInHand

	print(`[EquipmentController] Toggled weapon in hand: {self.weaponInHand}`)
end

return EquipmentController
