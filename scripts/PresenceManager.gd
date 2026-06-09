extends Node

const SERVER_URL_V6 = "http://[2a03:b0c0:1:e0:0:1:7a5e:2001]:8000"
const SERVER_URL_V4 = "http://161.35.41.206:8000"
const SERVER_URL   = "http://161.35.41.206:8000"

var _active_url: String = SERVER_URL_V6
const CONFIG_PATH  = "user://config.cfg"
const HEARTBEAT_INTERVAL := 2.0

var username: String = ""
var scoreboard_open: bool = false

var _heartbeat_timer: Timer = null
var _is_online: bool = false

func _ready() -> void:
	_load_username()
	_detect_server_url()

func _detect_server_url() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _h, _b):
		if result == OK and code == 200:
			print("[Presence] Using IPv6 server")
			_active_url = SERVER_URL_V6
		else:
			print("[Presence] IPv6 failed, falling back to IPv4")
			_active_url = SERVER_URL_V4
		http.queue_free()
	)
	http.request(SERVER_URL_V6 + "/version")

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		go_offline()

func _exit_tree() -> void:
	go_offline()

func _load_username() -> void:
	# First try game_config.cfg written by launcher (next to game exe)
	var game_config_path := OS.get_executable_path().get_base_dir() + "/game_config.cfg"
	var config := ConfigFile.new()
	if config.load(game_config_path) == OK:
		var name_from_launcher := config.get_value("player", "username", "")
		if name_from_launcher != "":
			username = name_from_launcher
			print("[PresenceManager] Username loaded from launcher: ", username)
			return
	# Fallback to user://config.cfg
	if config.load(CONFIG_PATH) == OK:
		username = config.get_value("player", "username", "")
		print("[PresenceManager] Username loaded from config: ", username)

func save_username(player_name: String) -> void:
	username = player_name
	var config := ConfigFile.new()
	config.set_value("player", "username", player_name)
	config.save(CONFIG_PATH)

func has_username() -> bool:
	return username != ""

func save_setting(key: String, value) -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("settings_" + username, key, value)
	config.save(CONFIG_PATH)

func load_setting(key: String, default):
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		return config.get_value("settings_" + username, key, default)
	return default

# ─── Presence: Online / Offline / Heartbeat ──────────────────────────────────

func _ensure_heartbeat_timer() -> void:
	if _heartbeat_timer and is_instance_valid(_heartbeat_timer):
		return
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.autostart = false
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(_send_heartbeat)

func _start_heartbeat() -> void:
	_ensure_heartbeat_timer()
	if not _heartbeat_timer.is_stopped():
		return
	_heartbeat_timer.start()

func _stop_heartbeat() -> void:
	if _heartbeat_timer and is_instance_valid(_heartbeat_timer):
		_heartbeat_timer.stop()

func _send_heartbeat() -> void:
	if username == "" or not _is_online:
		return
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"username": username})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(_active_url + "/heartbeat", headers, HTTPClient.METHOD_POST, body)

func go_online(player_name: String) -> void:
	username = player_name
	if username == "":
		return
	_is_online = true
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"username": username})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(_active_url + "/online", headers, HTTPClient.METHOD_POST, body)
	_start_heartbeat()
	_send_heartbeat()

func go_offline() -> void:
	if not _is_online or username == "":
		return
	_is_online = false
	_stop_heartbeat()
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"username": username})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(_active_url + "/offline", headers, HTTPClient.METHOD_POST, body)

func get_friends_status(names: Array, callback: Callable) -> void:
	if names.is_empty():
		if callback.is_valid():
			callback.call({})
		return
	var http := HTTPRequest.new()
	add_child(http)
	var query := ",".join(names)
	var url := _active_url + "/friends/status?names=" + query + "&t=" + str(Time.get_ticks_msec())
	print("[Presence] Requesting: ", url)
	http.request_completed.connect(func(_result, _code, _headers, body):
		var text: String = body.get_string_from_utf8()
		print("[Presence] friends/status raw: ", text)
		var data = JSON.parse_string(text)
		if data == null:
			data = {}
		if callback.is_valid():
			callback.call(data)
		http.queue_free()
	)
	http.request(url)

func get_friends_list(callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, _code, _headers, body):
		var text: String = body.get_string_from_utf8()
		var data = JSON.parse_string(text)
		if data == null:
			data = {"friends": []}
		if not is_instance_valid(http):
			return
		if callback.is_valid():
			callback.call(data.get("friends", []))
		http.queue_free()
	)
	http.request(_active_url + "/friends/list?username=" + username)

func get_friend_requests(callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, _code, _headers, body):
		var text: String = body.get_string_from_utf8()
		var data = JSON.parse_string(text)
		if data == null:
			data = {"requests": []}
		if callback.is_valid():
			callback.call(data.get("requests", []))
		http.queue_free()
	)
	http.request(_active_url + "/friends/requests?username=" + username)

func send_friend_request(recipient: String, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"requester": username, "recipient": recipient})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_result, code, _headers, response_body):
		var text: String = response_body.get_string_from_utf8()
		var data = JSON.parse_string(text)
		if callback.is_valid():
			callback.call(code, data)
		http.queue_free()
	)
	http.request(_active_url + "/friends/request", headers, HTTPClient.METHOD_POST, body)

func accept_friend_request(requester: String, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"requester": requester, "recipient": username})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_result, _code, _headers, _body): if callback.is_valid(): callback.call(); http.queue_free())
	http.request(_active_url + "/friends/accept", headers, HTTPClient.METHOD_POST, body)

func decline_friend_request(requester: String, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"requester": requester, "recipient": username})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_result, _code, _headers, _body): if callback.is_valid(): callback.call(); http.queue_free())
	http.request(_active_url + "/friends/decline", headers, HTTPClient.METHOD_POST, body)

func lobby_join() -> void:
	if username == "":
		return
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"username": username})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(_active_url + "/lobby/join", headers, HTTPClient.METHOD_POST, body)

func lobby_leave() -> void:
	if username == "":
		return
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"username": username})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(_active_url + "/lobby/leave", headers, HTTPClient.METHOD_POST, body)

func get_lobby_members(callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, _code, _headers, body):
		var text: String = body.get_string_from_utf8()
		var data = JSON.parse_string(text)
		if data == null:
			data = {"members": []}
		if callback.is_valid():
			callback.call(data.get("members", []))
		http.queue_free()
	)
	http.request(_active_url + "/lobby/members")
