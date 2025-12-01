# Knockdown System Documentation

## Overview
The knockdown system handles player "death" by ragdolling them for 6 seconds instead of killing them. After recovery, they get 8 seconds of immunity before they can be knocked again.

## Key Files
- `src/server/managers/deathManager.luau` - Main knockdown logic

## Configuration
```lua
KNOCKDOWN_DURATION = 6.0      -- Seconds ragdolled
MIN_KNOCKDOWN_HP = 1          -- HP floor (prevents actual death)
POST_RECOVERY_IMMUNITY = 8.0  -- Seconds of immunity after standing up
```

## Bugs Fixed

### 1. Recovery Abort Bug ("Stiff" State)
**Problem:** If HP was 0 when recovery triggered (from last-second M1 damage), recovery would abort early:
- `_knockedPlayers` cleared (not "knocked")
- But ragdoll stayed enabled, PlatformStand stayed true
- Player was standing but frozen/stiff

**Root Cause:** Line checking `if humanoid.Health <= 0 then return` aborted recovery before disabling ragdoll.

**Fix:**
- Moved existence checks before state changes
- If HP is 0 at recovery start, set to MIN_KNOCKDOWN_HP first
- Recovery always completes (ragdoll disabled, movement restored)

### 2. HP Oscillation Loop (7% → 0% → 7% → 0%)
**Problem:** During immunity, not setting HP caused:
1. HP hits 0 → immunity returns without setting HP
2. Roblox regen brings HP to ~7%
3. Another hit → HP to 0
4. Repeat forever

**Fix:** During immunity window, set HP to MIN_KNOCKDOWN_HP (1) to give regen a stable base.

### 3. Knockdown Re-trigger After Protection Expires
**Problem:** Previous approach tracked time from knockdown START. With 10s cooldown and 6s knockdown, only 4s protection after recovery.

**Fix:** Track `_recoveryTime` (when player RECOVERED), giving full 8s immunity after standing up.

## Flow

### Knockdown Triggered
```
HP hits 0
    → Check if already knocked (skip if true)
    → Check if being executed (allow death)
    → Check post-recovery immunity (set HP to 1, return)
    → Check instant-kill vs combat (lastKnownHP > 15% = instant-kill)
    → _handleKnockdown()
        → Set _knockedPlayers[player] = true
        → Clear _recoveryTime (fresh start)
        → Set HP to MIN_KNOCKDOWN_HP
        → Apply Knockdown status effect
        → Enable ragdoll physics
        → Start 6s recovery timer
```

### Recovery
```
6 seconds pass
    → _handleRecovery()
        → Check player/character exists
        → If HP <= 0, set to MIN_KNOCKDOWN_HP (prevents stiff bug)
        → Set _recoveryTime = tick()
        → Set KnockdownImmunity attribute
        → Disconnect health protection
        → End Knockdown status effect
        → Disable ragdoll
        → Restore humanoid properties
        → Clear _knockedPlayers[player]
```

### During Immunity (8 seconds after recovery)
```
HP hits 0
    → Check _recoveryTime or KnockdownImmunity attribute
    → If within 8s: set HP to 1, return (no knockdown)
    → After 8s: normal knockdown can occur
```

## Key State Variables
| Variable | Purpose |
|----------|---------|
| `_knockedPlayers[player]` | Currently ragdolled |
| `_recoveryTime[player]` | Timestamp of last recovery (for immunity) |
| `KnockdownImmunity` attribute | Backup immunity check on character |
| `_knockdownHealthConnections[player]` | HP protection while knocked |
| `_knockdownStatusEffects[player]` | WCS Knockdown effect reference |

## Immunity Attribute
The `KnockdownImmunity` attribute on character serves as:
1. Backup check if `_recoveryTime` fails
2. Other systems can check if player is immune
3. Auto-removed after POST_RECOVERY_IMMUNITY seconds

## Common Issues & Debugging

### Player stuck in ragdoll
- Check `_handleRecovery` completed (look for "recovering from knockdown" print)
- Verify `_disableRagdoll` was called
- Check Motor6Ds are re-enabled

### Knockdown loop persists
- Check `_recoveryTime` is being set
- Verify immunity window duration (8s)
- Look for prints showing "post-recovery immunity"

### Player dies instead of knockdown
- Check `BreakJointsOnDeath = false` is set
- Verify `_executingPlayers` isn't set
- Check instant-kill threshold (15% HP)
