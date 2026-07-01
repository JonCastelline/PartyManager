# PartyManager Path Forward
**Goal:** Finish and stabilize the current PartyManager implementation before it is treated as a baseline for anything else.

This document is the practical checklist for getting PartyManager to a trustworthy baseline. The intent is to reduce drift, close out known behavior questions, and freeze the addon state before any future work depends on it.

---

## 1. Pick the Canonical PartyManager

Use the workspace copy in:

`C:\Users\fishy\Develop\FFXI Addons\PartyManager`

Treat it as the source of truth, not the in-game client copy in Windower. The client copy is useful as a reference, but it is already divergent and should not become the baseline for new work.

---

## 2. Resolve the Level Sync Question First

Before adding anything new on top of PartyManager, verify the current level sync behavior in `PartyManager.lua`.

Focus on:
- whether sync-off is being issued when intended
- whether the addon waits the full cooldown before re-syncing
- whether the current state machine can re-enter sync cleanly after a party change
- whether the target sync mode is still correct for all join paths

If there is a bug here, fix it now while the scope is still isolated.

---

## 3. Stabilize Party Lifecycle Flow

Make sure these paths are clean and predictable:

- invite sent
- invite accepted
- invite timed out
- member left
- party full
- trust summon start and completion
- sync request and sync clear

The goal is not to redesign the state machine, only to make its transitions reliable and easy to trace.

---

## 4. Keep the Feature Boundary Tight

The current PartyManager should continue to own only:
- invite and party coordination
- level sync intent
- trust summon timing
- local party state

Do not add telemetry or downstream-consumer concerns into PartyManager.

That means no new work for:
- death tracking
- disconnect tracking
- job point milestones
- exemplar-per-hour math
- Discord formatting

---

## 5. Reconcile Local Drift

The workspace copy currently contains the broader experimental work:
- healer/DPS caps
- pessimistic mode
- composition validation
- dynamic trust selection work

Before treating PartyManager as stable, decide whether those changes are:
- part of the final PartyManager baseline
- worth keeping but needing more validation
- or temporary experiments that should stay out of the canonical flow

Do not let the client copy define that decision.

---

## 6. Freeze the Contract

Once PartyManager behaves the way you want, freeze the output contract it exposes to anything that reads it.

At minimum, keep the following stable:
- file path
- `last_updated`
- `zone`
- `current_state`
- `sync_mode`
- `sync_target`
- `party_count`
- `last_pc_count`
- `event_trigger`

The `partymanager_state.json` contract note should become the reference point.

---

## 7. Validate Before Moving On

Before moving on to any new work, test PartyManager in-game for:
- invite acceptance
- timeout handling
- sync transition behavior
- trust summon timing after sync changes
- player leaving and reconfiguration
- state stability after repeated party cycles

If any of those are shaky, fix them before building anything else on top of PartyManager.

---

## 8. Ready State

PartyManager is ready for future work when:

- its state machine is stable
- its sync behavior is trusted
- its outputs are predictable
- its contract is frozen
- the workspace copy is the only active baseline

At that point, PartyManager can be treated as stable and future work can build on it without needing to guess at its internals.
