--!strict
-- Equipment Controller (Client)
-- Handles weapon selection, equip/unequip logic with dynamic 2-slot hotbar

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HotbarUI = require(ReplicatedStorage.Client.ui.hotbarUI)

local EquipmentController = {}
EquipmentController.__index = EquipmentController

-- Remote events for equip requests (will be created by server)
local EquipRemote: RemoteEvent
local ToggleWeaponInHandRemote: RemoteEvent

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
-- If slot is already selected: unselect it (toggle off, sheath physical weapon)
-- Otherwise: select the slot (draw physical weapon if equipped)
function EquipmentController:selectSlot(slotNumber: number)
	local slotWeapon = self.hotbarUI:getSlotWeapon(slotNumber)

	if not slotWeapon then
		print(`[EquipmentController] Slot {slotNumber} is empty`)
		return
	end

	-- Check if this slot is already selected - toggle it off
	if self.hotbarUI:isSlotSelected(slotNumber) then
		self.hotbarUI:updateSlot(slotNumber, "none")
		self.selectedSlot = nil

		-- For physical weapons that are equipped, sheath (put back on back)
		if self.equipped == slotWeapon and PHYSICAL_WEAPONS[slotWeapon] and self.weaponInHand then
			self.weaponInHand = false
			if ToggleWeaponInHandRemote then
				ToggleWeaponInHandRemote:FireServer()
			end
		end

		print(`[EquipmentController] Unselected slot {slotNumber}`)
		return
	end

	-- Clear previous selection if any (and sheath previous weapon if physical)
	if self.selectedSlot and self.selectedSlot ~= slotNumber then
		local prevWeapon = self.hotbarUI:getSlotWeapon(self.selectedSlot)
		-- Sheath previous physical weapon if it was in hand
		if self.equipped == prevWeapon and PHYSICAL_WEAPONS[prevWeapon] and self.weaponInHand then
			self.weaponInHand = false
			if ToggleWeaponInHandRemote then
				ToggleWeaponInHandRemote:FireServer()
			end
		end
		self.hotbarUI:updateSlot(self.selectedSlot, "none")
	end

	-- Select this slot
	self.selectedSlot = slotNumber
	self.hotbarUI:updateSlot(slotNumber, "selected")

	-- If this weapon is already equipped and physical, draw it (put in hand)
	if self.equipped == slotWeapon and PHYSICAL_WEAPONS[slotWeapon] and not self.weaponInHand then
		self.weaponInHand = true
		if ToggleWeaponInHandRemote then
			ToggleWeaponInHandRemote:FireServer()
		end
	end

	print(`[EquipmentController] Selected slot {slotNumber} ({slotWeapon})`)
end

-- Confirm action: equip weapon from selected slot
-- Returns true if weapon was just equipped, false if already equipped or nothing to do
function EquipmentController:confirmAction(): boolean
	-- Don't process M1 as equipment confirm if clicking on hotbar
	if self.hotbarUI:isMouseOverHotbar() then
		return false
	end

	if not EquipRemote then
		warn("[EquipmentController] EquipWeapon remote not found")
		return false
	end

	if not self.selectedSlot then
		return false -- No slot selected, nothing to confirm
	end

	local weaponId = self.hotbarUI:getSlotWeapon(self.selectedSlot)
	if not weaponId then
		return false
	end

	-- If weapon already equipped, nothing to do (keep selection, allow attack)
	if self.equipped == weaponId then
		return false
	end

	-- Clear selection on old slot before moving
	self.hotbarUI:updateSlot(self.selectedSlot, "none")

	-- Move the weapon to slot 1 (swaps with whatever was there)
	self.hotbarUI:moveWeaponToFirstSlot(weaponId)

	-- Move selection to slot 1 (where the weapon now is)
	self.selectedSlot = 1
	self.hotbarUI:updateSlot(1, "selected")

	-- Equip the weapon
	print(`[EquipmentController] Equipping: {weaponId}`)
	EquipRemote:FireServer(weaponId)
	self.equipped = weaponId

	-- All weapons are ready to use immediately after equipping
	-- Physical weapons: put in hand right away so player can attack
	if PHYSICAL_WEAPONS[weaponId] then
		self.weaponInHand = true
		-- Tell server to draw weapon into hand
		if ToggleWeaponInHandRemote then
			ToggleWeaponInHandRemote:FireServer()
		end
	else
		self.weaponInHand = true
	end

	-- Keep selection frame visible (don't clear selection)
	-- Player must click slot again to unselect

	return true
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
	return self.hotbarUI:getSlotWeapon(slotNumber)
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
