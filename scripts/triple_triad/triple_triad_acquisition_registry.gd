extends Resource
class_name TripleTriadAcquisitionRegistry

@export var bundles: Array[TripleTriadAcquisitionBundle] = []

var _cache: Dictionary = {}


func get_bundle(bundle_id: StringName) -> TripleTriadAcquisitionBundle:
	_ensure_cache()
	return _cache.get(bundle_id, null)


func get_all_bundles() -> Array[TripleTriadAcquisitionBundle]:
	var result: Array[TripleTriadAcquisitionBundle] = []
	for bundle in bundles:
		if bundle != null:
			result.append(bundle)
	return result


func validate_registry(card_catalog: Resource = null) -> Dictionary:
	_cache.clear()
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var seen: Dictionary = {}
	for index in range(bundles.size()):
		var bundle: TripleTriadAcquisitionBundle = bundles[index]
		if bundle == null:
			errors.append("null acquisition bundle at index %d" % index)
			continue
		var key: String = String(bundle.bundle_id).strip_edges()
		if key.is_empty():
			errors.append("empty acquisition bundle id at index %d" % index)
			continue
		if seen.has(key):
			errors.append("duplicate acquisition bundle id: %s" % key)
			continue
		seen[key] = true
		_cache[bundle.bundle_id] = bundle
		var audit: Dictionary = bundle.validate_bundle(card_catalog)
		for error_text in audit.get("errors", []):
			errors.append("%s: %s" % [key, str(error_text)])
		for warning_text in audit.get("warnings", []):
			warnings.append("%s: %s" % [key, str(warning_text)])
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"bundle_count": _cache.size(),
	}


func invalidate_cache() -> void:
	_cache.clear()


func _ensure_cache() -> void:
	if _cache.size() == bundles.size() and not bundles.is_empty():
		return
	_cache.clear()
	for bundle in bundles:
		if bundle == null:
			continue
		if String(bundle.bundle_id).strip_edges().is_empty():
			continue
		if not _cache.has(bundle.bundle_id):
			_cache[bundle.bundle_id] = bundle
