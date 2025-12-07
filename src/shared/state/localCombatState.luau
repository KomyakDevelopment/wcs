--!strict
-- Local Combat State
-- Shared client-side state for combat prediction
-- Updated by block.luau, read by blockVFXManager for client-side parry prediction

local LocalCombatState = {}

-- Parry window timing (must match block.luau)
LocalCombatState.BLOCK_STARTUP_TIME = 0.03
LocalCombatState.PARRY_WINDOW_DURATION = 0.2975

-- Current block/parry state
LocalCombatState.isBlocking = false
LocalCombatState.blockStartTime = 0 -- When block button was pressed
LocalCombatState.parryWindowStartTime = 0 -- When parry window opened (after startup)
LocalCombatState.parryOnCooldown = false

-- Update block state (called by block.luau OnStartClient)
function LocalCombatState.startBlock(onCooldown: boolean)
	LocalCombatState.isBlocking = true
	LocalCombatState.blockStartTime = tick()
	LocalCombatState.parryOnCooldown = onCooldown

	-- Parry window opens after startup delay (if not on cooldown)
	if not onCooldown then
		LocalCombatState.parryWindowStartTime = LocalCombatState.blockStartTime + LocalCombatState.BLOCK_STARTUP_TIME
	else
		LocalCombatState.parryWindowStartTime = 0
	end
end

-- Update block state (called by block.luau OnEndClient)
function LocalCombatState.endBlock()
	-- Don't immediately clear - parry window lingers after release
	-- The parry window will naturally expire based on timing
	LocalCombatState.isBlocking = false
end

-- Check if currently in parry window
function LocalCombatState.isInParryWindow(): boolean
	if LocalCombatState.parryOnCooldown then
		return false
	end

	if LocalCombatState.parryWindowStartTime == 0 then
		return false
	end

	local currentTime = tick()
	local parryWindowEnd = LocalCombatState.parryWindowStartTime + LocalCombatState.PARRY_WINDOW_DURATION

	return currentTime >= LocalCombatState.parryWindowStartTime and currentTime <= parryWindowEnd
end

-- Check if currently blocking (but not parrying)
function LocalCombatState.isBlockingOnly(): boolean
	if not LocalCombatState.isBlocking then
		return false
	end

	-- If we're in parry window, we're parrying not just blocking
	if LocalCombatState.isInParryWindow() then
		return false
	end

	-- Check if past startup time
	local currentTime = tick()
	local startupEnd = LocalCombatState.blockStartTime + LocalCombatState.BLOCK_STARTUP_TIME

	return currentTime >= startupEnd
end

-- Get time until parry window closes (for debugging)
function LocalCombatState.getParryTimeRemaining(): number
	if LocalCombatState.parryWindowStartTime == 0 then
		return 0
	end

	local parryWindowEnd = LocalCombatState.parryWindowStartTime + LocalCombatState.PARRY_WINDOW_DURATION
	return math.max(0, parryWindowEnd - tick())
end

return LocalCombatState
