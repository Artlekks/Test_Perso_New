extends RefCounted
class_name EconomyProgressionSimulator
const EconomyConfigResource = preload(
	"res://data/economy/economy_foundation_v1.tres"
)
const ShopCatalogResource = preload(
	"res://data/bof4/shops/all_shops.tres"
)
const TradeCatalogResource = preload(
	"res://data/bof4/trades/all_trades.tres"
)
## Deterministic 0-12 hour economy/progression design simulator.
##
## This is a QA/design tool only. It never reads or writes save data and it does
## not change runtime balance. The defaults model the current design target:
##   0-1h  learn the loop
##   1-4h  connect fishing / gathering / cards
##   4-12h build specialization
##
## Prepared bait is intentionally modelled as a cross-system loop:
##   1 cheap/common fish + 2 gathered herb units -> 3 prepared bait portions.
## A baited catch shifts the expected catch mix toward better/bigger fish and
## improves discovery pace. BAIT_VALUE_BONUS models expected catch quality, not
## a literal +30% vendor price multiplier on an individual fish.
## The exact recipe/bonuses are assumptions for tuning, not shipped gameplay.

const STEP_HOURS: float = 0.25
const STARTING_ZENNY: float = 100.0
const STARTING_CARDS: float = 0.0
const STARTER_CASE_TARGET_CATCHES: float = 5.0
const STARTER_CASE_CARDS: float = 5.0
const STARTING_RODS: int = 1
const STARTING_LURES: int = 1

const BAIT_COOKING_UNLOCK_HOUR: float = 1.0
const CARD_MAKER_UNLOCK_HOUR: float = 1.5
const BAIT_FISH_PER_BATCH: float = 1.0
const BAIT_HERBS_PER_BATCH: float = 2.0
const BAIT_PORTIONS_PER_BATCH: float = 3.0
const BAIT_VALUE_BONUS: float = 0.30
const BAIT_DISCOVERY_BONUS: float = 0.25

const CHECKPOINT_HOURS := [0.25, 1.0, 4.0, 12.0]


func run_default_suite(print_to_output: bool = true) -> Dictionary:
	var profile_reports: Dictionary = {}
	for profile in _build_profiles():
		var profile_id: String = str(profile.get("id", "UNKNOWN"))
		profile_reports[profile_id] = _simulate_profile(profile)

	var source_truth: Dictionary = _audit_purchase_plan_sources()
	var checks: Array = _evaluate_suite(profile_reports)
	checks.append({
		"label": "First-10h acquisition plan resolves to authored economy sources",
		"passed": bool(source_truth.get("ok", false)),
		"value": (
			"YES"
			if bool(source_truth.get("ok", false))
			else "NO"
		),
		"target": "all planned buys/trades resolve exactly",
	})
	var passed: int = 0
	for check in checks:
		if bool(check.get("passed", false)):
			passed += 1

	var report := {
		"version": "0.5",
		"hours_simulated": 12.0,
		"step_hours": STEP_HOURS,
		"profiles": profile_reports,
		"checks": checks,
		"checks_passed": passed,
		"checks_total": checks.size(),
		"summary": "%d/%d economy checks healthy" % [passed, checks.size()],
		"source_truth": source_truth,
		"assumptions": _get_assumption_snapshot(),
	}

	if print_to_output:
		_print_report(report)
	return report


func simulate_profile(profile_id: StringName) -> Dictionary:
	var wanted := str(profile_id).strip_edges().to_upper()
	for profile in _build_profiles():
		if str(profile.get("id", "")).to_upper() == wanted:
			return _simulate_profile(profile)
	return {}


func get_profile_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for profile in _build_profiles():
		ids.append(str(profile.get("id", "")))
	return ids


func _simulate_profile(profile: Dictionary) -> Dictionary:
	var state := {
		"hour": 0.0,
		"zenny": STARTING_ZENNY,
		"zenny_earned": 0.0,
		"zenny_spent_gear": 0.0,
		"zenny_spent_cards": 0.0,
		"fish_caught": 0.0,
		"fish_sold": 0.0,
		"fish_reserved": 0.0,
		"fish_reserved_by_species": {},
		"fish_spent_trades": 0.0,
		"bait_fish_bank": 0.0,
		"card_fish_bank": 0.0,
		"herbs": 0.0,
		"bait_portions": 0.0,
		"bait_batches": 0.0,
		"baited_catches": 0.0,
		"unique_cards": STARTING_CARDS,
		"card_game_unlocked": false,
		"starter_case_discovered": false,
		"species_discovered": 0.0,
		"rods_owned": STARTING_RODS,
		"lures_owned": STARTING_LURES,
	}
	var purchased: Dictionary = {}
	var checkpoints: Dictionary = {}
	var purchase_plan: Array = _build_purchase_plan()
	var hour: float = 0.0

	while hour < 12.0 - 0.0001:
		var stage: Dictionary = _get_stage(hour)
		_simulate_step(state, profile, stage, purchased, purchase_plan, hour)
		hour = snappedf(hour + STEP_HOURS, 0.001)
		state["hour"] = hour

		for checkpoint_hour in CHECKPOINT_HOURS:
			if is_equal_approx(hour, float(checkpoint_hour)):
				checkpoints[_checkpoint_key(hour)] = _snapshot_state(state, purchased)

	return {
		"profile_id": str(profile.get("id", "UNKNOWN")),
		"display_name": str(profile.get("display_name", profile.get("id", "UNKNOWN"))),
		"description": str(profile.get("description", "")),
		"checkpoints": checkpoints,
		"final": _snapshot_state(state, purchased),
	}


