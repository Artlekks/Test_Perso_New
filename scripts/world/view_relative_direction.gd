extends RefCounted
## Matches the player's established +Z=south eight-sector convention.
const DIRECTIONS = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]

static func sector(world_facing: Vector3, camera_basis: Basis) -> int:
	var right := camera_basis.x
	var down := camera_basis.z
	right.y = 0.0
	down.y = 0.0
	return posmod(int(round(atan2(right.normalized().dot(world_facing), down.normalized().dot(world_facing)) / (PI / 4.0))), 8)

static func world_vector(direction: String) -> Vector3:
	var index := DIRECTIONS.find(direction.to_upper())
	if index < 0: return Vector3.BACK
	return Vector3(sin(index * PI / 4.0), 0, cos(index * PI / 4.0))

static func animation_map(frames: SpriteFrames, prefix: String, aliases: Dictionary) -> Dictionary:
	# Authored art always wins. Mirroring is explicit profile data and can only
	# exchange east/west within the same front/back hemisphere.
	var result := {}
	if not prefix.is_empty():
		for direction in DIRECTIONS:
			var animation := prefix + String(direction).to_lower()
			if frames.has_animation(animation): result[direction] = {"animation": animation, "flip_h": false}
	for direction in aliases:
		if result.has(direction): continue
		var alias: Dictionary = aliases[direction]
		if not frames.has_animation(alias.get("animation", "")): continue
		result[direction] = alias
	return result

static func resolve(available: Dictionary, requested_sector: int) -> Dictionary:
	# At an exact side view, prefer the front diagonal over the rear diagonal.
	# Canonical index alone picked SE at S but NW at W: a 90-degree camera
	# turn incorrectly crossed front/back on four-diagonal sheets.
	# Remaining equidistant ties use canonical ordering. No implicit
	# mirroring or invented front/back art: aliases must be authored explicitly.
	var result: Dictionary = {}
	var nearest := 9
	for index in DIRECTIONS.size():
		var direction: String = DIRECTIONS[index]
		if not available.has(direction): continue
		var separation := absi(index - posmod(requested_sector, 8))
		var distance := mini(separation, 8 - separation)
		var side_tie := distance == nearest and posmod(requested_sector, 8) in [2, 6] and index in [0, 1, 7]
		if distance < nearest or side_tie:
			nearest = distance
			result = available[direction]
	return result
