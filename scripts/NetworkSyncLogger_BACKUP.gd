extends Node

## NetworkSyncLogger.gd
## Logs network synchronization — position updates, message frequency, dropped packets.

func log_position_sent(player: String, position: Vector3, tick: int) -> void:
	SessionLogger.log_event("network_sync", "SENT | Player: %s | Pos: %s | Tick: %d" % [player, position, tick])
	SessionLogger.record_sync(true)

func log_position_received(player: String, position: Vector3, tick: int) -> void:
	SessionLogger.log_event("network_sync", "RECV | Player: %s | Pos: %s | Tick: %d" % [player, position, tick])
	SessionLogger.record_sync(false)

func log_packet_loss(player: String, expected_tick: int, received_tick: int) -> void:
	var dropped := received_tick - expected_tick
	SessionLogger.log_event("network_sync", "PACKET LOSS | Player: %s | Expected tick: %d | Got tick: %d | Dropped: %d" % [player, expected_tick, received_tick, dropped])

func log_sync_error(player: String, detail: String) -> void:
	SessionLogger.log_event("network_sync", "SYNC ERROR | Player: %s | %s" % [player, detail])

func log_peer_connected(peer_id: int, username: String) -> void:
	SessionLogger.log_event("network_sync", "PEER CONNECTED | ID: %d | Username: %s" % [peer_id, username])

func log_peer_disconnected(peer_id: int, username: String) -> void:
	SessionLogger.log_event("network_sync", "PEER DISCONNECTED | ID: %d | Username: %s" % [peer_id, username])