func _simulate_step(
	state: Dictionary,
	profile: Dictionary,
	stage: Dictionary,
	purchased: Dictionary,
	purchase_plan: Array,
	hour: float
) -> void:
	var step_end: float = hour + STEP_HOURS
	var base_catches: float = (
		float(stage.get("catches_per_hour", 0.0))
		* float(profile.get("catch_multiplier", 1.0))
		* STEP_HOURS
	)

	# Prepared bait is consumed by catches already prepared for this step. New
	# bait cooked below becomes available on the next step.
	var bait_available: float = float(state.get("bait_portions", 0.0))
	var bait_used: float = minf(bait_available, base_catches)
	state["bait_portions"] = bait_available - bait_used
	state["baited_catches"] = float(state.get("baited_catches", 0.0)) + bait_used
	var bait_coverage: float = 0.0
	if base_catches > 0.0:
		bait_coverage = bait_used / base_catches

	# Gathering is intentionally independent from fishing so the simulator can
	# expose whether herbs become a meaningful bottleneck for prepared bait.
	state["herbs"] = (
		float(state.get("herbs", 0.0))
		+ float(stage.get("herbs_per_hour", 0.0))
		* float(profile.get("gather_multiplier", 1.0))
		* STEP_HOURS
	)

	state["fish_caught"] = float(state.get("fish_caught", 0.0)) + base_catches

	# Campaign-loop v1 begins from the real fresh-save state. Runtime onboarding
	# now exposes a visible salvage glint after roughly 3-5 catches and resolves
	# the Saltworn Card Case on the targeted follow-up catch. The simulator uses
	# five total catches as the representative midpoint for that discovery.
	if (
		not bool(state.get("card_game_unlocked", false))
		and float(state.get("fish_caught", 0.0)) >= STARTER_CASE_TARGET_CATCHES
	):
		state["card_game_unlocked"] = true
		state["starter_case_discovered"] = true
		state["unique_cards"] = (
			float(state.get("unique_cards", 0.0)) + STARTER_CASE_CARDS
		)

	var sell_share: float = float(profile.get("sell_share", 0.0))
	var bait_share: float = float(profile.get("bait_share", 0.0))
	var card_share: float = 0.0
	if (
		bool(state.get("card_game_unlocked", false))
		and step_end >= CARD_MAKER_UNLOCK_HOUR
	):
		card_share = float(profile.get("card_share", 0.0))

	# First-10-hours economy v1.1: fish trades now reserve the actual required
	# species before the profile decides what to sell, cook, craft into cards, or
	# keep. This lets the simulator prove acquisition feasibility instead of
	# treating every fish as an interchangeable trade token.
	var species_catches: Dictionary = _build_species_catch_batch(
		stage,
		base_catches
	)
	var targeted_trade_reserve: float = 0.0
	var discretionary_catches: float = base_catches
	if not species_catches.is_empty():
		targeted_trade_reserve = _reserve_trade_target_fish(
			state,
			purchased,
			purchase_plan,
			species_catches
		)
		discretionary_catches = _sum_species_amounts(species_catches)

	var sold_count: float = discretionary_catches * sell_share
	var bait_count: float = discretionary_catches * bait_share
	var card_count: float = discretionary_catches * card_share
	var reserve_share: float = maxf(
		1.0 - sell_share - bait_share - card_share,
		0.0
	)
	var general_reserved_count: float = discretionary_catches * reserve_share

	if not species_catches.is_empty():
		general_reserved_count = _reserve_discretionary_species(
			state,
			species_catches,
			reserve_share
		)

	state["fish_sold"] = float(state.get("fish_sold", 0.0)) + sold_count
	state["bait_fish_bank"] = float(state.get("bait_fish_bank", 0.0)) + bait_count
	state["card_fish_bank"] = float(state.get("card_fish_bank", 0.0)) + card_count
	state["fish_reserved"] = (
		float(state.get("fish_reserved", 0.0))
		+ targeted_trade_reserve
		+ general_reserved_count
	)

	var effective_value: float = float(stage.get("average_fish_value_zenny", 0.0))
	effective_value *= 1.0 + (BAIT_VALUE_BONUS * bait_coverage)
	var revenue: float = sold_count * effective_value
	state["zenny"] = float(state.get("zenny", 0.0)) + revenue
	state["zenny_earned"] = float(state.get("zenny_earned", 0.0)) + revenue

	# Cards from actual card play remain the backbone. Fishing contributes a
	# smaller discovery stream; the Card Maker is handled separately below.
	var card_activity: float = float(profile.get("card_play_multiplier", 1.0))
	var uniqueness: float = float(stage.get("card_unique_factor", 1.0))
	var passive_card_gain: float = 0.0
	if bool(state.get("card_game_unlocked", false)):
		passive_card_gain = (
			float(stage.get("npc_cards_per_hour", 0.0)) * card_activity
			+ float(stage.get("fishing_cards_per_hour", 0.0))
		) * uniqueness * STEP_HOURS
	state["unique_cards"] = float(state.get("unique_cards", 0.0)) + passive_card_gain

	var discovery_gain: float = (
		float(stage.get("species_discovery_per_hour", 0.0))
		* (1.0 + BAIT_DISCOVERY_BONUS * bait_coverage)
		* STEP_HOURS
	)
	state["species_discovered"] = minf(
		float(stage.get("max_species_pool", 0.0)),
		float(state.get("species_discovered", 0.0)) + discovery_gain
	)

	if step_end >= BAIT_COOKING_UNLOCK_HOUR:
		_cook_prepared_bait(state)

	if bool(profile.get("gear_first", true)):
		_attempt_due_purchases(state, profile, purchased, purchase_plan, step_end)
		_run_card_maker(state, profile, stage, step_end)
	else:
		_run_card_maker(state, profile, stage, step_end)
		_attempt_due_purchases(state, profile, purchased, purchase_plan, step_end)


