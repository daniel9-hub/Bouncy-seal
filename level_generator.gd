extends Node2D

signal player_died
signal clock_collected

## Endloser, aber spielbarer Level-Generator.
## Alle wichtigen Werte stehen hier oben, damit ihr sie beim Hackathon schnell tunen koennt.

@export var player_path: NodePath
@export var floor_y := 520.0
@export var generate_ahead := 1900.0
@export var delete_behind := 1200.0
@export var random_seed := 0

const BLOCK_SIZE := Vector2(96.0, 64.0)
const MAX_SURFACE_LEVEL := 8
## Fuenf Schichten reichen von der Oberflaeche bis deutlich unter den Bildschirm.
## Eine Luecke laesst immer die gesamte Spalte frei.
const TERRAIN_DEPTH := 5
const START_X := -576.0
const SAFE_START_END := 720.0
const FULL_DIFFICULTY_X := 12000.0
const GAP_CHANCE_START := 16
const GAP_CHANCE_MAX := 24
const SLIDE_CHANCE_START := 32
const SLIDE_CHANCE_MAX := 40
const ICE_BLOCK_REGION := Rect2(144.0, 208.0, 96.0, 64.0)
const PALE_SNOW_BLOCK_REGION := Rect2(304.0, 80.0, 96.0, 64.0)
const SNOW_FRONT_REGION := Rect2(528.0, 80.0, 64.0, 64.0)
const ICE_TEXTURE := preload("res://assets/SnowTileset/SnowTileset.png")
const ICE_ATLAS_TEXTURE := preload("res://assets/Ice_Tileset.png")
const BLUE_FULL_BLOCK_REGION := Rect2(64.0, 0.0, 64.0, 64.0)
const BLACK_FULL_BLOCK_REGION := Rect2(0.0, 0.0, 64.0, 64.0)
const BLUE_GROUND_TEXTURE := preload("res://assets/IceTiles/blue_ground.png")
const BLUE_CORNER_TEXTURE := preload("res://assets/IceTiles/blue_corner.png")
const BLUE_CENTER_TEXTURE := preload("res://assets/IceTiles/blue_center.png")
const BLUE_SIDE_TEXTURE := preload("res://assets/IceTiles/blue_side.png")
const BLACK_GROUND_TEXTURE := preload("res://assets/IceTiles/black_ground.png")
const BLACK_CORNER_TEXTURE := preload("res://assets/IceTiles/black_corner.png")
const BLACK_CENTER_TEXTURE := preload("res://assets/IceTiles/black_center.png")
const BLACK_SIDE_TEXTURE := preload("res://assets/IceTiles/black_side.png")
const BLUE_SLOPE_TEXTURE := preload("res://assets/IceTiles/blue_slope.png")
const BLACK_SLOPE_TEXTURE := preload("res://assets/IceTiles/black_slope.png")
const ATLAS_ICE_CAP_REGION := Rect2(130.0, 0.0, 28.0, 18.0)
const PENGUIN_TEXTURE := preload("res://assets/SnowTileset/Animations/penguinAnimationsPng.png")
const CLOCK_TEXTURE := preload("res://assets/Clock.png")
const TREE_REGIONS := [
	Rect2(613.0, 26.0, 24.0, 38.0),
	Rect2(658.0, 21.0, 31.0, 43.0),
]
const TREE_SCALES := [2.2, 3.2, 4.4]
const TREE_NAMES := ["TreeSmall", "TreeMedium", "TreeBig"]
const SMALL_PROP_REGIONS := [
	Rect2(611.0, 144.0, 8.0, 16.0), # Eisnadel
	Rect2(625.0, 149.0, 14.0, 8.0), # Flacher Schneehaufen
	Rect2(644.0, 148.0, 8.0, 8.0), # Kleiner Schneeball
	Rect2(659.0, 148.0, 10.0, 9.0), # Runder Schneeball
	Rect2(676.0, 136.0, 25.0, 22.0), # Breiter Eisklumpen
	Rect2(710.0, 135.0, 21.0, 24.0), # Hoher Eisklumpen
	Rect2(688.0, 160.0, 32.0, 32.0), # Holzkiste
]
const SMALL_PROP_SCALES := [1.8, 1.7, 2.0, 1.8, 1.25, 1.2, 1.1]

