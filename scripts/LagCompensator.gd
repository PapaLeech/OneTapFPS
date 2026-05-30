## LagCompensator.gd
## Server-side lag compensation using the Valve/CS2 rewind approach.
## Stores a rolling history of player positions and rewinds them for hit checks.
##
## Usage:
##   - Autoloaded as LagCompensator on the server
##   - Call LagCompensator.record_snapshot() every physics tick
##   - Call LagCompensator.check_hit() from your shot RPC handler

extends Node

# How many seconds of history to store per player
const HISTORY_DURATION := 0.3

# How often to record snapshots (seconds) — every physics tick at 60hz = 0.016
const SNAPSHOT_INTERVAL := 0.016

# Maximum ping we'll compensate for (ms). Shots older than this are rejected.
const MAX_COMPENSATE_MS := 250

# Stores position history per peer ID
# { peer_id: [ { time: float, position: Vector3, rotation_y: float }, ... ] }
var _history: Dictionary = {}

var _last_snapshot_time: float = 0.0

func _ready() -> void:
	if not (OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args()):
		# Only run on server
		set_process(false)
		set_physics_process(false)

func _physics_process(_delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	if now - _last_snapshot_time < SNAPSHOT_INTERVAL:
		return
	_last_snapshot_time = now
	record_snapshot()

## Called every tick to snapshot all player positions
func record_snapshot() -> void:
	var now := Time.get_unix_time_from_system()
	var level := _get_level()
	if not level:
		return

	for child in level.get_children():
		if not child is CharacterBody3D:
			continue
		var peer_id := child.name.to_int()
		if peer_id <= 0:
			continue

		if not _history.has(peer_id):
			_history[peer_id] = []

		var snapshot := {
			"time": now,
			"position": child.global_position,
			"rotation_y": child.global_rotation.y
		}

		_history[peer_id].append(snapshot)

		# Prune old snapshots beyond HISTORY_DURATION
		while _history[peer_id].size() > 0:
			var oldest: float = _history[peer_id][0]["time"]
			if now - oldest > HISTORY_DURATION:
				_history[peer_id].pop_front()
			else:
				break

## Remove history when a player disconnects
func remove_player(peer_id: int) -> void:
	_history.erase(peer_id)

## Main hit check — call this from your shot RPC on the server.
## shooter_id: peer ID of the shooting player
## shot_origin: world position the ray starts from
## shot_direction: normalised direction of the ray
## shot_time: Time.get_unix_time_from_system() captured on the client when firing
## max_distance: maximum raycast distance
## Returns: { "hit": bool, "peer_id": int, "hitbox": Node, "position": Vector3 }
func check_hit(
	shooter_id: int,
	shot_origin: Vector3,
	shot_direction: Vector3,
	shot_time: float,
	max_distance: float = 500.0
) -> Dictionary:

	var now := Time.get_unix_time_from_system()
	var latency := now - shot_time

	# Reject shots that are too old
	if latency > MAX_COMPENSATE_MS / 1000.0:
		push_warning("LagCompensator: shot from %d rejected, latency %.0fms > max %dms" % [
			shooter_id, latency * 1000, MAX_COMPENSATE_MS
		])
		return { "hit": false }

	# Save current positions and rewind all players
	var saved_positions: Dictionary = {}
	var level := _get_level()
	if not level:
		return { "hit": false }

	for child in level.get_children():
		if not child is CharacterBody3D:
			continue
		var peer_id := child.name.to_int()
		if peer_id <= 0 or peer_id == shooter_id:
			continue

		saved_positions[peer_id] = {
			"position": child.global_position,
			"rotation_y": child.global_rotation.y
		}

		# Find the snapshot closest to shot_time
		var rewound := _get_position_at_time(peer_id, shot_time)
		if rewound:
			child.global_position = rewound["position"]
			child.global_rotation.y = rewound["rotation_y"]

	# Do the raycast with players in rewound positions
	var result := _do_raycast(shot_origin, shot_direction, max_distance, shooter_id)

	# Restore all player positions
	for peer_id in saved_positions:
		var node := level.get_node_or_null(str(peer_id))
		if node:
			node.global_position = saved_positions[peer_id]["position"]
			node.global_rotation.y = saved_positions[peer_id]["rotation_y"]

	if result:
		LagCompLogger.log_shot(shooter_id, shot_time, latency * 1000, result.get("hit", false))

	return result if result else { "hit": false }

## Find the interpolated position at a given timestamp from history
func _get_position_at_time(peer_id: int, target_time: float) -> Dictionary:
	if not _history.has(peer_id):
		return {}

	var snapshots: Array = _history[peer_id]
	if snapshots.is_empty():
		return {}

	# Find the two snapshots surrounding target_time
	var before: Dictionary = {}
	var after: Dictionary = {}

	for i in range(snapshots.size()):
		var snap: Dictionary = snapshots[i]
		if snap["time"] <= target_time:
			before = snap
		elif snap["time"] > target_time and after.is_empty():
			after = snap
			break

	if before.is_empty():
		return snapshots[0]

	if after.is_empty():
		return before

	# Interpolate between the two snapshots
	var t: float = (target_time - before["time"]) / (after["time"] - before["time"])
	t = clamp(t, 0.0, 1.0)

	return {
		"time": target_time,
		"position": before["position"].lerp(after["position"], t),
		"rotation_y": lerp_angle(before["rotation_y"], after["rotation_y"], t)
	}

## Raycast against the rewound scene state
func _do_raycast(origin: Vector3, direction: Vector3, max_dist: float, exclude_id: int) -> Dictionary:
	var space := get_tree().root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_dist)
	query.collide_with_areas = true
	query.collision_mask = 1

	# Exclude the shooter's body
	var level := _get_level()
	if level:
		var shooter_node := level.get_node_or_null(str(exclude_id))
		if shooter_node:
			query.exclude = [shooter_node.get_rid()]

	var result := space.intersect_ray(query)
	if not result:
		return { "hit": false }

	var collider := result["collider"] as Node

	# Walk up to find Hitbox
	var hitbox: Node = null
	var check := collider
	while check:
		if check.get_script() and check.get_script().get_global_name() == "Hitbox":
			hitbox = check
			break
		check = check.get_parent()

	if not hitbox:
		return { "hit": false }

	# Find which player was hit
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

func _get_level() -> Node:
	# Find the level node containing spawned players
	var root := get_tree().root
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.contains("level_"):
			return child
	return null