func _cook_prepared_bait(state: Dictionary) -> void:
	var fish_bank: float = float(state.get("bait_fish_bank", 0.0))
	var herb_bank: float = float(state.get("herbs", 0.0))
	var batches: float = minf(
		fish_bank / BAIT_FISH_PER_BATCH,
		herb_bank / BAIT_HERBS_PER_BATCH
	)
	if batches <= 0.0:
		return

	state["bait_fish_bank"] = fish_bank - batches * BAIT_FISH_PER_BATCH
	state["herbs"] = herb_bank - batches * BAIT_HERBS_PER_BATCH
	state["bait_portions"] = (
		float(state.get("bait_portions", 0.0))
		+ batches * BAIT_PORTIONS_PER_BATCH
	)
	state["bait_batches"] = float(state.get("bait_batches", 0.0)) + batches


func _build_species_catch_batch(
	stage: Dictionary,
	catch_count: float
) -> Dictionary:
	var batch: Dictionary = {}
	if catch_count <= 0.0:
		return batch

	var species_mix: Dictionary = stage.get(
		"trade_species_mix",
		{}
	)
	if species_mix.is_empty():
		return batch

	var total_weight: float = 0.0
	for raw_species_id in species_mix.keys():
		total_weight += maxf(
			float(species_mix.get(raw_species_id, 0.0)),
			0.0
		)

	if total_weight <= 0.0:
		return batch

	for raw_species_id in species_mix.keys():
		var species_id: String = str(raw_species_id)
		var weight: float = maxf(
			float(species_mix.get(raw_species_id, 0.0)),
			0.0
		)
		if species_id.is_empty() or weight <= 0.0:
			continue
		batch[species_id] = catch_count * weight / total_weight

	return batch


func _sum_species_amounts(species_amounts: Dictionary) -> float:
	var total: float = 0.0
	for raw_species_id in species_amounts.keys():
		total += maxf(
			float(species_amounts.get(raw_species_id, 0.0)),
			0.0
		)
	return total


func _reserve_trade_target_fish(
	state: Dictionary,
	purchased: Dictionary,
	purchase_plan: Array,
	species_catches: Dictionary
) -> float:
	var bank: Dictionary = state.get(
		"fish_reserved_by_species",
		{}
	)
	var outstanding: Dictionary = {}

	for purchase in purchase_plan:
		var purchase_id: String = str(purchase.get("id", ""))
		if purchase_id.is_empty() or purchased.has(purchase_id):
			continue
		if str(purchase.get("acquisition", "buy")) != "fish_trade":
			continue

		var requirements: Dictionary = purchase.get(
			"fish_requirements",
			{}
		)
		for raw_species_id in requirements.keys():
			var species_id: String = str(raw_species_id)
			if species_id.is_empty():
				continue
			outstanding[species_id] = (
				float(outstanding.get(species_id, 0.0))
				+ maxf(
					float(requirements.get(raw_species_id, 0.0)),
					0.0
				)
			)

	var reserved_total: float = 0.0
	for raw_species_id in species_catches.keys():
		var species_id: String = str(raw_species_id)
		var available: float = maxf(
			float(species_catches.get(raw_species_id, 0.0)),
			0.0
		)
		var still_needed: float = maxf(
			float(outstanding.get(species_id, 0.0))
			- float(bank.get(species_id, 0.0)),
			0.0
		)
		var reserve_now: float = minf(available, still_needed)
		if reserve_now <= 0.0:
			continue

		species_catches[raw_species_id] = available - reserve_now
		bank[species_id] = float(bank.get(species_id, 0.0)) + reserve_now
		reserved_total += reserve_now

	state["fish_reserved_by_species"] = bank
	return reserved_total


func _reserve_discretionary_species(
	state: Dictionary,
	species_catches: Dictionary,
	reserve_share: float
) -> float:
	if reserve_share <= 0.0:
		return 0.0

	var bank: Dictionary = state.get(
		"fish_reserved_by_species",
		{}
	)
	var reserved_total: float = 0.0

	for raw_species_id in species_catches.keys():
		var species_id: String = str(raw_species_id)
		var reserve_now: float = (
			maxf(
				float(species_catches.get(raw_species_id, 0.0)),
				0.0
			)
			* reserve_share
		)
		if species_id.is_empty() or reserve_now <= 0.0:
			continue
		bank[species_id] = float(bank.get(species_id, 0.0)) + reserve_now
		reserved_total += reserve_now

	state["fish_reserved_by_species"] = bank
	return reserved_total


func _can_pay_fish_trade(
	state: Dictionary,
	requirements: Dictionary
) -> bool:
	if requirements.is_empty():
		return false

	var bank: Dictionary = state.get(
		"fish_reserved_by_species",
		{}
	)
	for raw_species_id in requirements.keys():
		var species_id: String = str(raw_species_id)
		var required: float = maxf(
			float(requirements.get(raw_species_id, 0.0)),
			0.0
		)
		if float(bank.get(species_id, 0.0)) + 0.0001 < required:
			return false

	return true


func _pay_fish_trade(
	state: Dictionary,
	requirements: Dictionary
) -> float:
	var bank: Dictionary = state.get(
		"fish_reserved_by_species",
		{}
	)
	var spent_total: float = 0.0

	for raw_species_id in requirements.keys():
		var species_id: String = str(raw_species_id)
		var required: float = maxf(
			float(requirements.get(raw_species_id, 0.0)),
			0.0
		)
		if required <= 0.0:
			continue
		bank[species_id] = maxf(
			float(bank.get(species_id, 0.0)) - required,
			0.0
		)
		spent_total += required

	state["fish_reserved_by_species"] = bank
	return spent_total


