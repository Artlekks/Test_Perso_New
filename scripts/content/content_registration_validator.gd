extends RefCounted
## QA-only contract adapters. Never mutates catalogues, unlocks, scenes or saves.
const World = preload("res://scripts/world/world_location_service.gd")
const Route = preload("res://scripts/progression/economy_runtime_route.gd")
const Content = preload("res://data/bof4/catalogs/all_content.tres")
const Shops = preload("res://data/bof4/shops/all_shops.tres")
const Trades = preload("res://data/bof4/trades/all_trades.tres")
const Craft = preload("res://data/crafting/beach/beach_vertical_slice_catalog.tres")
const Maker = preload("res://data/economy/card_maker/card_maker_catalog_v1.tres")
const Cards = preload("res://data/triple_triad/card_catalog.tres")
const Opponents = preload("res://data/triple_triad/opponents/opponent_registry.tres")
const Bundles = preload("res://data/triple_triad/acquisition/acquisition_registry.tres")
const Masters = preload("res://data/bof4/mastery/all_techniques.tres")
const NPCs = preload("res://data/npc/catalog/npc_catalog.tres")
const Requests = preload("res://data/requests/request_catalog.tres")
const Rewards = preload("res://data/bof4/rewards/all_rewards.tres")
const BINDINGS = "res://data/world/provider_bindings_v1.json"
var checks := 0
var issues: Array[Dictionary] = []
var providers: Array[Dictionary] = []
var exceptions: Array[String] = []
var indexes: Dictionary = {}

func require(ok: bool, code: String, id: String, file: String, location := "", binding := "") -> void:
	checks += 1
	if not ok:
		issues.append({"code": code, "id": id, "file": file, "location": location, "binding": binding})

func field(object: Object, key: String, fallback = null):
	for property in object.get_property_list():
		if String(property.name) == key: return object.get(key)
	return fallback

func index(domain: String, entries: Array, id_field: String) -> Dictionary:
	var result := {}
	require(not entries.is_empty(), "empty_registry", domain, "registry")
	for entry in entries:
		require(entry != null, "null_entry", domain, "registry")
		if entry == null: continue
		var id := String(entry.get_stable_species_id()) if id_field == "species" else String(field(entry, id_field, ""))
		require(not id.is_empty() and not result.has(id), "empty_or_duplicate_id", id, entry.resource_path)
		result[id] = entry
	indexes[domain] = result
	return result

func ref(domain: String, id, file: String, location := "", binding := "") -> void:
	require(indexes[domain].has(String(id)), "invalid_" + domain + "_reference", String(id), file, location, binding)

func item(kind: int, id, file: String) -> void:
	ref("lure" if kind == 0 else "rod", id, file)

func validate_acquisition(targets: Array) -> void:
	var route := Route.new()
	var acquired := {}
	var pending := targets.duplicate(true)
	for pass_index in range(targets.size() + 1):
		var remaining: Array = []
		for target in pending:
			var source = indexes.offer.get(target.source_id) if target.source_type == "shop_offer" else indexes.trade.get(target.source_id)
			if source == null:
				remaining.append(target)
				continue
			var output := String(source.item_id) if target.source_type == "shop_offer" else String(source.reward_id)
			var kind: int = source.item_type if target.source_type == "shop_offer" else source.reward_type
			require(output == target.item_id and ("lure" if kind == 0 else "rod") == target.kind, "acquisition_output_mismatch", target.item_id, source.resource_path)
			var possible := route.available(target, acquired)
			if possible and target.source_type != "shop_offer":
				var available_species := {}
				for spot in route.reachable(acquired).spots:
					for spawn in spot.fish_population:
						if spawn.fish != null and spawn.get_base_bite_weight() > 0.0:
							available_species[spawn.fish.get_stable_species_id()] = true
				for species in source.required_fish_ids:
					possible = possible and available_species.has(species)
			if possible: acquired[target.item_id] = true
			else: remaining.append(target)
		if remaining.size() == pending.size():
			pending = remaining
			break
		pending = remaining
	for target in targets:
		require(acquired.has(target.item_id), "unreachable_required_acquisition", target.item_id, Route.PlanPath, "beach", target.source_id)

