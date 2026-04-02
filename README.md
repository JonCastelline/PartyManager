# PartyManager

A Windower 4 addon for Final Fantasy XI that automates party management, specifically designed for Master Leveling and coordination.

## Features
- **Automated Invitations:** Whitelist-based invitations triggered by Tells (with optional password protection).
- **Dynamic Trust Management:** Automatically manages trust sets (1PC to 5PC) based on the number of players in the party.
- **Auto Trust Resummon:** Monitors the party and automatically stops the puller, kills the current mob, and re-summons trusts if a player leaves.
- **Master Level Sync:** Automated level sync using raw packet injection (0x077) for 100% reliability.
- **Sync Modes:** Supports `sender` (sync to the person joining), `fixed` (sync to a specific character), or `lowest` (automatically finds the lowest Master Level in the party).
- **Puller Coordination:** Coordinates with a puller (self or alt via `/console send`) to safely pause and resume pulling during party changes.
- **Interactive UI:** A real-time UI for monitoring party status, Master Levels, and managing settings.
- **Safety Logic:** State-machine driven to handle combat, trust cooldowns (2-minute timer), and player distance.

## Commands

### Basic Setup
- `//pm on` / `off`: Enable or disable the addon.
- `//pm ui`: Toggle the graphical interface.
- `//pm whitelist add <name>`: Add a player to the whitelist.
- `//pm whitelist rm <name>`: Remove a player from the whitelist.
- `//pm password <word>`: Set a trigger password (visible in UI).
- `//pm limit <1-6>`: Set the maximum number of human players allowed in the party.
- `//pm resummon on/off`: Toggle the Auto Trust Resummon feature.
- `//pm status`: Check current state and settings.
- `//pm reset`: Force reset the state machine to IDLE.

### Coordination & Sync
- `//pm puller name <name>`: Set the name of the character pulling (supports alts).
- `//pm sync mode sender|fixed|lowest|none`: Set how the addon chooses a sync target.
- `//pm sync target <name>`: Set the specific target for `fixed` sync mode.
- `//pm puller stop/start <command>`: Customize the puller commands (default: `//trust stop/start`).

### Trust Sets
Define which trusts to summon based on how many human players (PCs) are in the party (1PC to 5PC).
- `//pm trust <pc_count> add <trust_name>`: Add a trust to the set for that PC count.
- `//pm trust <pc_count> clear`: Clear the trust set for that PC count.

Example:
```
//pm trust 1 add "Sylvie (UC)"
//pm trust 1 add "Kupipi"
//pm trust 2 add "Kupipi"
```

## UI Functionality
- **Live Party List:** Shows all members, their job, and their **Master Level**.
- **Responsive Toggles:** Instant visual feedback for addon state, AutoSync, and AutoTrust.
- **Interactive Pickers:** Click on "Puller," "Whitelist," or any "PC" count to open a side-panel for easy management.
- **Auto-Truncation:** Handles long passwords and names gracefully within the interface.

## How It Works (The Cycle)
1. **Detection:** Receives a tell from a whitelisted player (matching password if set).
2. **Safety:** Stops the puller and waits for the current mob to die.
3. **Clearing:** Dismisses all current trusts.
4. **Invite:** Sends the party invitation and waits up to 10 minutes for the player to join and be in range.
5. **Sync:** Targets the chosen player and injects a 0x077 packet to trigger Level Sync.
6. **Summon:** Waits for the 2-minute trust cooldown (if a sync occurred or party changed) and summons the appropriate trust set.
7. **Resume:** Restarts the puller and returns to IDLE.
