extends Node

## ClientPredictionLogger.gd
## Logs client-side prediction events — input timestamps, predicted vs actual positions.

func log_input(player: String, action: String, tick: int) -> void:
	SessionLogger.log_event("client_prediction", "INPUT | Player: %s | Action: %s | Tick: %d" % [player, action, tick])

func log_prediction(player: String, predicted_pos: Vector3, actual_pos: Vector3) -> void:
	var delta := predicted_pos.distance_to(actual_pos)
	SessionLogger.log_event("client_prediction", "PREDICT | Player: %s | Predicted: %s | Actual: %s | Delta: %.3fm" % [player, predicted_pos, actual_pos, delta])

func log_correction(player: String, correction_amount: float) -> void:
	SessionLogger.log_event("client_prediction", "CORRECTION | Player: %s | Correction: %.3fm" % [player, correction_amount])

func log_reconciliation(player: String, tick: int, server_pos: Vector3) -> void:
	SessionLogger.log_event("client_prediction", "RECONCILE | Player: %s | Tick: %d | Server pos: %s" % [player, tick, server_pos])
