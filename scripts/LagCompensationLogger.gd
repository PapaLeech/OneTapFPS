extends Node

## LagCompensationLogger.gd
## Logs ping, timestamp deltas, rewind events, and hit validation results.

func log_ping(player: String, ping_ms: float) -> void:
	SessionLogger.log_event("lag_compensation", "PING | Player: %s | %.1f ms" % [player, ping_ms])
	SessionLogger.record_ping(ping_ms)

func log_timestamp_delta(player: String, client_time: float, server_time: float) -> void:
	var delta := abs(client_time - server_time) * 1000.0
	SessionLogger.log_event("lag_compensation", "TIMESTAMP DELTA | Player: %s | Delta: %.1f ms" % [player, delta])

func log_rewind(target: String, rewind_ms: float, rewound_pos: Vector3) -> void:
	SessionLogger.log_event("lag_compensation", "REWIND | Target: %s | Rewound: %.1f ms | Pos: %s" % [target, rewind_ms, rewound_pos])

func log_hit_validated(shooter: String, target: String, result: bool, ping_ms: float) -> void:
	var outcome := "VALID" if result else "REJECTED"
	SessionLogger.log_event("lag_compensation", "HIT VALIDATION | %s -> %s | %s | Ping: %.1f ms" % [shooter, target, outcome, ping_ms])

func log_compensation_applied(player: String, compensation_ms: float) -> void:
	SessionLogger.log_event("lag_compensation", "COMPENSATION | Player: %s | Applied: %.1f ms" % [player, compensation_ms])
