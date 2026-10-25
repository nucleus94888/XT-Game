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


## 畫面記號：掛在鐵環上的 3D 圓圈（永遠面向鏡頭、固定螢幕大小、不被牆擋）。
## 以前在 2D 畫面上算位置，網頁版的縮放跟本機不同，圓圈畫到別的地方去。改成 3D 就由鏡頭自己投影，哪台裝置都對得準。
## 0＝不顯示、1＝白色小圈（射程內）、2＝綠色大圈（點一下會鉤到這個）
static var _ring_tex: ImageTexture
var _icon: MeshInstance3D
var _icon_mat: StandardMaterial3D
var _mark := 0


func set_mark(m: int) -> void:
	if m == _mark:
		return
	_mark = m
	if _icon == null:
		_build_icon()
	_icon.visible = m > 0
	_icon_mat.albedo_color = Color(0.45, 1.0, 0.55, 0.95) if m == 2 else Color(1, 1, 1, 0.8)


func _build_icon() -> void:
	if _ring_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in range(64):
			for x in range(64):
				var d := Vector2(x - 31.5, y - 31.5).length()
				var a := 0.0
				if d > 24.0 and d < 30.0:
					a = 1.0
				elif d < 5.0:
					a = 1.0
				elif d >= 30.0 and d < 31.5:
					a = 31.5 - d
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		_ring_tex = ImageTexture.create_from_image(img)
	_icon = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_icon.mesh = q
	_icon_mat = StandardMaterial3D.new()
	_icon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_icon_mat.albedo_texture = _ring_tex
	_icon_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_icon_mat.fixed_size = true
	_icon_mat.no_depth_test = true
	_icon_mat.render_priority = 10
	_icon.material_override = _icon_mat
	_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_icon)
	_icon.top_level = true


func _process(delta: float) -> void:
	_t += delta
	# 被吸附時鐵環輕輕晃
	_ring.rotation.x = sin(_t * 9.0) * 0.25 if (_target or _mark == 2) else 0.0
	if _icon and _icon.visible:
		_icon.global_position = _ring.global_position
		# 固定螢幕大小的材質會忽略縮放，只能改網格尺寸（1.0 ≈ 畫面高的四成）：白圈小、綠圈大且輕輕脈動
		var s := 0.03 if _mark == 1 else 0.05 + 0.005 * sin(_t * 9.0)
		(_icon.mesh as QuadMesh).size = Vector2(s, s)


func land_pos() -> Vector3:
	return global_position


## 畫面記號錨點：鐵環的位置
func mark_pos() -> Vector3:
	return _ring.global_position


func set_target(on: bool) -> void:
	_target = on
