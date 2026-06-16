extends Node

# ─── Search & Destroy Mode Controller ────────────────────────────────────────
# Attached as a child node (SearchAndDestroyController) of snd_level_001.tscn.
# Completely isolated from level_001.tscn and Deathmatch.
# Server-authoritative: all state changes happen on the server and are
# broadcast to clients via RPC.

# ─── Tuneable constants (change these manually as needed) ────────────────────
const ROUNDS_TO_WIN      : int   = 3    # First team to reach this wins the match (change to 13 later)
const TEAM_SIZE          : int   = 3    # Players per team (change to 5 for 5v5)
const READY_UP_DURATION  : float = 120.0 # 2-minute ready-up window
const READY_UP_COUNTDOWN : float = 5.0   # Seconds between "all ready" and spawn
const ROUND_TIME         : float = 120.0 # 2-minute round timer
const ROUND_END_PAUSE    : float = 3.0   # Brief pause after round win announcement

# ─── State ───────────────────────────────────────────────────────────────────
enum Phase { READY_UP, COUNTDOWN, ROUND_ACTIVE, ROUND_END, MATCH_END }

var _phase             : Phase  = Phase.READY_UP
var _team_a_rounds     : int    = 0
var _team_b_rounds     : int    = 0
var _round_number      : int    = 0
var _ready_players     : Dictionary = {}   # peer_id -> true
var _ready_up_elapsed  : float  = 0.0
var _countdown_elapsed : float  = 0.0
var _round_elapsed     : float  = 0.0
var _alive_a           : Dictionary = {}   # peer_id -> true (server only)
var _alive_b           : Dictionary = {}   # peer_id -> true (server only)

# ─── UI references (built at runtime, client-side only) ──────────────────────
var _hud_canvas        : CanvasLayer    = null
var _ready_up_panel    : PanelContainer = null
var _center_label      : Label          = null
var _round_timer_label : Label          = null
var _end_scoreboard    : PanelContainer = null

# Pause-menu style shared across all SND UI panels
const PANEL_BG_COLOR     := Color(0.12, 0.12, 0.12, 0.97)
const PANEL_BORDER_COLOR := Color(0.4,  0.4,  0.4,  1.0)
const PANEL_SHADOW_COLOR := Color(0.0,  0.0,  0.0,  0.8)

# ─── Focus helper ─────────────────────────────────────────────────────────────
func _disable_focus_recursive(node: Node) -> void:
	if node is Control:
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_focus_recursive(child)

func _set_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)

# ─── Ready ───────────────────────────────────────────────────────────────────
func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		return  # Server has no UI
	await get_tree().process_frame
	_build_hud()

func _build_hud() -> void:
	_hud_canvas = CanvasLayer.new()
	_hud_canvas.layer = 64
	get_parent().add_child.call_deferred(_hud_canvas)
	await get_parent().child_entered_tree
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_ready_up_panel()
	_build_center_label()
	_build_round_timer_label()
	_disable_focus_recursive(_ready_up_panel)
	# Ensure all SND UI nodes pass mouse events through so HUDLayer chat remains clickable
	for child in _hud_canvas.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(_ready_up_panel, Control.MOUSE_FILTER_IGNORE)
	_set_mouse_filter_recursive(_center_label, Control.MOUSE_FILTER_IGNORE)
	_set_mouse_filter_recursive(_round_timer_label, Control.MOUSE_FILTER_IGNORE)
	# Wait two frames to let all SND UI finish building
	await get_tree().process_frame
	await get_tree().process_frame
	# Restore focus to InputLine if chat is open
	var level := get_tree().get_root().get_node_or_null("Node3D")
	if level and level.has_node("HUDLayer/ChatTerminalPanel/VBox/InputLine"):
		var chat_focus = level.get("_chat_focus")
		if chat_focus != null and chat_focus != 0:  # 0 = ChatFocus.NONE
			var input_line := level.get_node("HUDLayer/ChatTerminalPanel/VBox/InputLine")
			input_line.grab_focus()

