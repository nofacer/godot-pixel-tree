@tool
extends EditorPlugin

const PIXEL_TREE_SCRIPT := preload("res://addons/pixel_tree/pixel_tree_node.gd")
const PIXEL_TREE_ICON := preload("res://icon.svg")


func _enter_tree() -> void:
	add_custom_type("PixelTree", "Node2D", PIXEL_TREE_SCRIPT, PIXEL_TREE_ICON)


func _exit_tree() -> void:
	remove_custom_type("PixelTree")
