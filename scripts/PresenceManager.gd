extends Node

const SERVER_URL = "http://161.35.41.206:8000"
const CONFIG_PATH = "user://config.cfg"

var username: String = ""

func _ready() -> void:
	_load_username()

func _load_username() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		username = config.get_value("player", "username", "")

func save_username(name: String) -> void:
	username = name
	var config := ConfigFile.new()
	config.set_value("player", "username", name)
	config.save(CONFIG_PATH)

func has_username() -> bool:
	return username != ""

func go_online(player_name: String) -> void:
	username = player_name
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"username": player_name})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(SERVER_URL + "/online", headers, HTTPClient.METHOD_POST, body)

func go_offline() -> void:
	if username == "":
		return
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"username": username})
	var headers := ["Content-Type: application/json"]
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(SERVER_URL + "/offline", headers, HTTPClient.METHOD_POST, body)

func get_friends_status(names: Array, callback: Callable) -> void:
	if names.is_empty():
		callback.call({})
		return
	var http := HTTPRequest.new()
	add_child(http)
	var query := ",".join(names)
	http.request_completed.connect(func(_result, _code, _headers, body):
		var text: String = body.get_string_from_utf8()
		var data = JSON.parse_string(text)
		if data == null:
			data = {}
		callback.call(data)
		http.queue_free()
	)
	http.request(SERVER_URL + "/friends/status?names=" + query)