# ─── Process ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	match _phase:
		Phase.READY_UP:
			_ready_up_elapsed += delta
			var remaining := int(READY_UP_DURATION - _ready_up_elapsed)
			_sync_ready_up_state.rpc(
				_ready_up_elapsed >= READY_UP_DURATION,
				remaining,
				var_to_bytes(_ready_players)
			)
			if _ready_up_elapsed >= READY_UP_DURATION:
				_begin_countdown(false)

		Phase.COUNTDOWN:
			_countdown_elapsed += delta
			var remaining := int(READY_UP_COUNTDOWN - _countdown_elapsed) + 1
			_sync_countdown.rpc(remaining, _countdown_elapsed >= READY_UP_COUNTDOWN)
			if _countdown_elapsed >= READY_UP_COUNTDOWN:
				_start_round()

		Phase.ROUND_ACTIVE:
			_round_elapsed += delta
			var remaining := int(ROUND_TIME - _round_elapsed)
			_sync_round_timer.rpc(remaining)
			if _round_elapsed >= ROUND_TIME:
				_end_round(2)

# ─── Ready-Up Phase ──────────────────────────────────────────────────────────
func player_pressed_ready(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _phase != Phase.READY_UP:
		return
	_ready_players[peer_id] = true
	# Solo bypass: no peers means just this player, treat as all ready
	var all_players := multiplayer.get_peers()
	if all_players.is_empty():
		_begin_countdown(true)
		return
	var all_ready := true
	for pid in all_players:
		if not _ready_players.has(pid):
			all_ready = false
			break
	if all_ready and all_players.size() > 0:
		_begin_countdown(true)

@rpc("any_peer", "reliable")
func _client_pressed_ready() -> void:
	if not multiplayer.is_server():
		return
	player_pressed_ready(multiplayer.get_remote_sender_id())

func _begin_countdown(all_ready: bool) -> void:
	_phase = Phase.COUNTDOWN
	_countdown_elapsed = 0.0
	_notify_countdown_start.rpc(all_ready)

# ─── Round Flow ──────────────────────────────────────────────────────────────
func _start_round() -> void:
	_phase = Phase.ROUND_ACTIVE
	_round_elapsed = 0.0
	_round_number += 1
	_alive_a.clear()
	_alive_b.clear()
	_spawn_teams()
	# Connect death signals for all players (server only)
	if multiplayer.is_server():
		var level := get_parent()
		var stats : Dictionary = level.get("_stats") if level and level.get("_stats") != null else {}
		for pid in stats.keys():
			var team : String = stats[pid].get("team", "A")
			if team == "A":
				_alive_a[pid] = true
			else:
				_alive_b[pid] = true
			var player := level.get_node_or_null(str(pid))
			if player:
				var health := player.get_node_or_null("Health")
				if health and not health.died.is_connected(_on_player_died.bind(pid)):
					health.died.connect(_on_player_died.bind(pid))
					print("[SND] Connected death signal for peer ", pid, " team=", team)
			else:
				print("[SND] WARNING: player node not found for peer ", pid)
		print("[SND] _start_round alive_a=", _alive_a, " alive_b=", _alive_b)
	_notify_round_start.rpc(_round_number)

func _on_player_died(peer_id: int) -> void:
	print("[SND] _on_player_died: peer_id=", peer_id, " alive_a=", _alive_a, " alive_b=", _alive_b)
	if _phase != Phase.ROUND_ACTIVE:
		return
	_alive_a.erase(peer_id)
	_alive_b.erase(peer_id)
	if _alive_a.is_empty():
		_end_round(2)  # Team B wins
	elif _alive_b.is_empty():
		_end_round(1)  # Team A wins

func _end_round(winning_team: int) -> void:
	if _phase != Phase.ROUND_ACTIVE:
		return
	_phase = Phase.ROUND_END
	if winning_team == 1:
		_team_a_rounds += 1
	else:
		_team_b_rounds += 1
	_notify_round_end.rpc(winning_team, _team_a_rounds, _team_b_rounds)
	await get_tree().create_timer(ROUND_END_PAUSE).timeout
	if _team_a_rounds >= ROUNDS_TO_WIN:
		_end_match(1)
	elif _team_b_rounds >= ROUNDS_TO_WIN:
		_end_match(2)
	else:
		# Reset health for all players before next round
		_reset_all_health()
		_phase = Phase.COUNTDOWN
		_countdown_elapsed = 0.0
		_notify_countdown_start.rpc(false)

func _end_match(winning_team: int) -> void:
	_phase = Phase.MATCH_END
	var summary := _build_match_summary()
	_notify_match_end.rpc(winning_team, var_to_bytes(summary))

func _reset_all_health() -> void:
	if not multiplayer.is_server():
		return
	var level := get_parent()
	if not level:
		return
	var stats : Dictionary = level.get("_stats") if level.get("_stats") != null else {}
	for pid in stats.keys():
		var player := level.get_node_or_null(str(pid))
		if player:
			var health := player.get_node_or_null("Health")
			if health:
				health.current_health = health.max_health
				health.emit_signal("health_changed", health.current_health, health.max_health)

# ─── Team Spawning ───────────────────────────────────────────────────────────
func _spawn_teams() -> void:
	if not multiplayer.is_server():
		return
	var level := get_parent()
	if not level:
		return
	var team_a_spawns := get_tree().get_nodes_in_group("TeamA_Spawn")
	var team_b_spawns := get_tree().get_nodes_in_group("TeamB_Spawn")
	if team_a_spawns.is_empty() or team_b_spawns.is_empty():
		push_error("SND: Spawn groups TeamA_Spawn or TeamB_Spawn not found!")
		return
	var stats : Dictionary = level.get("_stats") if level.get("_stats") != null else {}
	var team_a_peers : Array = []
	var team_b_peers : Array = []
	for pid in stats.keys():
		if stats[pid].get("team", "A") == "A":
			team_a_peers.append(pid)
		else:
			team_b_peers.append(pid)
	for i in range(team_a_peers.size()):
		var spawn_node = team_a_spawns[i % team_a_spawns.size()]
		_teleport_peer.rpc(team_a_peers[i], spawn_node.global_position)
	for i in range(team_b_peers.size()):
		var spawn_node = team_b_spawns[i % team_b_spawns.size()]
		_teleport_peer.rpc(team_b_peers[i], spawn_node.global_position)

@rpc("authority", "call_local", "reliable")
func _teleport_peer(peer_id: int, pos: Vector3) -> void:
	var level := get_parent()
	if not level:
		return
	var player := level.get_node_or_null(str(peer_id))
	if player:
		player.global_position = pos + Vector3(0, 1.0, 0)

# ─── Match Summary ───────────────────────────────────────────────────────────
func _build_match_summary() -> Dictionary:
	var level := get_parent()
	if not level:
		return {}
	var stats : Dictionary = level.get("_stats") if level.get("_stats") != null else {}
	var top_kills     := {"name": "—", "value": 0}
	var top_assists   := {"name": "—", "value": 0}
	var top_headshots := {"name": "—", "value": 0}
	for pid in stats.keys():
		var s : Dictionary = stats[pid]
		if s.get("kills", 0) > top_kills["value"]:
			top_kills = {"name": s.get("username", "?"), "value": s["kills"]}
		if s.get("assists", 0) > top_assists["value"]:
			top_assists = {"name": s.get("username", "?"), "value": s["assists"]}
		if s.get("headshots", 0) > top_headshots["value"]:
			top_headshots = {"name": s.get("username", "?"), "value": s["headshots"]}
	return {
		"top_kills":     top_kills,
		"top_assists":   top_assists,
		"top_headshots": top_headshots,
	}

# ─── RPC Broadcasts (server → all clients) ───────────────────────────────────
@rpc("authority", "call_local", "reliable")
func _sync_ready_up_state(timed_out: bool, seconds_remaining: int, ready_bytes: PackedByteArray) -> void:
	if multiplayer.is_server():
		return
	var ready_dict : Dictionary = bytes_to_var(ready_bytes)
	_update_ready_up_ui(seconds_remaining, ready_dict)

@rpc("authority", "call_local", "reliable")
func _notify_countdown_start(all_ready: bool) -> void:
	if multiplayer.is_server():
		return
	_hide_ready_up_panel()
	_show_center_label("MATCH STARTS IN 5" if all_ready else "READY IN 5")

@rpc("authority", "call_local", "reliable")
func _sync_countdown(seconds_remaining: int, finished: bool) -> void:
	if multiplayer.is_server():
		return
	if finished:
		_hide_center_label()
		return
	var prefix := "MATCH STARTS IN " if _phase == Phase.COUNTDOWN else "READY IN "
	_show_center_label(prefix + str(seconds_remaining))

@rpc("authority", "call_local", "reliable")
func _notify_round_start(round_num: int) -> void:
	if multiplayer.is_server():
		return
	_set_local_player_frozen(false)
	_show_center_label("ROUND " + str(round_num))
	_show_round_timer(int(ROUND_TIME))
	get_tree().create_timer(2.0).timeout.connect(func(): _hide_center_label())

@rpc("authority", "call_local", "reliable")
func _sync_round_timer(seconds_remaining: int) -> void:
	if multiplayer.is_server():
		return
	_show_round_timer(seconds_remaining)

@rpc("authority", "call_local", "reliable")
func _notify_round_end(winning_team: int, a_rounds: int, b_rounds: int) -> void:
	if multiplayer.is_server():
		return
	_hide_round_timer()
	var team_name := "TEAM A" if winning_team == 1 else "TEAM B"
	_show_center_label("ROUND WON – " + team_name)
	get_tree().create_timer(ROUND_END_PAUSE - 0.5).timeout.connect(func(): _hide_center_label())

@rpc("authority", "call_local", "reliable")
func _notify_match_end(winning_team: int, summary_bytes: PackedByteArray) -> void:
	if multiplayer.is_server():
		return
	_hide_round_timer()
	_hide_center_label()
	var summary : Dictionary = bytes_to_var(summary_bytes)
	var my_team := _get_local_team()
	var won := (winning_team == 1 and my_team == "A") or (winning_team == 2 and my_team == "B")
	_show_end_scoreboard(won, summary)
	# Return to lobby after 5 seconds
	await get_tree().create_timer(5.0).timeout
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://assets/ui/main_menu.tscn")

# ─── UI: Helpers ─────────────────────────────────────────────────────────────
func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color     = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = PANEL_SHADOW_COLOR
	style.shadow_size  = 8
	return style

# ─── UI: Ready-Up Panel ───────────────────────────────────────────────────────
func _build_ready_up_panel() -> void:
	_ready_up_panel = PanelContainer.new()
	_ready_up_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_ready_up_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ready_up_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ready_up_panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	_ready_up_panel.offset_top = -16
	_ready_up_panel.custom_minimum_size = Vector2(340, 0)
	_ready_up_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_up_panel.focus_mode = Control.FOCUS_NONE
	_ready_up_panel.visible = true
	_hud_canvas.add_child(_ready_up_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_ready_up_panel.add_child(vbox)

	var title_bar := ColorRect.new()
	title_bar.color = Color(0.08, 0.08, 0.08, 1.0)
	title_bar.custom_minimum_size = Vector2(340, 32)
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "Ready Up"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_bar.add_child(title)

	var instr := Label.new()
	instr.name = "InstructionLabel"
	instr.text = "Press F to Ready Up"
	instr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr.add_theme_font_size_override("font_size", 13)
	instr.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	vbox.add_child(instr)

	var count_lbl := Label.new()
	count_lbl.name = "ReadyCountLabel"
	count_lbl.text = "Players Ready: 0 / 0"
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	vbox.add_child(count_lbl)

	var div := ColorRect.new()
	div.color = Color(0.4, 0.4, 0.4, 0.4)
	div.custom_minimum_size = Vector2(340, 1)
	vbox.add_child(div)

	var player_list := VBoxContainer.new()
	player_list.name = "PlayerList"
	player_list.add_theme_constant_override("separation", 4)
	vbox.add_child(player_list)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(pad)

func _update_ready_up_ui(seconds_remaining: int, ready_dict: Dictionary) -> void:
	if not _ready_up_panel or not _ready_up_panel.visible:
		return
	var vbox := _ready_up_panel.get_node_or_null("VBoxContainer")
	if not vbox:
		return
	var count_lbl := vbox.get_node_or_null("ReadyCountLabel") as Label
	var player_list := vbox.get_node_or_null("PlayerList") as VBoxContainer
	if not count_lbl or not player_list:
		return
	var level := get_parent()
	var stats : Dictionary = level.get("_stats") if level and level.get("_stats") != null else {}
	count_lbl.text = "Players Ready: %d / %d" % [ready_dict.size(), stats.size()]
	for child in player_list.get_children():
		child.queue_free()
	for pid in stats.keys():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		player_list.add_child(row)
		var tick := Label.new()
		var is_ready : bool = ready_dict.has(pid)
		tick.text = "[✓]" if is_ready else "[ ]"
		tick.add_theme_font_size_override("font_size", 13)
		tick.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2, 1.0) if is_ready else Color(0.6, 0.6, 0.6, 1.0))
		row.add_child(tick)
		var name_lbl := Label.new()
		name_lbl.text = stats[pid].get("username", "Player")
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(name_lbl)

