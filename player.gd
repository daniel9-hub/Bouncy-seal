extends CharacterBody2D


const SPEED = 400.0
const JUMP_VELOCITY = -500.0
const BLUE_SLIDE_SPEED = 560.0
const SLIDE_STICK_SPEED = 90.0
const BLUE_BOOST_JUMP_VELOCITY = -720.0
const BLUE_BOOST_FORWARD_SPEED = 680.0
const SLOPE_ANGLE = 0.5880026 # atan2(64, 96)
const SLOPE_TILT_SPEED = 10.0
const KNOCKBACK_HORIZONTAL_SPEED = 560.0
const KNOCKBACK_VERTICAL_SPEED = -360.0
const KNOCKBACK_DURATION = 0.38

var _blue_slide_zone_count := 0
var _black_slope_zone_count := 0
var _blue_boost_used := false
var _base_sprite_rotation := 0.0
var _knockback_time_remaining := 0.0

@onready var player_sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	# Haelt die Robbe auch zwischen zwei Rampensegmenten sauber am Hang.
	floor_snap_length = 12.0
	floor_stop_on_slope = false
	_base_sprite_rotation = player_sprite.rotation


func _process(delta: float) -> void:
	# Nur das sichtbare Modell neigt sich. Der CharacterBody und seine Kollision
	# bleiben aufrecht und dadurch auch auf Segmentnahtstellen stabil.
	var on_any_slope := _blue_slide_zone_count > 0 or _black_slope_zone_count > 0
	var target_rotation := _base_sprite_rotation + SLOPE_ANGLE if on_any_slope else _base_sprite_rotation
	player_sprite.rotation = lerp_angle(
		player_sprite.rotation,
		target_rotation,
		minf(1.0, SLOPE_TILT_SPEED * delta)
	)


func _physics_process(delta: float) -> void:
	if _knockback_time_remaining > 0.0:
		_knockback_time_remaining = maxf(0.0, _knockback_time_remaining - delta)
		velocity += get_gravity() * delta
		move_and_slide()
		return

	var on_blue_slide := is_on_floor() and _blue_slide_zone_count > 0

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Blaues Eis wird zu einer echten Rutsche. Schwarze Rampen gehoeren nicht
	# zur Slide-Gruppe und behalten deshalb das normale automatische Hopsen.
	if on_blue_slide:
		if Input.is_action_just_pressed("jump_boost") and not _blue_boost_used:
			velocity.x = maxf(velocity.x, BLUE_BOOST_FORWARD_SPEED)
			velocity.y = BLUE_BOOST_JUMP_VELOCITY
			_blue_boost_used = true
		else:
			velocity.x = maxf(velocity.x, BLUE_SLIDE_SPEED)
			velocity.y = SLIDE_STICK_SPEED
	elif is_on_floor():
		velocity.y = JUMP_VELOCITY

	if _blue_slide_zone_count == 0:
		_blue_boost_used = false

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	if not on_blue_slide:
		var direction := Input.get_axis("left", "right")
		if direction:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()


func _enter_blue_slide_zone() -> void:
	_blue_slide_zone_count += 1


func _exit_blue_slide_zone() -> void:
	_blue_slide_zone_count = maxi(0, _blue_slide_zone_count - 1)


func _enter_black_slope_zone() -> void:
	_black_slope_zone_count += 1


func _exit_black_slope_zone() -> void:
	_black_slope_zone_count = maxi(0, _black_slope_zone_count - 1)


func apply_knockback() -> void:
	if _knockback_time_remaining > 0.0:
		return
	velocity = Vector2(-KNOCKBACK_HORIZONTAL_SPEED, KNOCKBACK_VERTICAL_SPEED)
	_knockback_time_remaining = KNOCKBACK_DURATION
