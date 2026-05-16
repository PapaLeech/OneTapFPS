extends Node

const SERVER_URL := "http://161.35.41.206:8000"
const RYSIU := "Rysiu"

var session_active := false
var session_start_time := ""
var session_start_unix := 0.0
var opponent_name := ""

var logs: Dictionary = {
	"client_prediction": [],
	"hit_detection": [],
	"network_sync": [],
	"enemy_state": [],
	"lag_compensation": [],
	"debug_log": [],
}

var total_shots := 0
var total_hits := 0
var total_deaths := 0
var sync_sent := 0
var sync_received := 0
var ping_samples: Array[float] = []

signal session_started
signal session_ended

func _ready() -> void:
	get_tree().root.connect("tree_exiting", _on_exit)

func try_start_session(player_a: String, player_b: String) -> void:
	if session_active:
		return
	if player_a != RYSIU and player_b != RYSIU:
		return
	opponent_name = player_b if player_a == RYSIU else player_a
	var now := Time.get_datetime_dict_from_system()
	session_start_time = "%04d-%02d-%02d_%02d-%02d" % [now["year"], now["month"], now["day"], now["hour"], now["minute"]]
	session_start_unix = Time.get_unix_time_from_system()
	session_active = true
	_reset_logs()
	log_event("debug_log", "SESSION STARTED: %s vs %s" % [RYSIU, opponent_name])
	print("[SessionLogger] Session started: %s vs %s" % [RYSIU, opponent_name])
	session_started.emit()

func end_session(reason: String = "normal") -> void:
	if not session_active:
		return
	session_active = false
	log_event("debug_log", "SESSION ENDED. Reason: %s" % reason)
	_save_all_logs()
	print("[SessionLogger] Session ended. Logs uploading.")
	session_ended.emit()

func log_event(script_name: String, message: String) -> void:
	if not session_active:
		return
	if not logs.has(script_name):
		return
	var now := Time.get_datetime_dict_from_system()
	var ts := "%02d:%02d:%02d" % [now["hour"], now["minute"], now["second"]]
	logs[script_name].append("[%s] %s" % [ts, message])

func record_shot(hit: bool) -> void:
	total_shots += 1
	if hit:
		total_hits += 1

func record_death() -> void:
	total_deaths += 1

func record_sync(sent: bool) -> void:
	if sent:
		sync_sent += 1
	else:
		sync_received += 1

func record_ping(ms: float) -> void:
	ping_samples.append(ms)

func _reset_logs() -> void:
	for key in logs:
		logs[key] = []
	total_shots = 0
	total_hits = 0
	total_deaths = 0
	sync_sent = 0
	sync_received = 0
	ping_samples.clear()

func _build_summary(script_name: String) -> String:
	var duration: float = Time.get_unix_time_from_system() - session_start_unix
	var mins: int = int(duration) / 60
	var secs: int = int(duration) % 60
	var lines: Array[String] = []
	lines.append("--- Summary ---")
	lines.append("Duration: %dm %ds" % [mins, secs])
	lines.append("Players: %s vs %s" % [RYSIU, opponent_name])
	match script_name:
		"hit_detection":
			var acc := "N/A"
			if total_shots > 0:
				acc = "%.1f%%" % (float(total_hits) / float(total_shots) * 100.0)
			lines.append("Shots: %d | Hits: %d | Accuracy: %s | Deaths: %d" % [total_shots, total_hits, acc, total_deaths])
		"network_sync":
			lines.append("Sent: %d | Received: %d" % [sync_sent, sync_received])
		"lag_compensation":
			if ping_samples.size() > 0:
				var avg := 0.0
				for p in ping_samples:
					avg += p
				avg /= ping_samples.size()
				lines.append("Avg ping: %.1f ms | Max: %.1f ms | Samples: %d" % [avg, ping_samples.max(), ping_samples.size()])
			else:
				lines.append("No ping data.")
	return "\n".join(lines)

func _build_log_content(script_name: String) -> String:
	var lines: Array[String] = []
	lines.append("=== OneTapFPS Session Log ===")
	lines.append("Script:  %s" % script_name)
	lines.append("Session: %s" % session_start_time)
	lines.append("Players: %s vs %s" % [RYSIU, opponent_name])
	lines.append("")
	lines.append("--- Events ---")
	if logs[script_name].size() == 0:
		lines.append("No events recorded.")
	else:
		for entry in logs[script_name]:
			lines.append(entry)
	lines.append("")
	lines.append(_build_summary(script_name))
	return "\n".join(lines)

func _save_all_logs() -> void:
	for script_name in logs:
		var filename := "%s_%s_vs_%s_%s.log" % [session_start_time, RYSIU, opponent_name, script_name]
		_upload_log(filename, _build_log_content(script_name))

func _upload_log(filename: String, content: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"filename": filename, "content": content})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		if code == 200:
			print("[SessionLogger] Saved: %s" % filename)
		else:
			print("[SessionLogger] Failed: %s (code %d)" % [filename, code])
	)
	http.request(SERVER_URL + "/save-log", headers, HTTPClient.METHOD_POST, body)

func _on_exit() -> void:
	if session_active:
		end_session("crash_or_force_exit")
