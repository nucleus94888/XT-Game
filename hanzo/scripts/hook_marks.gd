extends Control
## 鉤點畫面記號（第十三次議會驗收時發現：直立手機鏡頭在決定點只看得到正前方，側邊屋簷的鉤點都在畫面外）。
## 照隻狼：射程內、看得到的鉤點，在畫面上畫一個金色菱形；跑出畫面外就貼在螢幕邊緣、尖端指向它。
## 最多畫最近的 4 個；準心吸附中的那個畫大、畫亮。

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
	var rect := get_viewport_rect()
	if OS.is_debug_build() and Engine.get_process_frames() % 120 == 0 and "--markdebug" in OS.get_cmdline_user_args():
		print("MARKS cands=%d rect=%s" % [cands.size(), rect])
	var center := rect.size / 2.0
	var t := Time.get_ticks_msec() * 0.004
	for i in range(mini(cands.size(), MAX_MARKS)):
		var hp: Node3D = cands[i][1]
		var world := hp.global_position + Vector3(0, 1.3, 0)
		var target: bool = hp.get("_target") == true
		var behind := cam.is_position_behind(world)
		var sp := cam.unproject_position(world)
		if behind:
			sp = center - (sp - center) * 1000.0
		var inside := not behind and sp.x > EDGE and sp.x < rect.size.x - EDGE and sp.y > EDGE and sp.y < rect.size.y - EDGE
		var col := Color(1.0, 1.0, 0.7, 0.95) if target else Color(1.0, 0.82, 0.35, 0.85)
		if inside:
			var r := (15.0 if target else 9.0) + sin(t + i) * 1.5
			_diamond(sp, r, col, target)
		else:
			# 夾到螢幕邊緣，菱形加一個指向它的小尖角
			var dir := (sp - center)
			if dir.length() < 0.01:
				dir = Vector2.UP
			# 夾在「上面避開羅盤與任務字、下面避開按鍵」的區域裡（不然邊緣記號會被 HUD 蓋住）
			var top := 150.0
			var bottom := rect.size.y - 240.0
			var mid := Vector2(center.x, (top + bottom) / 2.0)
			dir = sp - mid
			if dir.length() < 0.01:
				dir = Vector2.UP
			var half := Vector2(rect.size.x / 2.0 - EDGE, (bottom - top) / 2.0)
			var k := minf(absf(half.x / maxf(absf(dir.x), 0.001)), absf(half.y / maxf(absf(dir.y), 0.001)))
			var ep := mid + dir * k
			var nd := dir.normalized()
			_diamond(ep, 10.0, Color(col, 0.75), false)
			draw_colored_polygon(PackedVector2Array([ep + nd * 22.0, ep + nd * 12.0 + nd.orthogonal() * 6.0, ep + nd * 12.0 - nd.orthogonal() * 6.0]), Color(col, 0.75))


func _diamond(c: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	if filled:
		draw_colored_polygon(pts, Color(col, 0.6))
	pts.append(pts[0])
	draw_polyline(pts, col, 2.5, true)