enum SurfaceKind {
	NORMAL_ICE,
	BLUE_ICE,
	BLACK_ICE,
	HALF_SNOW,
	FULL_SNOW,
}

enum AtlasMaterial {
	BLUE,
	BLACK,
}

var _player: CharacterBody2D
var _rng := RandomNumberGenerator.new()
var _next_x := START_X
var _safe_columns := 0
var _gap_columns := 0
var _surface_level := 0
var _height_run_remaining := 0
var _columns: Array[Node2D] = []
var _last_terrain_column: Node2D
var _last_surface_y := 520.0
var _needs_left_edge := false
var _slide_segments_remaining := 0
var _slide_material := AtlasMaterial.BLUE
var _last_surface_kind := -1
var _same_surface_run := 0


func _ready() -> void:
	_player = get_node(player_path) as CharacterBody2D
	_last_surface_y = floor_y
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

	# Der Anfang ist immer flach. Danach entstehen mehrere Hoehenebenen.
	if column_x < SAFE_START_END:
		var needs_decoration := (
			is_equal_approx(column_x, 384.0)
			or is_equal_approx(column_x, 672.0)
		)
		var start_surface := _random_surface_kind(needs_decoration)
		# Die zwei garantierten Figuren bekommen immer eine dekorierbare Eisart.
		_add_terrain_column(column, floor_y, start_surface)
		_add_guaranteed_start_decoration(column, column_x)
		_last_terrain_column = column
		_last_surface_y = floor_y
		return

	if _gap_columns > 0:
		column.queue_free()
		_columns.pop_back()
		_gap_columns -= 1
		if _gap_columns == 0:
			_safe_columns = 3
			_needs_left_edge = true
		return

	# Eine begonnene Rampe wird immer als geschlossene Kette fortgesetzt.
	# Dadurch koennen weder Luecken noch normale Plattformen sie zerhacken.
	if _slide_segments_remaining > 0:
		_generate_slide_segment(column)
		return

	var difficulty := _difficulty_at(column_x)

	# Rampen beginnen nur hoch genug und am Ende eines flachen Abschnitts.
	# Die Laenge ist auf die aktuelle Hoehe begrenzt, damit der letzte Hang
	# nicht unterhalb des normalen Bodens endet.
	if (
		_safe_columns == 0
		and _height_run_remaining <= 0
		and _surface_level >= 4
		and _rng.randi_range(0, 99) < roundi(lerpf(SLIDE_CHANCE_START, SLIDE_CHANCE_MAX, difficulty))
	):
		# Auch Rampen folgen der Drei-gleiche-Tiles-Regel.
		_slide_segments_remaining = _rng.randi_range(2, mini(3, _surface_level))
		_slide_material = AtlasMaterial.BLUE if _rng.randi_range(0, 99) < 70 else AtlasMaterial.BLACK
		_reset_surface_run()
		_generate_slide_segment(column)
		return

	# Nach ein paar sicheren Spalten darf eine Luecke beginnen. Zu Beginn ist
	# sie hoechstens zwei, spaeter hoechstens drei Blocks breit.
	var gap_chance := roundi(lerpf(GAP_CHANCE_START, GAP_CHANCE_MAX, difficulty))
	if _safe_columns == 0 and _rng.randi_range(0, 99) < gap_chance:
		# Erst jetzt kennen wir das Ende der Plattform. Nur dort werden Ecke
		# und Seitenwand des letzten Atlas-Blocks sichtbar.
		_set_column_edge(_last_terrain_column, false, INF)
		column.queue_free()
		_columns.pop_back()
		var max_gap_tail := 1 if difficulty < 0.45 else 2
		_gap_columns = _rng.randi_range(0, max_gap_tail)
		_safe_columns = 2
		_needs_left_edge = _gap_columns == 0
		_reset_surface_run()
		return

	var previous_surface_y := _last_surface_y
	var rose_this_column := _choose_platform_height()
	var surface_y := floor_y - _surface_level * BLOCK_SIZE.y
	var surface_kind := _random_surface_kind()
	_add_terrain_column(column, surface_y, surface_kind)
	_height_run_remaining -= 1

	# Nach einer Luecke ist die komplette linke Wand frei. Bei einer Stufe nach
	# oben ist nur der Teil oberhalb des vorherigen Bodens frei. Faellt das
	# Terrain ab, bekommt stattdessen die vorherige Spalte eine rechte Kante.
	if _needs_left_edge:
		_set_column_edge(column, true, INF)
		_needs_left_edge = false
	elif surface_y < previous_surface_y:
		_set_column_edge(column, true, previous_surface_y)
	elif surface_y > previous_surface_y:
		_set_column_edge(_last_terrain_column, false, surface_y)

	_last_terrain_column = column
	_last_surface_y = surface_y

	# Bei einer neuen Stufe ist nur die Vorderseite gefaehrlich. Die Oberseite
	# bleibt eine normale, landbare Plattform.
	if rose_this_column:
		if surface_kind == SurfaceKind.HALF_SNOW:
			_add_knockback_side(column, surface_y + BLOCK_SIZE.y * 0.5, BLOCK_SIZE.y * 0.5)
		else:
			_add_knockback_side(column, surface_y, BLOCK_SIZE.y)

	# Schneeoberflaechen bleiben frei. Auf den normalen Eisarten duerfen
	# weiterhin Baeume, Schneehaeufchen und Pinguine stehen.
	var decoration_chance := 52
	if _safe_columns > 0:
		_safe_columns -= 1
		decoration_chance = 34
	if _surface_allows_decoration(surface_kind):
		_maybe_add_decoration(column, surface_y, decoration_chance)


