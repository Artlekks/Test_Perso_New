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

static func resolve(available: Dictionary, requested_sector: int) -> Dictionary:
	# Canonical ordering breaks equidistant ties consistently. No implicit
	# mirroring or invented front/back art: aliases must be authored explicitly.
	var result: Dictionary = {}
	var nearest := 9
	for index in DIRECTIONS.size():
		var direction: String = DIRECTIONS[index]
		if not available.has(direction): continue
		var separation := absi(index - posmod(requested_sector, 8))
		var distance := mini(separation, 8 - separation)
		if distance < nearest:
			nearest = distance
			result = available[direction]
	return result
