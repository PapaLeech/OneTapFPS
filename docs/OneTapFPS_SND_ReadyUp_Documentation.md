# OneTapFPS — Search & Destroy Ready-Up Mode Documentation

## Overview

The Search & Destroy (SND) mode is implemented in `res://scripts/modes/SearchAndDestroy.gd`, attached as a child node (`SearchAndDestroyController`) inside `snd_level_001.tscn`. It is completely isolated from Deathmatch (`level_001.tscn`). The entire mode is server-authoritative — all state changes happen on the server and are broadcast to clients via RPC.

---

## Scene Location

```
snd_level_001.tscn (uses level_001.gd as root script)
└── SearchAndDestroyController (Node, SearchAndDestroy.gd)
├── TeamA_SpawnMarker (Node3D, group: "TeamA_Spawn")
├── TeamB_SpawnMarker (Node3D, group: "TeamB_Spawn")
└── HUDLayer (CanvasLayer, layer=64)       ← chat + health bar
```

The `SearchAndDestroyController` node runs `SearchAndDestroy.gd` which manages all SND UI and game logic.

---

## Constants (tunable)

```gdscript
const ROUNDS_TO_WIN      : int   = 3      # First to 3 rounds wins
const TEAM_SIZE          : int   = 3      # Players per team
const READY_UP_DURATION  : float = 120.0  # 2-minute ready-up window
const READY_UP_COUNTDOWN : float = 5.0    # Countdown before round start
const ROUND_TIME         : float = 120.0  # 2-minute round timer
const ROUND_END_PAUSE    : float = 3.0    # Pause after round end announcement
```

---

## Game Phases

```gdscript
enum Phase { READY_UP, COUNTDOWN, ROUND_ACTIVE, ROUND_END, MATCH_END }
```

| Phase | Description |
|-------|-------------|
| `READY_UP` | Players press F to ready up. 2-minute window. |
| `COUNTDOWN` | All ready (or timeout) — 5-second countdown before spawn |
| `ROUND_ACTIVE` | Round in progress, 2-minute timer running |
| `ROUND_END` | Round over, brief pause before next round or match end |
| `MATCH_END` | Match over, end scoreboard shown |

---

## Ready-Up Panel (UI)

The ready-up panel is built entirely in code. It is centred on screen.

### Visual Style
- **Panel**: `Color(0.12, 0.12, 0.12, 0.97)`, 1px border `Color(0.4, 0.4, 0.4)`, 4px corners, shadow size 8
- **Title bar**: `Color(0.08, 0.08, 0.08)`, 32px tall, text "Ready Up", white, 14pt, centred
- **Min width**: 340px
- **Mouse filter**: `MOUSE_FILTER_IGNORE` — never blocks player movement or camera

### Contents (top to bottom)
1. Title bar — "Ready Up"
2. Instruction label — "Press F to Ready Up", 13pt, `Color(0.85, 0.85, 0.85)`
3. Count label — "Players Ready: X / Y", 12pt, grey
4. Divider — `Color(0.4, 0.4, 0.4, 0.4)`, 1px
5. Player list — one row per player, checkbox + username
6. Bottom padding — 8px

### Player List Rows
Each row shows:
- `[✓]` in green `Color(0.2, 1.0, 0.2)` if ready, `[ ]` in grey if not
- Player username, white, 13pt, centred

### Key Binding
| Key | Action |
|-----|--------|
| `F` | Toggle ready (sends `_client_pressed_ready` RPC to server) |

---

## HUD Canvas

```gdscript
_hud_canvas = CanvasLayer.new()
_hud_canvas.layer = 64
```

The HUD canvas is added to the parent level node (`snd_level_001`) and contains three UI elements:

| Element | Position | Purpose |
|---------|----------|---------|
| `_ready_up_panel` | Centre screen | Ready-up panel |
| `_center_label` | Centre screen | "MATCH STARTS IN X", "ROUND 1", etc. |
| `_round_timer_label` | Top centre, offset 12px | "M:SS" countdown |

---

## Centre Label

- Anchor: `PRESET_CENTER`
- Font size: 32pt, white
- Hidden by default, shown via `_show_center_label(text)`
- Messages: "MATCH STARTS IN X", "READY IN X", "ROUND N", "ROUND WON – TEAM A/B"

---

## Round Timer Label

- Anchor: `PRESET_CENTER_TOP`, offset_top = 12px
- Font size: 20pt, white
- Format: `"%d:%02d" % [mins, secs]`
- Hidden during ready-up and countdown, shown during `ROUND_ACTIVE`

---

## Ready-Up Flow (Server-Authoritative)

```
Client presses F
    → _client_pressed_ready.rpc_id(1)
        → server: player_pressed_ready(peer_id)
            → _ready_players[peer_id] = true
            → check if ALL peers ready
                → if yes: _begin_countdown(true)
                → if no: continue waiting
```

The server broadcasts state every frame during `READY_UP` via:
```gdscript
_sync_ready_up_state.rpc(timed_out, seconds_remaining, var_to_bytes(_ready_players))
```

Clients receive this and call `_update_ready_up_ui(seconds_remaining, ready_dict)`.

---

## Countdown Flow

```
_begin_countdown(all_ready)
    → _phase = COUNTDOWN
    → _notify_countdown_start.rpc(all_ready)
        → clients: hide ready-up panel
        → clients: show "MATCH STARTS IN 5"
    → _process: countdown runs 5 → 0
    → _start_round()
```

