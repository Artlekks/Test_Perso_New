extends Node
## Environmental Wind v1: read-only and deterministic by authoritative game minute.
## Wind direction is the direction the air travels TOWARDS; coordinates follow
## the fishing game's X/Z plane (north=-Z, east=+X).
## No force is applied to lures, fish, camera or player in this foundation.

const MAX_SPEED_MPS: float = 7.0


func get_snapshot() -> Dictionary:
	var clock: Node = get_node_or_null("/root/GameClock")
	if clock == null or not clock.has_method("get_snapshot"):
		return {"available": false, "display": "N/A"}
	var snapshot: Dictionary = clock.call("get_snapshot") as Dictionary
	return get_snapshot_at_minutes(int(snapshot.get("total_minutes", 480)))


func get_snapshot_at_minutes(total_minutes: int) -> Dictionary:
	# Smooth, bounded multi-frequency cycles. Being keyed to game minutes
	# makes the same day/time reproduce the same wind after restarting or travel.
	var t: float = float(maxi(0, total_minutes))
	var speed: float = clampf(
		2.65 + 1.12 * sin(t / 61.0) + 0.66 * sin(t / 19.0 + 0.7)
		+ 0.48 * sin(t / 213.0 - 0.3), 0.0, MAX_SPEED_MPS
	)
	# Clockwise bearings, 0=north, 90=east. Direction changes gradually,
	# not by random steps when the UI polls or a window changes shape.
	var degrees: float = fposmod(
		65.0 + 34.0 * sin(t / 145.0) + 21.0 * sin(t / 51.0 + 0.4),
		360.0
	)
	var angle: float = deg_to_rad(degrees)
	var velocity := Vector2(sin(angle), -cos(angle)) * speed
	var direction := _cardinal(degrees) if speed >= 0.2 else "Calm"
	return {
		"available": true,
		"speed_mps": speed,
		"bearing_degrees": degrees,
		"direction": direction,
		"velocity_xz": velocity,
		"display": "%s %.1f m/s" % [direction, speed],
		"compact": "%s %.1f" % [direction, speed],
		"total_minutes": maxi(0, total_minutes),
	}


static func _cardinal(bearing_degrees: float) -> String:
	var directions := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var idx: int = posmod(int(round(bearing_degrees / 45.0)), 8)
	return directions[idx]
