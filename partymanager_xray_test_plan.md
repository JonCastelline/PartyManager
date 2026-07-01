# PartyManager X-Ray Test Plan

**Purpose:** Run PartyManager in-game step by step and observe state transitions, chat output, and state persistence before any downstream addon depends on it.

**Use this file as a checklist.**  
Do one step at a time, confirm the expected result, then move to the next step.

---

## 0. Before You Start

- Use the workspace copy in `C:\Users\fishy\Develop\FFXI Addons\PartyManager`
- Make sure the addon is loaded from that copy, not the client copy
- Enable any debug output the addon already supports
- Have a small, controlled test party available if possible
- Keep `partymanager_state.json` visible if you are watching file output

**Pass criteria:** you can see PartyManager chat messages and know which copy is active.

---

## 1. Idle Baseline

1. Load PartyManager with no party actions in progress.
2. Confirm the addon starts in an idle-ready state.
3. Confirm the UI opens and the current settings match expectations.
4. Confirm no stale invite, sync, or trust state is left over from a prior run.

**Expected:** clean startup, no surprise actions, no stuck state.

---

## 2. Whitelist Invite Flow

1. Add one test character to the whitelist.
2. Have that character request an invite.
3. Confirm PartyManager recognizes the request.
4. Confirm the addon sends the invite response and enters the join-wait path.
5. Confirm the player joins successfully.
6. Confirm the addon exits the join flow and returns to normal operation.

**Expected:** invite is accepted cleanly, state advances once, and the join completes without delay or duplication.

---

## 3. Password Invite Flow

1. Set a password if that mode is part of your current flow.
2. Have a test character request an invite with the password path you use.
3. Confirm the request is handled the way PartyManager expects.
4. Confirm the invite proceeds only when the password condition is satisfied.

**Expected:** password handling works exactly as designed and does not bypass the invite gate.

---

## 4. Already-In-Party Rejection

1. Put a test character into the party.
2. Have that same character trigger the invite request again.
3. Confirm PartyManager detects the player is already in the party.
4. Confirm it sends the rejection message and does not re-enter invite flow.

**Expected:** clean refusal, no duplicate invite logic.

---

## 5. Full Party Rejection

1. Fill the party to its maximum allowed size.
2. Trigger a new invite request.
3. Confirm PartyManager rejects the request because the party is full.
4. Confirm the addon stays stable after the rejection.

**Expected:** no invite is sent, no partial state is left behind.

---

## 6. Invite Timeout

1. Trigger an invite request.
2. Do not accept it.
3. Wait for the full timeout window.
4. Confirm the addon times out exactly once.
5. Confirm it returns to idle or its next valid state without hanging.

**Expected:** timeout path completes cleanly and does not keep retrying forever.

---

## 7. Sync Mode: Sender

1. Set sync mode to `sender`.
2. Trigger a join cycle with a test character.
3. Confirm the sender becomes the sync target.
4. Confirm sync is requested at the correct time.
5. Confirm PartyManager does not move forward before the sync state is valid.

**Expected:** sender-based sync is consistent and predictable.

---

## 8. Sync Mode: Fixed

1. Set sync mode to `fixed`.
2. Set a known sync target.
3. Trigger a join cycle.
4. Confirm PartyManager targets the fixed character.
5. Confirm the fixed target remains stable until you change it.

**Expected:** fixed sync uses the configured target and no other.

---

## 9. Sync Mode: Lowest

1. Set sync mode to `lowest`.
2. Arrange a party with more than one human character at different levels.
3. Trigger a join cycle.
4. Confirm PartyManager picks the lowest valid level target.
5. Confirm it does not choose a trust or invalid target.

**Expected:** lowest-mode targeting is correct and repeatable.

---

## 10. Sync Mode: None

1. Set sync mode to `none`.
2. Trigger a join cycle.
3. Confirm PartyManager skips sync behavior.
4. Confirm it still continues the rest of the lifecycle correctly.

**Expected:** no sync actions are taken, but the rest of the flow remains stable.

---

## 11. Sync-Off / Cooldown Behavior

1. Force a situation where sync needs to be removed.
2. Confirm PartyManager sends the sync-off action.
3. Confirm it waits the full cooldown before trying to re-sync.
4. Confirm it does not skip the wait when the current sync is still active.
5. Confirm it does not get stuck waiting after the cooldown completes.

**Expected:** sync-off and re-sync timing are correct, and the addon does not race the cooldown.

---

## 12. Trust Summon Timing

1. Reach the point where trusts should be summoned.
2. Confirm PartyManager waits for any required cooldown or sync completion.
3. Confirm trusts begin summoning in the expected order.
4. Confirm the summon loop advances without skipping or repeating the same trust indefinitely.

**Expected:** trust timing is stable and does not overlap with sync changes.

---

## 13. Party Member Leaves

1. Start with a stable party.
2. Have one human member leave.
3. Confirm PartyManager detects the reduced party count.
4. Confirm it does not double-handle the departure.
5. Confirm it reconfigures once and only once.

**Expected:** one clean member-left transition and correct recovery.

---

## 14. Trust Leaves

1. Start with trusts active.
2. Remove a trust in the normal in-game way.
3. Confirm PartyManager recognizes the change.
4. Confirm it does not confuse a trust departure with a human departure.

**Expected:** trust removal is recognized, but human lifecycle logic remains separate.

---

## 15. Carry Limit Flow

1. Trigger a carry request.
2. Confirm the carry limit is enforced.
3. Confirm PartyManager rejects the request when the limit is reached.
4. Confirm the rejection message is correct.

**Expected:** carry cap logic behaves exactly as intended.

---

## 16. Experimental Role Logic

Run these one at a time:

1. Healer cap check
2. DPS cap check
3. Pessimistic mode on
4. Pessimistic mode off
5. Dynamic trust selection on
6. Dynamic trust selection off

For each one:
- confirm the UI change is saved
- confirm the addon message matches the toggle
- confirm the next invite behaves according to the selected mode

**Expected:** you can clearly tell which behaviors are final and which are still experimental.

---

## 17. Repeated Join / Leave Loop

1. Complete one full invite and join cycle.
2. Remove a member or reset the party.
3. Repeat the cycle at least three times.
4. Watch for stale state, duplicate messages, or bad transition order.

**Expected:** repeated cycles stay stable and do not drift.

---

## 18. Stress End State

After the repeated cycles:

1. Confirm the addon returns to idle cleanly.
2. Confirm no timer is still active unexpectedly.
3. Confirm no internal state appears stuck.
4. Confirm the current settings still match what you last chose.

**Expected:** PartyManager ends in a clean steady state, ready for the next test.

---

## 19. Final Pass / Ready Check

PartyManager is ready for the next phase when all of these are true:

- invite flow is clean
- timeout flow is clean
- sync flow is clean
- trust timing is clean
- leave handling is clean
- experimental toggles behave predictably
- repeated cycles do not drift
- the workspace copy is still the active baseline

If any step fails, fix that behavior before moving on.