func _choose_platform_height() -> bool:
	if _height_run_remaining > 0:
		return false

	var previous_level := _surface_level
	var height_roll := _rng.randi_range(0, 99)
	if _surface_level == 0:
		# Nach der flachen Startzone geht es bewusst nach oben.
		_surface_level = 1
	elif _surface_level == MAX_SURFACE_LEVEL:
		# Oben entweder bleiben oder eine Stufe absteigen.
		if height_roll < 58:
			_surface_level -= 1
	elif height_roll < (66 if _surface_level < 4 else 55):
		_surface_level += 1
	elif height_roll < 80:
		_surface_level -= 1

	_surface_level = clampi(_surface_level, 0, MAX_SURFACE_LEVEL)
	_height_run_remaining = _rng.randi_range(2, 5)
	return _surface_level > previous_level


func _difficulty_at(column_x: float) -> float:
	return clampf((column_x - SAFE_START_END) / (FULL_DIFFICULTY_X - SAFE_START_END), 0.0, 1.0)


func _generate_slide_segment(column: Node2D) -> void:
	var slope_top_y := floor_y - _surface_level * BLOCK_SIZE.y
	# Fuer die Kamera zaehlt die Mitte der schraegen Oberflaeche. So folgt sie
	# der Rampe gleichmaessig statt pro Segment hart um 64 Pixel zu springen.
	column.set_meta("camera_surface_y", slope_top_y + BLOCK_SIZE.y * 0.5)
	_add_slope_terrain(column, slope_top_y, _slide_material)
	_slide_segments_remaining -= 1
	_surface_level = maxi(0, _surface_level - 1)
	_last_terrain_column = column
	_last_surface_y = slope_top_y + BLOCK_SIZE.y
	_needs_left_edge = false

	if _slide_segments_remaining == 0:
		# Nach der Rampe folgt ein kurzer sicherer, flacher Auslauf.
		_height_run_remaining = _rng.randi_range(3, 6)
		_safe_columns = maxi(_safe_columns, 3)


