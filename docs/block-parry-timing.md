# Block/Parry Timing System Documentation

## Overview

This document describes the block and parry timing system, including the shakyblock punishment mechanic for failed parries.

---

## Timing Flow (When Player Holds F)

```
0.00s ─────────────────────────────────────────────────────────────────────────
│ PLAYER PRESSES F
│ Block skill becomes active
│ No status effects applied yet
▼
0.00s - 0.03s: STARTUP PHASE (0.03s duration)
├── Status Effects: NONE
├── Block skill: ACTIVE
├── Vulnerable: YES
├── If hit:
│   ├── Takes full damage
│   ├── Applies SoftHitstun (0.6s)
│   └── Applies SHAKYBLOCK (0.8s) ← Failed parry punishment
│
0.03s ─────────────────────────────────────────────────────────────────────────
│ STARTUP COMPLETE
│ Parrying status applied (if not on cooldown/shakyblock)
▼
0.03s - 0.3275s: PARRY WINDOW (0.2975s duration)
├── Status Effects: PARRYING only (no Blocking)
├── Block skill: ACTIVE
├── Vulnerable: NO (protected by parry)
├── If hit:
│   ├── SUCCESSFUL PARRY
│   ├── Attacker gets SoftHitstun (0.8s)
│   ├── Attacker gets Parried status
│   ├── Defender gets Autoparry (0.4s)
│   └── Posture changes applied
│
0.3275s ───────────────────────────────────────────────────────────────────────
│ PARRYING STATUS EXPIRES
│ No status effects active
▼
0.3275s - 0.5s: FAILED PARRY WINDOW (0.1725s duration)
├── Status Effects: NONE
├── Block skill: ACTIVE
├── Vulnerable: YES
├── If hit:
│   ├── Takes full damage
│   ├── Applies SoftHitstun (0.6s)
│   └── Applies SHAKYBLOCK (0.8s) ← Failed parry punishment
│
0.5s ──────────────────────────────────────────────────────────────────────────
│ BLOCKING STATUS APPLIED
▼
0.5s - ∞: BLOCK WINDOW (while holding F)
├── Status Effects: BLOCKING only
├── Block skill: ACTIVE
├── Vulnerable: PARTIAL (directional)
├── If hit while FACING attacker:
│   ├── SUCCESSFUL BLOCK
│   ├── No damage taken
│   ├── BlockStunned applied (0.1s)
│   ├── Posture damage applied
│   └── Block VFX/SFX plays
├── If hit while NOT FACING attacker:
│   ├── Takes full damage
│   ├── Applies SoftHitstun (0.6s)
│   └── NO shakyblock (they're in block phase, not failed parry)
│
∞ ─────────────────────────────────────────────────────────────────────────────
│ PLAYER RELEASES F
│ Block skill ends
│ Blocking status removed
▼
Release - Release + 0.5s: COOLDOWN PHASE
├── Can still block (skill can be activated)
├── Parry window DISABLED during cooldown
└── Prevents spam parrying
```

---

## Shakyblock Status Effect

### Purpose
Punishes players who fail their parry timing by disabling their ability to parry for a duration.

### Duration
- **0.8 seconds**

### When Applied
1. **Startup Phase (0.00s - 0.03s)**: Player pressed F too early
2. **Failed Parry Window (0.3275s - 0.5s)**: Player pressed F too late (parry window expired)

### Effects
- Disables parrying (player can still block, but no parry window)
- Visual indicator: Tweens in `StarterGui.Main.PostureGUI.Posture.shaky_block` frame

### Detection Logic (punch.luau)
```lua
-- Check if target is in failed parry window or startup phase
local targetBlockSkill = targetWCSCharacter:GetSkillFromConstructor(Block)
if targetBlockSkill then
    local blockState = targetBlockSkill:GetState()
    if blockState.IsActive then
        -- Block skill is active - check if they're in failed parry window or startup
        local hasParryingOrBlocking = targetWCSCharacter:HasStatusEffects({ Parrying, Autoparry, Blocking })
        if not hasParryingOrBlocking then
            -- They're holding block but have no status = failed parry window OR startup
            inFailedParryWindow = true
        end
    end
end
```

---

## Configuration Constants

### block.luau
```lua
local BLOCK_STARTUP_TIME = 0.03        -- Windup before parry becomes active
local PARRY_WINDOW_DURATION = 0.2975   -- Perfect parry window duration
local BLOCK_COOLDOWN = 0.5             -- Cooldown after releasing block
local FAILED_PARRY_WINDOW = 0.1725     -- Gap between parry end and block start
```

