extends CharacterBody2D


const SPEED = 400.0
const JUMP_VELOCITY = -500.0
const BLUE_SLIDE_SPEED = 560.0
const SLIDE_STICK_SPEED = 90.0

var _blue_slide_zone_count := 0


func _ready() -> void:
	# Haelt die Robbe auch zwischen zwei Rampensegmenten sauber am Hang.
	floor_snap_length = 12.0
	floor_stop_on_slope = false


func _physics_process(delta: float) -> void:
	var on_blue_slide := is_on_floor() and _blue_slide_zone_count > 0

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Blaues Eis wird zu einer echten Rutsche. Schwarze Rampen gehoeren nicht
	# zur Slide-Gruppe und behalten deshalb das normale automatische Hopsen.
	if on_blue_slide:
		velocity.x = maxf(velocity.x, BLUE_SLIDE_SPEED)
		velocity.y = SLIDE_STICK_SPEED
	elif is_on_floor():
		velocity.y = JUMP_VELOCITY

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
