extends Node3D
class_name Lobby


var clients : Array[int] = []


func add_client(id : int) -> void:
	clients.append(id)

func remove_client(id : int) -> void:
	clients.erase(id)