func _hide_ready_up_panel() -> void:
	if _ready_up_panel:
		_ready_up_panel.visible = false

# ─── UI: Center Label ─────────────────────────────────────────────────────────
func _build_center_label() -> void:
	var center_panel := PanelContainer.new()
	center_panel.add_theme_stylebox_override("panel", _make_panel_style())
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	center_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_panel.focus_mode = Control.FOCUS_NONE
	center_panel.visible = false
	_hud_canvas.add_child(center_panel)
	_center_label = Label.new()
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 32)
	_center_label.add_theme_color_override("font_color", Color.WHITE)
	_center_label.add_theme_constant_override("margin_left", 24)
	_center_label.add_theme_constant_override("margin_right", 24)
	_center_label.add_theme_constant_override("margin_top", 12)
	_center_label.add_theme_constant_override("margin_bottom", 12)
	_center_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_label.focus_mode = Control.FOCUS_NONE
	center_panel.add_child(_center_label)
	_center_label.set_meta("panel", center_panel)

func _show_center_label(text: String) -> void:
	if _center_label:
		_center_label.text = text
		if _center_label.has_meta("panel"):
			_center_label.get_meta("panel").visible = true
		_center_label.visible = true

func _hide_center_label() -> void:
	if _center_label:
		if _center_label.has_meta("panel"):
			_center_label.get_meta("panel").visible = false
		_center_label.visible = false

