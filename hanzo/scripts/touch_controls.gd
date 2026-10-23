extends Control
## 觸控操作：左 60% 畫面為「浮動搖桿」（手指落點即中心，拖超出半徑時中心跟著走），
## 右下兩顆鍵：「斬」攻擊、「閃」閃步。桌機以滑鼠模擬觸控，另有鍵盤 WASD / J / K。

signal attack_pressed
signal dash_pressed

const JOY_R := 72.0
const ATK_R := 66.0
const DASH_R := 46.0

var move_vector := Vector2.ZERO
## 這些控制項可見且覆蓋到的區域，不會觸發搖桿（例如手感面板）
var blockers: Array[Control] = []

var _joy_idx := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _btn_touch := {}
var _atk_flash := 0.0
var _dash_flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _atk_center() -> Vector2:
	return Vector2(size.x - 120.0, size.y - 120.0)


func _dash_center() -> Vector2:
	return Vector2(size.x - 250.0, size.y - 78.0)


func _blocked(pos: Vector2) -> bool:
	for b in blockers:
		if b and b.visible and b.get_global_rect().has_point(pos):
			return true
	return false


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			if _blocked(t.position):
				return
			if t.position.distance_to(_atk_center()) < ATK_R * 1.35:
				_btn_touch[t.index] = "attack"
				_atk_flash = 1.0
				attack_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if t.position.distance_to(_dash_center()) < DASH_R * 1.5:
				_btn_touch[t.index] = "dash"
				_dash_flash = 1.0
				dash_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if _joy_idx == -1 and t.position.x < size.x * 0.6:
				_joy_idx = t.index
				_joy_origin = t.position
				_joy_pos = t.position
				move_vector = Vector2.ZERO
				get_viewport().set_input_as_handled()
		else:
			if t.index == _joy_idx:
				_joy_idx = -1
				move_vector = Vector2.ZERO
			_btn_touch.erase(t.index)
	elif ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		if d.index == _joy_idx:
			_joy_pos = d.position
			var v := _joy_pos - _joy_origin
			var l := v.length()
			if l > JOY_R:
				_joy_origin = _joy_pos - v / l * JOY_R
				v = v / l * JOY_R
				l = JOY_R
			var n := l / JOY_R
			move_vector = Vector2.ZERO if n < 0.12 else v / JOY_R
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_atk_flash = maxf(_atk_flash - delta * 5.0, 0.0)
	_dash_flash = maxf(_dash_flash - delta * 5.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var font: Font = Fx.ui_font
	if _joy_idx != -1:
		draw_circle(_joy_origin, JOY_R, Color(1, 1, 1, 0.07))
		draw_arc(_joy_origin, JOY_R, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		draw_circle(_joy_pos, 28.0, Color(1, 1, 1, 0.55))
	var ac := _atk_center()
	draw_circle(ac, ATK_R, Color(0.72, 0.14, 0.12, 0.55 + 0.4 * _atk_flash))
	draw_arc(ac, ATK_R, 0.0, TAU, 64, Color(1, 0.92, 0.85, 0.9), 3.0, true)
	if font:
		draw_string(font, ac + Vector2(-ATK_R, 15.0), "斬", HORIZONTAL_ALIGNMENT_CENTER, ATK_R * 2.0, 42, Color(1, 1, 1, 0.95))
	var dc := _dash_center()
	draw_circle(dc, DASH_R, Color(0.2, 0.3, 0.55, 0.5 + 0.4 * _dash_flash))
	draw_arc(dc, DASH_R, 0.0, TAU, 48, Color(0.85, 0.9, 1, 0.85), 2.5, true)
	if font:
		draw_string(font, dc + Vector2(-DASH_R, 11.0), "閃", HORIZONTAL_ALIGNMENT_CENTER, DASH_R * 2.0, 30, Color(1, 1, 1, 0.95))