func _add_slope_terrain(parent: Node2D, top_y: float, material: AtlasMaterial) -> void:
	var slope_body := StaticBody2D.new()
	slope_body.name = "BlueSlide" if material == AtlasMaterial.BLUE else "BlackSlope"
	slope_body.position = Vector2(0.0, top_y)
	if material == AtlasMaterial.BLUE:
		slope_body.add_to_group("blue_slide_surface")
	parent.add_child(slope_body)
	_add_slope_area(slope_body, material)

	# Nur die sichtbare Hanglinie kollidiert. Ein gefuelltes Dreieck haette an
	# jedem Segmentanfang eine unsichtbare senkrechte Naht, an der die Robbe
	# haengen bleiben wuerde.
	var slope_shape := SegmentShape2D.new()
	slope_shape.a = Vector2(0.0, 0.0)
	slope_shape.b = Vector2(BLOCK_SIZE.x, BLOCK_SIZE.y)
	var collision := CollisionShape2D.new()
	collision.name = "SlopeCollision"
	collision.shape = slope_shape
	slope_body.add_child(collision)

	var sprite := Sprite2D.new()
	sprite.name = "SlopeSprite"
	sprite.texture = BLUE_SLOPE_TEXTURE if material == AtlasMaterial.BLUE else BLACK_SLOPE_TEXTURE
	sprite.position = BLOCK_SIZE * 0.5
	# Die saubere Slope-Grafik ist 32x64 Pixel gross. Dreifache X-Skalierung
	# zieht nur die Schräge ueber die volle 96-px-Spalte; das separate Atlas-
	# Eisstueck links daneben wird bewusst nicht mehr mitgerendert.
	sprite.scale = Vector2(3.0, 1.0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slope_body.add_child(sprite)

	# Direkt unter jedem Hang liegt zwingend ein farblich passender Mittelpunkt-
	# Block. So schliesst das Dreieck sichtbar ab und es entsteht kein freier
	# oder farblich unpassender Raum unter der Rampe.
	var bottom_y := floor_y + TERRAIN_DEPTH * BLOCK_SIZE.y
	var layer_y := top_y + BLOCK_SIZE.y
	if layer_y < bottom_y:
		_add_slope_support_block(parent, layer_y, material)
		layer_y += BLOCK_SIZE.y
	var layer := 2
	while layer_y < bottom_y:
		_add_subsurface_block(parent, layer_y, layer)
		layer += 1
		layer_y += BLOCK_SIZE.y


func _add_slope_support_block(parent: Node2D, top_y: float, material: AtlasMaterial) -> void:
	# Fuer den direkten Unterbau wird das vollstaendige normale 64x64-Blockbild
	# verwendet, nicht ein Muster aus einzelnen Mittelpunkt-Tiles.
	var region := BLUE_FULL_BLOCK_REGION if material == AtlasMaterial.BLUE else BLACK_FULL_BLOCK_REGION
	_add_ice_block(
		parent,
		top_y,
		region,
		Vector2(1.5, 1.0),
		BLOCK_SIZE,
		Vector2.ZERO,
		ICE_ATLAS_TEXTURE
	)


func _add_slope_area(parent: Node2D, material: AtlasMaterial) -> void:
	# Ein schmales Band folgt dem Hang. Anders als Floor-Snap-Kollisionen bleibt
	# ein Area-Kontakt auch an den Naehten zwischen zwei Segmenten stabil. Beide
	# Materialien nutzen es fuer die Neigung, nur Blau aktiviert Slide/Boost.
	var area := Area2D.new()
	area.name = "BlueSlideArea" if material == AtlasMaterial.BLUE else "BlackSlopeArea"
	area.collision_layer = 0
	area.collision_mask = 1
	parent.add_child(area)

	var band := CollisionPolygon2D.new()
	band.polygon = PackedVector2Array([
		Vector2(0.0, -32.0),
		Vector2(BLOCK_SIZE.x, BLOCK_SIZE.y - 32.0),
		Vector2(BLOCK_SIZE.x, BLOCK_SIZE.y + 32.0),
		Vector2(0.0, 32.0),
	])
	area.add_child(band)
	area.body_entered.connect(_on_slope_body_entered.bind(material))
	area.body_exited.connect(_on_slope_body_exited.bind(material))


func _on_slope_body_entered(body: Node2D, material: AtlasMaterial) -> void:
	var method_name := (
		"_enter_blue_slide_zone"
		if material == AtlasMaterial.BLUE
		else "_enter_black_slope_zone"
	)
	if body.has_method(method_name):
		body.call(method_name)


func _on_slope_body_exited(body: Node2D, material: AtlasMaterial) -> void:
	var method_name := (
		"_exit_blue_slide_zone"
		if material == AtlasMaterial.BLUE
		else "_exit_black_slope_zone"
	)
	if body.has_method(method_name):
		body.call(method_name)


func _random_surface_kind(decoration_safe: bool = false) -> SurfaceKind:
	# Pro Spalte neu entscheiden: Schnee und Eis wirken dadurch natuerlich
	# durchmischt. Nach drei gleichen Oberflaechen wird zwingend eine andere
	# gewaehlt, damit horizontal nie vier gleiche Tiles nebeneinander stehen.
	var surface_roll := _rng.randi_range(0, 99)
	var surface_kind: SurfaceKind
	if surface_roll < 18:
		surface_kind = SurfaceKind.HALF_SNOW
	elif surface_roll < 36:
		surface_kind = SurfaceKind.FULL_SNOW
	elif surface_roll < 56:
		surface_kind = SurfaceKind.BLUE_ICE
	elif surface_roll < 70:
		surface_kind = SurfaceKind.BLACK_ICE
	else:
		surface_kind = SurfaceKind.NORMAL_ICE

	var allowed_kinds: Array[SurfaceKind] = [
		SurfaceKind.NORMAL_ICE,
		SurfaceKind.BLUE_ICE,
		SurfaceKind.BLACK_ICE,
	]
	if not decoration_safe:
		allowed_kinds.append(SurfaceKind.HALF_SNOW)
		allowed_kinds.append(SurfaceKind.FULL_SNOW)
	if surface_kind not in allowed_kinds:
		surface_kind = allowed_kinds[_rng.randi_range(0, allowed_kinds.size() - 1)]
	if surface_kind == _last_surface_kind and _same_surface_run >= 3:
		allowed_kinds.erase(surface_kind)
		surface_kind = allowed_kinds[_rng.randi_range(0, allowed_kinds.size() - 1)]

	if surface_kind == _last_surface_kind:
		_same_surface_run += 1
	else:
		_last_surface_kind = surface_kind
		_same_surface_run = 1
	return surface_kind


func _reset_surface_run() -> void:
	_last_surface_kind = -1
	_same_surface_run = 0


func _surface_allows_decoration(surface_kind: SurfaceKind) -> bool:
	return (
		surface_kind == SurfaceKind.NORMAL_ICE
		or surface_kind == SurfaceKind.BLUE_ICE
		or surface_kind == SurfaceKind.BLACK_ICE
	)


func _add_terrain_column(parent: Node2D, surface_y: float, surface_kind: SurfaceKind) -> void:
	# Nicht nur eine schwebende Plattform: Jede Bodenspalte wird bis unterhalb
	# des sichtbaren Bereichs mit Eis gefuellt. Luecken rufen diese Funktion nie
	# auf und bleiben deshalb von oben bis unten offen.
	var playable_surface_y := (
		surface_y + BLOCK_SIZE.y * 0.5
		if surface_kind == SurfaceKind.HALF_SNOW
		else surface_y
	)
	parent.set_meta("camera_surface_y", playable_surface_y)
	var bottom_y := floor_y + TERRAIN_DEPTH * BLOCK_SIZE.y
	var layer_y := surface_y
	var layer := 0
	while layer_y < bottom_y:
		if layer == 0:
			_add_surface_block(parent, layer_y, surface_kind)
		else:
			# Schnee-Caps duerfen niemals hier landen. Unter jeder Oberflaeche
			# stehen ausschliesslich voll ausgefuellte Eisblocks. Der neue Atlas-
			# Block darf hier fuer Abwechslung verwendet werden, Schnee nicht.
			_add_subsurface_block(parent, layer_y, layer)
		layer += 1
		layer_y += BLOCK_SIZE.y


func _add_surface_block(parent: Node2D, top_y: float, surface_kind: SurfaceKind) -> void:
	match surface_kind:
		SurfaceKind.HALF_SNOW:
			# Im Atlas liegen die sichtbaren Pixel nur in der unteren 32-px-Haelfte.
			# Kollision und Bild stimmen dadurch exakt ueberein.
			_add_ice_block(
				parent,
				top_y,
				SNOW_FRONT_REGION,
				Vector2(1.5, 1.0),
				Vector2(BLOCK_SIZE.x, BLOCK_SIZE.y * 0.5),
				Vector2(0.0, BLOCK_SIZE.y * 0.25)
			)
		SurfaceKind.FULL_SNOW:
			_add_ice_block(parent, top_y, PALE_SNOW_BLOCK_REGION)
		SurfaceKind.BLUE_ICE:
			_add_atlas_ice_block(parent, top_y, AtlasMaterial.BLUE, true)
		SurfaceKind.BLACK_ICE:
			_add_atlas_ice_block(parent, top_y, AtlasMaterial.BLACK, true)
		_:
			_add_ice_block(parent, top_y)


func _add_subsurface_block(parent: Node2D, top_y: float, layer: int) -> void:
	var material_roll := _rng.randi_range(0, 99)
	var black_chance := 38 if layer >= 2 else 20
	if material_roll < black_chance:
		# Dunkles Gestein wird nach unten hin haeufiger.
		_add_atlas_ice_block(parent, top_y, AtlasMaterial.BLACK, false)
	elif material_roll < black_chance + 25:
		_add_atlas_ice_block(parent, top_y, AtlasMaterial.BLUE, false)
	else:
		_add_ice_block(parent, top_y)


func _add_atlas_ice_block(
	parent: Node2D,
	top_y: float,
	material: AtlasMaterial,
	is_surface: bool
) -> void:
	var body := StaticBody2D.new()
	body.name = "AtlasIceBlock"
	body.position = Vector2(BLOCK_SIZE.x * 0.5, top_y + BLOCK_SIZE.y * 0.5)
	body.set_meta("atlas_material", int(material))
	body.set_meta("atlas_surface", is_surface)
	parent.add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = BLOCK_SIZE
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	# Beim Erzeugen ist noch nicht bekannt, wo die Plattform endet. Darum
	# bestehen alle inneren Felder zuerst nur aus Boden bzw. Mittelpunkt.
	var top_texture := _atlas_ground_texture(material) if is_surface else _atlas_center_texture(material)
	var center_texture := _atlas_center_texture(material)
	_add_atlas_tile(body, top_texture, Vector2(-32.0, -16.0), "TopLeft")
	_add_atlas_tile(body, top_texture, Vector2(0.0, -16.0), "TopCenter")
	_add_atlas_tile(body, top_texture, Vector2(32.0, -16.0), "TopRight")
	_add_atlas_tile(body, center_texture, Vector2(-32.0, 16.0), "BottomLeft")
	_add_atlas_tile(body, center_texture, Vector2(0.0, 16.0), "BottomCenter")
	_add_atlas_tile(body, center_texture, Vector2(32.0, 16.0), "BottomRight")


func _add_atlas_tile(
	parent: Node2D,
	texture: Texture2D,
	local_position: Vector2,
	node_name: String
) -> void:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.position = local_position
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(sprite)


func _set_column_edge(column: Node2D, left_edge: bool, edge_bottom_y: float) -> void:
	if not is_instance_valid(column):
		return
	for child in column.get_children():
		if not child.has_meta("atlas_material"):
			continue
		var block := child as StaticBody2D
		var block_top_y := block.position.y - BLOCK_SIZE.y * 0.5
		if block_top_y < edge_bottom_y:
			_set_atlas_block_edge(block, left_edge)


func _set_atlas_block_edge(block: StaticBody2D, left_edge: bool) -> void:
	var material: AtlasMaterial = block.get_meta("atlas_material")
	var corner_texture := _atlas_corner_texture(material)
	var side_texture := _atlas_side_texture(material)
	var top_name := "TopLeft" if left_edge else "TopRight"
	var bottom_name := "BottomLeft" if left_edge else "BottomRight"
	var top_sprite := block.get_node(top_name) as Sprite2D
	var bottom_sprite := block.get_node(bottom_name) as Sprite2D
	top_sprite.texture = corner_texture if bool(block.get_meta("atlas_surface")) else side_texture
	bottom_sprite.texture = side_texture
	top_sprite.flip_h = left_edge
	bottom_sprite.flip_h = left_edge


func _atlas_ground_texture(material: AtlasMaterial) -> Texture2D:
	return BLUE_GROUND_TEXTURE if material == AtlasMaterial.BLUE else BLACK_GROUND_TEXTURE


func _atlas_corner_texture(material: AtlasMaterial) -> Texture2D:
	return BLUE_CORNER_TEXTURE if material == AtlasMaterial.BLUE else BLACK_CORNER_TEXTURE


func _atlas_center_texture(material: AtlasMaterial) -> Texture2D:
	return BLUE_CENTER_TEXTURE if material == AtlasMaterial.BLUE else BLACK_CENTER_TEXTURE


func _atlas_side_texture(material: AtlasMaterial) -> Texture2D:
	return BLUE_SIDE_TEXTURE if material == AtlasMaterial.BLUE else BLACK_SIDE_TEXTURE


func _add_ice_block(
	parent: Node2D,
	top_y: float,
	region: Rect2 = ICE_BLOCK_REGION,
	visual_scale: Vector2 = Vector2.ONE,
	collision_size: Vector2 = BLOCK_SIZE,
	collision_offset: Vector2 = Vector2.ZERO,
	texture: Texture2D = ICE_TEXTURE
) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(BLOCK_SIZE.x * 0.5, top_y + BLOCK_SIZE.y * 0.5)
	parent.add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = collision_size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = collision_offset
	body.add_child(collision)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.scale = visual_scale
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(sprite)


func _add_knockback_side(parent: Node2D, top_y: float, edge_height: float) -> void:
	# Die Zone steht ein wenig vor der linken Wand. Wer die Oberseite verfehlt,
	# wird getroffen und nach hinten geschleudert, statt sofort zu sterben.
	var knockback_area := Area2D.new()
	knockback_area.name = "KnockbackSide"
	knockback_area.position = Vector2(-8.0, top_y + edge_height * 0.5)
	knockback_area.collision_layer = 0
	knockback_area.collision_mask = 1
	parent.add_child(knockback_area)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(16.0, maxf(8.0, edge_height - 8.0))
	var collision := CollisionShape2D.new()
	collision.shape = shape
	knockback_area.add_child(collision)
	knockback_area.body_entered.connect(_on_knockback_side_entered)


func _on_knockback_side_entered(body: Node2D) -> void:
	if body == _player and body.has_method("apply_knockback"):
		body.call("apply_knockback")


func _maybe_add_decoration(parent: Node2D, surface_y: float, chance_percent: int) -> void:
	if _rng.randi_range(1, 100) > chance_percent:
		return

	var decoration_roll := _rng.randi_range(0, 99)
	if decoration_roll < 10:
		_add_clock_item(parent, surface_y)
	elif decoration_roll < 42:
		_add_random_tree(parent, surface_y)
	elif decoration_roll < 70:
		_add_penguin_decoration(parent, surface_y)
	elif decoration_roll < 97:
		_add_small_prop(parent, surface_y)
	else:
		# Diese Kappe zeigt im Atlas nach oben und wird daher nur auf einer
		# begehbaren Oberflaeche platziert, nie seitlich oder im Untergrund.
		_add_decoration_sprite(
			parent,
			ICE_ATLAS_TEXTURE,
			ATLAS_ICE_CAP_REGION,
			surface_y,
			Vector2.ONE
		)


func _add_random_tree(parent: Node2D, surface_y: float) -> void:
	var tree_region: Rect2 = TREE_REGIONS[_rng.randi_range(0, TREE_REGIONS.size() - 1)]
	var size_index := _rng.randi_range(0, TREE_SCALES.size() - 1)
	var tree_scale: float = TREE_SCALES[size_index]
	var horizontal_position := (
		_rng.randf_range(38.0, 58.0)
		if size_index == 2
		else _rng.randf_range(28.0, 68.0)
	)
	_add_decoration_sprite(
		parent,
		ICE_TEXTURE,
		tree_region,
		surface_y,
		Vector2(tree_scale, tree_scale),
		horizontal_position,
		TREE_NAMES[size_index]
	)


func _add_small_prop(parent: Node2D, surface_y: float) -> void:
	var prop_index := _rng.randi_range(0, SMALL_PROP_REGIONS.size() - 1)
	var prop_scale: float = SMALL_PROP_SCALES[prop_index]
	_add_decoration_sprite(
		parent,
		ICE_TEXTURE,
		SMALL_PROP_REGIONS[prop_index],
		surface_y,
		Vector2(prop_scale, prop_scale),
		_rng.randf_range(20.0, 76.0),
		"SmallProp"
	)


func _add_clock_item(parent: Node2D, surface_y: float) -> void:
	var clock_area := Area2D.new()
	clock_area.name = "ClockItem"
	clock_area.collision_layer = 0
	clock_area.collision_mask = 1
	clock_area.position = Vector2(48.0, surface_y - 38.0)
	parent.add_child(clock_area)

	var sprite := Sprite2D.new()
	sprite.texture = CLOCK_TEXTURE
	sprite.scale = Vector2(0.07, 0.07)
	sprite.z_index = 4
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clock_area.add_child(sprite)

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 27.0
	collision.shape = shape
	clock_area.add_child(collision)
	clock_area.body_entered.connect(_on_clock_body_entered.bind(clock_area))

	var bob_tween := clock_area.create_tween().set_loops()
	bob_tween.tween_property(clock_area, "position:y", surface_y - 45.0, 0.55)
	bob_tween.tween_property(clock_area, "position:y", surface_y - 38.0, 0.55)


func _on_clock_body_entered(body: Node2D, clock_area: Area2D) -> void:
	if body == _player:
		clock_collected.emit()
		clock_area.queue_free()


func _add_penguin_decoration(parent: Node2D, surface_y: float) -> void:
	# Gelegentliche Paare beleben die langen Plattformen, bleiben aber rein
	# visuell und veraendern weder Sprungweg noch Kollision.
	if _rng.randi_range(0, 99) < 35:
		_add_penguin(parent, surface_y, 30.0, 2.35, false)
		_add_penguin(parent, surface_y, 68.0, 2.2, true)
	else:
		_add_penguin(
			parent,
			surface_y,
			_rng.randf_range(32.0, 64.0),
			_rng.randf_range(2.55, 3.15),
			_rng.randi_range(0, 1) == 1
		)


func _add_guaranteed_start_decoration(parent: Node2D, column_x: float) -> void:
	# Sofort sichtbar: Damit man nicht auf einen guten Zufallswurf warten muss,
	# stehen im sicheren Startbereich immer ein Pinguin und eine Tanne.
	if is_equal_approx(column_x, 384.0):
		_add_penguin(parent, floor_y)
	elif is_equal_approx(column_x, 672.0):
		_add_decoration_sprite(parent, ICE_TEXTURE, TREE_REGIONS[0], floor_y, Vector2(3.8, 3.8))


func _add_penguin(
	parent: Node2D,
	surface_y: float,
	horizontal_position: float = 48.0,
	penguin_scale: float = 3.0,
	flip_horizontal: bool = false
) -> void:
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
	penguin.position = Vector2(horizontal_position, surface_y - 8.0 * penguin_scale)
	penguin.scale = Vector2(penguin_scale, penguin_scale)
	penguin.flip_h = flip_horizontal
	penguin.z_index = 2
	penguin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(penguin)
	penguin.play()


func _add_decoration_sprite(
	parent: Node2D,
	texture: Texture2D,
	region: Rect2,
	surface_y: float,
	decoration_scale: Vector2,
	horizontal_position: float = 48.0,
	node_name: String = "Decoration"
) -> void:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.position = Vector2(
		horizontal_position,
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


func get_camera_surface_y(world_x: float) -> float:
	# Die naechste existierende Bodenspalte bestimmt die Kamerahoehe. Da
	# Luecken gar keine Spalte besitzen, bleibt die Kamera beim Ueberspringen
	# stabil auf der letzten bzw. naechsten Landschaftshoehe.
	var closest_surface_y := floor_y
	var closest_distance := INF
	for column in _columns:
		if not is_instance_valid(column) or not column.has_meta("camera_surface_y"):
			continue
		var column_center_x := column.global_position.x + BLOCK_SIZE.x * 0.5
		var distance := absf(column_center_x - world_x)
		if distance < closest_distance:
			closest_distance = distance
			closest_surface_y = float(column.get_meta("camera_surface_y"))
	return closest_surface_y
