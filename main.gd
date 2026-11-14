extends Node2D

const CAMERA_SPEED := 165.0
const LEFT_EDGE_GRACE := 24.0

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Player/Camera2D
@onready var level: Node2D = $Level

var _restarting := false


func _ready() -> void:
	# Aus der Player-Kamera wird zur Laufzeit eine unabhaengige Runner-Kamera.
	camera.reparent(self, true)
	camera.global_position = Vector2(576.0, 300.0)
	camera.position_smoothing_enabled = false
	level.player_died.connect(_restart_game)


func _process(delta: float) -> void:
	if _restarting:
		return

	camera.global_position.x += CAMERA_SPEED * delta
	var half_view_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var camera_left_edge := camera.global_position.x - half_view_width

	if player.global_position.x < camera_left_edge + LEFT_EDGE_GRACE:
		_restart_game()
	elif player.global_position.y > 760.0:
		_restart_game()
	elif Input.is_action_just_pressed("restart"):
		_restart_game()


func _restart_game() -> void:
	if _restarting:
		return
	_restarting = true
	get_tree().call_deferred("reload_current_scene")
