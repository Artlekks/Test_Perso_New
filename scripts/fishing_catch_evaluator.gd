extends RefCounted
class_name FishingCatchEvaluator

const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)


static func create_snapshot(
	fish: FishInstance,
	catch_context: Dictionary = {}
) -> Dictionary:
	if fish == null or fish.species == null:
		return {}

	return create_snapshot_from_values(
		fish.species,
		fish.size,
		catch_context
	)


static func create_snapshot_from_values(
	data: FishData,
	size: float,
	catch_context: Dictionary = {}
) -> Dictionary:
	if data == null:
		return {}

	var species_id: String = (
		data.get_stable_species_id()
		.strip_edges()
		.to_lower()
	)

	if species_id.is_empty():
		return {}

	var score: Dictionary = CatchScoring.evaluate(
		data,
		size
	)

	if score.is_empty():
		return {}

	var context: Dictionary = sanitize_context(
		catch_context
	)

	return {
		"species_id": species_id,
		"fish_name": data.fish_name,
		"journal_name": data.get_journal_name(),
		"size": float(score.get("size", 0.0)),
		"is_king": bool(score.get("is_king", false)),
		"size_band": str(score.get("size_band", &"normal")),
		"score_tier": int(score.get("score_tier", 0)),
		"score_tier_count": int(score.get("score_tier_count", 10)),
		"points": int(score.get("points", 0)),
		"max_points": int(score.get("max_points", 0)),
		"points_remaining": int(score.get("points_remaining", 0)),
		"average_size": float(score.get("average_size", 0.0)),
		"king_size": float(score.get("king_size", 0.0)),
		"size_ratio_to_king": float(
			score.get("size_ratio_to_king", 0.0)
		),
		"score_completion_ratio": float(
			score.get("score_completion_ratio", 0.0)
		),
		"spot_id": str(context.get("spot_id", "")),
		"spot_name": str(context.get("spot_name", "")),
		"lure_id": str(context.get("lure_id", "")),
		"lure_name": str(context.get("lure_name", "")),
		"catch_context": context.duplicate(true),
	}


static func sanitize_context(
	catch_context: Dictionary
) -> Dictionary:
	return {
		"spot_id": str(
			catch_context.get("spot_id", "")
		).strip_edges(),
		"spot_name": str(
			catch_context.get("spot_name", "")
		).strip_edges(),
		"lure_id": str(
			catch_context.get("lure_id", "")
		).strip_edges(),
		"lure_name": str(
			catch_context.get("lure_name", "")
		).strip_edges(),
	}