### Calculated Timings
```lua
-- When blocking status starts (after failed parry window)
blockingStartDelay = BLOCK_STARTUP_TIME + PARRY_WINDOW_DURATION + FAILED_PARRY_WINDOW
-- 0.03 + 0.2975 + 0.1725 = 0.5s
```

### punch.luau
```lua
local SOFT_HITSTUN_DURATION = 0.6      -- Hitstun applied on all M1 hits
```

### shakyblock.luau
```lua
shakyblock:Start(0.8)                   -- Shakyblock duration
```

---

## Files Modified

### 1. block.luau (`src/shared/skills/block.luau`)
**Changes:**
- Separated Parrying and Blocking status application
- Parrying status now applies at 0.03s (startup complete)
- Blocking status now applies at 0.5s (after failed parry window)
- Added Shakyblock check to disable parry window when active

**Key Code:**
```lua
-- Apply startup delay before block becomes active
task.delay(BLOCK_STARTUP_TIME, function()
    -- Apply ONLY Parrying status (no Blocking)
    if not self.parryOnCooldown then
        self.parryingEffect = Parrying.new(self.Character)
        self.parryingEffect:Start(PARRY_WINDOW_DURATION)
    end
end)

-- Apply Blocking status after failed parry window expires (0.5s total)
local FAILED_PARRY_WINDOW = 0.1725
local blockingStartDelay = BLOCK_STARTUP_TIME + PARRY_WINDOW_DURATION + FAILED_PARRY_WINDOW

task.delay(blockingStartDelay, function()
    self.blockingEffect = Blocking.new(self.Character)
    self.blockingEffect:Start(-1)
end)
```

### 2. punch.luau (`src/shared/skills/punch.luau`)
**Changes:**
- Added Shakyblock import
- Added failed parry window detection in `_hitTarget`
- Applies Shakyblock when player is hit during startup or failed parry window

**Key Code:**
```lua
-- In _hitTarget function
local inFailedParryWindow = false

local targetBlockSkill = targetWCSCharacter:GetSkillFromConstructor(Block)
if targetBlockSkill then
    local blockState = targetBlockSkill:GetState()
    if blockState.IsActive then
        local hasParryingOrBlocking = targetWCSCharacter:HasStatusEffects({ Parrying, Autoparry, Blocking })
        if not hasParryingOrBlocking then
            inFailedParryWindow = true
        end
    end
end

-- Later, after applying damage and hitstun:
if inFailedParryWindow then
    local shakyblock = Shakyblock.new(targetWCSCharacter)
    shakyblock:Start(0.8)
end
```

### 3. shakyblock.luau (`src/shared/statusEffects/shakyblock.luau`) - NEW FILE
**Purpose:** Status effect that disables parrying

**Features:**
- Sets `Character.HasShakyblock = true` flag
- Shows visual indicator via tween animation
- Prevents parry window activation in block.luau

**Key Code:**
```lua
function Shakyblock:OnStartServer()
    character.HasShakyblock = true
end

function Shakyblock:OnStartClient()
    -- Tween in shaky_block visual indicator
    self:_showShakyBlockIndicator()
end
```

---

## Visual Indicator

**Location:** `StarterGui.Main.PostureGUI.Posture.shaky_block`

**Animation:**
- **Show:** Tweens from 80% size + transparent to 100% size + visible (0.2s, Back easing)
- **Hide:** Tweens from 100% size + visible to 80% size + transparent (0.2s, Quad easing)

---

## Interaction with Other Systems

### Sprint
- Sprint checks for `SoftHitstun` at startup
- Getting hit applies SoftHitstun (0.6s), preventing sprint during that time
- This is intended behavior

### Guardbreak (Blockbreak)
- If a block results in guardbreak (posture >= max), block VFX is skipped
- Only guardbreak VFX plays (no double VFX)
- Uses blockbreak animation: `rbxassetid://78365067000333`

### Autoparry
- Applied after successful parry (0.4s duration)
- Protects player during attack window after parrying
- Counted as "parrying" for failed parry detection (won't trigger shakyblock)

---

## Summary Table

| Phase | Time | Duration | Status Effects | If Hit |
|-------|------|----------|----------------|--------|
| Startup | 0.00s - 0.03s | 0.03s | None | Damage + Hitstun + **Shakyblock** |
| Parry | 0.03s - 0.3275s | 0.2975s | Parrying | Successful Parry |
| Failed Parry | 0.3275s - 0.5s | 0.1725s | None | Damage + Hitstun + **Shakyblock** |
| Block | 0.5s - ∞ | ∞ | Blocking | Block (if facing) or Damage |
| Cooldown | Release - +0.5s | 0.5s | None | N/A (block ends) |
