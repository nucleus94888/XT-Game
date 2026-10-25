extends Node3D
## 鉤點（第十三次議會：鉤繩只能鉤鉤點；之後使用者要求「參考隻狼」）。
## 隻狼的鉤點是場景裡本來就有的東西（樹枝、屋簷的橫木），本身不發光；
## 進入射程時畫面上才在它上面出現圓形記號（白），準心吸附到的那個變綠、放大（hook_marks.gd 畫）。
## 這裡只做外觀：一截從落腳點旁邊突出的木樑＋掛著的鐵環。節點位置＝落腳點。

var _target := false
var _ring: MeshInstance3D
var _t := randf() * TAU


func _ready() -> void:
	add_to_group("hook_points")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.21, 0.13)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.32, 0.35)
	iron.metallic = 0.7
	iron.roughness = 0.4
	# 木樑：落腳點上方 0.9 公尺，斜斜往外伸 0.8 公尺
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.9)
	beam.mesh = bm
	beam.material_override = wood
	beam.position = Vector3(0, 0.95, 0.25)
	beam.rotation_degrees = Vector3(-12, 0, 0)
	add_child(beam)
	# 樑頭的鐵環
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.15
	tm.rings = 12
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring.material_override = iron
	_ring.position = Vector3(0, 0.88, 0.62)
	_ring.rotation_degrees = Vector3(0, 0, 90)
	add_child(_ring)
	_orient.call_deferred()


## 木樑朝「最空曠」的方向伸出去（像屋簷橫木伸向巷子），不要插進牆裡
func _orient() -> void:
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.9, 0)
	var best_a := 0.0
	var best_d := -1.0
	for i in range(8):
		var a := TAU * i / 8.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4.0, 1)
		var hit := space.intersect_ray(q)
		var d := 4.0 if hit.is_empty() else from.distance_to(hit.position)
		if d > best_d + 0.01:
			best_d = d
			best_a = a
	rotation.y = best_a


func _process(delta: float) -> void:
	_t += delta
	# 被吸附時鐵環輕輕晃（不發光，記號由畫面上的圓圈負責）
	_ring.rotation.x = sin(_t * 9.0) * 0.25 if _target else 0.0


func land_pos() -> Vector3:
	return global_position


## 畫面記號錨點：鐵環的位置
func mark_pos() -> Vector3:
	return _ring.global_position


func set_target(on: bool) -> void:
	_target = on
