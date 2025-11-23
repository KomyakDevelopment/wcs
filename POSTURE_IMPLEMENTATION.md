# Posture System Implementation Plan

## Overview

A Sekiro-inspired posture system where blocking attacks builds up posture damage. When posture reaches maximum, the character becomes "guardbroken" and is vulnerable for a short duration.

---

## Core Mechanics

### Posture Bar Behavior
- Posture starts at **0** and increases toward **max posture**
- When posture reaches max → **Guardbreak** occurs
- Max posture scales with character stats (future implementation)
- Default max posture: **100** (placeholder until stats system exists)

### Posture Actions

| Action | Effect | Details |
|--------|--------|---------|
| **Blocking an M1** | Defender gains posture | Amount based on attacker's weapon/stats |
| **Getting parried** | Attacker gains posture | Capped at 99% of max (can NEVER guardbreak from parry alone) |
| **Successfully parrying** | Defender loses posture | Reward for good timing |
| **Getting hit (unblocked)** | Nothing | Posture unaffected by raw damage |
| **Blocking while guardbroken** | Cannot block | Block skill should check for Guardbroken status |

### Posture Recovery
- **Delay**: 1 second after last posture-affecting action before recovery begins
- **Rate**: 5% of max posture per second
- **Holding Block**: Recovery rate is reduced (e.g., 50% slower)
- **Always Active**: Recovery happens regardless of combat status

### Guardbreak State
- **Duration**: 1.5 seconds
- **Animation ID**: `rbxassetid://120994424404934` (placeholder)
- **Effects**:
  - WalkSpeed = 0 (cannot move)
  - JumpPower = 0 (cannot jump)
  - Cannot block
  - Essentially "TrueHitstun" but with 0 movement

---

## Technical Implementation

### Data Storage (Server-Authoritative)

