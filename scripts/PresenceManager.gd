extends Node

const SERVER_URL = "http://161.35.41.206:8000"

var username: String = ""

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
