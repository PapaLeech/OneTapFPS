# 1Deag — Server-Authoritative Shot Registration Architecture
## SNDv72 (commit 57078f7) — June 23 2026

This document describes the complete server-side hit registration system for the 1Deag FPS game (Godot 4.6.2). It is intended for any AI assistant continuing work on this project.

---

## Project Overview

- **Game**: 1Deag — dedicated-server multiplayer FPS, Search and Destroy mode
- **Engine**: Godot 4.6.2
- **Server**: DigitalOcean droplet at `161.35.41.206`, service `onetap-game.service` (ENet, port 7777)
- **SSH**: `onetap@161.35.41.206`, game runs as user `1deag`
- **Game log**: `~/gameserver/server.log` on server
- **Deploy scripts**: `~/Documents/deploy_server_and_client.sh`, `~/Documents/deploy_server_only.sh`
- **Git backup**: `~/Documents/git_backup.sh SND`
- **Repo**: `github.com/PapaLeech/OneTapFPS`

---

## Key File Paths

| File | Purpose |
|---|---|
| `res://controllers/player.gd` | Player controller — camera, movement, shot RPC, calibration |
| `res://controllers/player.tscn` | Player scene — CameraController, Camera3D, hitbox hierarchy |
| `res://scripts/LagCompensator.gd` | Server-side lag compensation, history snapshots, hit detection |
| `res://assets/scripts/health.gd` | Health system — damage application, died signal |
| `res://assets/weapons/scripts/weapon_controller.gd` | Client-side weapon firing, ray origin calculation |
| `res://scripts/modes/SearchAndDestroy.gd` | SND game mode — round flow, spawn, revive, health reset |
| `res://scripts/server.gd` | Multiplayer server — lobby management, session reset |
| `res://levels/snd_level_001.tscn` | SND map — TeamA_SpawnMarker Y=1.0, TeamB_SpawnMarker Y=1.0 |

---

## Shot Registration Flow

### Client Side (`weapon_controller.gd`)
1. Player fires weapon
2. Client performs local raycast for visual feedback (bullet decals etc.)
3. Client sends to server via RPC:
   - `ray_origin` = `_camera.global_position` (Camera3D world position)
   - `aim_dir` = `-_camera.global_transform.basis.z` (camera forward vector)
   - `shot_time` = `Time.get_ticks_usec() / 1_000_000.0` (uptime seconds, same basis as server)
   - `damage` = weapon damage value (AK47 = 30)

### Server Side (`player.gd` → `LagCompensator.gd`)
1. `_server_shot` RPC received
2. **Camera calibration correction applied**: `apply_camera_offset(shooter_id, origin)` corrects ray origin Y to match client's actual camera world Y
3. `LagCompensator.check_hit()` called with corrected origin, direction, shot_time
4. Lag compensator calculates `latency = ENet RTT / 2` (from `ENetPacketPeer.PEER_ROUND_TRIP_TIME`)
5. `target_time = now - latency` used to rewind player history
6. Server rewinds target player to their position at `target_time`
7. Raycast fires against rewound `Area3D` hitboxes (`collide_with_bodies=false`, `collide_with_areas=true`)
8. If hit: `hitbox.take_damage(damage)` called

---

## Camera Calibration System (SNDv72 addition)

**Problem**: Client camera world Y differs from server's computed camera Y due to physics settling differences between machines.

**Solution**: After each `revive()` call, client waits one physics frame then sends its actual `CAMERA_CONTROLLER.global_position.y` to the server.

```gdscript
# In player.gd revive():
await get_tree().physics_frame
_send_camera_calibration.rpc_id(1, CAMERA_CONTROLLER.global_position.y)
```

Server stores this per-peer in `LagCompensator._camera_offsets` dictionary. On every shot, `apply_camera_offset()` replaces the ray origin Y with the stored client camera Y.

**Log tag**: `[CalibDebug]` — prints peer camera_world_Y on registration and corrected Y on each shot.

---

## Health & Death System (`health.gd`)

**Critical fix**: In server-authoritative mode, `take_damage()` must apply damage on BOTH the server AND the client.

```gdscript
func take_damage(amount: float) -> void:
    if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
        var authority_id := get_multiplayer_authority()
        _take_damage_rpc.rpc_id(authority_id, amount, "unknown", -1)  # client HUD update
        _apply_damage(amount)  # server health tracking + died signal for SND
        return
    _apply_damage(amount)
```

Without the server-side `_apply_damage()`, the `died` signal only fires on the client and the SND controller (running on server) never ends the round.

---

## Skeleton Animation Sync

**Problem**: Server headless mode disables skeleton updates, leaving hitboxes frozen at rest/T-pose positions.

**Fixes applied**:

1. **Force skeleton physics update** (in `player.gd _ready()`, server path before early return):
```gdscript
var skeleton := get_node_or_null("CollisionShape3D/PlayerModel/Armature/Skeleton3D") as Skeleton3D
if skeleton:
    skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
```

2. **Animation time sync**: `_send_state` RPC includes `anim_time` (current `AnimationPlayer.current_animation_position`). Server calls `anim_player.seek(anim_time, true)` in `_update_remote_animation()`.

3. **`_receive_state` is `call_local`**: So when server broadcasts state to clients, it also processes it locally — updating its own copies of player node animations.

---

## LagCompensator Key Details

