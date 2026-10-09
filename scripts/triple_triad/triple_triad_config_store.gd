extends RefCounted

## Same-directory replace: an interrupted staging write never truncates the primary.
## .bak is the last committed snapshot, .tmp is never a recovery candidate.
static func commit(config: ConfigFile, path: String) -> Error:
	var staged := path + ".tmp"
	var error: Error = config.save(staged)
	if error != OK:
		return error
	var verified := ConfigFile.new()
	error = verified.load(staged)
	if error == OK and verified.encode_to_text() != config.encode_to_text():
		error = ERR_INVALID_DATA
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(staged), ProjectSettings.globalize_path(path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staged))
		return error
	# Commit succeeded even if the redundant recovery copy cannot be refreshed.
	var backup_error: Error = config.save(path + ".bak.tmp")
	if backup_error == OK:
		backup_error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".bak.tmp"), ProjectSettings.globalize_path(path + ".bak"))
	if backup_error != OK:
		push_warning("Triple Triad recovery copy could not be refreshed: %s" % path)
	return OK

static func load_recover(config: ConfigFile, path: String) -> Error:
	var error: Error = config.load(path)
	# A zero-byte/truncated config parses as OK; it is not a valid card/deck save.
	if error == OK and config.get_value("meta", "version", null) is int:
		return OK
	var backup := ConfigFile.new()
	if backup.load(path + ".bak") == OK and backup.get_value("meta", "version", null) is int:
		config.clear()
		config.parse(backup.encode_to_text())
		return commit(config, path)
	if error == ERR_FILE_NOT_FOUND and not FileAccess.file_exists(path + ".bak"):
		return error
	return ERR_INVALID_DATA

static func delete_save(path: String) -> Error:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		var target: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(target):
			var error: Error = DirAccess.remove_absolute(target)
			if error != OK:
				return error
	return OK