# ─── UI: Round Timer ──────────────────────────────────────────────────────────
func _build_round_timer_label() -> void:
	var timer_panel := PanelContainer.new()
	timer_panel.add_theme_stylebox_override("panel", _make_panel_style())
	timer_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	timer_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	timer_panel.offset_top = 12
	timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_panel.focus_mode = Control.FOCUS_NONE
	timer_panel.visible = false
	_hud_canvas.add_child(timer_panel)
	_round_timer_label = Label.new()
	_round_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_timer_label.add_theme_font_size_override("font_size", 20)
	_round_timer_label.add_theme_color_override("font_color", Color.WHITE)
	_round_timer_label.add_theme_constant_override("margin_left", 12)
	_round_timer_label.add_theme_constant_override("margin_right", 12)
	_round_timer_label.add_theme_constant_override("margin_top", 6)
	_round_timer_label.add_theme_constant_override("margin_bottom", 6)
	timer_panel.add_child(_round_timer_label)
	_round_timer_label.visible = true
	_round_timer_label.set_meta("panel", timer_panel)

func _show_round_timer(seconds: int) -> void:
	if not _round_timer_label:
		return
	var mins := seconds / 60
	var secs := seconds % 60
	_round_timer_label.text = "%d:%02d" % [mins, secs]
	if _round_timer_label.has_meta("panel"):
		_round_timer_label.get_meta("panel").visible = true
	_round_timer_label.visible = true

