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

	-- Per-skill overrides (if needed)
	HeavyPunch = {
		Range = 11,
		KnockbackPower = 40,
	},
	HeavySlash = {
		Range = 11,
		KnockbackPower = 45,
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
	BlockStunned = 0.1, -- Brief stun when blocking a hit
	Shakyblock = 0.3, -- Failed parry punishment

	-- Hitstun
	ParriedAttackerHitstun = 0.8, -- Attacker stagger when parried
	HeavyParriedHitstun = 0.9, -- Slightly longer for heavy attacks

	-- Other
	RollcancelStun = 0.15, -- Stun when hitting iframes
	Guardbroken = 1.5, -- Default guardbreak duration
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