func validate() -> Dictionary:
	checks = 0
	issues.clear()
	providers.clear()
	exceptions.clear()
	indexes.clear()
	index("fish", Content.fish, "species")
	index("spot", Content.spots, "spot_id")
	index("lure", Content.tackle.lure_catalog.lures, "lure_id")
	index("rod", Content.tackle.rods, "rod_id")
	index("offer", Shops.offers, "offer_id")
	index("trade", Trades.recipes, "recipe_id")
	index("material", Craft.materials, "material_id")
	index("craft", Craft.recipes, "recipe_id")
	index("maker", Maker.recipes, "recipe_id")
	index("opponent", Opponents.opponents, "opponent_id")
	index("bundle", Bundles.bundles, "bundle_id")
	index("mastery", Masters.techniques, "technique_id")
	index("npc", NPCs.entries, "id")
	index("request", Requests.definitions, "request_id")
	index("reward", Rewards.rewards, "reward_key")
	index("location", World.LOCATION_REGISTRY.locations, "location_id")
	for reward in Rewards.rewards:
		require(reward.is_valid_definition(), "invalid_reward", String(reward.reward_key), reward.resource_path)
		if reward.reward_type in [0, 1]: item(reward.reward_type, reward.reward_item_id, reward.resource_path)
		if not reward.species_id.is_empty(): ref("fish", reward.species_id, reward.resource_path)
	for spot in Content.spots:
		require(not spot.fish_population.is_empty(), "empty_population", String(spot.spot_id), spot.resource_path)
		for spawn in spot.fish_population:
			require(spawn != null and spawn.fish != null, "null_population_fish", String(spot.spot_id), spot.resource_path)
			if spawn != null and spawn.fish != null:
				ref("fish", spawn.fish.get_stable_species_id(), spot.resource_path)
				require(indexes.fish.get(spawn.fish.get_stable_species_id()) == spawn.fish, "noncanonical_population_fish", String(spot.spot_id), spot.resource_path)
	for offer in Shops.offers:
		require(offer.is_valid_definition(), "invalid_offer", String(offer.offer_id), offer.resource_path)
		item(offer.item_type, offer.item_id, offer.resource_path)
	for trade in Trades.recipes:
		require(trade.is_valid_definition(), "invalid_trade", String(trade.recipe_id), trade.resource_path)
		item(trade.reward_type, trade.reward_id, trade.resource_path)
		for species in trade.required_fish_ids: ref("fish", species, trade.resource_path)
	for recipe in Craft.recipes:
		ref("lure", recipe.template_lure_id, recipe.resource_path)
		for slot in [recipe.body_material_ids, recipe.core_material_ids, recipe.accent_material_ids]:
			for material in slot: ref("material", material, recipe.resource_path)
	for recipe in Maker.recipes:
		var result: Dictionary = recipe.validate_recipe(Content, Cards)
		require(result.valid, "invalid_card_maker_recipe", String(recipe.recipe_id), recipe.resource_path, "", str(result.errors))
	for opponent in Opponents.opponents:
		var result: Dictionary = opponent.validate_profile(Cards)
		require(result.valid, "invalid_opponent", String(opponent.opponent_id), opponent.resource_path, "", str(result.errors))
		for required in opponent.unlock_after_opponent_ids: ref("opponent", required, opponent.resource_path)
	var bundle_result: Dictionary = Bundles.validate_registry(Cards)
	require(bundle_result.valid, "invalid_acquisition_bundles", "bundles", Bundles.resource_path, "", str(bundle_result.errors))
	require(Masters.is_valid_catalog(), "invalid_mastery_catalog", "mastery", Masters.resource_path)
	validate_dependency_graph("mastery", "prerequisite_ids")
	validate_dependency_graph("opponent", "unlock_after_opponent_ids")
	var acquisition = load("res://scripts/triple_triad/triple_triad_world_acquisition_catalog.gd").new()
	acquisition.initialize(Cards, Opponents, Bundles)
	var acquisition_result: Dictionary = acquisition.validate_map()
	require(acquisition_result.valid, "invalid_card_acquisition_map", "card_acquisition", acquisition.DATA_PATH, "", str(acquisition_result.errors))
	indexes.source = {}
	for source in acquisition.get_all_source_snapshots():
		var key: String = source.source_type + ":" + source.source_id
		require(not indexes.source.has(key), "duplicate_card_acquisition_source", key, acquisition.DATA_PATH)
		indexes.source[key] = source
	indexes.competition = {}
	var competition_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/triple_triad/competition/competition_catalog.json"))
	for competition in competition_data.competitions:
		var key: String = competition.competition_id
		require(not indexes.competition.has(key), "duplicate_competition", key, "res://data/triple_triad/competition/competition_catalog.json")
		indexes.competition[key] = competition
	var competitions = load("res://scripts/triple_triad/triple_triad_competition_catalog.gd").new()
	var competition_result: Dictionary = competitions.initialize(Opponents, acquisition)
	require(competition_result.valid, "invalid_competition_registry", "competition", competitions.DATA_PATH, "", str(competition_result.errors))
	for entry in NPCs.entries:
		require(entry.scene != null and entry.profile != null, "missing_npc_scene_profile", String(entry.id), entry.resource_path)
		if entry.scene == null or entry.profile == null: continue
		var actor: Node = entry.scene.instantiate()
		var presentation: Node = actor.get_node_or_null("GroundPresentation")
		require(presentation != null and field(presentation, "profile") == entry.profile and field(actor, "visual_profile") == entry.profile, "npc_scene_profile_mismatch", String(entry.id), entry.scene.resource_path)
		actor.free()
		var profile = entry.profile
		require(profile.sprite_frames != null, "missing_sprite_frames", String(entry.id), profile.resource_path)
		if profile.sprite_frames == null: continue
		require(profile.sprite_frames.has_animation(profile.default_animation), "missing_default_animation", String(entry.id), profile.resource_path)
		for pose in profile.directional_aliases:
			for direction in profile.directional_aliases[pose]:
				require(profile.sprite_frames.has_animation(profile.directional_aliases[pose][direction].animation), "invalid_directional_alias", String(entry.id), profile.resource_path, "", str(direction))
		for pose in profile.directional_animation_prefixes:
			var prefix: String = profile.directional_animation_prefixes[pose]
			require(Array(profile.sprite_frames.get_animation_names()).any(func(name): return String(name).begins_with(prefix)), "invalid_directional_prefix", String(entry.id), profile.resource_path, "", prefix)
	for request in Requests.definitions:
		var metadata: Dictionary = request.objective_metadata
		if metadata.has("material_id"): ref("material", metadata.material_id, request.resource_path)
		if metadata.has("species_id"): ref("fish", metadata.species_id, request.resource_path)
		if metadata.has("opponent_id"): ref("opponent", metadata.opponent_id, request.resource_path)
		ref("source", "quest_reward:" + String(request.reward_source_id), request.resource_path)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(BINDINGS))
	require(manifest is Dictionary and manifest.get("schema_version") == 1, "invalid_provider_manifest", "providers", BINDINGS)
	if manifest is Dictionary:
		validate_providers(manifest.get("providers", []))
		validate_world_content_coverage(manifest)
	validate_acquisition(Route.new().targets())
	validate_unregistered_resources()
	issues.sort_custom(func(a, b): return JSON.stringify(a) < JSON.stringify(b))
	return {"checks": checks, "issues": issues.duplicate(true), "providers": providers.duplicate(true), "exceptions": exceptions.duplicate()}

