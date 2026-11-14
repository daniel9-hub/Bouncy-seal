extends Node2D

const CAMERA_START_SPEED := 180.0
const PLAYER_FORWARD_SPEED := 400.0
const CAMERA_PLAYER_SPEED_RATIO := 0.9
const CAMERA_MAX_SPEED := PLAYER_FORWARD_SPEED * CAMERA_PLAYER_SPEED_RATIO
const CAMERA_ACCELERATION := 8.0
const SCORE_PIXELS_PER_POINT := 96.0
const CAMERA_MAX_SHAKE := Vector2(7.0, 4.0)
const CAMERA_TRAUMA_DECAY := 2.8
const CAMERA_MAX_SPEED_ZOOM := 0.94
const CAMERA_ZOOM_RECOVERY := 9.0
const ZOOM_PUNCH_DECAY := 0.18
const CAMERA_SURFACE_OFFSET_Y := -220.0
const CAMERA_VERTICAL_FOLLOW_SPEED := 3.4
const AVALANCHE_EDGE_OFFSET := 32.0
const AVALANCHE_HEIGHT := 900.0
const AVALANCHE_BOTTOM_EXTENSION := 180.0
const AVALANCHE_FOLLOW_SPEED := 18.0
const SLIDE_QTE_TIME_SCALE := 0.42
const SLIDE_QTE_CAMERA_ZOOM := 1.15
const SLIDE_QTE_ZOOM_IN_DURATION := 0.72
const SLIDE_QTE_FADE_IN_DURATION := 0.34
const SLIDE_QTE_FADE_OUT_DURATION := 0.16
const SLIDE_QTE_MAX_REAL_SECONDS := 2.0
const MOVE_KEY_CHANGE_INTERVAL := 8.0
const CLOCK_TIME_BONUS := 4.0
const MAX_MOVE_KEY_TIME := MOVE_KEY_CHANGE_INTERVAL + CLOCK_TIME_BONUS
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
@onready var slide_qte_overlay: Control = $UI/SlideQTE
@onready var slide_qte_prompt: Label = $UI/SlideQTE/Prompt
@onready var death_sound: AudioStreamPlayer = $DeathSound
@onready var move_key_tick_sound: AudioStreamPlayer = $MoveKeyTickSound
@onready var avalanche: Area2D = $Avalanche
@onready var death_screen: Control = $UI/DeathScreen
@onready var death_score_label: Label = $UI/DeathScreen/Panel/Score
@onready var restart_button: Button = $UI/DeathScreen/Panel/Restart
@onready var pause_menu: Control = $UI/PauseMenu
@onready var resume_button: Button = $UI/PauseMenu/Panel/Resume
@onready var title_button: Button = $UI/PauseMenu/Panel/Title2

var _restarting := false
var _start_countdown_active := true
var _camera_speed := CAMERA_START_SPEED
var _score_start_x := 0.0
var _furthest_player_x := 0.0
var _score_points := 0
var _camera_trauma := 0.0
var _zoom_punch := 0.0
var _slide_qte_active := false
var _slide_qte_elapsed := 0.0
var _slide_qte_started_msec := 0
var _slide_qte_camera_tween: Tween
var _slide_qte_time_tween: Tween
var _slide_qte_fade_tween: Tween
var _move_key := "D"
var _move_key_time_remaining := MOVE_KEY_CHANGE_INTERVAL
var _last_move_key_second := int(MOVE_KEY_CHANGE_INTERVAL)
var _score_tween: Tween
var _move_key_tween: Tween
var _move_key_timer_tween: Tween
var _new_key_alert_tween: Tween
var _fx_rng := RandomNumberGenerator.new()


func _ready() -> void:
	Engine.time_scale = 1.0
	player.process_mode = Node.PROCESS_MODE_DISABLED
	camera.reparent(self, true)
	camera.global_position = Vector2(576.0, 300.0)
	camera.position_smoothing_enabled = false
	level.player_died.connect(_restart_game)
	level.clock_collected.connect(_on_clock_collected)
	avalanche.body_entered.connect(_on_avalanche_body_entered)
	player.connect(&"bounced", _on_player_bounced)
	player.connect(&"slide_boosted", _on_player_slide_boosted)
	player.connect(&"slide_qte_started", _on_slide_qte_started)
	player.connect(&"slide_qte_ended", _on_slide_qte_ended)
	player.connect(&"knocked_back", _on_player_knocked_back)
	_fx_rng.randomize()
	_set_move_key("D", false)
	_score_start_x = player.global_position.x
	_furthest_player_x = _score_start_x
	score_label.pivot_offset = score_label.size * 0.5
	move_key_label.pivot_offset = move_key_label.size * 0.5
	move_key_timer_label.pivot_offset = move_key_timer_label.size * 0.5
	new_key_alert.pivot_offset = new_key_alert.size * 0.5
	slide_qte_prompt.pivot_offset = slide_qte_prompt.size * 0.5
	var half_view_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	avalanche.global_position = Vector2(
		camera.global_position.x - half_view_width + AVALANCHE_EDGE_OFFSET,
		level.call("get_camera_surface_y", player.global_position.x)
		- AVALANCHE_HEIGHT * 0.5
		+ AVALANCHE_BOTTOM_EXTENSION
	)
	_update_score()
	call_deferred("_run_start_countdown")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	if _restarting or _start_countdown_active:
		return
	var should_pause := not get_tree().paused
	get_tree().paused = should_pause
	pause_menu.visible = should_pause
	if should_pause:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		resume_button.grab_focus()


