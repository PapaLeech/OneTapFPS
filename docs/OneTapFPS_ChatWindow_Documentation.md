# OneTapFPS — Chat Window Documentation

## Overview

The chat window is a draggable, resizable, lockable in-game panel built into `level_001.gd` (and `snd_level_001.gd`). It appears in the bottom-left of the screen and supports two tabs: **Chat** (multiplayer messaging) and **Terminal** (dev commands). The player can move freely and idle-bobs while the chat is open — only movement input is blocked, not physics.

---

## Scene Structure

The chat panel lives inside `level_001.tscn` under:

```
Node3D (level_001.gd)
└── HUDLayer (CanvasLayer)
    ├── ChatTerminalPanel (PanelContainer)
    │   └── VBox (VBoxContainer)
    │       ├── DragBar (Panel)         ← drag handle at top
    │       ├── TabBar (HBoxContainer)
    │       │   ├── ChatTab (Button)
    │       │   ├── TerminalTab (Button)
    │       │   └── LockBtn (Button)    ← lock/unlock toggle
    │       ├── ChatOutput (RichTextLabel)
    │       ├── TerminalOutput (RichTextLabel)
    │       └── InputLine (LineEdit)
    └── ResizeHandle (Button)           ← drag to resize, hidden by default, rotated 90° CW
```

**HUDLayer** must have its **Visible** property set to **true** in the scene. If it is toggled off, the entire HUD (chat + health bar) disappears.

**ResizeHandle** starts with `visible = false` and `rotation = 1.5708` (90° CW) in the scene. It is shown/hidden by `_update_lock_ui()` based on lock state.

---

## Default Position & Size

- **Anchor**: Bottom-left (`PRESET_BOTTOM_LEFT`)
- **Default position**: `offset_left = 8`, `offset_top = -212`
- **Default size**: `162 × 124` px
- **Min size**: `160 × 100` px
- **Max size**: `500 × 400` px
- Position and size are **clamped to screen bounds** on load so the panel can never go off-screen.
- Position/size/lock state are **saved per-user** via `PresenceManager.save_setting()` / `load_setting()` to `user://config.cfg` under the key prefix `settings_<username>`.

---

## Behaviour

### Visibility States
| State | `visible` | `modulate.a` |
|-------|-----------|--------------|
| Idle, no messages | `false` | `0.0` (fully hidden) |
| Idle, has messages | `true` | `0.25` (25% opacity) |
| Focused (typing) | `true` | `1.0` (fully opaque) |
| Chat disabled (death) | `false` | `0.0` |

### Key Bindings
| Key | Action |
|-----|--------|
| `Enter` | Open chat tab (if not already open) |
| `` ` `` (backtick) | Toggle between Chat and Terminal tabs |
| `Esc` | Close chat / release focus |
| `Enter` (while typing) | Send message / run command |
| `Tab` | Hold to show scoreboard (separate system) |

### Player Behaviour While Chat is Open
- Physics process **continues** — idle bobbing animation plays normally
- Movement input (`WASD`, jump, sprint) is **blocked** via `player._chat_open = true`
- Mouse mode switches to `MOUSE_MODE_VISIBLE` (cursor appears)
- On close: mouse mode returns to `MOUSE_MODE_CAPTURED`, movement re-enabled

### Chat Enable/Disable
- `set_chat_enabled(false)` is called by `player.gd` on player death — hides the panel and releases focus
- `set_chat_enabled(true)` is called by `pause_menu.gd` on respawn

---

## Drag & Resize

- **Drag**: Click and hold the `DragBar` at the top of the panel
- **Resize**: Click and hold the `ResizeHandle` (bottom-right corner)
- Both are **disabled when locked** (`_chat_locked = true`)
- Layout is **auto-saved** to `PresenceManager` when drag/resize ends

---

## Multiplayer Messaging

Messages are sent via RPC to all peers:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _send_chat_message(sender: String, message: String) -> void:
    _chat_output.append_text("[color=yellow][b]" + sender + ":[/b][/color] " + message + "\n")
```

The sender's username comes from `PresenceManager.username`.

---

## Terminal Commands

| Command | Output |
|---------|--------|
| `help` | Lists available commands |
| `clear` | Clears terminal output |
| `version` | Shows game version string |
| `ping` | Placeholder (coming soon) |

---

## Key Variables in `level_001.gd`

```gdscript
enum ChatFocus { NONE, CHAT, TERMINAL }
var _chat_focus   : ChatFocus = ChatFocus.NONE
var _chat_enabled : bool      = true
var _chat_locked  : bool      = false
var _dragging     : bool      = false
var _resizing     : bool      = false

const CHAT_MIN_SIZE : Vector2 = Vector2(160, 100)
const CHAT_MAX_SIZE : Vector2 = Vector2(500, 400)
```

---

## Key Functions

| Function | Purpose |
|----------|---------|
| `_setup_chat()` | Called from `_ready()` on client — connects signals, hides panel, calls `_setup_chat_window()` |
| `_setup_chat_window()` | Loads saved position/size/lock, clamps to screen, positions panel |
| `_switch_chat_tab(focus)` | Opens chat or terminal tab, shows panel, blocks player movement |
| `_release_chat_focus()` | Closes chat, restores mouse/movement, fades panel |
| `set_chat_enabled(bool)` | Enables/disables chat (called on death/respawn) |
| `_send_chat_message(sender, msg)` | RPC — broadcasts message to all peers |
| `_execute_chat_command(cmd)` | Runs terminal commands locally |
| `_process_chat_drag(delta)` | Called in `_process()` — handles drag and resize each frame |
| `_save_chat_layout()` | Saves position/size to PresenceManager |
| `_update_lock_ui()` | Updates lock button text and ResizeHandle visibility |

---

## Player Integration (`player.gd`)

A single flag blocks movement while keeping physics alive:

```gdscript
var _chat_open : bool = false
```

In `_physics_process`:
```gdscript
if Input.is_action_just_pressed("jump") and is_on_floor() and not _chat_open:
    velocity.y = JUMP_VELOCITY

var input_dir := Vector2.ZERO if _chat_open else Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
```

Animation RPC guard (prevents errors in solo/editor mode):
```gdscript
if multiplayer.has_multiplayer_peer():
    _update_anim_state.rpc(new_state)
```

---

## Important Notes for Other AI

1. **Never toggle HUDLayer visibility off** — this hides both the chat panel AND the health bar.
2. **ResizeHandle must start hidden** (`visible = false` in scene) — `_setup_chat_window()` controls its visibility.
3. **Chat position is saved per-user** in `user://config.cfg` via PresenceManager — deleting this file resets position to default.
4. **Do not call `set_physics_process(false)`** on the player when opening chat — use `player._chat_open = true` instead to preserve idle bobbing.
5. **`multiplayer.get_unique_id()` must be guarded** with `multiplayer.has_multiplayer_peer()` check or it crashes silently in solo/editor mode.
6. The chat system is **client-only** — the dedicated server skips `_setup_chat()` entirely.