func validate_providers(bindings: Array) -> void:
	var by_location := {}
	var seen := {}
	for binding in bindings:
		var id: String = binding.get("provider_id", "")
		var location: String = binding.get("location_id", "")
		var path: String = binding.get("path", "")
		require(not id.is_empty() and not seen.has(id), "duplicate_or_empty_provider_id", id, BINDINGS, location, path)
		seen[id] = true
		ref("location", location, BINDINGS, location, path)
		require(not String(binding.get("provider_type", "")).is_empty(), "missing_provider_type", id, BINDINGS, location, path)
		if not by_location.has(location): by_location[location] = {}
		require(not by_location[location].has(path), "duplicate_provider_binding", id, BINDINGS, location, path)
		by_location[location][path] = binding
	for location in World.LOCATION_REGISTRY.locations:
		var loc := String(location.location_id)
		for destination in location.destinations: ref("location", destination, location.resource_path, loc)
		for id in location.required_lure_ids: ref("lure", id, location.resource_path, loc)
		for id in location.required_rod_ids: ref("rod", id, location.resource_path, loc)
		require(location.fishing_spot != null and indexes.spot.values().has(location.fishing_spot), "unregistered_location_spot", loc, location.resource_path, loc)
		require(ResourceLoader.exists(location.scene_path), "missing_location_scene", loc, location.resource_path, loc, location.scene_path)
		if not ResourceLoader.exists(location.scene_path): continue
		var packed = load(location.scene_path)
		require(packed is PackedScene, "invalid_location_scene_type", loc, location.resource_path, loc, location.scene_path)
		if not packed is PackedScene: continue
		var scene: Node = packed.instantiate()
		require(field(scene, "location_context") == location, "scene_location_mismatch", loc, location.scene_path, loc)
		var metadata: Dictionary = by_location.get(loc, {})
		for path in metadata:
			var binding: Dictionary = metadata[path]
			var node: Node = scene.get_node_or_null(NodePath(path))
			require(node != null, "missing_provider_node", binding.provider_id, location.scene_path, loc, path)
			if node == null: continue
			require(node.get_script() != null and node.get_script().resource_path == binding.script, "provider_script_mismatch", binding.provider_id, location.scene_path, loc, path)
			if binding.has("disabled_exception"):
				var collider: CollisionShape3D = node.get_node_or_null("BodyCollider/CollisionShape3D")
				require(not node.visible and node.process_mode == Node.PROCESS_MODE_DISABLED and collider != null and collider.disabled, "disabled_exception_became_active", binding.provider_id, location.scene_path, loc, path)
				exceptions.append(binding.provider_id + ": " + binding.disabled_exception)
				continue
			for key in binding.get("refs", {}):
				var value = node.call("get_" + key) if key in ["technique_id", "teacher_id"] and node.has_method("get_" + key) else field(node, key)
				var actual: String = value.resource_path if value is Resource else str(value)
				require(actual == binding.refs[key], "provider_reference_mismatch", binding.provider_id, location.scene_path, loc, path + ":" + key)
				if key == "technique_id": ref("mastery", actual, location.scene_path, loc, path)
				if key in ["opponent_id", "card_opponent_id", "required_opponent_id"]: ref("opponent", actual, location.scene_path, loc, path)
				if key == "material_id": ref("material", actual, location.scene_path, loc, path)
				if key == "request_id": ref("request", actual, location.scene_path, loc, path)
				if key == "source_id": ref("source", "treasure_cache:" + actual, location.scene_path, loc, path)
				if key == "competition_id": ref("competition", actual, location.scene_path, loc, path)
				if key == "destination_id":
					require(location.destinations.has(actual), "travel_not_in_location_metadata", binding.provider_id, location.scene_path, loc, path)
			for key in binding.get("constants", {}):
				var constants: Dictionary = node.get_script().get_script_constant_map()
				require(String(constants.get(key, "")) == binding.constants[key], "provider_constant_mismatch", binding.provider_id, location.scene_path, loc, path + ":" + key)
			for catalog in binding.get("catalogs", []):
				require(ResourceLoader.exists(catalog), "missing_provider_catalog", binding.provider_id, catalog, loc, path)
			var technique_id: String = binding.get("refs", {}).get("technique_id", binding.get("constants", {}).get("TECHNIQUE_ID", ""))
			var teacher_id: String = binding.get("refs", {}).get("teacher_id", binding.get("constants", {}).get("TEACHER_ID", ""))
			if not technique_id.is_empty(): ref("mastery", technique_id, location.scene_path, loc, path)
			if not technique_id.is_empty() and indexes.mastery.has(technique_id):
				require(String(indexes.mastery[technique_id].teacher_id) == teacher_id, "master_teacher_mismatch", technique_id, Masters.resource_path, loc, path)
			providers.append(describe_provider(binding, node))
		walk_providers(scene, scene, metadata, loc, location.scene_path)
		require(location.economy_contexts.size() == location.economy_provider_paths.size(), "economy_metadata_shape", loc, location.resource_path, loc)
		for i in mini(location.economy_contexts.size(), location.economy_provider_paths.size()):
			var path: String = location.economy_provider_paths[i]
			var node: Node = scene.get_node_or_null(NodePath(path))
			var context = location.economy_contexts[i]
			require(node != null and field(node, "economy_context") == context and context != null, "economy_binding_mismatch", loc + ":" + path, location.resource_path, loc, path)
			if context != null: validate_economy_context(context, loc, path)
		scene.free()

