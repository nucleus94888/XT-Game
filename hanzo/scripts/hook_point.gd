extends Node3D
## 鉤點（第十三次議會：鉤繩改成「只能鉤發光鉤點」，照隻狼）。
## 節點位置＝落腳點（屋脊、牆頂、平台）；落腳點上方 1.3 公尺浮一顆金色菱形＋一圈光環，遠遠就看得到。
## 玩家按住鉤繩時自動吸附畫面前方最近的鉤點，被選中的那一顆變大變亮。
## 關卡裡一個鉤點都沒有時，鉤繩退回舊的「任何牆頂／屋頂邊緣」判定（道場、測試場景）。

var _gem: MeshInstance3D
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _t := randf() * TAU
var _target := false


func _ready() -> void:
	add_to_group("hook_points")
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.82, 0.35)
	_gem = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.28, 0.28)
	_gem.mesh = bm
	_gem.material_override = _mat
	_gem.rotation_degrees = Vector3(45, 0, 45)
	_gem.position = Vector3(0, 1.3, 0)
	_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gem)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.36
	tm.outer_radius = 0.42
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1.0, 0.85, 0.4, 0.55)
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_ring.material_override = rm
	_ring.rotation_degrees = Vector3(90, 0, 0)
	_ring.position = _gem.position
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	# 細繩垂到落腳點：看得出「鉤上去會落在哪」
	var cord := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.03, 1.1, 0.03)
	cord.mesh = cm
	cord.material_override = _mat
	cord.position = Vector3(0, 0.6, 0)
	add_child(cord)


func _process(delta: float) -> void:
	_t += delta
	_gem.rotation.y += delta * (4.0 if _target else 1.2)
	_gem.position.y = 1.3 + sin(_t * 2.0) * 0.06
	_ring.position.y = _gem.position.y
	var s := 1.7 if _target else 1.0 + 0.08 * sin(_t * 3.0)
	_gem.scale = _gem.scale.lerp(Vector3.ONE * s, 1.0 - exp(-12.0 * delta))
	_ring.scale = _gem.scale * (1.0 + (0.25 * absf(sin(_t * 6.0)) if _target else 0.0))
	_mat.albedo_color = Color(1.0, 1.0, 0.75) if _target else Color(1.0, 0.82, 0.35)


func land_pos() -> Vector3:
	return global_position


## 準心吸附到這一顆時亮起來
func set_target(on: bool) -> void:
	_target = on
