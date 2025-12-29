--!strict
-- Combat Configuration
-- Central location for all combat-related balance values
-- Edit this file to tune combat without touching skill code

local CombatConfig = {}

--============================================================================--
-- WEAPONS (M1 Attacks)
--============================================================================--
CombatConfig.Weapons = {
	fists = {
		Damage = 10,
		Range = 10,
		Cooldown = 0.65,
		HitstunDuration = 0.6,
		-- Combo damage delays (synced to animation timing)
		DamageDelays = { 0.41, 0.41, 0.41, 0.51 },
		-- Flourish (combo finisher)
		FlourishKnockbackPower = 55,
		FlourishKnockbackDuration = 0.18,
		FlourishSelfHitstun = 0.5,
	},
	kunai = {
		Damage = 9,
		Range = 11,
		Cooldown = 0.7,
		HitstunDuration = 0.65,
		-- Combo damage delays (synced to animation timing)
		DamageDelays = { 0.38, 0.38, 0.38, 0.48 },
		-- Flourish (combo finisher)
		FlourishKnockbackPower = 60,
		FlourishKnockbackDuration = 0.2,
		FlourishSelfHitstun = 0.5,
	},
	uchigatana = {
		Damage = 11,
		Range = 12,
		Cooldown = 0.8,
		HitstunDuration = 0.7,
		-- Combo damage delays (synced to animation timing)
		DamageDelays = { 0.42, 0.42, 0.42, 0.52 },
		-- Flourish (combo finisher)
		FlourishKnockbackPower = 65,
		FlourishKnockbackDuration = 0.22,
		FlourishSelfHitstun = 0.55,
	},
	kusanagi = {
		Damage = 11,
		Range = 12,
		Cooldown = 0.75, -- Slightly faster than uchigatana
		HitstunDuration = 0.7,
		-- Combo damage delays (synced to animation timing)
		DamageDelays = { 0.38, 0.38, 0.38, 0.48 }, -- Faster combo
		-- Flourish (combo finisher)
		FlourishKnockbackPower = 65,
		FlourishKnockbackDuration = 0.22,
		FlourishSelfHitstun = 0.55,
	},
	kubikiribocho = {
		Damage = 14, -- Heavy hits harder
		Range = 16, -- Longer reach
		Cooldown = 1.1, -- Slower swing speed for heavy weapon
		HitstunDuration = 0.8, -- Longer stagger
		-- Combo damage delays (synced to animation timing)
		DamageDelays = { 0.78, 0.78, 0.78, 0.98 }, -- Heavy swings hit late
		-- Flourish (combo finisher)
		FlourishKnockbackPower = 75, -- Stronger knockback
		FlourishKnockbackDuration = 0.25,
		FlourishSelfHitstun = 0.6,
	},
	bostaff = {
		Damage = 11, -- Medium weapon damage
		Range = 12, -- Medium reach
		Cooldown = 0.8, -- Medium swing speed
		HitstunDuration = 0.7, -- Medium stagger
		-- Combo damage delays (synced to animation timing)
		DamageDelays = { 0.68, 0.68, 0.68, 0.68 },
		-- Flourish (combo finisher)
		FlourishKnockbackPower = 65,
		FlourishKnockbackDuration = 0.22,
		FlourishSelfHitstun = 0.55,
	},
}

--============================================================================--
-- HEAVY ATTACKS (Critical/R Attacks)
--============================================================================--
CombatConfig.HeavyAttacks = {
	-- Shared values for all heavy attacks
	DamageMultiplier = 1.5, -- 1.5x base weapon damage
	Cooldown = 5,
	WindupDuration = 0.4, -- Time before parry flash appears
	DamageDelay = 0.8, -- Total time before damage (includes windup)
	KnockbackDuration = 0.2,
	GuardbreakDuration = 1.5, -- When hitting a blocking target
	DefaultSlowMultiplier = 0.1, -- Default 90% slow (10% of normal speed)

	-- Per-skill overrides (if needed)
	HeavyPunch = {
		Range = 11,
		KnockbackPower = 40,
		SlowMultiplier = 0.5, -- 60% slow (40% of normal speed)
	},
	HeavySlash = {
		Range = 11,
		SlowMultiplier = 0.7, -- 75% slow (25% of normal speed)
	},
}

--============================================================================--
-- COMBO SYSTEM
--============================================================================--
CombatConfig.Combo = {
	ResetTime = 2.0, -- Seconds before combo resets to phase 1
	MaxPhase = 4, -- Total combo phases (1, 2, 3, flourish)
}

--============================================================================--
-- HITBOX
--============================================================================--
CombatConfig.Hitbox = {
	HitAngleThreshold = 0.3, -- Dot product (~72 degrees in front)
	BlockAngleThreshold = 0, -- 180 degree block arc (90 degrees each side)
}

--============================================================================--
-- STATUS EFFECT DURATIONS
--============================================================================--
CombatConfig.StatusDurations = {
	-- Parry/Block
	Autoparry = 0.4, -- Protection window after successful parry
	BlockStunned = 0.2, -- Brief stun when blocking a hit
	Shakyblock = 0, -- Failed parry punishment

	-- Hitstun
	ParriedAttackerHitstun = 0.8, -- Attacker stagger when parried
	HeavyParriedHitstun = 0.9, -- Slightly longer for heavy attacks

	-- Other
	RollcancelStun = 0, -- Stun when hitting iframes
	Guardbroken = 1.2, -- Default guardbreak duration
}

--============================================================================--
-- POSTURE SYSTEM
--============================================================================--
CombatConfig.Posture = {
	MaxPosture = 100,
	RecoveryDelay = 3.0, -- Seconds before recovery starts
	RecoveryRate = 0.02, -- 2% of max per second
	RecoveryRateBlocking = 0.01, -- 1% while blocking (50% slower)

	-- Damage values
	BlockDamage = 15, -- Per blocked M1
	HeavyBlockDamageMultiplier = 1.5, -- Heavy attacks deal 1.5x posture damage
	ParriedDamage = 30, -- Attacker loses when parried (capped at 99%)
	ParryReward = 15, -- Defender gains on successful parry

	-- Guardbreak
	GuardbreakDuration = 1.5,
}

--============================================================================--
-- PARRY SYSTEM
--============================================================================--
CombatConfig.Parry = {
	WindowDuration = 0.2, -- How long parry is active after pressing block
	Cooldown = 0.4, -- Time after failed parry before can parry again
}

--============================================================================--
-- DODGE/ROLL
--============================================================================--
CombatConfig.Dodge = {
	IframeDuration = 0.3,
	Cooldown = 1.0,
	Distance = 20,
}

--============================================================================--
-- INPUT BUFFER
--============================================================================--
CombatConfig.InputBuffer = {
	-- How long inputs are stored before expiring (in seconds)
	-- Higher = more forgiving, lower = more precise
	BufferWindow = 0.075, -- 75ms (similar to fighting games)

	-- Default state (can be toggled by player in settings)
	EnabledByDefault = true,
}

--============================================================================--
-- HOLD TO M1
--============================================================================--
CombatConfig.HoldToM1 = {
	-- When enabled, holding M1 will automatically chain attacks through the combo
	-- Players can still click to attack normally - this just adds hold functionality
	EnabledByDefault = true,
}

return CombatConfig