func walk_providers(node: Node, root: Node, metadata: Dictionary, location: String, file: String) -> void:
	if node.has_method("interact_from_world") or field(node, "request_id") != null or (node.get_script() != null and node.get_script().resource_path == "res://scripts/fish_zone_v2.gd"):
		var path := String(root.get_path_to(node))
		require(metadata.has(path), "missing_required_provider_metadata", location + ":" + path, file, location, path)
		var context = field(node, "economy_context")
		if context != null:
			var location_data = indexes.location[location]
			require(location_data.economy_provider_paths.has(path), "scene_economy_provider_not_registered", location + ":" + path, file, location, path)
	for child in node.get_children(): walk_providers(child, root, metadata, location, file)

func validate_economy_context(context: Resource, location: String, path: String) -> void:
	var offers := {}
	var trades := {}
	for offer in Shops.offers: offers[String(offer.shop_id)] = true
	for trade in Trades.recipes: trades[String(trade.shop_id)] = true
	require(not context.full_catalog_access, "unrestricted_world_provider", location + ":" + path, context.resource_path, location, path)
	require(not context.shop_ids.is_empty() or not context.trade_shop_ids.is_empty(), "provider_without_content", location + ":" + path, context.resource_path, location, path)
	for id in context.shop_ids: require(offers.has(id), "unknown_shop", id, context.resource_path, location, path)
	for id in context.trade_shop_ids: require(trades.has(id), "unknown_trade_shop", id, context.resource_path, location, path)
	for id in context.trade_recipe_ids:
		ref("trade", id, context.resource_path, location, path)
		if indexes.trade.has(id): require(context.trade_shop_ids.has(String(indexes.trade[id].shop_id)), "recipe_shop_not_allowed", id, context.resource_path, location, path)

