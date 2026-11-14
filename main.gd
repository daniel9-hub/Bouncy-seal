extends Node2D

const CAMERA_START_SPEED := 180.0
const CAMERA_MAX_SPEED := 370.0
const CAMERA_ACCELERATION := 8.0
const LEFT_EDGE_GRACE := 12.0
const SCORE_PIXELS_PER_POINT := 96.0
const CAMERA_MAX_SHAKE := Vector2(7.0, 4.0)
const CAMERA_TRAUMA_DECAY := 2.8
const CAMERA_MAX_SPEED_ZOOM := 0.94
const CAMERA_ZOOM_RECOVERY := 9.0
const ZOOM_PUNCH_DECAY := 0.18
const CAMERA_SURFACE_OFFSET_Y := -220.0
const CAMERA_VERTICAL_FOLLOW_SPEED := 3.4
const MOVE_KEY_CHANGE_INTERVAL := 8.0
const MOVE_KEY_POOL := [
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
	"N", "O", "P", "Q", "S", "T", "U", "V", "W", "X", "Y", "Z",
]

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Player/Camera2D
@onready var level: Node2D = $Level
@onready var score_label: Label = $UI/Score
@onready var move_key_label: Label = $UI/MoveKey
@onready var move_key_timer_label: Label = $UI/MoveKeyTimer
@onready var new_key_alert: Label = $UI/NewKeyAlert
@onready var death_sound: AudioStreamPlayer = $DeathSound
@onready var move_key_tick_sound: AudioStreamPlayer = $MoveKeyTickSound

var _restarting := false
var _camera_speed := CAMERA_START_SPEED
var _score_start_x := 0.0
var _furthest_player_x := 0.0
var _score_points := 0
var _camera_trauma := 0.0
var _zoom_punch := 0.0
var _move_key := "D"
var _move_key_time_remaining := MOVE_KEY_CHANGE_INTERVAL
var _last_move_key_second := int(MOVE_KEY_CHANGE_INTERVAL)
var _score_tween: Tween
var _move_key_tween: Tween
var _move_key_timer_tween: Tween
var _new_key_alert_tween: Tween
var _fx_rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Aus der Player-Kamera wird zur Laufzeit eine unabhaengige Runner-Kamera.
	camera.reparent(self, true)
	camera.global_position = Vector2(576.0, 300.0)
	camera.position_smoothing_enabled = false
	level.player_died.connect(_restart_game)
	player.connect(&"bounced", _on_player_bounced)
	player.connect(&"slide_boosted", _on_player_slide_boosted)
	player.connect(&"knocked_back", _on_player_knocked_back)
	_fx_rng.randomize()
	_set_move_key("D", false)
	_score_start_x = player.global_position.x
	_furthest_player_x = _score_start_x
	score_label.pivot_offset = score_label.size * 0.5
	move_key_label.pivot_offset = move_key_label.size * 0.5
	move_key_timer_label.pivot_offset = move_key_timer_label.size * 0.5
	new_key_alert.pivot_offset = new_key_alert.size * 0.5
	_update_score()


func _process(delta: float) -> void:
	if _restarting:
		return

	# Jede Sekunde wird die Kamera etwas schneller, bis zum fairen Maximum.
	_camera_speed = minf(_camera_speed + CAMERA_ACCELERATION * delta, CAMERA_MAX_SPEED)
	camera.global_position.x += _camera_speed * delta
	_update_move_key_timer(delta)
	_update_camera_vertical(delta)
	_update_camera_effects(delta)
	_update_score()
	var half_view_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var camera_left_edge := camera.global_position.x - half_view_width

	if player.global_position.x < camera_left_edge + LEFT_EDGE_GRACE:
		_restart_game()
	elif player.global_position.y > 760.0:
		_restart_game()
	elif Input.is_action_just_pressed("restart"):
		_restart_game(false)


func _update_score() -> void:
	# Rueckstoss darf den Punktestand nicht wieder verkleinern.
	_furthest_player_x = maxf(_furthest_player_x, player.global_position.x)
	var points := maxi(0, int((_furthest_player_x - _score_start_x) / SCORE_PIXELS_PER_POINT))
	score_label.text = str(points)
	if points > _score_points:
		_score_points = points
		_pulse_score(points % 10 == 0)


func _update_move_key_timer(delta: float) -> void:
	_move_key_time_remaining -= delta
	if _move_key_time_remaining <= 0.0:
		_change_move_key()
	var seconds_remaining := maxi(1, ceili(_move_key_time_remaining))
	move_key_timer_label.text = "KEY CHANGES IN %d%s" % [
		seconds_remaining,
		"!" if seconds_remaining <= 4 else "",
	]
	move_key_timer_label.modulate = (
		Color(1.0, 0.3, 0.22, 1.0)
		if seconds_remaining <= 2
		else Color(1.0, 0.78, 0.18, 1.0)
		if seconds_remaining <= 4
		else Color.WHITE
	)
	if seconds_remaining != _last_move_key_second:
		_last_move_key_second = seconds_remaining
		if seconds_remaining <= 4:
			_pulse_key_warning()
		if seconds_remaining == 3:
			move_key_tick_sound.play()


