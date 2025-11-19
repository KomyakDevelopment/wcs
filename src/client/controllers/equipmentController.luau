--!strict
-- Equipment Controller (Client)
-- Handles weapon selection and equip/unequip logic

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentController = {}
EquipmentController.__index = EquipmentController

-- Remote event for equip requests (will be created by server)
local EquipRemote: RemoteEvent

function EquipmentController.new()
	local self = setmetatable({}, EquipmentController)

	-- Wait for remote event
	EquipRemote = ReplicatedStorage:WaitForChild("EquipWeapon") :: RemoteEvent

	-- Track selected slot and equipped state
	self.selectedSlot = nil -- Currently selected hotbar slot
	self.equipped = nil -- Currently equipped weapon ID

	return self
end

-- Select a hotbar slot (doesn't equip yet)
function EquipmentController:selectSlot(slotNumber: number)
	self.selectedSlot = slotNumber
	print(`[EquipmentController] Selected slot {slotNumber}`)

	-- TODO: Update UI to show selection
end

-- Confirm action: equip if nothing equipped, unequip if same slot selected
function EquipmentController:confirmAction(weaponId: string)
	if not EquipRemote then
		warn("[EquipmentController] EquipWeapon remote not found")
		return
	end

	-- Check if we need to equip or unequip
	if self.equipped == weaponId then
		-- Same weapon selected - unequip it
		print(`[EquipmentController] Unequipping: {weaponId}`)
		EquipRemote:FireServer(nil)
		self.equipped = nil
		self.selectedSlot = nil
	else
		-- Different weapon or nothing equipped - equip it
		print(`[EquipmentController] Equipping: {weaponId}`)
		EquipRemote:FireServer(weaponId)
		self.equipped = weaponId
		self.selectedSlot = nil -- Clear selection after equipping
	end
end

-- Get currently selected slot
function EquipmentController:getSelectedSlot(): number?
	return self.selectedSlot
end

-- Get currently equipped weapon
function EquipmentController:getEquipped(): string?
	return self.equipped
end

return EquipmentController