func _run_card_maker(
	state: Dictionary,
	profile: Dictionary,
	stage: Dictionary,
	step_end: float
) -> void:
	if step_end < CARD_MAKER_UNLOCK_HOUR:
		return

	var fee: float = float(stage.get("card_maker_fee_zenny", 0.0))
	if fee <= 0.0:
		return

	var card_bank: float = float(state.get("card_fish_bank", 0.0))
	if card_bank <= 0.0:
		return

	# The reserve prevents the simulator from making the Card Maker an automatic
	# wallet drain. Profiles can still intentionally prioritize cards over gear.
	var reserve: float = float(profile.get("card_cash_reserve", 0.0))
	var spendable: float = maxf(float(state.get("zenny", 0.0)) - reserve, 0.0)
	var craft_count: float = minf(card_bank, spendable / fee)
	if craft_count <= 0.0:
		return

	var cost: float = craft_count * fee
	state["card_fish_bank"] = card_bank - craft_count
	state["zenny"] = float(state.get("zenny", 0.0)) - cost
	state["zenny_spent_cards"] = float(state.get("zenny_spent_cards", 0.0)) + cost
	state["unique_cards"] = (
		float(state.get("unique_cards", 0.0))
		+ craft_count * float(stage.get("card_unique_factor", 1.0))
	)



func _audit_purchase_plan_sources() -> Dictionary:
	var errors := PackedStringArray()
	var sources: Array[Dictionary] = []

	for purchase in _build_purchase_plan():
		var purchase_id: String = str(purchase.get("id", ""))
		var source_type: String = str(purchase.get("source_type", ""))
		var source_id: StringName = StringName(
			str(purchase.get("source_id", ""))
		)
		var valid: bool = _purchase_source_is_valid(purchase)
		var source_snapshot := {
			"purchase_id": purchase_id,
			"source_type": source_type,
			"source_id": str(source_id),
			"valid": valid,
		}

		if source_type == "shop_offer":
			var offer = ShopCatalogResource.get_offer_by_id(source_id)
			if offer != null:
				source_snapshot["shop_id"] = str(offer.shop_id)
				source_snapshot["availability_tag"] = str(
					offer.availability_tag
				)

		elif source_type == "manillo_trade":
			var recipe = TradeCatalogResource.get_recipe_by_id(source_id)
			if recipe != null:
				source_snapshot["shop_id"] = str(recipe.shop_id)
				source_snapshot["fish_requirements"] = (
					recipe.get_cost_dictionary().duplicate(true)
				)

		sources.append(source_snapshot)

		if not valid:
			errors.append(
				"%s -> %s:%s does not match the planned acquisition"
				% [
					purchase_id,
					source_type,
					str(source_id),
				]
			)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"sources": sources,
	}


func _purchase_source_is_valid(purchase: Dictionary) -> bool:
	var source_type: String = str(
		purchase.get(
			"source_type",
			""
		)
	)
	var source_id := StringName(
		str(
			purchase.get(
				"source_id",
				""
			)
		)
	)
	var item_id := StringName(
		str(
			purchase.get(
				"item_id",
				purchase.get(
					"id",
					""
				)
			)
		)
	)
	var kind: String = str(purchase.get("kind", ""))
	var acquisition: String = str(
		purchase.get(
			"acquisition",
			"buy"
		)
	)

	if source_id == &"" or item_id == &"":
		return false

	match source_type:
		"shop_offer":
			if acquisition != "buy":
				return false
			var offer = ShopCatalogResource.get_offer_by_id(source_id)
			if offer == null or offer.item_id != item_id:
				return false
			var expected_item_type: int = 1 if kind == "rod" else 0
			return int(offer.item_type) == expected_item_type

		"manillo_trade":
			if acquisition != "fish_trade":
				return false
			var recipe = TradeCatalogResource.get_recipe_by_id(source_id)
			if recipe == null or recipe.reward_id != item_id:
				return false
			var requirements: Dictionary = purchase.get(
				"fish_requirements",
				{}
			)
			return _fish_requirements_match(
				requirements,
				recipe.get_cost_dictionary()
			)

		_:
			return false


func _fish_requirements_match(
	planned: Dictionary,
	authored: Dictionary
) -> bool:
	if planned.size() != authored.size():
		return false

	for raw_species_id in planned.keys():
		var species_id: String = str(raw_species_id)
		if not authored.has(raw_species_id) and not authored.has(species_id):
			return false

		var authored_count: int = int(
			authored.get(
				raw_species_id,
				authored.get(
					species_id,
					-1
				)
			)
		)
		if authored_count != int(planned.get(raw_species_id, 0)):
			return false

	return true


