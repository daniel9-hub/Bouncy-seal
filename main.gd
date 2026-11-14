extends Node2D

const CAMERA_SPEED := 165.0
const LEFT_EDGE_GRACE := 24.0
const TILE_TEXTURE := preload("res://assets/SnowTileset/SnowTileset.png")
const PENGUIN_TEXTURE := preload("res://assets/SnowTileset/Animations/penguinAnimationsPng.png")

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Player/Camera2D
@onready var level: Node2D = $Level
@onready var ui: CanvasLayer = $UI

var _score_label: Label
var _game_over_overlay: Control
var _death_reason_label: Label
var _final_score_label: Label
var _restart_button: Button
var _start_camera_x := 0.0
var _distance := 0
var _game_over := false


func _ready() -> void:
	# Die Team-Szene darf ihre alte Player-Kamera behalten. Zur Laufzeit wird sie
	# zur unabhaengigen Runner-Kamera, damit Editor-Saves nichts kaputtmachen.
	camera.reparent(self, true)
	camera.global_position = Vector2(576.0, 300.0)
	camera.position_smoothing_enabled = false
	_start_camera_x = camera.global_position.x

	_build_ui()
	level.player_died.connect(_on_level_hazard)
	_restart_button.pressed.connect(_restart_game)


func _process(delta: float) -> void:
	if _game_over:
		if Input.is_action_just_pressed("restart"):
			_restart_game()
		return

	# Der Bildschirm laeuft konstant nach rechts. Die Robbe muss mitkommen.
	camera.global_position.x += CAMERA_SPEED * delta
	_distance = maxi(0, int((camera.global_position.x - _start_camera_x) / 100.0))
	_score_label.text = "%04d m" % _distance

	var half_view_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var camera_left_edge := camera.global_position.x - half_view_width
	if player.global_position.x < camera_left_edge + LEFT_EDGE_GRACE:
		_finish_run("THE CAMERA CAUGHT YOU")
	elif player.global_position.y > 760.0:
		_finish_run("YOU FELL INTO THE COLD")
	elif Input.is_action_just_pressed("restart"):
		_restart_game()


func _on_level_hazard() -> void:
	_finish_run("YOU MISSED THE PLATFORM")


func _finish_run(reason: String) -> void:
	if _game_over:
		return
	_game_over = true
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	level.set_process(false)
	_death_reason_label.text = reason
	_final_score_label.text = "%04d METERS" % _distance
	_game_over_overlay.show()
	_restart_button.grab_focus()


func _restart_game() -> void:
	get_tree().reload_current_scene()


func _build_ui() -> void:
	# Die alten Prototyp-Labels bleiben in der Team-Szene erhalten, werden aber
	# durch das neue HUD ersetzt.
	for old_control: Node in ui.get_children():
		if old_control is Control:
			old_control.hide()

	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["DejaVu Sans", "Noto Sans", "Arial"])
	ui_font.font_weight = 700
	var ui_theme := Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 18

	var hud := Control.new()
	hud.name = "RunnerHUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = ui_theme
	ui.add_child(hud)

	var score_panel := PanelContainer.new()
	score_panel.name = "ScorePanel"
	score_panel.anchor_left = 0.5
	score_panel.anchor_right = 0.5
	score_panel.offset_left = -155.0
	score_panel.offset_top = 16.0
	score_panel.offset_right = 155.0
	score_panel.offset_bottom = 82.0
	score_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.035, 0.16, 0.25, 0.92), Color(0.72, 0.92, 1.0), 18, 8)
	)
	hud.add_child(score_panel)

	var score_margin := MarginContainer.new()
	_set_margins(score_margin, 18, 8, 18, 8)
	score_panel.add_child(score_margin)
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 13)
	score_margin.add_child(score_row)

	var score_icon := TextureRect.new()
	score_icon.custom_minimum_size = Vector2(42.0, 42.0)
	score_icon.texture = _atlas(TILE_TEXTURE, Rect2(680.0, 134.0, 32.0, 28.0))
	score_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	score_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	score_row.add_child(score_icon)

	var score_title := Label.new()
	score_title.text = "DISTANCE"
	score_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_title.add_theme_color_override("font_color", Color(0.69, 0.88, 0.96))
	score_title.add_theme_font_size_override("font_size", 14)
	score_row.add_child(score_title)

	_score_label = Label.new()
	_score_label.text = "0000 m"
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.add_theme_color_override("font_color", Color.WHITE)
	_score_label.add_theme_font_size_override("font_size", 27)
	score_row.add_child(_score_label)

	var help := Label.new()
	help.text = "A / D  MOVE     R  RESTART"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 24.0
	help.offset_top = -48.0
	help.offset_right = 340.0
	help.offset_bottom = -16.0
	help.add_theme_color_override("font_color", Color(0.04, 0.18, 0.28, 0.9))
	help.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.8))
	help.add_theme_constant_override("shadow_offset_x", 1)
	help.add_theme_constant_override("shadow_offset_y", 1)
	help.add_theme_font_size_override("font_size", 16)
	hud.add_child(help)

	_build_game_over(ui_theme)


func _build_game_over(ui_theme: Theme) -> void:
	_game_over_overlay = Control.new()
	_game_over_overlay.name = "GameOver"
	_game_over_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.theme = ui_theme
	ui.add_child(_game_over_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.015, 0.07, 0.12, 0.72)
	_game_over_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520.0, 350.0)
	card.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.055, 0.2, 0.3, 0.98), Color(0.75, 0.94, 1.0), 26, 18)
	)
	center.add_child(card)

	var margin := MarginContainer.new()
	_set_margins(margin, 54, 38, 54, 34)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	var title := _center_label("FROZEN OUT!", 42, Color(0.86, 0.97, 1.0))
	content.add_child(title)
	_death_reason_label = _center_label("THE CAMERA CAUGHT YOU", 17, Color(0.61, 0.83, 0.92))
	content.add_child(_death_reason_label)
	_final_score_label = _center_label("0000 METERS", 31, Color.WHITE)
	content.add_child(_final_score_label)

	_restart_button = Button.new()
	_restart_button.custom_minimum_size = Vector2(0.0, 72.0)
	_restart_button.text = "START AGAIN"
	_restart_button.icon = _atlas(PENGUIN_TEXTURE, Rect2(16.0, 0.0, 16.0, 16.0))
	_restart_button.expand_icon = true
	_restart_button.add_theme_font_size_override("font_size", 24)
	_restart_button.add_theme_color_override("font_color", Color(0.02, 0.15, 0.23))
	_restart_button.add_theme_color_override("font_hover_color", Color(0.01, 0.11, 0.18))
	_restart_button.add_theme_color_override("font_pressed_color", Color(0.84, 0.97, 1.0))
	_restart_button.add_theme_stylebox_override("normal", _button_style(Color(0.22, 0.66, 0.82), 2))
	_restart_button.add_theme_stylebox_override("hover", _button_style(Color(0.35, 0.8, 0.92), 3))
	_restart_button.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.47, 0.66), 3))
	content.add_child(_restart_button)

	var hint := _center_label("CLICK THE PENGUIN OR PRESS R", 14, Color(0.53, 0.74, 0.83))
	content.add_child(hint)
	_game_over_overlay.hide()


func _center_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _set_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)


func _panel_style(background: Color, border: Color, radius: int, shadow: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.01, 0.04, 0.08, 0.55)
	style.shadow_size = shadow
	return style


func _button_style(background: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color(0.82, 0.97, 1.0)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(14)
	return style


func _atlas(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = texture
	atlas_texture.region = region
	return atlas_texture