func _resume_game() -> void:
	get_tree().paused = false
	pause_menu.visible = false
	if not _restarting:
		player.process_mode = Node.PROCESS_MODE_INHERIT


func _quit_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://title_screen.tscn")


func _run_start_countdown() -> void:
	for number in ["3", "2", "1"]:
		await _animate_start_countdown_step(number)
	_start_countdown_active = false
	player.process_mode = Node.PROCESS_MODE_INHERIT


func _animate_start_countdown_step(value: String) -> void:
	var countdown_label: Label = $UI/StartCountdown
	countdown_label.text = value
	countdown_label.visible = true
	countdown_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	countdown_label.scale = Vector2.ONE * 0.55
	var tween := create_tween().set_parallel()
	tween.tween_property(countdown_label, "modulate:a", 1.0, 0.1)
	tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	await get_tree().create_timer(0.68).timeout
	var fade := create_tween()
	fade.tween_property(countdown_label, "modulate:a", 0.0, 0.22)
	await fade.finished
	countdown_label.visible = false


func _process(delta: float) -> void:
	if _restarting:
		return
	if get_tree().paused:
		return
	if _start_countdown_active:
		return

	_camera_speed = minf(_camera_speed + CAMERA_ACCELERATION * delta, CAMERA_MAX_SPEED)
	camera.global_position.x += _camera_speed * delta
	if not _slide_qte_active:
		_update_move_key_timer(delta)
	else:
		_slide_qte_elapsed += delta
		var qte_real_elapsed := (Time.get_ticks_msec() - _slide_qte_started_msec) / 1000.0
		if qte_real_elapsed >= SLIDE_QTE_MAX_REAL_SECONDS:
			_end_slide_qte()
		elif _slide_qte_elapsed > 0.18 and not player.is_on_blue_slide_zone():
			_end_slide_qte()
		_update_slide_qte_prompt()
	_update_camera_vertical(delta)
	_update_avalanche(delta)
	_update_camera_effects(delta)
	_update_score()
	if player.global_position.y > 760.0:
		_restart_game()
	elif Input.is_action_just_pressed("restart"):
		_restart_game(false)


func _update_avalanche(_delta: float) -> void:
	var half_view_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var camera_left_edge := camera.global_position.x - half_view_width
	var target_x := camera_left_edge + AVALANCHE_EDGE_OFFSET
	var follow_weight := minf(1.0, AVALANCHE_FOLLOW_SPEED * _delta)
	avalanche.global_position.x = lerpf(avalanche.global_position.x, target_x, follow_weight)
	var target_y := camera.global_position.y - 50.0
	avalanche.global_position.y = lerpf(
		avalanche.global_position.y,
		target_y,
		minf(1.0, 12.0 * _delta)
	)


func _update_score() -> void:
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


func _on_clock_collected() -> void:
	_move_key_time_remaining = minf(
		MAX_MOVE_KEY_TIME,
		_move_key_time_remaining + CLOCK_TIME_BONUS
	)
	_last_move_key_second = ceili(_move_key_time_remaining)
	if _move_key_time_remaining > 3.0:
		move_key_tick_sound.stop()
	_show_center_alert("TIME +%d SEC!" % int(CLOCK_TIME_BONUS))


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
	_show_center_alert("NEW KEY!\n[ %s ]" % letter)


func _show_center_alert(message: String) -> void:
	if _new_key_alert_tween and _new_key_alert_tween.is_valid():
		_new_key_alert_tween.kill()
	new_key_alert.text = message
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
	var target_zoom := (
		SLIDE_QTE_CAMERA_ZOOM
		if _slide_qte_active
		else lerpf(1.0, CAMERA_MAX_SPEED_ZOOM, speed_ratio) + _zoom_punch
	)
	if not _slide_qte_camera_tween or not _slide_qte_camera_tween.is_valid():
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
	_end_slide_qte()
	_add_camera_impact(0.62, 0.035)