func _attempt_due_purchases(
	state: Dictionary,
	profile: Dictionary,
	purchased: Dictionary,
	purchase_plan: Array,
	step_end: float
) -> void:
	var floor_zenny: float = float(
		profile.get(
			"gear_cash_floor",
			0.0
		)
	)

	for purchase in purchase_plan:
		var purchase_id: String = str(
			purchase.get(
				"id",
				""
			)
		)

		if (
			purchase_id.is_empty()
			or purchased.has(
				purchase_id
			)
		):
			continue

		if (
			step_end + 0.0001
			< float(
				purchase.get(
					"hour",
					0.0
				)
			)
		):
			continue

		if not _purchase_source_is_valid(purchase):
			continue

		var acquisition: String = str(
			purchase.get(
				"acquisition",
				"buy"
			)
		)

		match acquisition:
			"fish_trade":
				var requirements: Dictionary = purchase.get(
					"fish_requirements",
					{}
				)
				if not _can_pay_fish_trade(
					state,
					requirements
				):
					continue

				var fish_cost: float = _pay_fish_trade(
					state,
					requirements
				)
				state["fish_reserved"] = maxf(
					float(state.get("fish_reserved", 0.0)) - fish_cost,
					0.0
				)
				state["fish_spent_trades"] = (
					float(state.get("fish_spent_trades", 0.0))
					+ fish_cost
				)

			_:
				var cost: float = (
					_resolve_purchase_zenny_cost(
						purchase
					)
				)

				if (
					float(
						state.get(
							"zenny",
							0.0
						)
					)
					< cost + floor_zenny
				):
					continue

				state["zenny"] = (
					float(
						state.get(
							"zenny",
							0.0
						)
					)
					- cost
				)

				state["zenny_spent_gear"] = (
					float(
						state.get(
							"zenny_spent_gear",
							0.0
						)
					)
					+ cost
				)

		purchased[purchase_id] = true

		match str(
			purchase.get(
				"kind",
				""
			)
		):
			"rod":
				state["rods_owned"] = (
					int(
						state.get(
							"rods_owned",
							0
						)
					)
					+ int(
						purchase.get(
							"count",
							1
						)
					)
				)

			"lure":
				state["lures_owned"] = (
					int(
						state.get(
							"lures_owned",
							0
						)
					)
					+ int(
						purchase.get(
							"count",
							1
						)
					)
				)


func _resolve_purchase_zenny_cost(
	purchase: Dictionary
) -> float:
	if str(
		purchase.get(
			"acquisition",
			"buy"
		)
	) != "buy":
		return 0.0

	var item_id := StringName(
		str(
			purchase.get(
				"item_id",
				purchase.get(
					"id",
					""
				)
			)
		)
	)

	var fallback: int = maxi(
		0,
		int(
			purchase.get(
				"fallback_cost_zenny",
				0
			)
		)
	)

	match str(
		purchase.get(
			"kind",
			""
		)
	):
		"rod":
			return float(
				EconomyConfigResource.get_rod_buy_price(
					item_id,
					fallback
				)
			)

		"lure":
			return float(
				EconomyConfigResource.get_lure_buy_price(
					item_id,
					fallback
				)
			)

		_:
			return float(
				fallback
			)

func _snapshot_state(state: Dictionary, purchased: Dictionary) -> Dictionary:
	var purchased_ids: Array = purchased.keys()
	purchased_ids.sort()
	var species_bank: Dictionary = state.get(
		"fish_reserved_by_species",
		{}
	)
	return {
		"hour": float(state.get("hour", 0.0)),
		"zenny": roundi(float(state.get("zenny", 0.0))),
		"zenny_earned": roundi(float(state.get("zenny_earned", 0.0))),
		"zenny_spent_gear": roundi(float(state.get("zenny_spent_gear", 0.0))),
		"zenny_spent_cards": roundi(float(state.get("zenny_spent_cards", 0.0))),
		"fish_caught": roundi(
			float(
				state.get(
					"fish_caught",
					0.0
				)
			)
		),

		"fish_sold": roundi(
			float(
				state.get(
					"fish_sold",
					0.0
				)
			)
		),

		"fish_reserved": roundi(
			float(
				state.get(
					"fish_reserved",
					0.0
				)
			)
		),

		"fish_spent_trades": roundi(
			float(
				state.get(
					"fish_spent_trades",
					0.0
				)
			)
		),
		"fish_reserved_by_species": species_bank.duplicate(true),
		"herbs_remaining": roundi(float(state.get("herbs", 0.0))),
		"bait_batches": roundi(float(state.get("bait_batches", 0.0))),
		"bait_portions_remaining": roundi(float(state.get("bait_portions", 0.0))),
		"baited_catches": roundi(float(state.get("baited_catches", 0.0))),
		"unique_cards": roundi(float(state.get("unique_cards", 0.0))),
		"card_game_unlocked": bool(state.get("card_game_unlocked", false)),
		"starter_case_discovered": bool(state.get("starter_case_discovered", false)),
		"species_discovered": roundi(float(state.get("species_discovered", 0.0))),
		"rods_owned": int(state.get("rods_owned", 0)),
		"lures_owned": int(state.get("lures_owned", 0)),
		"purchases": purchased_ids,
	}