---

## Round Flow

```
_start_round()
    → _phase = ROUND_ACTIVE
    → _spawn_teams()          ← teleport players to team spawns
    → _notify_round_start.rpc(round_num)
        → clients: show "ROUND N"
        → clients: show round timer
        → clients: unfreeze player (set_physics_process, set_process_input)
```

---

## Team Spawning

Team spawn positions are read from scene groups:
- `TeamA_Spawn` → `TeamA_SpawnMarker` node in `snd_level_001.tscn`
- `TeamB_Spawn` → `TeamB_SpawnMarker` node in `snd_level_001.tscn`

Players are teleported via:
```gdscript
@rpc("authority", "call_local", "reliable")
func _teleport_peer(peer_id: int, pos: Vector3) -> void:
    var player := level.get_node_or_null(str(peer_id))
    if player:
        player.global_position = pos + Vector3(0, 1.0, 0)
```

Team assignment comes from `level_001.gd`'s `_stats[peer_id]["team"]` — "A" or "B".

---

## End Scoreboard (Victory / Defeat)

Shown after the match ends. Fades in over 0.5s.

### Visual Style
- Same panel style as ready-up (dark, bordered)
- **Min width**: 520px, centred
- Title bar: 36px, "VICTORY" in green `Color(0.2, 1.0, 0.2)` or "DEFEAT" in red `Color(1.0, 0.2, 0.2)`
- Fade-in: tween `modulate.a` from 0 → 1 over 0.5s (`Tween.EASE_OUT`)

### Match Summary Section
Shows top performers:
- Most Kills: `name (count)`
- Most Assists: `name (count)`
- Most Headshots: `name (count)`

### Player Table Columns
| Column | Width |
|--------|-------|
| PLAYER | 180px |
| K | 55px |
| D | 55px |
| A | 55px |
| HS | 55px |
| PING | 80px |

Players sorted by kills descending, split by Team A / Team B.

---

## Solo Test Mode (Editor Only)

When running in the Godot editor without a server connection (`OS.is_debug_build() and not multiplayer.has_multiplayer_peer()`), the controller starts in solo test mode:

```gdscript
func _start_solo_test() -> void:
    _is_solo = true
    _phase = Phase.READY_UP
    # Press F to ready up locally
```

In solo mode, all RPC calls are bypassed and UI is updated directly. This allows testing the full SND flow without deploying to the server.

---

## Mode Activation Flow (Main Menu → SND)

```
Player clicks SND button
    → main_menu.gd: _on_mode_clicked(event, Mode.SEARCH_AND_DESTROY)
    → _start_countdown(Mode.SEARCH_AND_DESTROY)
    → _load_mode()
        → ClientToServer.request_snd_mode()
            → c_request_snd_mode.rpc_id(1)
                → server: MultiplayerManager.set_mode("snd")
                    → server.gd: set_mode("snd")
                        → get_tree().change_scene_to_file("res://levels/snd_level_001.tscn")
        → get_tree().change_scene_to_file("res://levels/snd_map_splash.tscn")
```

The SND map splash (`snd_map_splash.tscn`) shows a progress bar and the map thumbnail for 2 seconds, then loads `snd_level_001.tscn`.

---

## Key RPCs

| RPC | Direction | Purpose |
|-----|-----------|---------|
| `_client_pressed_ready` | Client → Server | Player pressed F |
| `_sync_ready_up_state` | Server → All | Broadcast ready state every frame |
| `_notify_countdown_start` | Server → All | Begin countdown |
| `_sync_countdown` | Server → All | Update countdown display |
| `_notify_round_start` | Server → All | Round begins |
| `_sync_round_timer` | Server → All | Update round timer display |
| `_notify_round_end` | Server → All | Round over, who won |
| `_notify_match_end` | Server → All | Match over, show end scoreboard |
| `_teleport_peer` | Server → All | Move player to spawn position |

---

## Important Notes for Other AI

1. **SearchAndDestroy.gd is completely isolated** from Deathmatch. Never modify `level_001.gd` to add SND logic.
2. **TeamA_Spawn and TeamB_Spawn groups** must be assigned to spawn marker nodes in `snd_level_001.tscn` or `_spawn_teams()` will fail silently.
3. **The HUD canvas is added via `call_deferred`** and awaits `child_entered_tree` before building UI — this prevents "parent busy" crashes on scene load.
4. **`Input.mouse_mode = MOUSE_MODE_CAPTURED`** is set in `_build_hud()` — this is required for player camera movement during ready-up.
5. **`MOUSE_FILTER_IGNORE`** is set on the ready-up panel — it must never block mouse input to the game.
6. The player is **NOT frozen during ready-up** — `_set_local_player_frozen(false)` is called on round start (after countdown). Players can move freely during ready-up.
7. **`c_request_snd_mode` RPC** must exist in both client and server PCKs or the server will never switch to `snd_level_001.tscn`.
8. The server calls `set_mode("snd")` on `MultiplayerManager` (server.gd) which triggers `change_scene_to_file` to reload the scene.
9. SND uses `level_001.gd` as the root script of `snd_level_001.tscn` — this gives it access to the existing spawn, stats, ping, chat, and scoreboard systems.