func _hide_round_timer() -> void:
	if _round_timer_label:
		if _round_timer_label.has_meta("panel"):
			_round_timer_label.get_meta("panel").visible = false
		_round_timer_label.visible = false

# ─── UI: End Scoreboard (Victory / Defeat) ───────────────────────────────────
func _show_end_scoreboard(won: bool, summary: Dictionary) -> void:
	if _end_scoreboard:
		_end_scoreboard.queue_free()
	_end_scoreboard = PanelContainer.new()
	_end_scoreboard.add_theme_stylebox_override("panel", _make_panel_style())
	_end_scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	_end_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_scoreboard.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_end_scoreboard.custom_minimum_size = Vector2(520, 0)
	_end_scoreboard.modulate.a = 0.0
	_hud_canvas.add_child(_end_scoreboard)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_end_scoreboard.add_child(vbox)

	var title_bar := ColorRect.new()
	title_bar.custom_minimum_size = Vector2(520, 36)
	title_bar.color = Color(0.08, 0.08, 0.08, 1.0)
	vbox.add_child(title_bar)
	var title_lbl := Label.new()
	title_lbl.text = "VICTORY" if won else "DEFEAT"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color",
		Color(0.2, 1.0, 0.2, 1.0) if won else Color(1.0, 0.2, 0.2, 1.0))
	title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_bar.add_child(title_lbl)

	var summary_vbox := VBoxContainer.new()
	summary_vbox.add_theme_constant_override("separation", 6)
	var pad_top := Control.new()
	pad_top.custom_minimum_size = Vector2(0, 10)
	summary_vbox.add_child(pad_top)
	for entry in [
		["Most Kills",     summary.get("top_kills",     {})],
		["Most Assists",   summary.get("top_assists",    {})],
		["Most Headshots", summary.get("top_headshots", {})],
	]:
		var row := Label.new()
		var data : Dictionary = entry[1]
		row.text = "%-18s %s (%d)" % [entry[0] + ":", data.get("name", "—"), data.get("value", 0)]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
		summary_vbox.add_child(row)
	var pad_mid := Control.new()
	pad_mid.custom_minimum_size = Vector2(0, 8)
	summary_vbox.add_child(pad_mid)
	vbox.add_child(summary_vbox)

	var div := ColorRect.new()
	div.color = Color(0.4, 0.4, 0.4, 0.5)
	div.custom_minimum_size = Vector2(520, 1)
	vbox.add_child(div)

	var level := get_parent()
	var stats : Dictionary = level.get("_stats") if level and level.get("_stats") != null else {}
	vbox.add_child(_make_score_row("PLAYER", "K", "D", "A", "HS", "PING", true))
	var div2 := ColorRect.new()
	div2.color = Color(0.4, 0.4, 0.4, 0.5)
	div2.custom_minimum_size = Vector2(520, 1)
	vbox.add_child(div2)

	for team_label in ["A", "B"]:
		vbox.add_child(_make_team_bar("TEAM " + team_label))
		var peers := stats.keys().filter(func(p): return stats[p].get("team", "A") == team_label)
		peers.sort_custom(func(a, b): return stats[a]["kills"] > stats[b]["kills"])
		for pid in peers:
			var s : Dictionary = stats[pid]
			vbox.add_child(_make_score_row(
				s.get("username", "?"),
				str(s.get("kills", 0)),
				str(s.get("deaths", 0)),
				str(s.get("assists", 0)),
				str(s.get("headshots", 0)),
				str(s.get("ping", 0)) + " ms",
				false
			))
			var rdiv := ColorRect.new()
			rdiv.color = Color(0.3, 0.3, 0.3, 0.3)
			rdiv.custom_minimum_size = Vector2(520, 1)
			vbox.add_child(rdiv)

	var pad_bot := Control.new()
	pad_bot.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(pad_bot)

	var tween := create_tween()
	tween.tween_property(_end_scoreboard, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)

