## LagCompensator.gd
## Server-side lag compensation using a CS2-style rewind.
## - Stores a rolling history of player + hitbox transforms
## - Rewinds to client fire time, raycasts, then restores

extends Node

const HISTORY_DURATION := 0.3          # seconds of history per player
const SNAPSHOT_INTERVAL := 0.016       # seconds between snapshots (60 Hz)
const MAX_COMPENSATE_MS := 250         # max latency we accept

# { peer_id: [ { time: float, position: Vector3, rotation_y: float, hitboxes: Array }, ... ] }
var _history: Dictionary = {}
var _last_snapshot_time: float = 0.0

func _ready() -> void:
	if not (OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args()):
		set_process(false)
		set_physics_process(false)

func _physics_process(_delta: float) -> void:
	var now := _now()
	if now - _last_snapshot_time < SNAPSHOT_INTERVAL:
		return
	_last_snapshot_time = now
	record_snapshot()

func _now() -> float:
	# High-resolution, monotonic time in seconds
	return Time.get_ticks_usec() / 1_000_000.0

## Snapshot all player positions + hitboxes
func record_snapshot() -> void:
	var now := _now()
	var level := _get_level()
	if not level:
		return

	for child in level.get_children():
		if not child is CharacterBody3D:
			continue
		if not child.is_inside_tree():
			continue

		var peer_id := child.name.to_int()
		if peer_id <= 0:
			continue

		if not _history.has(peer_id):
			_history[peer_id] = []

		var hitboxes := _snapshot_hitboxes(child)

		var snapshot := {
			"time": now,
			"position": child.global_position,
			"rotation_y": child.global_rotation.y,
			"hitboxes": hitboxes
		}

		_history[peer_id].append(snapshot)

		# Prune old snapshots
		var snapshots: Array = _history[peer_id]
		while snapshots.size() > 0:
			var oldest_time: float = snapshots[0]["time"]
			if now - oldest_time > HISTORY_DURATION:
				snapshots.pop_front()
			else:
				break

func _snapshot_hitboxes(player: Node) -> Array:
	var result: Array = []
	var stack: Array = [player]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
			if child is Hitbox and child.is_inside_tree():
				result.append({
					"path": child.get_path(),
					"transform": child.global_transform
				})
	return result

func remove_player(peer_id: int) -> void:
	_history.erase(peer_id)

func clear_history() -> void:
	_history.clear()
	print("[LagComp] history cleared")

func _get_peer_latency(peer_id: int) -> float:
	var enet := get_tree().get_multiplayer().multiplayer_peer as ENetMultiplayerPeer
	if enet:
		var peer := enet.get_peer(peer_id)
		if peer:
			var rtt_ms := peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			return rtt_ms / 2000.0  # one-way latency in seconds
	return 0.05  # default 50ms fallback

## Main hit check — call from shot RPC on server
func check_hit(
	shooter_id: int,
	shot_origin: Vector3,
	shot_direction: Vector3,
	shot_time: float,
	max_distance: float = 500.0
) -> Dictionary:

	var now := _now()
	var latency := _get_peer_latency(shooter_id)
	var target_time := now - latency
	print("[LagCompDebug] now=", now, " latency=", latency, " target_time=", target_time)

	var level := _get_level()
	if not level:
		return { "hit": false }

	# Save current state and rewind
	var saved_state: Dictionary = {}

	for child in level.get_children():
		if not child is CharacterBody3D:
			continue
		if not child.is_inside_tree():
			continue

		var peer_id := child.name.to_int()
		if peer_id <= 0 or peer_id == shooter_id:
			continue

		saved_state[peer_id] = _save_player_state(child)

		var rewound := _get_state_at_time(peer_id, target_time)
		if not rewound.is_empty():
			_apply_player_state(child, rewound)
		var dbg_hitboxes := _snapshot_hitboxes(child)
		var dbg_hb_pos = dbg_hitboxes[0]["transform"].origin if dbg_hitboxes.size() > 0 else "none"
		# Print ALL hitbox positions so we can see where head/spine actually are
		for hb in dbg_hitboxes:
			var hb_node := get_tree().root.get_node_or_null(hb["path"])
			var hb_name := hb_node.get_parent().name if hb_node else "unknown"
			print("[HitboxDebug] ", hb_name, " world_Y=", hb["transform"].origin.y)
		print("[TargetDebug] peer_id=", peer_id, " current_pos=", saved_state[peer_id]["position"], " rewound_pos=", child.global_position, " first_hitbox_pos=", dbg_hb_pos)

	# Raycast in rewound state
	var result := _do_raycast(shot_origin, shot_direction, max_distance, shooter_id)
	print("[LagCompDebug] raycast result: ", result)

	# Restore all players
	for peer_id in saved_state.keys():
		var node := level.get_node_or_null(str(peer_id))
		if node:
			_restore_player_state(node, saved_state[peer_id])

	if result:
		LagCompLogger.log_shot(shooter_id, shot_time, latency * 1000.0, result.get("hit", false))

	return result if result else { "hit": false }

