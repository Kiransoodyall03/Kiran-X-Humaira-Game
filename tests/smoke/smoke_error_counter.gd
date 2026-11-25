class_name SmokeErrorCounter
extends Logger
## Counts engine and script errors during a smoke test, so a test fails when something
## errors even if every behaviour check passed. Register with OS.add_logger(counter).

var errors: int = 0
var first_error: String = ""


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	errors += 1
	if first_error.is_empty():
		first_error = "%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function]


func _log_message(_message: String, _error: bool) -> void:
	pass
