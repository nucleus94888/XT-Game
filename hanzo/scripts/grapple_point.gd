extends Node3D
class_name GrapplePoint
## 鉤繩點：放在屋頂／牆頂。半藏在範圍內面向它時會亮起，按「鉤」飛過去落在 land_offset 位置。

@export var land_offset := Vector3.ZERO

var highlight := false
var _t := 0.0
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	add_to_group("grapple")
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.42
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.6, 0.9, 1.0, 0.7)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = true
	_ring.mesh = tm
	_ring.material_override = _mat
	_ring.rotation.x = PI / 2.0
	add_child(_ring)
	_label = Label3D.new()
	_label.text = "鉤"
	_label.font = Fx.ui_font
	_label.font_size = 72
	_label.pixel_size = 0.012
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 10
	_label.modulate = Color(0.7, 0.95, 1.0)
	_label.position = Vector3(0, 0.9, 0)
	_label.visible = false
	add_child(_label)


func landing() -> Vector3:
	return global_position + land_offset


func _process(delta: float) -> void:
	_t += delta
	_ring.rotation.z += delta * (3.0 if highlight else 0.8)
	var s := 1.0 + (0.25 * (0.5 + 0.5 * sin(_t * 8.0)) if highlight else 0.0)
	_ring.scale = Vector3.ONE * s
	_mat.albedo_color = Color(1.0, 0.95, 0.6, 0.95) if highlight else Color(0.6, 0.9, 1.0, 0.55)
	_label.visible = highlight