Based on research from [Roblox Security Tactics](https://github.com/Roblox/creator-docs/blob/main/content/en-us/scripting/security/security-tactics.md) and [DevForum discussions](https://devforum.roblox.com/t/how-can-i-prevent-exploiters-from-modifying-a-value-explanation/2153412):

**Approach: Server-side table + Attribute for UI replication**

```
Server stores authoritative posture values in a module table
↓
Server updates NumberValue/Attribute on character for client display
↓
Client reads attribute for UI only (never trusts client values)
```

#### Why This Approach?
1. **Security**: All posture calculations happen server-side
2. **Replication**: Attributes replicate automatically to clients
3. **Performance**: No RemoteEvents needed for UI updates
4. **Simplicity**: Clients just read attributes, no complex sync logic

#### Implementation Details

**Server-side storage** (in PostureManager module):
```lua
local postureData = {} -- [player] = { current = 0, max = 100, lastActionTime = 0 }
```

**Character Attributes** (for client UI):
```lua
character:SetAttribute("Posture", currentPosture)
character:SetAttribute("MaxPosture", maxPosture)
```

---

## File Structure

```
src/
├── shared/
│   ├── statusEffects/
│   │   └── guardbroken.luau      -- NEW: Guardbroken status effect
│   └── managers/
│       └── postureManager.luau   -- NEW: Server-side posture logic
├── client/
│   └── managers/
│       └── postureUIManager.luau -- NEW: Client UI for posture display
```

---

## New Files

### 1. `guardbroken.luau` (Status Effect)

Similar to `TrueHitstun` but with 0 movement speed:

```lua
-- WCS Status Effect for Guardbroken state
-- Duration: 1.5 seconds
-- Effects:
--   - WalkSpeed = 0
--   - JumpPower = 0
--   - Cannot block (checked in Block skill)
--   - Play guardbroken animation
```

**Key behaviors:**
- Sets `WalkSpeed = 0`, `JumpPower = 0`
- Plays guardbroken animation (ID: `120994424404934`)
- Sets metadata `{ Active = true, Type = "Guardbroken" }`
- Block skill checks for this status and refuses to activate

### 2. `postureManager.luau` (Server Manager)

Handles all posture logic server-side:

```lua
local PostureManager = {}

-- Configuration
local DEFAULT_MAX_POSTURE = 100
local RECOVERY_DELAY = 1.0           -- Seconds before recovery starts
local RECOVERY_RATE = 0.05           -- 5% of max per second
local RECOVERY_RATE_BLOCKING = 0.025 -- 50% slower while blocking
local GUARDBREAK_DURATION = 1.5

-- Per-player posture data
local postureData = {}

-- Public API
function PostureManager:initializePlayer(player, character)
function PostureManager:addPosture(character, amount)      -- For blocking hits
function PostureManager:removePosture(character, amount)   -- For successful parries
function PostureManager:addPostureCapped(character, amount) -- For getting parried (max 99%)
function PostureManager:getPosture(character): number
function PostureManager:getMaxPosture(character): number
function PostureManager:isGuardbroken(character): boolean
function PostureManager:update(dt)                         -- Called from Heartbeat for recovery
function PostureManager:cleanup(player)                    -- On player leaving
```

**Recovery Logic (in update loop):**
```lua
for character, data in pairs(postureData) do
    local timeSinceAction = tick() - data.lastActionTime
    if timeSinceAction >= RECOVERY_DELAY and data.current > 0 then
        local rate = RECOVERY_RATE
        -- Check if character is blocking (slower recovery)
        if character:HasStatusEffect(Blocking) then
            rate = RECOVERY_RATE_BLOCKING
        end
        local recovery = data.max * rate * dt
        data.current = math.max(0, data.current - recovery)
        -- Update attribute for client UI
        character.Instance:SetAttribute("Posture", data.current)
    end
end
```

### 3. `postureUIManager.luau` (Client Manager)

Simple manager that updates the placeholder UI:

```lua
-- Reads character:GetAttribute("Posture") and MaxPosture
-- Updates StarterGui.Testing.Frame.Posture (TextLabel)
-- Format: "Posture: 45/100" or percentage
```

---

## Integration Points

### 1. Block Skill (`block.luau`)

Add check at start:
```lua
-- In OnStartServer and OnStartClient
if self.Character:HasStatusEffect(Guardbroken) then
    print("[Block] Cannot block - Guardbroken")
    return
end
```

### 2. Punch Skill (`punch.luau`)

In `_handleBlock()`:
```lua
-- After applying BlockStunned to defender
local PostureManager = require(...)
local postureAmount = 15 -- TODO: Base on attacker weapon/stats
PostureManager:addPosture(defenderWCSCharacter.Instance, postureAmount)
```

In `_handleParry()`:
```lua
-- Attacker gains posture (capped at 99%)
local attackerPosture = 30 -- TODO: Base on defender stats
PostureManager:addPostureCapped(self.Character.Instance, attackerPosture)

-- Defender loses posture (reward)
local defenderReduction = 20 -- TODO: Base on defender stats
PostureManager:removePosture(defenderWCSCharacter.Instance, defenderReduction)
```

### 3. Server Initialization (`init.server.luau`)

```lua
local PostureManager = require(...)
local RunService = game:GetService("RunService")

-- Initialize posture for new players
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        PostureManager:initializePlayer(player, character)
    end)
end)

-- Recovery tick
RunService.Heartbeat:Connect(function(dt)
    PostureManager:update(dt)
end)

-- Cleanup
Players.PlayerRemoving:Connect(function(player)
    PostureManager:cleanup(player)
end)
```

### 4. Client Initialization (`init.client.luau`)

```lua
local PostureUIManager = require(...)
local postureUIManager = PostureUIManager.new()
```

---

## Configuration Values (Initial)

| Constant | Value | Notes |
|----------|-------|-------|
| `DEFAULT_MAX_POSTURE` | 100 | Scales with future stats |
| `RECOVERY_DELAY` | 1.0s | Before recovery starts |
| `RECOVERY_RATE` | 5%/s | Of max posture |
| `RECOVERY_RATE_BLOCKING` | 2.5%/s | While holding block |
| `GUARDBREAK_DURATION` | 1.5s | Stagger duration |
| `BLOCK_POSTURE_DAMAGE` | 15 | Per blocked M1 (placeholder) |
| `PARRY_POSTURE_REWARD` | -20 | Defender gains on parry |
| `PARRIED_POSTURE_DAMAGE` | 30 | Attacker loses on parried (capped 99%) |

---

## UI (Placeholder)

Location: `StarterGui.Testing.Frame.Posture`

For now, just update this TextLabel with:
```
Posture: {current}/{max}
```

Later: Replace with actual bar UI.

---

## Implementation Order

1. **Create `guardbroken.luau`** - Status effect (like TrueHitstun but 0 speed)
2. **Create `postureManager.luau`** - Core posture logic
3. **Modify `block.luau`** - Add Guardbroken check
4. **Modify `punch.luau`** - Add posture calls in _handleBlock and _handleParry
5. **Modify `init.server.luau`** - Initialize PostureManager
6. **Create `postureUIManager.luau`** - Simple UI update
7. **Modify `init.client.luau`** - Initialize PostureUIManager

---

## Security Considerations

Based on [Roblox exploit prevention best practices](https://devforum.roblox.com/t/a-complete-guide-how-exploits-work-how-to-best-prevent-them/767594):

1. **All posture calculations are server-side** - Clients cannot modify posture
2. **Attributes are read-only for clients** - Used only for UI display
3. **No RemoteEvents for posture** - Eliminates injection attack vectors
4. **Status effect validation** - Guardbroken applied only by server

---

## Future Enhancements

- [ ] Character stats system integration (posture scaling)
- [ ] Weapon-specific posture damage values
- [ ] Posture bar visual UI (not just text)
- [ ] Posture damage VFX/SFX feedback
- [ ] Different guardbreak animations per weapon type
- [ ] Posture armor/reduction from equipment

---

## References

- [Sekiro Posture System Explained (GameWith)](https://gamewith.net/sekiro/article/show/8483)
- [Sekiro's Genius Posture Mechanic (What's in a Game?)](http://whats-in-a-game.com/sekiros-genius-posture-mechanic/)
- [Roblox Security Tactics](https://github.com/Roblox/creator-docs/blob/main/content/en-us/scripting/security/security-tactics.md)
- [Roblox Exploit Prevention Guide](https://devforum.roblox.com/t/a-complete-guide-how-exploits-work-how-to-best-prevent-them/767594)
- [Open Source Combat System (DevForum)](https://devforum.roblox.com/t/open-source-simple-combat-system-with-blocking-and-stun/2484521)
