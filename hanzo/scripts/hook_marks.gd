extends Control
## 鉤點畫面記號（參考隻狼）：
##   射程內、看得到的鉤點 → 鐵環上出現白色小圓圈
##   準心吸附到的那一個   → 綠色圓圈、放大、外圈脈動（放開鉤繩就飛過去）
##   射程內但在畫面外     → 螢幕邊緣淡淡的白色小箭頭（直立手機視野窄，隻狼沒有這個，但手機需要）
## 射程外的鉤點不顯示任何記號。

var player: Node3D
const MAX_MARKS := 4
const EDGE := 46.0
const GREEN := Color(0.4, 1.0, 0.5)
## 座標換算方式（--markmode=N 測試用）
var _mode := 2   # 2＝扣掉 canvas_items 縮放（實測才對得準：視窗像素 ÷ 縮放倍率）


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--markmode="):
			_mode = int(a.substr(11))


func _process(_delta: float) -> void:
	queue_redraw()


## 3D 點 → 這個畫布上的座標（canvas_items 縮放＋介面大小倍率下，unproject 給的座標要再轉一次）
func _to_canvas(cam: Camera3D, world: Vector3) -> Vector2:
	var px := cam.unproject_position(world)
	match _mode:
		0:
			return px
		1:
			return get_viewport().get_canvas_transform().affine_inverse() * px
		2:
			return get_viewport().get_final_transform().affine_inverse() * px
	return px


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var range_m: float = player.get("hook_range") if player.get("hook_range") != null else 22.0
	var max_rise: float = player.HOOK_MAX_RISE
	var cands: Array = []
	for n in get_tree().get_nodes_in_group("hook_points"):
		var hp := n as Node3D
		if hp == null or not hp.is_visible_in_tree():
			continue
		var p := hp.global_position
		var d := player.global_position.distance_to(p)
		if d > range_m or d < 1.5 or p.y - player.global_position.y > max_rise:
			continue
		cands.append([d, hp])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# 沒在瞄準時：現在點一下鉤繩會飛去的那個點也亮綠色（隻狼：看得到綠圈就知道會鉤到哪）
	var pick: Node3D = null
	var rig = player.get("cam_rig")
	if player.get("aim_mode") == 0 and rig != null and rig.has_method("aim_ray") and not cands.is_empty():
		var r: Array = rig.aim_ray()
		pick = player._pick_hook_point(r[0], r[1])
	var rect := get_viewport_rect()
	var center := rect.size / 2.0
	var t := Time.get_ticks_msec() * 0.006
	for i in range(mini(cands.size(), MAX_MARKS)):
		var hp: Node3D = cands[i][1]
		var world: Vector3 = hp.call("mark_pos") if hp.has_method("mark_pos") else hp.global_position + Vector3(0, 0.9, 0)
		var target: bool = hp.get("_target") == true or hp == pick
		var behind := cam.is_position_behind(world)
		var sp := _to_canvas(cam, world)
		if behind:
			sp = center - (sp - center) * 1000.0
		var inside := not behind and sp.x > 8.0 and sp.x < rect.size.x - 8.0 and sp.y > 8.0 and sp.y < rect.size.y - 8.0
		if inside:
			if target:
				var pulse := 0.5 + 0.5 * sin(t * 1.6)
				draw_circle(sp, 15.0, Color(GREEN, 0.28))
				draw_arc(sp, 15.0, 0.0, TAU, 32, GREEN, 3.0, true)
				draw_arc(sp, 20.0 + pulse * 5.0, 0.0, TAU, 32, Color(GREEN, 0.6 * (1.0 - pulse)), 2.0, true)
				draw_circle(sp, 3.5, GREEN)
			else:
				draw_arc(sp, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 2.0, true)
				draw_circle(sp, 2.5, Color(1, 1, 1, 0.8))
		else:
			# 畫面外：淡白小箭頭，夾在「上面避開羅盤與任務字、下面避開按鍵」的區域
			var top := 150.0
			var bottom := rect.size.y - 240.0
			var mid := Vector2(center.x, (top + bottom) / 2.0)
			var dir := sp - mid
			if dir.length() < 0.01:
				dir = Vector2.UP
			var half := Vector2(rect.size.x / 2.0 - EDGE, (bottom - top) / 2.0)
			var k := minf(absf(half.x / maxf(absf(dir.x), 0.001)), absf(half.y / maxf(absf(dir.y), 0.001)))
			var ep := mid + dir * k
			var nd := dir.normalized()
			var col := Color(1, 1, 1, 0.55)
			draw_arc(ep, 7.0, 0.0, TAU, 20, col, 1.8, true)
			draw_colored_polygon(PackedVector2Array([ep + nd * 18.0, ep + nd * 10.0 + nd.orthogonal() * 5.0, ep + nd * 10.0 - nd.orthogonal() * 5.0]), col)
