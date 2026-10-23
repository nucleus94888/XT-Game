extends Control
## 觸控操作
## 左：常駐淡白色搖桿圓圈（左下），手指落在左 60% 畫面任意處即以落點為中心；拖超出半徑時圓圈跟著走。
## 右：「攻擊」（紅，大）、「閃」（藍）、「格擋」（綠，按住生效）。桌機以滑鼠模擬觸控，另有鍵盤。

signal attack_pressed
signal dash_pressed
signal block_changed(on: bool)
signal throw_pressed
## 右側空白處拖曳：轉視角（螢幕像素位移）
signal look_delta(delta: Vector2)

const JOY_R := 78.0
const ATK_R := 70.0
const DASH_R := 50.0
const BLOCK_R := 50.0
const THROW_R := 44.0

var move_vector := Vector2.ZERO
## 這些控制項可見且覆蓋到的區域，不會觸發搖桿（例如手感面板）
var blockers: Array[Control] = []

var _joy_idx := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _btn_touch := {}
var _atk_flash := 0.0
var _dash_flash := 0.0
var _block_on := false
var _throw_flash := 0.0
## 第四鍵顯示文字（投＝手裡劍，鉤＝鉤繩）與剩餘手裡劍數
var throw_label := "投"
var throw_count := 0
var _look_idx := -1
var _look_last := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _joy_home() -> Vector2:
	return Vector2(150.0, size.y - 150.0)


## 鍵位離角落稍遠一點，拇指自然彎曲就按得到，也避開 iPhone 圓角與手勢區
func _atk_center() -> Vector2:
	return Vector2(size.x - 140.0, size.y - 140.0)


func _dash_center() -> Vector2:
	return Vector2(size.x - 290.0, size.y - 92.0)


func _block_center() -> Vector2:
	return Vector2(size.x - 130.0, size.y - 300.0)


func _throw_center() -> Vector2:
	return Vector2(size.x - 300.0, size.y - 235.0)


func _blocked(pos: Vector2) -> bool:
	for b in blockers:
		if b and b.visible and b.get_global_rect().has_point(pos):
			return true
	return false


func _set_block(on: bool) -> void:
	if _block_on == on:
		return
	_block_on = on
	block_changed.emit(on)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			if _blocked(t.position):
				return
			if t.position.distance_to(_atk_center()) < ATK_R * 1.3:
				_btn_touch[t.index] = "attack"
				_atk_flash = 1.0
				attack_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if t.position.distance_to(_dash_center()) < DASH_R * 1.45:
				_btn_touch[t.index] = "dash"
				_dash_flash = 1.0
				dash_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if t.position.distance_to(_throw_center()) < THROW_R * 1.4:
				_btn_touch[t.index] = "throw"
				_throw_flash = 1.0
				throw_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if t.position.distance_to(_block_center()) < BLOCK_R * 1.45:
				_btn_touch[t.index] = "block"
				_set_block(true)
				get_viewport().set_input_as_handled()
				return
			if _joy_idx == -1 and t.position.x < size.x * 0.6:
				_joy_idx = t.index
				_joy_origin = t.position
				_joy_pos = t.position
				move_vector = Vector2.ZERO
				get_viewport().set_input_as_handled()
			elif _look_idx == -1 and t.position.x >= size.x * 0.6:
				_look_idx = t.index
				_look_last = t.position
				get_viewport().set_input_as_handled()
		else:
			if t.index == _joy_idx:
				_joy_idx = -1
				move_vector = Vector2.ZERO
			if t.index == _look_idx:
				_look_idx = -1
			if _btn_touch.get(t.index, "") == "block":
				_set_block(false)
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
		elif d.index == _look_idx:
			look_delta.emit(d.position - _look_last)
			_look_last = d.position
			get_viewport().set_input_as_handled()
		elif _btn_touch.get(d.index, "") == "block":
			# 手指滑出格擋鍵太遠就視為放開
			if d.position.distance_to(_block_center()) > BLOCK_R * 2.2:
				_btn_touch.erase(d.index)
				_set_block(false)


func _process(delta: float) -> void:
	_atk_flash = maxf(_atk_flash - delta * 5.0, 0.0)
	_dash_flash = maxf(_dash_flash - delta * 5.0, 0.0)
	_throw_flash = maxf(_throw_flash - delta * 5.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var font: Font = Fx.ui_font
	# 搖桿：閒置時停在左下，按住時跟著手指
	var jc := _joy_origin if _joy_idx != -1 else _joy_home()
	draw_circle(jc, JOY_R, Color(1, 1, 1, 0.10 if _joy_idx != -1 else 0.07))
	draw_arc(jc, JOY_R, 0.0, TAU, 48, Color(1, 1, 1, 0.42 if _joy_idx != -1 else 0.28), 2.5, true)
	var knob := _joy_pos if _joy_idx != -1 else jc
	draw_circle(knob, 28.0, Color(1, 1, 1, 0.55 if _joy_idx != -1 else 0.22))
	# 攻擊
	var ac := _atk_center()
	draw_circle(ac, ATK_R, Color(0.72, 0.14, 0.12, 0.55 + 0.4 * _atk_flash))
	draw_arc(ac, ATK_R, 0.0, TAU, 64, Color(1, 0.92, 0.85, 0.9), 3.0, true)
	if font:
		draw_string(font, ac + Vector2(-ATK_R, 13.0), "攻擊", HORIZONTAL_ALIGNMENT_CENTER, ATK_R * 2.0, 36, Color(1, 1, 1, 0.95))
	# 閃
	var dc := _dash_center()
	draw_circle(dc, DASH_R, Color(0.2, 0.3, 0.55, 0.5 + 0.4 * _dash_flash))
	draw_arc(dc, DASH_R, 0.0, TAU, 48, Color(0.85, 0.9, 1, 0.85), 2.5, true)
	if font:
		draw_string(font, dc + Vector2(-DASH_R, 12.0), "閃", HORIZONTAL_ALIGNMENT_CENTER, DASH_R * 2.0, 34, Color(1, 1, 1, 0.95))
	# 投／鉤
	var tc := _throw_center()
	var grapple := throw_label == "鉤"
	draw_circle(tc, THROW_R, (Color(0.9, 0.75, 0.25, 0.75 + 0.25 * _throw_flash) if grapple else Color(0.45, 0.3, 0.6, 0.5 + 0.4 * _throw_flash)))
	draw_arc(tc, THROW_R, 0.0, TAU, 48, Color(1, 0.95, 0.85, 0.9), 2.5, true)
	if font:
		draw_string(font, tc + Vector2(-THROW_R, 10.0), throw_label, HORIZONTAL_ALIGNMENT_CENTER, THROW_R * 2.0, 30, Color(1, 1, 1, 0.95))
		if not grapple:
			draw_string(font, tc + Vector2(-THROW_R, 30.0), str(throw_count), HORIZONTAL_ALIGNMENT_CENTER, THROW_R * 2.0, 14, Color(1, 1, 1, 0.8))
	# 格擋（按住時亮起）
	var bc := _block_center()
	draw_circle(bc, BLOCK_R, Color(0.18, 0.5, 0.32, 0.9 if _block_on else 0.5))
	draw_arc(bc, BLOCK_R, 0.0, TAU, 48, Color(0.85, 1, 0.9, 0.9), 2.5, true)
	if font:
		draw_string(font, bc + Vector2(-BLOCK_R, 10.0), "格擋", HORIZONTAL_ALIGNMENT_CENTER, BLOCK_R * 2.0, 28, Color(1, 1, 1, 0.95))
