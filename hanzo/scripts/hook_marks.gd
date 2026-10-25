extends Control
## 鉤點記號（參考隻狼）：
##   射程內、在畫面裡的鉤點 → 鐵環上的白色小圈（3D 圓圈，hook_point.set_mark 管，由鏡頭自己投影，位置一定對）
##   點一下鉤繩會飛去的那個 → 綠色大圈
##   射程內但在畫面外       → 螢幕邊緣淡淡的白色小箭頭（只用「方向」，用鏡頭座標算，不需要像素換算）
## 射程外的鉤點不顯示。

var player: Node3D
const MAX_MARKS := 4
const EDGE := 46.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var range_m: float = player.get("hook_range") if player.get("hook_range") != null else 22.0
	var max_rise: float = player.HOOK_MAX_RISE
	var cands: Array = []
	var all := get_tree().get_nodes_in_group("hook_points")
	for n in all:
		var hp := n as Node3D
		if hp == null or not hp.is_visible_in_tree():
			continue
		var p := hp.global_position
		var d := player.global_position.distance_to(p)
		if d > range_m or d < 1.5 or p.y - player.global_position.y > max_rise:
			continue
		cands.append([d, hp])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# 點一下鉤繩會飛去的那個（瞄準中則是吸附中的那個）
	var pick: Node3D = null
	var rig = player.get("cam_rig")
	if rig != null and rig.has_method("aim_ray") and not cands.is_empty():
		var r: Array = rig.aim_ray()
		pick = player._pick_hook_point(r[0], r[1])
	var shown := {}
	var rect := get_viewport_rect()
	var center := rect.size / 2.0
	for i in range(mini(cands.size(), MAX_MARKS)):
		var hp: Node3D = cands[i][1]
		var world: Vector3 = hp.call("mark_pos") if hp.has_method("mark_pos") else hp.global_position + Vector3(0, 0.9, 0)
		if cam.is_position_in_frustum(world):
			shown[hp] = 2 if (hp == pick or hp.get("_target") == true) else 1
			continue
		# 畫面外：用鏡頭座標的左右／上下決定箭頭方向
		var local := cam.global_transform.affine_inverse() * world
		var dir := Vector2(local.x, -local.y)
		if dir.length() < 0.001:
			dir = Vector2.UP
		var top := 150.0
		var bottom := rect.size.y - 240.0
		var mid := Vector2(center.x, (top + bottom) / 2.0)
		var half := Vector2(rect.size.x / 2.0 - EDGE, (bottom - top) / 2.0)
		var k := minf(absf(half.x / maxf(absf(dir.x), 0.0001)), absf(half.y / maxf(absf(dir.y), 0.0001)))
		var ep := mid + dir * k
		var nd := dir.normalized()
		var col := Color(1, 1, 1, 0.55)
		draw_arc(ep, 7.0, 0.0, TAU, 20, col, 1.8, true)
		draw_colored_polygon(PackedVector2Array([ep + nd * 18.0, ep + nd * 10.0 + nd.orthogonal() * 5.0, ep + nd * 10.0 - nd.orthogonal() * 5.0]), col)
	for n in all:
		if n.has_method("set_mark"):
			n.set_mark(shown.get(n, 0))
