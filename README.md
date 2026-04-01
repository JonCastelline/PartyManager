# PartyManager

A Windower 4 addon for Final Fantasy XI that automates party management, particularly for AFK master leveling.

## Features
- Automated invites based on whitelisted tells (+ optional password).
- Coordination with a puller (self or alt via `//send`).
- Dynamic trust management (dismisses trusts for invite, then re-summons based on new party size).
- Level sync automation.
- State-machine driven to handle combat and cooldowns.

## Commands

### Basic Setup
- `//pm on` / `off`: Enable or disable the addon.
- `//pm whitelist add <name>`: Add a player to the whitelist.
- `//pm whitelist rm <name>` or `//pm whitelist remove <name>`: Remove a player from the whitelist.
- `//pm password <word>`: Set an optional trigger password.
- `//pm status`: Check current state and settings.
- `//pm reset`: Force reset the state machine to IDLE.

### Coordination
- `//pm puller name <name>`: Set the name of the character doing the pulling.
- `//pm puller stop <command>`: Command to stop pulling (default: `//trust stop`).
- `//pm puller start <command>`: Command to start pulling (default: `//trust start`).
- `//pm limit <number>`: Set max number of human players allowed.
- `//pm sync self|sender|none`: Set level sync mode.

### Trust Sets
Define which trusts to summon based on how many human players (PCs) are in the party.
- `//pm trust <pc_count> add <trust_name>`: Add a trust to the set for that PC count. For UC trusts and trusts with a II, add the name in quotes (e.g. //pm trust 2 add "Sylvie (UC)").
- `//pm trust <pc_count> clear`: Clear the trust set for that PC count.

Example:
```
//pm trust 1 add "Sylvie (UC)"
//pm trust 1 add "Kupipi"
//pm trust 2 add "Kupipi"
```

## How It Works
1. Receives a tell from a whitelisted friend.
2. Replies to them to wait.
3. Stops the puller.
4. Waits for all current monsters to die.
5. Dismisses all trusts.
6. Invites the friend.
7. Waits for the friend to join and be in the same zone.
8. Sets level sync.
9. Summons trusts based on the new PC count.
10. Resumes the puller.
