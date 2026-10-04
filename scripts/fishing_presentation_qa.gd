extends RefCounted
class_name FishingPresentationQA

const Policy = preload("res://scripts/fishing_lure_presentation_policy.gd")


static func run() -> Dictionary:
	var failures := PackedStringArray()
	var passed: int = 0
	var total: int = 0

	var checks: Array[Dictionary] = [
		{
			"name": "bob likes a patient presentation",
			"ok": _m(LureActionProfile.MotionStyle.BOB, 0.20, 0.8, 9.0, 9.0) > _m(LureActionProfile.MotionStyle.BOB, 1.45, 0.0, 9.0, 9.0),
		},
		{
			"name": "pop reacts to a recent twitch",
			"ok": _m(LureActionProfile.MotionStyle.POP, 0.25, 0.4, 0.05, 9.0) > _m(LureActionProfile.MotionStyle.POP, 0.25, 0.4, 9.0, 9.0),
		},
		{
			"name": "pop reacts to a recent pull",
			"ok": _m(LureActionProfile.MotionStyle.POP, 0.25, 0.4, 9.0, 0.05) > _m(LureActionProfile.MotionStyle.POP, 0.25, 0.4, 9.0, 9.0),
		},
		{
			"name": "swim prefers moving over a long dead pause",
			"ok": _m(LureActionProfile.MotionStyle.SWIM, 0.58, 0.0, 9.0, 9.0) > _m(LureActionProfile.MotionStyle.SWIM, 0.0, 2.8, 9.0, 9.0),
		},
		{
			"name": "spinner prefers an active retrieve",
			"ok": _m(LureActionProfile.MotionStyle.SPIN, 0.78, 0.0, 9.0, 9.0) > _m(LureActionProfile.MotionStyle.SPIN, 0.0, 2.0, 9.0, 9.0),
		},
		{
			"name": "burning a popper is penalized",
			"ok": _m(LureActionProfile.MotionStyle.POP, 0.30, 0.5, 0.10, 9.0) > _m(LureActionProfile.MotionStyle.POP, 1.35, 0.0, 9.0, 9.0),
		},
		{
			"name": "spoon accepts moderate retrieve variation",
			"ok": _m(LureActionProfile.MotionStyle.SPOON, 0.50, 0.3, 0.20, 9.0) >= 0.90,
		},
		{
			"name": "multiplier never falls below safe floor",
			"ok": _m(LureActionProfile.MotionStyle.SPIN, 2.0, 5.0, 9.0, 9.0) >= Policy.MIN_MULTIPLIER,
		},
		{
			"name": "multiplier never exceeds safe ceiling",
			"ok": _m(LureActionProfile.MotionStyle.POP, 0.24, 1.0, 0.0, 0.0) <= Policy.MAX_MULTIPLIER,
		},
		{
			"name": "quality label is stable",
			"ok": str(Policy.evaluate(LureActionProfile.MotionStyle.SWIM, 0.58, 0.0, 9.0, 9.0).get("label", "")) in ["GOOD", "NATURAL"],
		},
	]

	for check in checks:
		total += 1
		if bool(check.get("ok", false)):
			passed += 1
		else:
			failures.append(str(check.get("name", "unnamed check")))

	return {
		"passed_count": passed,
		"test_count": total,
		"failures": failures,
	}


static func _m(
	style: int,
	speed: float,
	pause: float,
	twitch_age: float,
	pull_age: float
) -> float:
	return float(
		Policy.evaluate(style, speed, pause, twitch_age, pull_age).get(
			"multiplier",
			1.0
		)
	)