func _save_player_state(player: CharacterBody3D) -> Dictionary:
	player.set_physics_process(false)
	player.set_process(false)

	var hitboxes := _snapshot_hitboxes(player)

	return {
		"position": player.global_position,
		"rotation_y": player.global_rotation.y,
		"hitboxes": hitboxes
	}

func _apply_player_state(player: CharacterBody3D, state: Dictionary) -> void:
	player.global_position = state["position"]
	player.global_rotation.y = state["rotation_y"]

	# Restore hitbox transforms for this snapshot
	if state.has("hitboxes"):
		for hb in state["hitboxes"]:
			var node := player.get_tree().root.get_node_or_null(hb["path"])
			if node and node is Node3D:
				node.global_transform = hb["transform"]

func _restore_player_state(player: CharacterBody3D, state: Dictionary) -> void:
	_apply_player_state(player, state)
	player.set_physics_process(true)
	player.set_process(true)

## Interpolated state at a given time
func _get_state_at_time(peer_id: int, target_time: float) -> Dictionary:
	if not _history.has(peer_id):
		return {}

	var snapshots: Array = _history[peer_id]
	if snapshots.is_empty():
		return {}

	# Binary search by time
	var low := 0
	var high := snapshots.size() - 1

	if target_time <= snapshots[0]["time"]:
		return snapshots[0]
	if target_time >= snapshots[high]["time"]:
		return snapshots[high]

	while low <= high:
		var mid := (low + high) / 2
		var mid_time: float = snapshots[mid]["time"]

		if mid_time < target_time:
			low = mid + 1
		elif mid_time > target_time:
			high = mid - 1
		else:
			return snapshots[mid]

	var before: Dictionary = snapshots[high]
	var after: Dictionary = snapshots[low]

	var denom: float = after["time"] - before["time"]
	if denom <= 0.0:
		return before

	var t: float = (target_time - before["time"]) / denom
	t = clamp(t, 0.0, 1.0)

	return {
		"time": target_time,
		"position": before["position"].lerp(after["position"], t),
		"rotation_y": lerp_angle(before["rotation_y"], after["rotation_y"], t),
		# For hitboxes we just take the earlier snapshot (cheap but consistent)
		"hitboxes": before["hitboxes"]
	}

## Raycast against rewound scene
func _do_raycast(origin: Vector3, direction: Vector3, max_dist: float, exclude_id: int) -> Dictionary:
	var space := get_tree().root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_dist)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 1

	var level := _get_level()
	if level:
		var shooter_node := level.get_node_or_null(str(exclude_id))
		if shooter_node:
			query.exclude = _collect_rids(shooter_node)

	var result := space.intersect_ray(query)
	print("[RaycastDebug] origin=", origin, " direction=", direction, " raw_result=", result)
	if not result:
		return { "hit": false }

	var collider := result["collider"] as Node
	print("[RaycastDebug] collider=", collider, " collider_path=", collider.get_path() if collider else "null", " layer=", collider.collision_layer if collider and collider.has_method("get") and "collision_layer" in collider else "n/a")

	# Walk up to find Hitbox
	var hitbox: Node = null
	var check := collider
	while check:
		if check.is_in_group("hitbox"):
			hitbox = check
			break
		if check.get_script() and check.get_script().get_global_name() == "Hitbox":
			hitbox = check
			break
		check = check.get_parent()

	if not hitbox:
		return { "hit": false }

	# Find player
	var hit_player := hitbox.get_parent()
	while hit_player and not hit_player is CharacterBody3D:
		hit_player = hit_player.get_parent()

	var hit_peer_id := 0
	if hit_player:
		hit_peer_id = hit_player.name.to_int()

	return {
		"hit": true,
		"peer_id": hit_peer_id,
		"hitbox": hitbox,
		"position": result["position"]
	}

func _collect_rids(root: Node) -> Array:
	var rids: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject3D:
			rids.append(node.get_rid())
		for child in node.get_children():
			stack.append(child)
	return rids

func _get_level() -> Node:
	var root := get_tree().root
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.contains("level_"):
			return child
	return null