func describe_provider(binding: Dictionary, node: Node) -> Dictionary:
	var content_ids: Dictionary = binding.get("refs", {}).duplicate(true)
	var context = field(node, "economy_context")
	if context != null:
		content_ids.offers = []
		content_ids.trades = []
		for offer in Shops.offers:
			if context.shop_ids.has(String(offer.shop_id)): content_ids.offers.append(String(offer.offer_id))
		for trade in Trades.recipes:
			if context.trade_shop_ids.has(String(trade.shop_id)) and (context.trade_recipe_ids.is_empty() or context.trade_recipe_ids.has(String(trade.recipe_id))): content_ids.trades.append(String(trade.recipe_id))
	for path in binding.get("catalogs", []):
		if not ResourceLoader.exists(path): continue
		var catalog = load(path)
		var ids: Array = []
		for domain in ["craft", "maker", "reward"]:
			for id in indexes[domain]:
				var entries = field(catalog, "recipes", field(catalog, "rewards", []))
				if entries.any(func(entry): return entry == indexes[domain][id]): ids.append(id)
		content_ids[path] = ids
	return {"provider_id": binding.provider_id, "location_id": binding.location_id, "provider_type": binding.provider_type, "content_ids": content_ids, "scene_binding": binding.path, "resolved": true}

