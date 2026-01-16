# Parry System Rework Plan

## Problem Summary

The current parry system has fundamental architectural issues causing:
1. **"Impossible to parry" feeling** - Network latency creates a 100-180ms dead zone
2. **Animation smooshing** - Duplicate animation tracks from manual play + Roblox replication
3. **Inconsistent timing** - Server-authoritative parry detection can't respond faster than network latency

## Root Cause Analysis

### Current Flow (Broken)
```
Player presses F → Client sends to server → Server waits → Server applies Parrying status
→ Status replicates to attacker → Attacker checks status → PARRY DETECTED

Time: 100-180ms before parry is "visible" to attacker's hit detection
```

### The Problem
- Parry window is 300ms configured, but only ~130-210ms is usable after latency
- Attack hit detection runs on SERVER, checking server-side status effects
- By the time server knows defender is parrying, it might be too late

## Solution: Client-Prediction with Timestamp Validation

### Industry Standard Approach
Based on fighting game netcode (GGPO) and Roblox DevForum best practices:

1. **Client-Side Hit Detection**: Attacker's CLIENT detects hits and parry state
2. **Timestamp-Based Validation**: Use timestamps to verify parry was active at hit time
3. **Trust-But-Verify**: Server validates client decisions within latency tolerance
4. **Optimistic Updates**: Show results immediately, rollback only if server disagrees

### New Flow
```
Player presses F → Client sets local parry state + timestamp → Replicates attribute

Attacker attacks → Attacker's CLIENT detects hit → Checks defender's attributes
→ If parrying: Client shows parry VFX immediately
→ Sends hit result to server with timestamp
→ Server validates within latency tolerance → Confirms or denies
```

## Implementation Plan

### Phase 1: Attribute-Based Parry State (Replace Status Effects for Detection)

Instead of relying on WCS status effects for parry detection (which require server round-trip),
use **Character Attributes** that replicate automatically:

```lua
-- When block starts (client-side)
character:SetAttribute("IsParrying", true)
character:SetAttribute("ParryStartTime", workspace:GetServerTimeNow())

-- When parry window ends
character:SetAttribute("IsParrying", false)
```

Attributes replicate to all clients automatically, much faster than status effects.

### Phase 2: Client-Side Hit Detection

Move hit detection from server to client:

```lua
-- In slash.luau OnStartClient
function Slash:_detectHitClient()
    -- Find targets in range
    local targets = self:_getTargetsInRange()

    for _, target in targets do
        local isParrying = target:GetAttribute("IsParrying")
        local parryStartTime = target:GetAttribute("ParryStartTime")

        if isParrying and parryStartTime then
            -- Check if parry was active at time of our attack
            local attackTime = workspace:GetServerTimeNow()
            local parryAge = attackTime - parryStartTime

            if parryAge <= PARRY_WINDOW_DURATION then
                -- PARRY! Show VFX immediately
                self:_onParriedClient(target)
                -- Send to server for validation
                self:_sendHitToServer(target, "parried", attackTime, parryStartTime)
                return
            end
        end

        -- Check blocking...
        -- Apply damage...
    end
end
```

### Phase 3: Server Validation

Server validates client's parry decision:

```lua
-- In server hit handler
function validateHit(attacker, target, hitResult, attackTime, parryStartTime)
    local latencyTolerance = 0.2 -- 200ms tolerance for network variance

    if hitResult == "parried" then
        -- Verify parry was legitimately active
        local serverParryStart = target:GetAttribute("ParryStartTime")

        -- Allow some tolerance for network timing differences
        if math.abs(serverParryStart - parryStartTime) <= latencyTolerance then
            -- Valid parry
            return true
        else
            -- Suspicious - client claimed parry but timestamps don't match
            warn("Suspicious parry claim from", attacker.Name)
            return false
        end
    end
end
```

### Phase 4: Remove Animation Conflicts

Stop manually playing attack animations on other clients. Roblox handles this automatically.

```lua
-- blockVFXManager.luau - ALREADY DONE
-- Just show VFX, don't play animations
function BlockVFXManager:_playLocalAttackAnimation(attackerCharacter, attackPhase, _animationId)
    -- Just show parry flash VFX - Roblox handles animation replication
    self:playParryFlashVFX(attackerCharacter, attackPhase)
end
```

### Phase 5: Timing Adjustments

```lua
-- combatConfig.luau
CombatConfig.Parry = {
    WindowDuration = 0.25,     -- Slightly longer window (was 0.2)
    Cooldown = 0.3,            -- Reduced cooldown (was 0.5)
    LatencyTolerance = 0.15,   -- Server allows 150ms timing variance
}
```

## Key Changes Summary

| Component | Before | After |
|-----------|--------|-------|
| Parry Detection Location | Server (status effect check) | Client (attribute check) |
| Parry State Storage | WCS StatusEffect | Character Attribute |
| Hit Detection | Server-side | Client-side with server validation |
| Animation Sync | Manual play + Roblox replication | Roblox replication only |
| Parry Feedback | Delayed by network | Immediate (optimistic) |

## Security Considerations

1. **Timestamp Validation**: Server verifies parry timestamp matches within tolerance
2. **Cooldown Enforcement**: Server still tracks cooldowns authoritatively
3. **Damage Cap**: Server validates damage amounts
4. **Position Validation**: Server can verify attacker was in range

## Files to Modify

1. `src/shared/skills/block.luau` - Add attribute-based parry state
2. `src/shared/skills/slash.luau` - Client-side hit detection
3. `src/shared/skills/punch.luau` - Client-side hit detection
4. `src/shared/config/combatConfig.luau` - Timing adjustments
5. `src/client/managers/blockVFXManager.luau` - Remove animation conflicts (DONE)
6. `src/server/init.server.luau` - Add hit validation remote

## Expected Results

- Parry feels **instant** because client detects it locally
- No animation smooshing because we stopped duplicate animation play
- Server maintains authority through validation
- Timing is **consistent** regardless of ping (within reason)
