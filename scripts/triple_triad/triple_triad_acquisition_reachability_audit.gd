extends RefCounted
class_name TripleTriadAcquisitionReachabilityAudit

const ROUTE_BY_SOURCE_TYPE := {
	"starter_bundle": "starter_bundle",
	"opponent_win": "match_resolution",
	"fishing_salvage": "fishing_salvage_bridge",
	"treasure_cache": "world_gateway",
	"quest_reward": "quest_reward_adapter",
	"tournament_reward": "competition_world_gateway",
	"card_maker": "fishing_card_maker_service",
}

const DIRECT_CLAIM_TYPES := [
	"fishing_salvage",
	"treasure_cache",
	"quest_reward",
	"tournament_reward",
	"card_maker",
]


static func audit(world_catalog: RefCounted, card_catalog: Resource) -> Dictionary:
	var errors := PackedStringArray()
	var source_type_counts: Dictionary = {}
	var route_counts: Dictionary = {}
	var covered_cards: Dictionary = {}
	var sources = world_catalog.get_all_source_snapshots()

	for raw_source in sources:
		if not (raw_source is Dictionary):
			errors.append("World acquisition catalog returned a non-Dictionary source.")
			continue
		var source: Dictionary = raw_source
		var source_type: String = str(source.get("source_type", ""))
		var source_id: String = str(source.get("source_id", ""))
		if not ROUTE_BY_SOURCE_TYPE.has(source_type):
			errors.append(
				"Unsupported acquisition source route: %s:%s"
				% [source_type, source_id]
			)
			continue

		var route: String = str(ROUTE_BY_SOURCE_TYPE[source_type])
		source_type_counts[source_type] = int(source_type_counts.get(source_type, 0)) + 1
		route_counts[route] = int(route_counts.get(route, 0)) + 1

		var expected_direct: bool = DIRECT_CLAIM_TYPES.has(source_type)
		var actual_direct: bool = bool(
			world_catalog.can_direct_claim_source(StringName(source_type))
		)
		if expected_direct != actual_direct:
			errors.append(
				"Direct-claim ownership mismatch for %s:%s"
				% [source_type, source_id]
			)

		var ids = source.get("card_ids", PackedStringArray())
		if not (ids is PackedStringArray or ids is Array) or ids.is_empty():
			errors.append(
				"Acquisition source %s:%s has no cards."
				% [source_type, source_id]
			)
			continue
		if source_type == "card_maker" and ids.size() != 1:
			errors.append(
				"Card Maker source %s must resolve to exactly one card."
				% source_id
			)
		for raw_card_id in ids:
			covered_cards[str(raw_card_id)] = true

	var catalog_card_ids: Dictionary = {}
	if card_catalog != null and card_catalog.has_method("get_total_source_count"):
		for index in range(int(card_catalog.call("get_total_source_count"))):
			var card = card_catalog.call("get_card", index)
			if card != null:
				catalog_card_ids[String(card.card_id)] = true
	else:
		errors.append("Card catalog does not expose the canonical card iteration API.")

	for card_id in catalog_card_ids.keys():
		if not covered_cards.has(card_id):
			errors.append("Card %s has no gameplay delivery route." % card_id)

	for card_id in covered_cards.keys():
		if not catalog_card_ids.has(card_id):
			errors.append("Acquisition route references unknown card %s." % card_id)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"source_count": sources.size(),
		"source_type_count": source_type_counts.size(),
		"source_type_counts": source_type_counts,
		"route_counts": route_counts,
		"covered_card_count": covered_cards.size(),
		"catalog_card_count": catalog_card_ids.size(),
		"direct_claim_types": DIRECT_CLAIM_TYPES.duplicate(),
	}