func _change_move_key() -> void:
	var next_key := _move_key
	while next_key == _move_key:
		next_key = MOVE_KEY_POOL[_fx_rng.randi_range(0, MOVE_KEY_POOL.size() - 1)]
	_set_move_key(next_key, true)
	_move_key_time_remaining = MOVE_KEY_CHANGE_INTERVAL
	_last_move_key_second = int(MOVE_KEY_CHANGE_INTERVAL)
	move_key_tick_sound.stop()


func _set_move_key(letter: String, animate: bool = true) -> void:
	_move_key = letter
	InputMap.action_erase_events(&"right")
	var key_event := InputEventKey.new()
	key_event.keycode = OS.find_keycode_from_string(letter)
	InputMap.action_add_event(&"right", key_event)
	move_key_label.text = "MOVE  [ %s ]" % letter
	if not animate:
		return
	if _move_key_tween and _move_key_tween.is_valid():
		_move_key_tween.kill()
	move_key_label.scale = Vector2(1.18, 1.18)
	_move_key_tween = create_tween()
	_move_key_tween.tween_property(
		move_key_label,
		"scale",
		Vector2.ONE,
		0.22
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_new_key_alert(letter)


func _pulse_key_warning() -> void:
	if _move_key_timer_tween and _move_key_timer_tween.is_valid():
		_move_key_timer_tween.kill()
	move_key_timer_label.scale = Vector2.ONE
	_move_key_timer_tween = create_tween()
	_move_key_timer_tween.tween_property(
		move_key_timer_label,
		"scale",
		Vector2.ONE * 1.28,
		0.08
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_key_timer_tween.tween_property(
		move_key_timer_label,
		"scale",
		Vector2.ONE,
		0.2
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_new_key_alert(letter: String) -> void:
	if _new_key_alert_tween and _new_key_alert_tween.is_valid():
		_new_key_alert_tween.kill()
	new_key_alert.text = "NEW KEY!\n[ %s ]" % letter
	new_key_alert.visible = true
	new_key_alert.modulate = Color.WHITE
	new_key_alert.scale = Vector2.ONE * 0.7
	_new_key_alert_tween = create_tween()
	_new_key_alert_tween.tween_property(
		new_key_alert,
		"scale",
		Vector2.ONE * 1.15,
		0.14
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_new_key_alert_tween.tween_property(new_key_alert, "scale", Vector2.ONE, 0.1)
	_new_key_alert_tween.tween_interval(0.75)
	_new_key_alert_tween.tween_property(new_key_alert, "modulate:a", 0.0, 0.25)
	_new_key_alert_tween.tween_callback(new_key_alert.hide)


func _pulse_score(is_milestone: bool) -> void:
	if _score_tween and _score_tween.is_valid():
		_score_tween.kill()
	score_label.scale = Vector2.ONE
	var pop_scale := 1.2 if is_milestone else 1.1
	_score_tween = create_tween()
	_score_tween.tween_property(score_label, "scale", Vector2.ONE * pop_scale, 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_score_tween.tween_property(score_label, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_milestone:
		_add_camera_impact(0.2, 0.008)


func _update_camera_effects(delta: float) -> void:
	_camera_trauma = move_toward(_camera_trauma, 0.0, CAMERA_TRAUMA_DECAY * delta)
	_zoom_punch = move_toward(_zoom_punch, 0.0, ZOOM_PUNCH_DECAY * delta)
	var shake_strength := _camera_trauma * _camera_trauma
	camera.offset = Vector2(
		roundf(_fx_rng.randf_range(-CAMERA_MAX_SHAKE.x, CAMERA_MAX_SHAKE.x) * shake_strength),
		roundf(_fx_rng.randf_range(-CAMERA_MAX_SHAKE.y, CAMERA_MAX_SHAKE.y) * shake_strength)
	)
	var speed_ratio := inverse_lerp(CAMERA_START_SPEED, CAMERA_MAX_SPEED, _camera_speed)
	var target_zoom := lerpf(1.0, CAMERA_MAX_SPEED_ZOOM, speed_ratio) + _zoom_punch
	camera.zoom = camera.zoom.lerp(
		Vector2.ONE * target_zoom,
		minf(1.0, CAMERA_ZOOM_RECOVERY * delta)
	)


func _update_camera_vertical(delta: float) -> void:
	var surface_y: float = level.call("get_camera_surface_y", player.global_position.x)
	var target_camera_y := surface_y + CAMERA_SURFACE_OFFSET_Y
	camera.global_position.y = lerpf(
		camera.global_position.y,
		target_camera_y,
		minf(1.0, CAMERA_VERTICAL_FOLLOW_SPEED * delta)
	)


func _add_camera_impact(trauma: float, zoom_punch: float) -> void:
	_camera_trauma = maxf(_camera_trauma, trauma)
	_zoom_punch = maxf(_zoom_punch, zoom_punch)


func _on_player_bounced() -> void:
	_add_camera_impact(0.22, 0.012)


func _on_player_slide_boosted() -> void:
	_add_camera_impact(0.62, 0.035)


func _on_player_knocked_back() -> void:
	_add_camera_impact(0.88, 0.025)


func _restart_game(play_death_sound: bool = true) -> void:
	if _restarting:
		return
	_restarting = true
	player.process_mode = Node.PROCESS_MODE_DISABLED
	move_key_tick_sound.stop()
	if play_death_sound and death_sound.stream:
		death_sound.finished.connect(_reload_game, CONNECT_ONE_SHOT)
		death_sound.play()
	else:
		_reload_game()


func _reload_game() -> void:
	get_tree().call_deferred("reload_current_scene")
