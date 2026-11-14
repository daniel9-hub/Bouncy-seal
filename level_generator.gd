extends Node2D

signal player_died

## Endloser, aber spielbarer Level-Generator.
## Alle wichtigen Werte stehen hier oben, damit ihr sie beim Hackathon schnell tunen koennt.

@export var player_path: NodePath
@export var floor_y := 520.0
@export var generate_ahead := 1900.0
@export var delete_behind := 1200.0
@export var random_seed := 0

const BLOCK_SIZE := Vector2(96.0, 64.0)
## Fuenf Schichten reichen von der Oberflaeche bis deutlich unter den Bildschirm.
## Eine Luecke laesst immer die gesamte Spalte frei.
const TERRAIN_DEPTH := 5
const START_X := -576.0
const SAFE_START_END := 720.0
const ICE_BLOCK_REGION := Rect2(144.0, 208.0, 96.0, 64.0)
const BLUE_ICE_FRONT_REGION := Rect2(384.0, 208.0, 64.0, 64.0)
const PALE_SNOW_BLOCK_REGION := Rect2(304.0, 80.0, 96.0, 64.0)
const SNOW_FRONT_REGION := Rect2(528.0, 80.0, 64.0, 64.0)
const ICE_TEXTURE := preload("res://assets/SnowTileset/SnowTileset.png")
const PENGUIN_TEXTURE := preload("res://assets/SnowTileset/Animations/penguinAnimationsPng.png")
const TREE_REGIONS := [
	Rect2(613.0, 26.0, 24.0, 38.0),
	Rect2(658.0, 21.0, 31.0, 43.0),
]
const SNOW_REGION := Rect2(624.0, 142.0, 33.0, 16.0)

var _player: CharacterBody2D
var _rng := RandomNumberGenerator.new()
var _next_x := START_X
var _safe_columns := 0
var _gap_columns := 0
var _raised_columns := 0
var _columns: Array[Node2D] = []


func _ready() -> void:
	_player = get_node(player_path) as CharacterBody2D
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed
	_generate_until(_player.global_position.x + generate_ahead)


func _process(_delta: float) -> void:
	_generate_until(_player.global_position.x + generate_ahead)
	_delete_old_columns()


func _generate_until(target_x: float) -> void:
	while _next_x < target_x:
		_generate_column(_next_x)
		_next_x += BLOCK_SIZE.x


func _generate_column(column_x: float) -> void:
	var column := Node2D.new()
	column.position.x = column_x
	column.name = "Column_%d" % int(column_x / BLOCK_SIZE.x)
	add_child(column)
	_columns.append(column)

	# Der Anfang ist immer flach. Danach entstehen kleine, bewusst begrenzte
	# Muster. So bleibt der Zufall fair statt unmoegliche Kombinationen zu bauen.
	if column_x < SAFE_START_END:
		_add_terrain_column(column)
		_add_guaranteed_start_decoration(column, column_x)
		return

	if _gap_columns > 0:
		_gap_columns -= 1
		if _gap_columns == 0:
			_safe_columns = 3
		return

	_add_terrain_column(column)

	# Ein begonnenes Hochplateau wird mehrere Tiles breit weitergebaut. Dadurch
	# kann die Robbe wirklich oben landen, statt nur auf eine einzelne Saeule zu
	# treffen.
	if _raised_columns > 0:
		_add_snow_front_block(column, floor_y - BLOCK_SIZE.y)
		_raised_columns -= 1
		if _raised_columns == 0:
			_maybe_add_decoration(column, floor_y - BLOCK_SIZE.y, 100)
		return

	if _safe_columns > 0:
		_safe_columns -= 1
		_maybe_add_decoration(column, floor_y, 12)
		return

	var roll := _rng.randi_range(0, 99)
	if roll < 22:
		# Ein kurzes Hochplateau. Wer die Oberseite verfehlt und gegen die
		# Vorderkante prallt, stirbt wie an einem Flappy-Bird-Hindernis.
		_add_snow_front_block(column, floor_y - BLOCK_SIZE.y)
		_add_deadly_front_edge(column, floor_y - BLOCK_SIZE.y)
		_raised_columns = _rng.randi_range(1, 3)
		_safe_columns = _rng.randi_range(3, 5)
	elif roll < 34:
		# Eine oder zwei Bodenplatten fehlen. Nie direkt nach einem Hindernis.
		# Die aktuelle Platte wird entfernt, damit die Luecke hier beginnt.
		column.queue_free()
		_columns.pop_back()
		_gap_columns = _rng.randi_range(0, 1)
		_safe_columns = 3
	else:
		_safe_columns = _rng.randi_range(1, 3)
		_maybe_add_decoration(column, floor_y, 16)


