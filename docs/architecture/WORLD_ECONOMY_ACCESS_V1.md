# World Economy Access v1 — Contextual Merchant Access

## Inspection and source selection

Inspected the façade, economy menu, BeachMerchantNPC, shop and Manillo trade
catalogs/resources, canonical economy config, foundation/regression QA, simulator
and session bootstrap. Bootstrap already called `clear_access_context()`, not
`enable_vertical_slice_full_access()`; it remains unchanged. The façade itself
previously defaulted to full access; its initial state is now restricted too.

There is no dedicated authored Beach shop source. The current level already
assigned `shyde`, so the new deliberate Beach context preserves that selection.
It exposes four existing early tackle offers without modifying them:

| Offer ID | Shop source ID | Item | Current canonical live price |
| --- | --- | --- | --- |
| shyde_straight | shyde | Straight | 200z |
| shyde_baby_frog | shyde | Baby Frog | 250z |
| shyde_floater | shyde | Floater | 300z |
| shyde_wooden_rod | shyde | Wooden Rod | 500z |

**Trade source IDs: none. Availability dictionary: empty. Full catalog: false.**
The three basic lures and starter rod match the current vertical slice's fishing
equipment. No Lyp/Wyndia Manillo recipes, late shop sources, fabricated Beach
offers, copied historical runtime prices or hour-based unlocks were introduced.

## Architecture and lifecycle

```text
Merchant NPC.economy_context (MerchantEconomyContext Resource)
  → FishingEconomyMenu.open_merchant_menu(context, owner, mode)
  → context.apply_to(FishingEconomyAccess)
  → set_access_context(shop_ids, trade_shop_ids, availability, full_catalog_access)
  → existing menu entries and backend transactions
```

The Resource exports only authored policy: `shop_ids`, `trade_shop_ids`,
`availability`, `full_catalog_access`. It has no wallet, inventory, progression
or save API. The façade copies its arrays and availability dictionary. Future
Sarai/Shyde/Lyp/Wyndia/Chiqua/Faerie merchants assign another Resource, without
changing the economy backend. The resource is assigned in BeachMerchantNPC's
scene, so it works outside the current level too. Old instance-level shop array
overrides were removed from FishingTestScene_V2.

The menu validates its ability to open before applying a context, then applies
it before building entries. Failed opens cannot replace an active menu's access.
The menu tracks a weak reference to its owning merchant. NPC cancellation,
leaving range or scene exit can close only that NPC's own menu; an inactive NPC
cannot clear another merchant's or debug menu's context. Dialogue itself does
not apply access until Buy/Sell is actually routed. A deferred choice cannot
reopen a merchant after the player has left its range.

Closing or freeing the menu clears sources, availability and full access, then
restores the previous pause state. Freeing the owner closes its menu. Rebinding
the menu to another façade closes/clears the old context and disconnects the old
changed signal. Unscoped `open_menu/open_buy_menu/open_sell_menu` calls clear any
previous context rather than inheriting it. Changing access refreshes open menu
entries and cancels stale purchase confirmations.

## Full access and prices

`enable_vertical_slice_full_access()` remains available for explicit backend
QA/debug calls and exposes all **16 offers / 14 trades**. It now resets stale
availability grants through `set_access_context(..., {}, true)`. Full catalog
means all sources are reachable, not that authored availability gates are ignored.
To explicitly supply a tag grant in full mode, use a full-access context Resource
or `set_access_context(..., availability, true)`.

The menu has a separate deliberate `open_debug_full_catalog_menu()` entry point.
It enables full access only after validating the menu can open. Closing it clears
that temporary context. No automatic debug hotkey or full-access bootstrap was
introduced; normal Merchant interactions always apply their assigned policy.

Inspection found a display mismatch: purchase execution already used the
canonical config, while façade entry prices/detail text still read the historical
offer resource price. Entries now use `evaluate_purchase().unit_price_zenny`,
the same service resolution used for execution. For example, Straight shows
and spends **200z**, while its unchanged historical resource still records 20z.
No canonical price, authored offer, trade cost or economy service was edited.

## Files changed

Modified:

1. `scripts/fishing_economy_access.gd`
2. `scripts/fishing_economy_menu.gd`
3. `scripts/beach_merchant_npc.gd`
4. `actors/BeachMerchantNPC.tscn`
5. `actors/FishingTestScene_V2.tscn`

New:

6. `scripts/economy/merchant_economy_context.gd`
7. `data/economy/contexts/beach_merchant.tres`
8. `scripts/qa/world_economy_access_qa.gd`
9. `docs/architecture/WORLD_ECONOMY_ACCESS_V1.md`

Canonical config, offer/trade resources, save schemas, simulator, fishing,
crafting, Triple Triad and shadow implementations remain unchanged.

## QA actually run

Godot **4.7.2 stable**, headless. The new fixture uses actual façade/services,
the real menu and Merchant scene, but a MemoryInventory whose disk save method
returns success without writing a player save. It never bootstraps the live
session. Existing foundation tests and the three selected regression groups
run their original code/assertions. Orphan Nodes from those older groups are
freed by the runner.

```powershell
$godotExe = 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe'
$qaOutput = 'C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c'
& $godotExe --headless --path . --log-file "$qaOutput/world_economy_access_qa.log" --script res://scripts/qa/world_economy_access_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/economy_interaction_regression.log" --script res://scripts/qa/world_interaction_qa.gd | Out-String
git diff --check
```

Results:

- New World Economy Access QA: **45 checks, 0 failures**.
- Existing economy foundation: **13/13**.
- Existing regression groups `_test_trades`, `_test_economy_contract`,
  `_test_player_economy_access_and_save_integrity`: **208/208**.
- Existing First-10-Hours source/economy simulator: **24/24**.
- Existing world interaction QA: **93/93**.
- `git diff --check`: passed.

The new checks cover all nine requested categories: full access, restricted
shops/trades, disallowed transactions, tagged offer gating, changing contexts
refreshing actual menu entries, clearing/closing preventing inheritance, and
nonpersistent policy. Additional checks cover canonical price labels/deductions,
no mutation of offer prices, defensive copies, no tag leakage into full mode,
failed/overlapping opens, stale confirmations, owner/menu destruction, menu
rebinding, merchant cancellation/leaving and explicit debug ownership.
The entire general fishing regression harness was **not** run; only its three
economy-related groups were run. No rendered playthrough is claimed.

## Manual Godot checks

Run FishingTestScene_V2 and press K at the Beach Merchant. Choose Buy and verify
only Straight/Baby Frog/Floater/Wooden Rod with 200/250/300/500z prices (owned
unique equipment may be disabled). Buy a permitted item, switch to Sell, close
with I/Escape, then reopen; verify selection, confirmation and pause behavior.

In a test scene, assign a second merchant a Sarai context and alternate between
merchants; no Shyde Floater should appear at Sarai. Exercise dialogue cancellation,
menu close and scene transitions. For deliberate debug testing, invoke
`open_debug_full_catalog_menu()`, check all shop sources are visible, close it,
then reopen the Beach Merchant and confirm restriction returns. Tagged Faerie
offers should stay locked until their explicit availability flag is supplied.
Current economy UI remains Buy/Sell; this pass adds no Manillo trade UI.