func _evaluate_suite(profile_reports: Dictionary) -> Array:
	var checks: Array = []
	var balanced_15m := _checkpoint(profile_reports, "BALANCED", 0.25)
	var balanced_1 := _checkpoint(profile_reports, "BALANCED", 1.0)
	var balanced_4 := _checkpoint(profile_reports, "BALANCED", 4.0)
	var balanced_12 := _checkpoint(profile_reports, "BALANCED", 12.0)
	var sell_4 := _checkpoint(profile_reports, "SELL_HEAVY", 4.0)
	var sell_12 := _checkpoint(profile_reports, "SELL_HEAVY", 12.0)
	var crafter_4 := _checkpoint(profile_reports, "CRAFTER", 4.0)
	var crafter_12 := _checkpoint(profile_reports, "CRAFTER", 12.0)
	var card_12 := _checkpoint(profile_reports, "CARD_HEAVY", 12.0)

	_add_bool_check(checks, "Fresh trip unlocks card game", balanced_15m, "card_game_unlocked", true)
	_add_bool_check(checks, "Fresh trip discovers starter case", balanced_15m, "starter_case_discovered", true)
	_add_exact_check(checks, "Fresh trip grants five starter cards", balanced_15m, "unique_cards", 5)
	_add_range_check(checks, "Balanced H1 species", balanced_1, "species_discovered", 4, 6)
	_add_range_check(checks, "Balanced H1 cards", balanced_1, "unique_cards", 7, 10)
	_add_purchase_check(
		checks,
		"Balanced H1 reaches first alternate lure",
		balanced_1,
		"baby_frog"
	)

	_add_purchase_check(
		checks,
		"Balanced H4 reaches Bamboo Rod",
		balanced_4,
		"bamboo_rod"
	)

	_add_purchase_check(
		checks,
		"Balanced H4 can use Tail fish trade",
		balanced_4,
		"tail"
	)

	_add_purchase_check(
		checks,
		"Balanced H4 can use Crab fish trade",
		balanced_4,
		"crab"
	)

	_add_purchase_check(
		checks,
		"Balanced H12 reaches Angling Rod",
		balanced_12,
		"angling_rod"
	)
	_add_min_check(checks, "Balanced H4 first rod upgrade", balanced_4, "rods_owned", 2)
	_add_min_check(checks, "Balanced H4 useful lure set", balanced_4, "lures_owned", 4)
	_add_range_check(checks, "Balanced H4 card collection", balanced_4, "unique_cards", 15, 22)
	_add_range_check(checks, "Balanced H12 species", balanced_12, "species_discovered", 15, 25)
	_add_range_check(checks, "Balanced H12 cards", balanced_12, "unique_cards", 30, 40)
	_add_max_check(checks, "Sell-heavy H4 cash does not explode", sell_4, "zenny", 5000)
	_add_max_check(checks, "Sell-heavy H12 cash remains a useful economy", sell_12, "zenny", 15500)
	_add_max_check(checks, "Balanced H12 cash remains spendable, not absurd", balanced_12, "zenny", 8000)
	_add_min_check(checks, "Crafter H4 can still afford progression rod", crafter_4, "rods_owned", 2)
	_add_min_check(checks, "Crafter H4 keeps a small cash buffer after progression", crafter_4, "zenny", 75)
	_add_min_check(checks, "Crafter actually uses cooked bait", crafter_12, "bait_batches", 20)
	_add_min_check(checks, "Card-heavy still reaches first rod upgrade", card_12, "rods_owned", 2)
	_add_min_check(checks, "Card-heavy collection beats balanced", card_12, "unique_cards", int(balanced_12.get("unique_cards", 0)) + 1)

	return checks

func _add_purchase_check(
	checks: Array,
	label: String,
	snapshot: Dictionary,
	purchase_id: String
) -> void:
	var raw_purchases = snapshot.get(
		"purchases",
		[]
	)

	var purchased: bool = false

	if raw_purchases is Array:
		purchased = (
			raw_purchases as Array
		).has(
			purchase_id
		)

	checks.append(
		{
			"label": label,
			"passed": purchased,
			"value": (
				"YES"
				if purchased
				else "NO"
			),
			"target": purchase_id,
		}
	)
	
func _add_exact_check(
	checks: Array,
	label: String,
	snapshot: Dictionary,
	field: String,
	expected: int
) -> void:
	var value: int = int(snapshot.get(field, 0))
	checks.append({
		"label": label,
		"passed": value == expected,
		"value": value,
		"target": "= %d" % expected,
	})


func _add_bool_check(
	checks: Array,
	label: String,
	snapshot: Dictionary,
	field: String,
	expected: bool
) -> void:
	var value: bool = bool(snapshot.get(field, false))
	checks.append({
		"label": label,
		"passed": value == expected,
		"value": ("YES" if value else "NO"),
		"target": ("YES" if expected else "NO"),
	})


func _add_range_check(
	checks: Array,
	label: String,
	snapshot: Dictionary,
	field: String,
	minimum: int,
	maximum: int
) -> void:
	var value: int = int(snapshot.get(field, 0))
	checks.append({
		"label": label,
		"passed": value >= minimum and value <= maximum,
		"value": value,
		"target": "%d-%d" % [minimum, maximum],
	})


func _add_min_check(
	checks: Array,
	label: String,
	snapshot: Dictionary,
	field: String,
	minimum: int
) -> void:
	var value: int = int(snapshot.get(field, 0))
	checks.append({
		"label": label,
		"passed": value >= minimum,
		"value": value,
		"target": ">= %d" % minimum,
	})


func _add_max_check(
	checks: Array,
	label: String,
	snapshot: Dictionary,
	field: String,
	maximum: int
) -> void:
	var value: int = int(snapshot.get(field, 0))
	checks.append({
		"label": label,
		"passed": value <= maximum,
		"value": value,
		"target": "<= %d" % maximum,
	})


func _checkpoint(profile_reports: Dictionary, profile_id: String, hour: float) -> Dictionary:
	var profile: Dictionary = profile_reports.get(profile_id, {})
	var checkpoints: Dictionary = profile.get("checkpoints", {})
	return checkpoints.get(_checkpoint_key(hour), {})


func _checkpoint_key(hour: float) -> String:
	if hour < 1.0:
		return "M%d" % roundi(hour * 60.0)
	return "H%d" % roundi(hour)


func _get_stage(hour: float) -> Dictionary:
	var stages: Array = _build_stages()
	for stage in stages:
		if hour >= float(stage.get("start_hour", 0.0)) and hour < float(stage.get("end_hour", 0.0)):
			return stage
	return stages[stages.size() - 1]


