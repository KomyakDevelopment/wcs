# Combat Tag System Plan

## Overview
A combat tag system marks players as "in combat" when they deal or receive PvP damage, preventing combat logging (leaving during a fight to avoid death).

## Specifications

- **Tag Duration**: 30 seconds (configurable)
- **Triggers**: Any PvP damage dealt (tags BOTH attacker and victim)
- **Combat Log Consequence**: Count as death, give kill credit to last attacker
- **Visual**: Use existing `StarterGui.Main.Ctag` frame with countdown
- **NPCs**: Not included for now (PvP only)

---

## Architecture

### CombatTagManager (Server Manager)
Server-side singleton that tracks combat state:

```lua
_taggedPlayers = {
    [Player] = {
        taggedUntil = number,      -- os.clock() timestamp when tag expires
        lastAttacker = Player?,    -- who last dealt damage to them
    }
}
```

**Methods:**
- `tagPlayer(player, attacker?)` - Tags player, stores attacker, refreshes timer
- `isTagged(player)` - Returns true if player is in combat
- `getLastAttacker(player)` - Returns who last attacked them
- `getTimeRemaining(player)` - Returns seconds left on tag

**Events:**
- `PlayerRemoving` - Check if player was tagged → award kill to attacker
- Heartbeat loop to clean up expired tags and update clients

### Client UI
- Use existing `StarterGui.Main.Ctag` frame
- `Ctag.TextTemp` shows "In combat for # seconds!"
- Frame visible when tagged, hidden when not
- RemoteEvent to sync tag state from server

---

## Implementation Steps

### Step 1: Create CombatTagManager
Create `src/server/managers/combatTagManager.luau`:
- Singleton pattern (like deathManager)
- Track tagged players with timestamps
- Handle PlayerRemoving for combat log detection
- RemoteEvent to update client UI
- Heartbeat loop to expire tags and sync remaining time

### Step 2: Create Client UI Manager
Create `src/client/managers/combatTagUIManager.luau`:
- Listen for server updates via RemoteEvent
- Show/hide `StarterGui.Main.Ctag` frame
- Update countdown text every second

### Step 3: Create RemoteEvent
Add to `src/server/init.server.luau`:
- Create `CombatTagUpdate` RemoteEvent in ReplicatedStorage
- Initialize CombatTagManager

### Step 4: Integrate with Damage Skills
Add combat tagging to damage-dealing functions in:
- `slash.luau` - After `targetHumanoid:TakeDamage()` (line ~597)
- `punch.luau` - After `targetHumanoid:TakeDamage()` (line ~557)
- `heavySlash.luau` - After `targetHumanoid:TakeDamage()` (line ~471)
- `heavySwing.luau` - After `targetHumanoid:TakeDamage()` (line ~464)
- `heavyPunch.luau` - After `targetHumanoid:TakeDamage()` (line ~405)

Each location adds:
```lua
-- Combat tag both players
if _G.CombatTagManager then
    local attackerPlayer = Players:GetPlayerFromCharacter(self.Character.Instance)
    local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
    if attackerPlayer and targetPlayer then
        _G.CombatTagManager:tagPlayer(attackerPlayer, targetPlayer)
        _G.CombatTagManager:tagPlayer(targetPlayer, attackerPlayer)
    end
end
```

---

## Files to Create

1. **`src/server/managers/combatTagManager.luau`**
   - Main combat tag logic
   - ~150 lines

2. **`src/client/managers/combatTagUIManager.luau`**
   - UI visibility and countdown
   - ~80 lines

---

## Files to Modify

1. **`src/server/init.server.luau`**
   - Create RemoteEvent
   - Initialize CombatTagManager
   - Store in `_G.CombatTagManager`

2. **`src/shared/skills/slash.luau`**
   - Add tag call after damage

3. **`src/shared/skills/punch.luau`**
   - Add tag call after damage

4. **`src/shared/skills/heavySlash.luau`**
   - Add tag call after damage

5. **`src/shared/skills/heavySwing.luau`**
   - Add tag call after damage

6. **`src/shared/skills/heavyPunch.luau`**
   - Add tag call after damage

7. **`src/client/init.client.luau`**
   - Initialize CombatTagUIManager

---

## Combat Log Flow

When a tagged player leaves:
1. `PlayerRemoving` fires
2. CombatTagManager checks if player was tagged
3. If tagged:
   - Get `lastAttacker`
   - Award kill to attacker (increment their kill stat)
   - Log the combat log event
   - Print: `[CombatTagManager] {player} combat logged - kill awarded to {attacker}`
4. Clean up player's tag data
