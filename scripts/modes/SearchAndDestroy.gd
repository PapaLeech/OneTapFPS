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

# ─── UI references (built at runtime, client-side only) ──────────────────────
var _hud_canvas        : CanvasLayer   = null
var _ready_up_panel    : PanelContainer = null
var _center_label      : Label          = null   # "MATCH STARTS IN X" / "READY IN X" / "ROUND START"
var _round_timer_label : Label          = null
var _end_scoreboard    : PanelContainer = null

# Pause-menu style shared across all SND UI panels
const PANEL_BG_COLOR     := Color(0.12, 0.12, 0.12, 0.97)
const PANEL_BORDER_COLOR := Color(0.4,  0.4,  0.4,  1.0)
const PANEL_SHADOW_COLOR := Color(0.0,  0.0,  0.0,  0.8)

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
	# End scoreboard built on demand in _show_end_scoreboard()
	# Restore chat input focus after HUD rebuild (SND HUD rebuild steals GUI focus from _input_line)
	var level := get_tree().get_root().get_node_or_null("Node3D")
	if level and level.has_node("HUDLayer/ChatTerminalPanel/VBox/InputLine"):
		var input_line := level.get_node("HUDLayer/ChatTerminalPanel/VBox/InputLine")
		if input_line.has_focus():
			input_line.grab_focus()
	# Wait two frames to let all SND UI finish building before restoring focus
	await get_tree().process_frame
	await get_tree().process_frame
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
	if not multiplayer.is_server():
		return
	if _phase != Phase.READY_UP:
		return
	_ready_players[peer_id] = true
	var all_players := multiplayer.get_peers()
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
	_spawn_teams()
	_notify_round_start.rpc(_round_number)

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
		_phase = Phase.COUNTDOWN
		_countdown_elapsed = 0.0
		_notify_countdown_start.rpc(false)

func _end_match(winning_team: int) -> void:
	_phase = Phase.MATCH_END
	var summary := _build_match_summary()
	_notify_match_end.rpc(winning_team, var_to_bytes(summary))

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

	# Spawn Team A
	for i in range(team_a_peers.size()):
		var spawn_node = team_a_spawns[i % team_a_spawns.size()]
		var pos : Vector3 = spawn_node.global_position
		_teleport_peer.rpc(team_a_peers[i], pos)

	# Spawn Team B
	for i in range(team_b_peers.size()):
		var spawn_node = team_b_spawns[i % team_b_spawns.size()]
		var pos : Vector3 = spawn_node.global_position
		_teleport_peer.rpc(team_b_peers[i], pos)

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
	var top_kills    := {"name": "—", "value": 0}
	var top_assists  := {"name": "—", "value": 0}
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
	_ready_up_panel.set_anchors_preset(Control.PRESET_CENTER)
	_ready_up_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ready_up_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_ready_up_panel.custom_minimum_size = Vector2(340, 0)
	_ready_up_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_up_panel.focus_mode = Control.FOCUS_NONE
	_ready_up_panel.visible = true
	_hud_canvas.add_child(_ready_up_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_ready_up_panel.add_child(vbox)

	# Title bar
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

	# Instruction
	var instr := Label.new()
	instr.name = "InstructionLabel"
	instr.text = "Press F to Ready Up"
	instr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr.add_theme_font_size_override("font_size", 13)
	instr.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	vbox.add_child(instr)

	# Ready count
	var count_lbl := Label.new()
	count_lbl.name = "ReadyCountLabel"
	count_lbl.text = "Players Ready: 0 / 0"
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	vbox.add_child(count_lbl)

	# Divider
	var div := ColorRect.new()
	div.color = Color(0.4, 0.4, 0.4, 0.4)
	div.custom_minimum_size = Vector2(340, 1)
	vbox.add_child(div)

	# Player list container
	var player_list := VBoxContainer.new()
	player_list.name = "PlayerList"
	player_list.add_theme_constant_override("separation", 4)
	vbox.add_child(player_list)

	# Bottom padding
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
	var total : int = stats.size()
	var ready_count : int = ready_dict.size()

	count_lbl.text = "Players Ready: %d / %d" % [ready_count, total]

	# Rebuild player list rows
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
	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_label.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 32)
	_center_label.add_theme_color_override("font_color", Color.WHITE)
	_center_label.visible = false
	_hud_canvas.add_child(_center_label)

func _show_center_label(text: String) -> void:
	if _center_label:
		_center_label.text = text
		_center_label.visible = true

func _hide_center_label() -> void:
	if _center_label:
		_center_label.visible = false

# ─── UI: Round Timer ──────────────────────────────────────────────────────────
func _build_round_timer_label() -> void:
	_round_timer_label = Label.new()
	_round_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round_timer_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_round_timer_label.offset_top = 12
	_round_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_timer_label.add_theme_font_size_override("font_size", 20)
	_round_timer_label.add_theme_color_override("font_color", Color.WHITE)
	_round_timer_label.visible = false
	_hud_canvas.add_child(_round_timer_label)

func _show_round_timer(seconds: int) -> void:
	if not _round_timer_label:
		return
	var mins := seconds / 60
	var secs := seconds % 60
	_round_timer_label.text = "%d:%02d" % [mins, secs]
	_round_timer_label.visible = true

func _hide_round_timer() -> void:
	if _round_timer_label:
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
	_end_scoreboard.modulate.a = 0.0   # Start invisible for fade-in
	_hud_canvas.add_child(_end_scoreboard)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_end_scoreboard.add_child(vbox)

	# Title ribbon
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

	# Match summary section
	var summary_vbox := VBoxContainer.new()
	summary_vbox.add_theme_constant_override("separation", 6)
	var pad_top := Control.new()
	pad_top.custom_minimum_size = Vector2(0, 10)
	summary_vbox.add_child(pad_top)
	for entry in [
		["Most Kills",      summary.get("top_kills",      {})],
		["Most Assists",    summary.get("top_assists",     {})],
		["Most Headshots",  summary.get("top_headshots",  {})],
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

	# Divider
	var div := ColorRect.new()
	div.color = Color(0.4, 0.4, 0.4, 0.5)
	div.custom_minimum_size = Vector2(520, 1)
	vbox.add_child(div)

	# Player table (reuse level_001 stats)
	var level := get_parent()
	var stats : Dictionary = level.get("_stats") if level and level.get("_stats") != null else {}
	var header := _make_score_row("PLAYER", "K", "D", "A", "HS", "PING", true)
	vbox.add_child(header)
	var div2 := ColorRect.new()
	div2.color = Color(0.4, 0.4, 0.4, 0.5)
	div2.custom_minimum_size = Vector2(520, 1)
	vbox.add_child(div2)

	for team_label in ["A", "B"]:
		var team_header := _make_team_bar("TEAM " + team_label)
		vbox.add_child(team_header)
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

	# Fade-in animation (0 → 1 over 0.5s)
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
		# Don't unfreeze if chat is open
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
		if event.keycode == KEY_F and _phase == Phase.READY_UP:
			_client_pressed_ready.rpc_id(1)
			get_viewport().set_input_as_handled()