func _build_stages() -> Array:
	return [
		{
			"id": "LEARN",
			"start_hour": 0.0,
			"end_hour": 1.0,
			"catches_per_hour": 20.0,
			"average_fish_value_zenny": 45.0,
			"herbs_per_hour": 2.0,
			"species_discovery_per_hour": 4.5,
			"max_species_pool": 6.0,
			"npc_cards_per_hour": 2.0,
			"fishing_cards_per_hour": 0.3,
			"card_maker_fee_zenny": 0.0,
			"card_unique_factor": 0.85,
			"trade_species_mix": {
				"flying_fish": 0.18,
				"piranha": 0.18,
				"blue_gill": 0.18,
				"sea_bream": 0.18,
				"jellyfish": 0.28,
			},
		},
		{
			"id": "CONNECT",
			"start_hour": 1.0,
			"end_hour": 4.0,
			"catches_per_hour": 12.0,
			"average_fish_value_zenny": 90.0,
			"herbs_per_hour": 6.0,
			"species_discovery_per_hour": 2.2,
			"max_species_pool": 12.0,
			"npc_cards_per_hour": 2.0,
			"fishing_cards_per_hour": 0.35,
			"card_maker_fee_zenny": 100.0,
			"card_unique_factor": 0.75,
			"trade_species_mix": {
				"flying_fish": 0.14,
				"black_bass": 0.12,
				"blue_gill": 0.12,
				"piranha": 0.12,
				"sea_bream": 0.12,
				"martian_squid": 0.12,
				"trout": 0.13,
				"browntail": 0.13,
			},
		},
		{
			"id": "SPECIALIZE",
			"start_hour": 4.0,
			"end_hour": 12.0,
			"catches_per_hour": 13.0,
			"average_fish_value_zenny": 180.0,
			"herbs_per_hour": 7.0,
			"species_discovery_per_hour": 1.3,
			"max_species_pool": 25.0,
			"npc_cards_per_hour": 1.5,
			"fishing_cards_per_hour": 0.45,
			"card_maker_fee_zenny": 180.0,
			"card_unique_factor": 0.60,
			"trade_species_mix": {
				"salmon": 0.08,
				"dorado": 0.08,
				"martian_squid": 0.08,
				"black_bass": 0.10,
				"blue_gill": 0.10,
				"piranha": 0.10,
				"flying_fish": 0.08,
				"sea_bream": 0.08,
				"blowfish": 0.08,
				"trout": 0.08,
				"browntail": 0.07,
				"sea_bass": 0.07,
			},
		},
	]


func _build_profiles() -> Array:
	return [
		{
			"id": "BALANCED",
			"display_name": "Balanced player",
			"description": "Uses every system without optimizing one at the expense of the others.",
			"sell_share": 0.52,
			"bait_share": 0.14,
			"card_share": 0.12,
			"catch_multiplier": 1.0,
			"gather_multiplier": 1.0,
			"card_play_multiplier": 1.0,
			"card_cash_reserve": 250.0,
			"gear_cash_floor": 75.0,
			"gear_first": true,
		},
		{
			"id": "SELL_HEAVY",
			"display_name": "Sell-heavy fisherman",
			"description": "Turns most catches into Zenny and minimally engages with side systems.",
			"sell_share": 0.82,
			"bait_share": 0.05,
			"card_share": 0.03,
			"catch_multiplier": 1.0,
			"gather_multiplier": 0.60,
			"card_play_multiplier": 0.65,
			"card_cash_reserve": 100.0,
			"gear_cash_floor": 75.0,
			"gear_first": true,
		},
		{
			"id": "CRAFTER",
			"display_name": "Crafter / gatherer",
			"description": "Uses many common fish and herbs for prepared bait and crafting.",
			"sell_share": 0.38,
			"bait_share": 0.30,
			"card_share": 0.07,
			"catch_multiplier": 1.0,
			"gather_multiplier": 1.50,
			"card_play_multiplier": 0.80,
			"card_cash_reserve": 300.0,
			"gear_cash_floor": 75.0,
			"gear_first": true,
		},
		{
			"id": "CARD_HEAVY",
			"display_name": "Card-heavy player",
			"description": "Prioritizes card play and the Card Maker while still expecting viable fishing progression.",
			"sell_share": 0.40,
			"bait_share": 0.08,
			"card_share": 0.32,
			"catch_multiplier": 1.0,
			"gather_multiplier": 0.80,
			"card_play_multiplier": 1.60,
			"card_cash_reserve": 1050.0,
			"gear_cash_floor": 50.0,
			"gear_first": false,
		},
		{
			"id": "EFFICIENT",
			"display_name": "Efficient experienced player",
			"description": "Catches faster, gathers efficiently, and engages strongly with every system.",
			"sell_share": 0.60,
			"bait_share": 0.15,
			"card_share": 0.15,
			"catch_multiplier": 1.15,
			"gather_multiplier": 1.15,
			"card_play_multiplier": 1.10,
			"card_cash_reserve": 300.0,
			"gear_cash_floor": 100.0,
			"gear_first": true,
		},
	]