func _on_slide_qte_started() -> void:
	if _slide_qte_active or _restarting:
		return
	_slide_qte_active = true
	_slide_qte_elapsed = 0.0
	_slide_qte_started_msec = Time.get_ticks_msec()
	if _slide_qte_camera_tween and _slide_qte_camera_tween.is_valid():
		_slide_qte_camera_tween.kill()
	if _slide_qte_time_tween and _slide_qte_time_tween.is_valid():
		_slide_qte_time_tween.kill()
	if _slide_qte_fade_tween and _slide_qte_fade_tween.is_valid():
		_slide_qte_fade_tween.kill()
	Engine.time_scale = 1.0
	move_key_tick_sound.stream_paused = true
	slide_qte_overlay.visible = true
	slide_qte_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	slide_qte_prompt.scale = Vector2.ONE
	_slide_qte_camera_tween = create_tween().set_ignore_time_scale(true)
	_slide_qte_camera_tween.tween_property(
		camera,
		"zoom",
		Vector2.ONE * SLIDE_QTE_CAMERA_ZOOM,
		SLIDE_QTE_ZOOM_IN_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_slide_qte_time_tween = create_tween().set_ignore_time_scale(true)
	_slide_qte_time_tween.tween_method(
		_set_time_scale,
		1.0,
		SLIDE_QTE_TIME_SCALE,
		SLIDE_QTE_FADE_IN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_slide_qte_fade_tween = create_tween().set_ignore_time_scale(true)
	_slide_qte_fade_tween.tween_property(
		slide_qte_overlay,
		"modulate:a",
		1.0,
		SLIDE_QTE_FADE_IN_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_slide_qte_ended() -> void:
	_end_slide_qte()


func _update_slide_qte_prompt() -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.014) * 0.08
	slide_qte_prompt.scale = Vector2.ONE * pulse


func _set_time_scale(value: float) -> void:
	Engine.time_scale = value


func _end_slide_qte() -> void:
	if not _slide_qte_active:
		return
	_slide_qte_active = false
	_slide_qte_elapsed = 0.0
	Engine.time_scale = 1.0
	move_key_tick_sound.stream_paused = false
	if _slide_qte_camera_tween and _slide_qte_camera_tween.is_valid():
		_slide_qte_camera_tween.kill()
	var speed_ratio := inverse_lerp(CAMERA_START_SPEED, CAMERA_MAX_SPEED, _camera_speed)
	var normal_zoom := lerpf(1.0, CAMERA_MAX_SPEED_ZOOM, speed_ratio) + _zoom_punch
	_slide_qte_camera_tween = create_tween().set_ignore_time_scale(true)
	_slide_qte_camera_tween.tween_property(
		camera,
		"zoom",
		Vector2.ONE * normal_zoom,
		SLIDE_QTE_FADE_OUT_DURATION
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	if _slide_qte_fade_tween and _slide_qte_fade_tween.is_valid():
		_slide_qte_fade_tween.kill()
	_slide_qte_fade_tween = create_tween().set_ignore_time_scale(true)
	_slide_qte_fade_tween.tween_property(
		slide_qte_overlay,
		"modulate:a",
		0.0,
		SLIDE_QTE_FADE_OUT_DURATION
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_slide_qte_fade_tween.tween_callback(_hide_slide_qte_overlay)


func _hide_slide_qte_overlay() -> void:
	slide_qte_overlay.visible = false
	slide_qte_overlay.modulate = Color.WHITE
	slide_qte_prompt.scale = Vector2.ONE


func _on_player_knocked_back() -> void:
	_add_camera_impact(0.88, 0.025)


func _on_avalanche_body_entered(body: Node2D) -> void:
	if body == player:
		_restart_game()


func _restart_game(play_death_sound: bool = true) -> void:
	if _restarting:
		return
	_end_slide_qte()
	Engine.time_scale = 1.0
	_restarting = true
	player.process_mode = Node.PROCESS_MODE_DISABLED
	move_key_tick_sound.stop()
	death_score_label.text = "SCORE  %d" % _score_points
	death_screen.visible = true
	restart_button.grab_focus()
	if play_death_sound and death_sound.stream:
		death_sound.play()


func _on_restart_button_pressed() -> void:
	if not _restarting:
		return
	_reload_game()


func _reload_game() -> void:
	get_tree().call_deferred("reload_current_scene")
