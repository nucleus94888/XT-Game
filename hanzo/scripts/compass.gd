extends Control
## 忍者羅盤（圓形雷達）：鏡頭正前方永遠朝上；北以朱紅標示；
## 目標以三角在盤緣指向；敵人以紅點顯示相對位置（警戒中的敵人會脈動放大），超出範圍貼在盤緣。

var cam_yaw := 0.0
var player: Node3D
var has_target := false
var target_bearing := 0.0
var target_color := Color(0.6, 0.9, 1.0)
## 雷達範圍（公尺）
var range_m := 22.0

const CARDINALS := [["北", 0.0], ["東", PI * 0.5], ["南", PI], ["西", -PI * 0.5]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func cam_bearing() -> float:
	var f := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, cam_yaw)
	return atan2(f.x, -f.z)


func _process(_delta: float) -> void:
	queue_redraw()


func _rel_to_point(rel: float, r: float) -> Vector2:
	return Vector2(sin(rel), -cos(rel)) * r


func _draw() -> void:
	var c := size / 2.0
	var R := minf(size.x, size.y) / 2.0
	var cb := cam_bearing()
	var font: Font = Fx.ui_font
	# 盤面
	draw_circle(c, R, Color(0.05, 0.05, 0.07, 0.72))
	draw_arc(c, R - 1.5, 0.0, TAU, 64, Color(0.85, 0.8, 0.7, 0.85), 2.5, true)
	draw_arc(c, R * 0.55, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 1.0, true)
	# 中央手裏劍（四芒）
	var star := PackedVector2Array()
	for i in range(8):
		var a := i * TAU / 8.0 - PI / 2.0
		var rr := R * 0.22 if i % 2 == 0 else R * 0.07
		star.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(star, Color(1, 1, 1, 0.18))
	# 方位
	for cd in CARDINALS:
		var rel := wrapf(float(cd[1]) - cb, -PI, PI)
		var p := c + _rel_to_point(rel, R - 13.0)
		var col := Color(0.95, 0.35, 0.3) if cd[0] == "北" else Color(0.9, 0.88, 0.8, 0.85)
		var tick0 := c + _rel_to_point(rel, R - 2.0)
		var tick1 := c + _rel_to_point(rel, R - 7.0)
		draw_line(tick0, tick1, col, 2.0)
		if font:
			draw_string(font, p + Vector2(-9.0, 6.0), cd[0], HORIZONTAL_ALIGNMENT_CENTER, 18.0, 15, col)
	# 敵人紅點
	if player:
		var t := float(Time.get_ticks_msec()) * 0.006
		for e in get_tree().get_nodes_in_group("enemies"):
			if not (e is Node3D) or e.get("state") == null:
				continue
			if e.state == e.State.DEAD:
				continue
			var d: Vector3 = e.global_position - player.global_position
			d.y = 0.0
			var dist := d.length()
			var rel := wrapf(atan2(d.x, -d.z) - cb, -PI, PI)
			var alert: bool = e.state in [e.State.ALERT, e.State.ATTACK, e.State.STAGGER, e.State.BROKEN]
			var suspicious: bool = e.state == e.State.SUSPICIOUS
			if dist > range_m:
				draw_circle(c + _rel_to_point(rel, R - 5.0), 2.5, Color(1.0, 0.3, 0.25, 0.45))
				continue
			var p := c + _rel_to_point(rel, dist / range_m * (R - 8.0))
			var rad := 4.0
			var col := Color(0.95, 0.25, 0.2, 0.9)
			if alert:
				rad = 5.0 + 1.5 * (0.5 + 0.5 * sin(t))
				col = Color(1.0, 0.15, 0.1, 1.0)
				draw_arc(p, rad + 3.0, 0.0, TAU, 20, Color(1.0, 0.3, 0.2, 0.5), 1.0, true)
			elif suspicious:
				col = Color(1.0, 0.7, 0.3, 0.95)
			draw_circle(p, rad, col)
	# 目標三角
	if has_target:
		var rel := wrapf(target_bearing - cb, -PI, PI)
		var tip := c + _rel_to_point(rel, R - 3.0)
		var base := c + _rel_to_point(rel, R - 13.0)
		var side := Vector2(cos(rel), sin(rel)) * 6.0
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), target_color)
	# 玩家（中心白點）
	draw_circle(c, 3.5, Color(1, 1, 1, 0.95))