func _build_purchase_plan() -> Array:
	return [
		{
			"id": "baby_frog",
			"item_id": "baby_frog",
			"display_name": "Baby Frog",
			"hour": 0.75,
			"kind": "lure",
			"count": 1,
			"acquisition": "buy",
			"source_type": "shop_offer",
			"source_id": "sarai_baby_frog",
		},
		{
			"id": "bamboo_rod",
			"item_id": "bamboo_rod",
			"display_name": "Bamboo Rod",
			"hour": 2.25,
			"kind": "rod",
			"count": 1,
			"acquisition": "buy",
			"source_type": "shop_offer",
			"source_id": "faerie_bamboo_rod",
		},
		{
			"id": "tail",
			"item_id": "tail",
			"display_name": "Tail",
			"hour": 3.0,
			"kind": "lure",
			"count": 1,
			"acquisition": "fish_trade",
			"source_type": "manillo_trade",
			"source_id": "wyndia_tail",
			"fish_requirements": {
				"flying_fish": 3,
			},
			"cost_note": "Flying Fish x3",
		},
		{
			"id": "crab",
			"item_id": "crab",
			"display_name": "Crab",
			"hour": 3.5,
			"kind": "lure",
			"count": 1,
			"acquisition": "fish_trade",
			"source_type": "manillo_trade",
			"source_id": "lyp_crab",
			"fish_requirements": {
				"black_bass": 1,
				"blue_gill": 1,
				"piranha": 1,
			},
			"cost_note": (
				"Black Bass x1 + "
				+ "Blue Gill x1 + "
				+ "Piranha x1"
			),
		},
		{
			"id": "floater",
			"item_id": "floater",
			"display_name": "Floater",
			"hour": 5.0,
			"kind": "lure",
			"count": 1,
			"acquisition": "buy",
			"source_type": "shop_offer",
			"source_id": "shyde_floater",
		},
		{
			"id": "popper",
			"item_id": "popper",
			"display_name": "Popper",
			"hour": 6.0,
			"kind": "lure",
			"count": 1,
			"acquisition": "buy",
			"source_type": "shop_offer",
			"source_id": "lyp_popper",
		},
		{
			"id": "angling_rod",
			"item_id": "angling_rod",
			"display_name": "Angling Rod",
			"hour": 7.0,
			"kind": "rod",
			"count": 1,
			"acquisition": "fish_trade",
			"source_type": "manillo_trade",
			"source_id": "lyp_angling_rod",
			"fish_requirements": {
				"salmon": 2,
				"dorado": 2,
				"martian_squid": 2,
			},
			"cost_note": (
				"Salmon x2 + "
				+ "Dorado x2 + "
				+ "Martian Squid x2"
			),
		},
		{
			"id": "silver_top",
			"item_id": "silver_top",
			"display_name": "Silver Top",
			"hour": 8.0,
			"kind": "lure",
			"count": 1,
			"acquisition": "buy",
			"source_type": "shop_offer",
			"source_id": "lyp_silver_top",
		},
		{
			"id": "hanger",
			"item_id": "hanger",
			"display_name": "Hanger",
			"hour": 9.0,
			"kind": "lure",
			"count": 1,
			"acquisition": "buy",
			"source_type": "shop_offer",
			"source_id": "chiqua_hanger",
		},
	]
	
func _get_assumption_snapshot() -> Dictionary:
	return {
		"starting_zenny": STARTING_ZENNY,
		"starting_cards": STARTING_CARDS,
		"starter_case_target_catches": STARTER_CASE_TARGET_CATCHES,
		"starter_case_cards": STARTER_CASE_CARDS,
		"bait_recipe": "1 common fish + 2 herbs -> 3 prepared bait portions",
		"bait_expected_catch_value_uplift": BAIT_VALUE_BONUS,
		"bait_discovery_bonus": BAIT_DISCOVERY_BONUS,
		"bait_cooking_unlock_hour": BAIT_COOKING_UNLOCK_HOUR,
		"card_maker_unlock_hour": CARD_MAKER_UNLOCK_HOUR,
		"fish_trade_model": "species-aware expected catch mix; trade targets reserve exact species before discretionary use",
		"acquisition_source_model": "every planned item resolves to an authored shop offer or Manillo recipe; world/NPC access timing remains a separate runtime wiring step",
		"stages": _build_stages(),
		"purchase_plan": _build_purchase_plan(),
	}


func _print_report(report: Dictionary) -> void:
	print("")
	print("=== ECONOMY / PROGRESSION SIMULATOR 0-12H ===")
	print("Fresh save: 0 cards / card game locked; after roughly 3-5 catches a visible water glint leads to the five-card Saltworn Card Case.")
	print("Prepared bait assumption: 1 common fish + 2 herbs -> 3 portions")
	print("Baited catches model a +30% expected quality/value mix, not a direct fish-price buff.")
	print("Profiles are deterministic design stress tests; no save/runtime state is touched.")

	var profiles: Dictionary = report.get("profiles", {})
	for profile_id in get_profile_ids():
		var profile: Dictionary = profiles.get(str(profile_id), {})
		print("")
		print("-- %s --" % str(profile.get("display_name", profile_id)))
		var checkpoints: Dictionary = profile.get("checkpoints", {})
		for checkpoint_key in ["M15", "H1", "H4", "H12"]:
			var snapshot: Dictionary = checkpoints.get(checkpoint_key, {})
			print(
				"%s | %dz | fish %d | species %d | cards %d | cards unlocked %s | rods %d | lures %d | bait batches %d" % [
					checkpoint_key,
					int(snapshot.get("zenny", 0)),
					int(snapshot.get("fish_caught", 0)),
					int(snapshot.get("species_discovered", 0)),
					int(snapshot.get("unique_cards", 0)),
					("YES" if bool(snapshot.get("card_game_unlocked", false)) else "NO"),
					int(snapshot.get("rods_owned", 0)),
					int(snapshot.get("lures_owned", 0)),
					int(snapshot.get("bait_batches", 0)),
				]
			)

	print("")
	print("-- DESIGN CHECKS --")
	for check in report.get("checks", []):
		print(
			"[%s] %s | value %s | target %s" % [
				("PASS" if bool(check.get("passed", false)) else "TUNE"),
				str(check.get("label", "")),
				str(check.get("value", "")),
				str(check.get("target", "")),
			]
		)
	print("SUMMARY: %s" % str(report.get("summary", "NO RESULT")))
	print("=== END ECONOMY SIMULATOR ===")
	print("")
