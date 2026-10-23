extends Control
## 指南針帶：北東南西隨鏡頭轉動；目標以三角標示方位，超出視野貼邊。
## 北 = 世界 -Z。方位角 bearing = atan2(x, -z)，順時針為正（東 = +X）。

var cam_yaw := 0.0
var has_target := false
var target_bearing := 0.0
var target_color := Color(0.6, 0.9, 1.0)

const HALF_FOV := PI * 0.5   # 帶子左右各顯示 90°
const CARDINALS := [["北", 0.0], ["東", PI * 0.5], ["南", PI], ["西", -PI * 0.5]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func cam_bearing() -> float:
	var f := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, cam_yaw)
	return atan2(f.x, -f.z)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cb := cam_bearing()
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.35))
	draw_line(Vector2(w / 2.0, 0), Vector2(w / 2.0, h), Color(1, 1, 1, 0.5), 2.0)
	var font: Font = Fx.ui_font
	for c in CARDINALS:
		var rel := wrapf(float(c[1]) - cb, -PI, PI)
		if absf(rel) > HALF_FOV:
			continue
		var x := w / 2.0 + rel / HALF_FOV * (w / 2.0)
		var a := 1.0 - pow(absf(rel) / HALF_FOV, 2.0) * 0.7
		var col := Color(1, 0.45, 0.4, a) if c[0] == "北" else Color(1, 1, 1, a)
		draw_line(Vector2(x, h - 6), Vector2(x, h), col, 2.0)
		if font:
			draw_string(font, Vector2(x - 12, h - 9), c[0], HORIZONTAL_ALIGNMENT_CENTER, 24, 18, col)
	# 每 30° 一個小刻度
	for i in range(12):
		var b := i * PI / 6.0
		var rel := wrapf(b - cb, -PI, PI)
		if absf(rel) > HALF_FOV:
			continue
		var x := w / 2.0 + rel / HALF_FOV * (w / 2.0)
		draw_line(Vector2(x, h - 4), Vector2(x, h), Color(1, 1, 1, 0.3), 1.0)
	if has_target:
		var rel := wrapf(target_bearing - cb, -PI, PI)
		var clamped := clampf(rel, -HALF_FOV, HALF_FOV)
		var x := w / 2.0 + clamped / HALF_FOV * (w / 2.0 - 8.0)
		var pts := PackedVector2Array([Vector2(x, 2), Vector2(x - 8, 14), Vector2(x + 8, 14)])
		var col := target_color if absf(rel) <= HALF_FOV else Color(target_color, 0.6)
		draw_colored_polygon(pts, col)
