--!strict
-- Airdash Camera Direction Storage
-- Stores camera directions sent from clients for airdash skill

local AirdashCameraStore = {}

local storage: {[Player]: Vector3} = {}

function AirdashCameraStore.set(player: Player, direction: Vector3)
	storage[player] = direction
end

function AirdashCameraStore.get(player: Player): Vector3?
	local direction = storage[player]
	-- Clear after reading (one-time use)
	storage[player] = nil
	return direction
end

function AirdashCameraStore.clear(player: Player)
	storage[player] = nil
end

return AirdashCameraStore
