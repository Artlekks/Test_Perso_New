extends RefCounted
class_name FishingCephalopodShadowQA

const Policy = preload("res://scripts/fishing_cephalopod_shadow_policy.gd")


static func run() -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	_record(report, "Jellyfish uses animated shadow", Policy.uses_animated_shadow(&"jellyfish"), "Jellyfish must use the soft-body animation.")
	_record(report, "Man-o'-War uses animated shadow", Policy.uses_animated_shadow(&"man_o_war"), "Man-o'-War must use the soft-body animation.")
	_record(report, "Martian Squid uses animated shadow", Policy.uses_animated_shadow(&"martian_squid"), "Martian Squid must use the soft-body animation.")
	_record(report, "Octopus uses animated shadow", Policy.uses_animated_shadow(&"octopus"), "Octopus must use the soft-body animation even though its legacy silhouette profile is WIDE.")
	_record(report, "Sea Bass keeps legacy shadow", not Policy.uses_animated_shadow(&"sea_bass"), "Ordinary fish must not be replaced by the cephalopod animation.")
	_record(report, "Flatfish keeps legacy shadow", not Policy.uses_animated_shadow(&"flatfish"), "The WIDE family must not globally become octopus-like.")

	var rise_mid := Policy.get_visibility_envelope(Policy.RISE_SECONDS * 0.5)
	var hold_sample := Policy.get_visibility_envelope(Policy.RISE_SECONDS + 0.3)
	var sink_start := Policy.RISE_SECONDS + Policy.DEFAULT_HOLD_SECONDS
	var sink_mid := Policy.get_visibility_envelope(sink_start + Policy.SINK_SECONDS * 0.5)
	var hidden_sample := Policy.get_visibility_envelope(sink_start + Policy.SINK_SECONDS + 0.2)
	var duration := Policy.get_cycle_duration()
	var repeat_sample := Policy.get_visibility_envelope(duration + Policy.RISE_SECONDS * 0.5)

	_record(report, "Cycle begins hidden", is_zero_approx(Policy.get_visibility_envelope(0.0)), "The silhouette should emerge rather than pop in fully visible.")
	_record(report, "Rise midpoint is partial", rise_mid > 0.35 and rise_mid < 0.65, "Rise should fade through a readable midpoint.")
	_record(report, "Hold is fully presented", is_equal_approx(hold_sample, 1.0), "The creature should remain readable during its hold.")
	_record(report, "Sink midpoint is partial", sink_mid > 0.35 and sink_mid < 0.65, "The creature should fade back down smoothly.")
	_record(report, "Hidden interval reaches zero", is_zero_approx(hidden_sample), "The silhouette should fully disappear between appearances.")
	_record(report, "Cycle repeats deterministically", absf(repeat_sample - rise_mid) < 0.001, "Repeated surfacing must preserve the same envelope.")
	_record(report, "Cycle duration is positive", duration > 2.0, "The presentation cycle must have meaningful dwell time.")
	_record(report, "Presented alpha is capped", Policy.get_presented_alpha(1.0, 1.0) <= 0.72, "The new art should read as a shadow, not an opaque sprite.")
	_record(report, "Hidden alpha is zero", is_zero_approx(Policy.get_presented_alpha(0.82, 0.0)), "A submerged hidden creature must not leave a ghost image.")
	_record(report, "Visible scale grows from submerged scale", Policy.get_presented_scale(1.0) > Policy.get_presented_scale(0.0), "Surfacing should carry a subtle scale read.")
	_record(report, "Octopus scale remains largest", Policy.get_species_scale_multiplier(&"octopus") > Policy.get_species_scale_multiplier(&"jellyfish"), "Large octopus silhouettes should preserve species readability.")
	_record(report, "Squid animates faster than Man-o'-War", Policy.get_animation_speed_scale(&"martian_squid") > Policy.get_animation_speed_scale(&"man_o_war"), "Soft-body personalities should not all pulse identically.")

	return report


static func _record(report: Dictionary, label: String, passed: bool, failure: String) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [label, failure])
	report["failures"] = failures
