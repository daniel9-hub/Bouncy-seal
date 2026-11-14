extends Node3D

var scenes = [
		preload("res://snow_block_1.tscn"),
		preload("res://block_1.tscn"),
		preload("res://snow_block_spike.tscn")
	]
var instance
func _ready() -> void:
	pass


func _process(delta: float) -> void:
	pass


func _on_area_3d_body_entered(body: Node3D) -> void:
	body.queue_free()
	instance = scenes.pick_random().instantiate()
	instance.position = Vector3(0,-4,0)
	instance.position.z = $Player3d.position.z + 30
	print(instance.position)
	self.add_child(instance)