func validate_unregistered_resources() -> void:
	# Only domain leaf definitions: aggregate catalogues and nested assets are excluded
	# by script identity, never by arbitrary filenames or ignored failure counts.
	var domains := {"fish": "res://data/bof4/fish", "spot": "res://data/bof4/spots", "lure": "res://data/bof4/lures", "rod": "res://data/bof4/rods", "offer": "res://data/bof4/shops", "trade": "res://data/bof4/trades", "mastery": "res://data/bof4/mastery", "npc": "res://data/npc/catalog", "location": "res://data/world/locations", "request": "res://data/requests", "opponent": "res://data/triple_triad/opponents", "craft": "res://data/crafting/beach/recipes", "material": "res://data/crafting/beach/materials", "maker": "res://data/economy/card_maker/recipes", "bundle": "res://data/triple_triad/acquisition/bundles", "reward": "res://data/bof4/rewards"}
	for domain in domains:
		var registered: Array = indexes[domain].values()
		if registered.is_empty(): continue
		var leaf_script = registered[0].get_script()
		for path in resource_paths(domains[domain]):
			var resource = load(path)
			require(resource != null, "unloadable_authored_resource", domain, path)
			if resource != null and resource.get_script() == leaf_script:
				require(registered.has(resource), "unregistered_authored_resource", domain, path)

func resource_paths(directory: String) -> Array[String]:
	var result: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".tres"): result.append(directory + "/" + file)
	for child in DirAccess.get_directories_at(directory):
		result.append_array(resource_paths(directory + "/" + child))
	result.sort()
	return result

func validate_dependency_graph(domain: String, property: String) -> void:
	var unresolved: Dictionary = indexes[domain].duplicate()
	var resolved := {}
	for pass_index in range(unresolved.size() + 1):
		var removed := false
		for id in unresolved.keys():
			var prerequisites = field(unresolved[id], property, [])
			if Array(prerequisites).all(func(prerequisite): return resolved.has(String(prerequisite))):
				resolved[id] = true
				unresolved.erase(id)
				removed = true
		if not removed: break
	for id in indexes[domain]:
		require(resolved.has(id), "cyclic_or_missing_" + domain + "_prerequisite", id, indexes[domain][id].resource_path, "", property)

func validate_world_content_coverage(manifest: Dictionary) -> void:
	var bound := {"opponent": {}, "mastery": {}, "request": {}}
	for binding in manifest.providers:
		if binding.has("disabled_exception"): continue
		var refs: Dictionary = binding.get("refs", {})
		for key in ["opponent_id", "card_opponent_id"]:
			if refs.has(key): bound.opponent[refs[key]] = true
		var technique: String = refs.get("technique_id", binding.get("constants", {}).get("TECHNIQUE_ID", ""))
		if not technique.is_empty(): bound.mastery[technique] = true
		if refs.has("request_id"): bound.request[refs.request_id] = true
	var deferred := {}
	for entry in manifest.get("deferred_world_content", []):
		var key: String = entry.domain + ":" + entry.id
		require(not deferred.has(key) and bound.has(entry.domain) and not String(entry.reason).is_empty(), "invalid_deferred_content_exception", key, BINDINGS)
		ref(entry.domain, entry.id, BINDINGS)
		require(not bound[entry.domain].has(entry.id), "stale_deferred_content_exception", key, BINDINGS)
		deferred[key] = true
		exceptions.append(key + ": " + entry.reason)
	for domain in bound:
		for id in indexes[domain]:
			require(bound[domain].has(id) or deferred.has(domain + ":" + id), "registered_content_without_world_provider", id, indexes[domain][id].resource_path)