- **Clock**: Both sides use `Time.get_ticks_usec() / 1_000_000.0` (uptime seconds). Do NOT use `Time.get_unix_time_from_system()` — cross-machine clock mismatch causes 63+ second latency rejection.
- **Latency**: Uses `ENetMultiplayerPeer.get_peer(id).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 2000.0` — actual network RTT, not clock comparison.
- **Raycast**: `collide_with_bodies = false`, `collide_with_areas = true`, `collision_mask = 1`. Rays pass through world geometry and only detect `Area3D` hitboxes.
- **Session reset**: `clear_history()` and `_camera_offsets.clear()` called when all players disconnect.
- **Physics**: `set_physics_process(false)` removed from `_save_player_state()` — was permanently disabling player nodes when they died mid-hitcheck.

---

## Player Scene Hierarchy (player.tscn)

```
CharacterBody3D  [scale 1.5,1.5,1.5 in file — stripped to 1.0 at runtime by physics]
├── CollisionShape3D  [CapsuleShape3D height=2.0, radius=0.286, position Y=1.5]
│   └── PlayerModel  [Y=-1.0 local, contains mesh + skeleton]
│       └── Armature  [scale 0.012, rotation X=90°]
│           └── Skeleton3D
│               ├── Ch15  [mesh]
│               ├── HitboxHead  [BoneAttachment3D → mixamorig_Head]
│               │   └── Area3D → CollisionShape3D (SphereShape3D)
│               ├── HitboxSpine  [BoneAttachment3D]
│               ├── HitboxLeftArm / HitboxRightArm
│               ├── HitboxLeftForearm / HitboxRightForearm
│               ├── HitboxLeftHand / HitboxRightHand
│               ├── HitboxLeftLeg / HitboxRightLeg
│               ├── HitboxLeftCalf / HitboxRightCalf
│               └── HitboxLeftFoot / HitboxRightFoot
├── CameraController  [Node3D, Y=1.2 local]
│   └── Camera3D  [Y=0.95 local, Z=-0.17]
└── [weapons, health, other nodes]
```

### Damage Multipliers (set manually in Inspector on each hitbox's Area3D)
| Hitbox | Multiplier |
|---|---|
| HitboxHead | 3.5× |
| HitboxSpine | 1.0× |
| Arms, Forearms, Hands, Legs, Calves, Feet | 0.75× |

AK47 base damage = 30. Headshot = 105 damage → instant kill (100 HP).

---

## Live Round Hitbox World Y Positions (SNDv72, player root at Y=1.0)

| Hitbox | World Y |
|---|---|
| HitboxHead | 3.334 |
| HitboxLeftArm / RightArm | ~3.14 |
| HitboxSpine | 2.741 |
| HitboxLeftForearm / RightForearm | ~2.91 |
| HitboxLeftHand / RightHand | ~2.91 |
| HitboxLeftLeg / RightLeg | ~2.54 |
| HitboxLeftCalf / RightCalf | ~2.06 |
| HitboxLeftFoot / RightFoot | ~1.64 |

Floor at Y=1.5. Camera eye at approximately Y=3.2 (after calibration correction).

---

## Camera Values (player.gd)

```gdscript
var _crouch_target_height : float = 1.2   # standing camera height (CameraController local Y)
# toggle_crouch() sets 1.2 (standing) or 0.7 (crouching)
# revive() sets CAMERA_CONTROLLER.position.y = 1.2
```

`_physics_process` lerps `CAMERA_CONTROLLER.position.y` toward `_crouch_target_height` every frame — this is what actually controls runtime camera height, overriding scene defaults.

---

## Debug Log Tags

| Tag | Meaning |
|---|---|
| `[ShotDebug]` | Shot received, hit result, damage applied |
| `[LagCompDebug]` | Latency, target_time, raycast result |
| `[TargetDebug]` | Target peer position and first hitbox position |
| `[RaycastDebug]` | Ray origin, direction, raw result |
| `[HitboxDebug]` | All hitbox world Y positions per shot |
| `[CalibDebug]` | Camera calibration offset registration and correction |
| `[SND]` | Round flow — death signals, round start, player died |
| `[ScaleDebug]` | Player root scale at _ready() |

---

## SND Game Mode Notes

- `revive()` called at start of each round — resets camera, enables physics, sends calibration
- `_reset_all_health()` called between rounds — broadcasts via RPC so both server and client reset
- Spawn markers: `TeamA_SpawnMarker` (group `TeamA_Spawn`) and `TeamB_SpawnMarker` (group `TeamB_Spawn`) in `snd_level_001.tscn`, both at Y=1.0
- `_teleport_peer` in `SearchAndDestroy.gd` places player at spawn marker position (no Y offset)
- Two spawn areas have different floor heights: TeamA floor ~Y=1.5, TeamB floor ~Y=2.185

---

## Known Remaining Issues

1. **Health bar visual** — not updating on client during live rounds. Off limits for now. Display-only issue, does not affect gameplay.
2. **SearchAndDestroyController node path error** — `get_node: Node not found: "Node3D/SearchAndDestroyController"` in client logs. Pre-existing, non-breaking.
3. **ScaleDebug print** — still active in `player.gd _ready()`. Remove before release.
4. **All debug prints** — `[ShotDebug]`, `[LagCompDebug]`, `[TargetDebug]`, `[RaycastDebug]`, `[HitboxDebug]`, `[CalibDebug]` all still live. Remove before release.

---

## What NOT to Change

- Hitbox shapes, sizes, positions, or bone assignments — these are correct
- `PlayerModel` Y offset (currently -1.0) — this is intentional mesh positioning
- `CharacterBody3D` scale (1.5 in scene file, 1.0 at runtime) — do not try to "fix" this
- `Armature` scale (0.012) — this is the Mixamo import scale, do not touch
- The `-basis.z` forward vector in `weapon_controller.gd` — this is correct for Godot cameras
