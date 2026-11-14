extends Control

@onready var status_label: Label = $Status

var _status_tween: Tween


func _ready() -> void:
	$TwoDButton.grab_focus()


func _on_two_d_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func _on_three_d_button_pressed() -> void:
	if _status_tween and _status_tween.is_valid():
		_status_tween.kill()
	status_label.text = "3D MODE COMING SOON!"
	status_label.visible = true
	status_label.modulate = Color.WHITE
	_status_tween = create_tween()
	_status_tween.tween_interval(1.5)
	_status_tween.tween_property(status_label, "modulate:a", 0.0, 0.35)
	_status_tween.tween_callback(func() -> void: status_label.visible = false)