func _add_terrain_column(parent: Node2D) -> void:
	# Nicht nur eine schwebende Plattform: Jede Bodenspalte wird bis unterhalb
	# des sichtbaren Bereichs mit Eis gefuellt. Luecken rufen diese Funktion nie
	# auf und bleiben deshalb von oben bis unten offen.
	for layer in range(TERRAIN_DEPTH):
		var layer_y := floor_y + layer * BLOCK_SIZE.y
		if layer == 0:
			_add_ice_block(parent, layer_y)
		else:
			# Die unteren Schichten mischen drei echte Frontansichten aus dem
			# Tileset. Das wirkt wie gewachsenes Eis statt einer kopierten Wand.
			var tile_variant := _rng.randi_range(0, 2)
			if tile_variant == 0:
				_add_ice_block(parent, layer_y)
			elif tile_variant == 1:
				_add_ice_block(parent, layer_y, BLUE_ICE_FRONT_REGION, Vector2(1.5, 1.0))
			else:
				_add_ice_block(parent, layer_y, PALE_SNOW_BLOCK_REGION)


func _add_snow_front_block(parent: Node2D, top_y: float) -> void:
	# Auch Hochplateaus wechseln zwischen zwei Schnee-Frontansichten.
	if _rng.randi_range(0, 1) == 0:
		_add_ice_block(parent, top_y, SNOW_FRONT_REGION, Vector2(1.5, 1.0))
	else:
		_add_ice_block(parent, top_y, PALE_SNOW_BLOCK_REGION)


func _add_ice_block(
	parent: Node2D,
	top_y: float,
	region: Rect2 = ICE_BLOCK_REGION,
	visual_scale: Vector2 = Vector2.ONE
) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(BLOCK_SIZE.x * 0.5, top_y + BLOCK_SIZE.y * 0.5)
	parent.add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = BLOCK_SIZE
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	var sprite := Sprite2D.new()
	sprite.texture = ICE_TEXTURE
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.scale = visual_scale
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(sprite)


func _add_deadly_front_edge(parent: Node2D, top_y: float) -> void:
	# Die Zone steht ein wenig vor der linken Wand. So wird sie ausgeloest,
	# bevor die feste Kollision den Spieler einfach nur stoppt.
	var danger := Area2D.new()
	danger.name = "DeadlyFrontEdge"
	danger.position = Vector2(-8.0, top_y + BLOCK_SIZE.y * 0.5)
	danger.collision_layer = 0
	danger.collision_mask = 1
	parent.add_child(danger)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(16.0, BLOCK_SIZE.y - 8.0)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	danger.add_child(collision)
	danger.body_entered.connect(_on_deadly_edge_entered)


func _on_deadly_edge_entered(body: Node2D) -> void:
	if body == _player:
		player_died.emit()


func _maybe_add_decoration(parent: Node2D, surface_y: float, chance_percent: int) -> void:
	if _rng.randi_range(1, 100) > chance_percent:
		return

	var decoration_kind := _rng.randi_range(0, 2)
	if decoration_kind == 0:
		var tree_region: Rect2 = TREE_REGIONS[_rng.randi_range(0, TREE_REGIONS.size() - 1)]
		_add_decoration_sprite(parent, ICE_TEXTURE, tree_region, surface_y, Vector2(2.5, 2.5))
	elif decoration_kind == 1:
		_add_decoration_sprite(parent, ICE_TEXTURE, SNOW_REGION, surface_y, Vector2(1.35, 1.35))
	else:
		_add_penguin(parent, surface_y)


func _add_guaranteed_start_decoration(parent: Node2D, column_x: float) -> void:
	# Sofort sichtbar: Damit man nicht auf einen guten Zufallswurf warten muss,
	# stehen im sicheren Startbereich immer ein Pinguin und eine Tanne.
	if is_equal_approx(column_x, 384.0):
		_add_penguin(parent, floor_y)
	elif is_equal_approx(column_x, 672.0):
		_add_decoration_sprite(parent, ICE_TEXTURE, TREE_REGIONS[0], floor_y, Vector2(2.7, 2.7))


func _add_penguin(parent: Node2D, surface_y: float) -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 2.5)

	var first_frame := AtlasTexture.new()
	first_frame.atlas = PENGUIN_TEXTURE
	first_frame.region = Rect2(16.0, 0.0, 16.0, 16.0)
	frames.add_frame("idle", first_frame)

	var second_frame := AtlasTexture.new()
	second_frame.atlas = PENGUIN_TEXTURE
	second_frame.region = Rect2(32.0, 0.0, 16.0, 16.0)
	frames.add_frame("idle", second_frame)

	var penguin := AnimatedSprite2D.new()
	penguin.sprite_frames = frames
	penguin.animation = "idle"
	penguin.position = Vector2(BLOCK_SIZE.x * 0.5, surface_y - 24.0)
	penguin.scale = Vector2(3.0, 3.0)
	penguin.z_index = 2
	penguin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(penguin)
	penguin.play()


func _add_decoration_sprite(
	parent: Node2D,
	texture: Texture2D,
	region: Rect2,
	surface_y: float,
	decoration_scale: Vector2
) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.position = Vector2(
		BLOCK_SIZE.x * 0.5,
		surface_y - region.size.y * decoration_scale.y * 0.5
	)
	sprite.scale = decoration_scale
	sprite.z_index = 2
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(sprite)


func _delete_old_columns() -> void:
	var cutoff := _player.global_position.x - delete_behind
	while not _columns.is_empty() and _columns.front().global_position.x < cutoff:
		var old_column: Node2D = _columns.pop_front()
		old_column.queue_free()
