--!strict
-- Equipment Controller (Client)
-- Sends equip requests to server

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

	return self
end

-- Request to equip a weapon
function EquipmentController:equipWeapon(weaponId: string)
	if not EquipRemote then
		warn("[EquipmentController] EquipWeapon remote not found")
		return
	end

	print(`[EquipmentController] Requesting to equip: {weaponId}`)
	EquipRemote:FireServer(weaponId)
end

-- Request to unequip current weapon
function EquipmentController:unequipWeapon()
	if not EquipRemote then
		warn("[EquipmentController] EquipWeapon remote not found")
		return
	end

	print("[EquipmentController] Requesting to unequip weapon")
	EquipRemote:FireServer(nil)
end

return EquipmentController
