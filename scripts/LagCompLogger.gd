## LagCompLogger.gd
## Logs lag compensation hit data to /home/onetap/reports/ on the server.
## Each session produces a CSV file for analysis.
## Columns: timestamp, shooter_id, shot_time, latency_ms, hit

extends Node

const LOG_DIR := "/home/onetap/reports/"
const LOG_PREFIX := "lagcomp_"

var _log_file: FileAccess = null
var _session_start: String = ""

func _ready() -> void:
	if not (OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args()):
		set_process(false)
		return
	_start_session()

func _start_session() -> void:
	_session_start = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := LOG_DIR + LOG_PREFIX + _session_start + ".csv"
	_log_file = FileAccess.open(path, FileAccess.WRITE)
	if _log_file:
		_log_file.store_line("timestamp,shooter_id,shot_time,latency_ms,hit")
		print("[LagCompLogger] Logging to: ", path)
	else:
		push_warning("[LagCompLogger] Could not open log file at: " + path)

func log_shot(shooter_id: int, shot_time: float, latency_ms: float, hit: bool) -> void:
	if not _log_file:
		return
	var now := Time.get_unix_time_from_system()
	_log_file.store_line("%f,%d,%f,%.1f,%s" % [now, shooter_id, shot_time, latency_ms, "true" if hit else "false"])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _log_file:
			_log_file.close()
			_log_file = null
