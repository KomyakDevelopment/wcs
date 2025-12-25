--!strict
-- Enhanced Dash Storage
-- Stores enhanced dash flag sent from client (momentum system at 100%)

local EnhancedDashStore = {}

local storage: {[Player]: boolean} = {}

function EnhancedDashStore.set(player: Player, enabled: boolean)
	storage[player] = enabled
end

function EnhancedDashStore.get(player: Player): boolean
	local enabled = storage[player]
	-- Clear after reading (one-time use)
	storage[player] = nil
	return enabled == true
end

function EnhancedDashStore.clear(player: Player)
	storage[player] = nil
end

return EnhancedDashStore
