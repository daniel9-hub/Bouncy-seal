extends Control

func _ready() -> void:
	$TwoDButton.grab_focus()


func _on_two_d_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func _on_three_d_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main3d.tscn")