func _make_team_bar(team_name: String) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0.18, 0.18, 0.18, 1.0)
	bar.custom_minimum_size = Vector2(520, 24)
	var lbl := Label.new()
	lbl.text = team_name
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(lbl)
	return bar

func _make_score_row(player: String, kills: String, deaths: String, assists: String, headshots: String, ping: String, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(520, 28)
	var cols   := [player, kills, deaths, assists, headshots, ping]
	var widths := [180,    55,    55,     55,      55,        80]
	for i in range(cols.size()):
		var lbl := Label.new()
		lbl.text = cols[i]
		lbl.custom_minimum_size.x = widths[i]
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if i > 0 else HORIZONTAL_ALIGNMENT_LEFT
		if is_header:
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
			lbl.add_theme_font_size_override("font_size", 11)
		else:
			lbl.add_theme_color_override("font_color", Color.WHITE)
			lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
	return row

# ─── Local Team Helper ────────────────────────────────────────────────────────
func _get_local_team() -> String:
	var level := get_parent()
	if not level:
		return "A"
	var stats : Dictionary = level.get("_stats") if level.get("_stats") != null else {}
	var my_id := multiplayer.get_unique_id()
	return stats.get(my_id, {}).get("team", "A")

func _set_local_player_frozen(frozen: bool) -> void:
	var level := get_parent()
	if not level:
		return
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var player := level.get_node_or_null(str(my_id))
	if player:
		if not frozen and player.get("_chat_open") == true:
			return
		player.set_physics_process(not frozen)

# ─── F Key Input ─────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		return
	# Don't handle SND input when chat is open
	var level := get_parent()
	if level and level.get("_chat_focus") != null and level._chat_focus != 0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			print("[SND] F pressed, phase=", _phase, " has_peer=", multiplayer.has_multiplayer_peer())
			if _phase == Phase.READY_UP:
				if multiplayer.has_multiplayer_peer():
					_client_pressed_ready.rpc_id(1)
				else:
					# Solo editor bypass — simulate server-side ready
					player_pressed_ready(1)
				get_viewport().set_input_as_handled()
