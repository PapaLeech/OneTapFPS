# OneTapFPS — Scoreboard Documentation

## Overview

The Deathmatch scoreboard is a dynamically built overlay in `level_001.gd`. It appears when the player holds **Tab** and shows live kills, deaths, assists, and ping for all players split into Team A and Team B. It uses a software cursor for right-click interaction while open.

---

## Architecture

The scoreboard is **entirely code-generated** — no scene nodes. It is created in `_setup_scoreboard()` called from `_ready()` on the client side.

```
Node3D (level_001.gd)
└── [dynamic] CanvasLayer (_scoreboard_canvas, layer=128)
    ├── PanelContainer (_scoreboard_panel)  ← main scoreboard panel
    └── Label (_software_cursor)            ← software arrow cursor ▶
```

**CanvasLayer layer = 128** — above death menu, pause menu, and chat (layer 64).

---

## Visual Style

All UI uses a consistent dark panel aesthetic:

| Property | Value |
|----------|-------|
| Background | `Color(0.12, 0.12, 0.12, 0.97)` |
| Border | `Color(0.4, 0.4, 0.4, 1.0)`, 1px all sides |
| Corner radius | 4px all corners |
| Shadow | `Color(0,0,0,0.8)`, size 8 |
| Min width | 520px |
| Anchor | `PRESET_CENTER` — dead centre of screen |

**Title bar**: `Color(0.08, 0.08, 0.08, 1.0)`, 32px tall, text "DEATHMATCH" centred, white, 14pt.

**Team headers**: `Color(0.18, 0.18, 0.18, 1.0)`, 24px tall, team name left-aligned, grey, 11pt.

**Player rows**: 28px tall, white text 13pt. Header row grey 11pt.

---

## Column Layout

| Column | Width | Alignment |
|--------|-------|-----------|
| PLAYER | 220px | Left |
| K (Kills) | 60px | Centre |
| D (Deaths) | 60px | Centre |
| A (Assists) | 60px | Centre |
| PING | 80px | Centre |

Each team shows up to 6 player slots. Empty slots fill with blank rows to maintain consistent height.

---

## Key Bindings

| Key | Action |
|-----|--------|
| `Tab` (hold) | Show scoreboard |
| `Tab` (release) | Hide scoreboard |
| `Right-click` (while open) | Toggle software cursor on/off |

---

## Software Cursor

When right-clicking while the scoreboard is open, a software cursor (▶ Unicode arrow label) appears. The cursor position is tracked via `_cursor_pos : Vector2` and updated in `_process()`. This allows clicking UI elements while in MOUSE_MODE_CAPTURED.

```gdscript
var _software_cursor : Control = null
var _cursor_pos      : Vector2 = Vector2(640, 360)
var _scoreboard_cursor : bool  = false
```

The cursor label:
- Text: `"\u25B6"` (▶)
- Font size: 20pt, white
- `MOUSE_FILTER_IGNORE` — never blocks input
- Hidden by default, shown when `_scoreboard_cursor = true`

---

## Stats System

Stats are stored in `_stats : Dictionary` on `level_001.gd`:

```gdscript
_stats[peer_id] = {
    "username": String,
    "kills":    int,
    "deaths":   int,
    "assists":  int,
    "ping":     int,
    "team":     "A" or "B"
}
```

### Stat Updates

| Event | Function | Who calls it |
|-------|----------|-------------|
| Player joins | `_on_player_connected_respawn()` | Server |
| Kill/death | `record_kill(killer_id, victim_id)` | `hitbox.gd` |
| Assist | `record_assist(assister_id)` | `health.gd` |
| Ping update | `_update_ping(peer_id, rtt)` | Client via RPC |
| Sync to all | `_sync_stats.rpc(var_to_bytes(_stats))` | Server |

### Team Assignment

Teams are balanced on join:
```gdscript
var team := "A" if team_a <= team_b else "B"
```

Players are never reassigned after initial join (stats persist through respawn).

---

## Ping System

Ping is measured as round-trip time (RTT) using a 1-second timer:

1. Client sends `_ping_request.rpc_id(1)` — records `_ping_sent_at`
2. Server immediately responds `_ping_response.rpc_id(sender)`
3. Client calculates `rtt = Time.get_ticks_msec() - _ping_sent_at`
4. Client sends `_update_ping.rpc_id(1, my_id, rtt)` to server
5. Server updates `_stats[peer_id]["ping"]` and broadcasts `_sync_stats`

---

## Key Functions

| Function | Purpose |
|----------|---------|
| `_setup_scoreboard()` | Creates CanvasLayer, panel, software cursor |
| `_show_scoreboard()` | Makes panel visible, rebuilds content |
| `_hide_scoreboard()` | Hides panel and software cursor |
| `_rebuild_scoreboard()` | Clears and rebuilds all rows from `_stats` |
| `_make_row(...)` | Returns HBoxContainer row with 5 columns |
| `_make_team_header(name)` | Returns coloured team section header |
| `record_kill(killer, victim)` | Updates kills/deaths, syncs to all |
| `record_assist(assister)` | Updates assists, syncs to all |
| `_sync_stats(data)` | RPC — receives stats update on all peers |

---

## Important Notes for Other AI

1. The scoreboard is **100% dynamically generated** — no scene nodes. Do NOT try to find it in `level_001.tscn`.
2. **CanvasLayer layer = 128** — must be above 64 (chat) and above death/pause menus (~10).
3. `_rebuild_scoreboard()` calls `queue_free()` on all children then rebuilds — this is intentional to refresh live stats.
4. The scoreboard panel has `MOUSE_FILTER_IGNORE` — it never blocks mouse input.
5. The software cursor is a workaround for MOUSE_MODE_CAPTURED — it's a Label node positioned by `_process()`, not a real OS cursor.
6. Stats persist through player respawn — `if not _stats.has(peer_id)` guards against overwrite.
7. The scoreboard is **client-only** — the dedicated server skips `_setup_scoreboard()`.
