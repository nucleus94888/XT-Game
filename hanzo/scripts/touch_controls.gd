extends Control
## 觸控操作
## 左：常駐淡白色搖桿圓圈（左下），手指落在左 60% 畫面任意處即以落點為中心；瞄準中搖桿變成瞄準方向。
## 右：「攻擊」（刀模式＝按下即斬；手裡劍模式＝按住瞄準、放開射出）、「閃」、「格擋」（按住）、
##     「鉤」（按住瞄準牆頂／屋頂、放開射出鉤繩）、武器切換小鍵「刀／劍」。右側空白處拖曳轉視角。

signal attack_down
signal attack_up
signal dash_pressed
signal block_changed(on: bool)
signal hook_down
signal hook_up
signal weapon_toggle
## 右側空白處拖曳：轉視角（螢幕像素位移）
signal look_delta(delta: Vector2)

const JOY_R := 78.0
const ATK_R := 70.0
const DASH_R := 50.0
const BLOCK_R := 50.0
const HOOK_R := 44.0
const SWAP_R := 30.0

var move_vector := Vector2.ZERO
## 這些控制項可見且覆蓋到的區域，不會觸發搖桿（例如手感面板）
var blockers: Array[Control] = []
## HUD 每幀更新：目前武器（"刀"/"劍"）、手裡劍數、是否瞄準中
var weapon_label := "刀"
var shuriken_count := 0
var aiming := false
## 準心狀態（player.aim_status）
var aim_status := ""

var _joy_idx := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _btn_touch := {}
var _btn_last := {}
var _atk_flash := 0.0
var _dash_flash := 0.0
var _hook_flash := 0.0
var _block_on := false
var _look_idx := -1
var _look_last := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _joy_home() -> Vector2:
	return _mx(Vector2(150.0, size.y - 150.0))


## 鍵位離角落稍遠一點，拇指自然彎曲就按得到，也避開 iPhone 圓角與手勢區
func _atk_center() -> Vector2:
	return _mx(Vector2(size.x - 140.0, size.y - 140.0))


func _dash_center() -> Vector2:
	return _mx(Vector2(size.x - 290.0, size.y - 92.0))


func _block_center() -> Vector2:
	return _mx(Vector2(size.x - 130.0, size.y - 300.0))


func _hook_center() -> Vector2:
	return _mx(Vector2(size.x - 315.0, size.y - 255.0))


func _swap_center() -> Vector2:
	return _mx(Vector2(size.x - 70.0, size.y - 235.0))


## 左撇子：左右鏡像（搖桿到右、按鍵到左）
func _lefty() -> bool:
	return Feel.get_p("lefty") >= 0.5


func _mx(p: Vector2) -> Vector2:
	return Vector2(size.x - p.x, p.y) if _lefty() else p


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
			if t.position.distance_to(_swap_center()) < SWAP_R * 1.4:
				_btn_touch[t.index] = "swap"
				weapon_toggle.emit()
				get_viewport().set_input_as_handled()
				return
			if t.position.distance_to(_atk_center()) < ATK_R * 1.25:
				_btn_touch[t.index] = "attack"
				_btn_last[t.index] = t.position
				_atk_flash = 1.0
				attack_down.emit()
				get_viewport().set_input_as_handled()
				return
			if t.position.distance_to(_dash_center()) < DASH_R * 1.45:
				_btn_touch[t.index] = "dash"
				_dash_flash = 1.0
				dash_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if t.position.distance_to(_hook_center()) < HOOK_R * 1.4:
				_btn_touch[t.index] = "hook"
				_btn_last[t.index] = t.position
				_hook_flash = 1.0
				hook_down.emit()
				get_viewport().set_input_as_handled()
				return
			if t.position.distance_to(_block_center()) < BLOCK_R * 1.45:
				_btn_touch[t.index] = "block"
				_set_block(true)
				get_viewport().set_input_as_handled()
				return
			var joy_side: bool = (t.position.x > size.x * 0.4) if _lefty() else (t.position.x < size.x * 0.6)
			if _joy_idx == -1 and joy_side:
				_joy_idx = t.index
				_joy_origin = t.position
				_joy_pos = t.position
				move_vector = Vector2.ZERO
				get_viewport().set_input_as_handled()
			elif _look_idx == -1 and not joy_side:
				_look_idx = t.index
				_look_last = t.position
				get_viewport().set_input_as_handled()
		else:
			if t.index == _joy_idx:
				_joy_idx = -1
				move_vector = Vector2.ZERO
			if t.index == _look_idx:
				_look_idx = -1
			var role: String = _btn_touch.get(t.index, "")
			if role == "block":
				_set_block(false)
			elif role == "attack":
				attack_up.emit()
			elif role == "hook":
				hook_up.emit()
			_btn_touch.erase(t.index)
			_btn_last.erase(t.index)
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
		elif aiming and _btn_touch.get(d.index, "") in ["hook", "attack"]:
			# 右手按著鉤／手裡劍不放，同一根手指拖曳＝調整瞄準角度
			var last: Vector2 = _btn_last.get(d.index, d.position)
			look_delta.emit(d.position - last)
			_btn_last[d.index] = d.position
			get_viewport().set_input_as_handled()
		elif _btn_touch.get(d.index, "") == "block":
			# 手指滑出格擋鍵太遠就視為放開
			if d.position.distance_to(_block_center()) > BLOCK_R * 2.2:
				_btn_touch.erase(d.index)
				_set_block(false)


func _process(delta: float) -> void:
	_atk_flash = maxf(_atk_flash - delta * 5.0, 0.0)
	_dash_flash = maxf(_dash_flash - delta * 5.0, 0.0)
	_hook_flash = maxf(_hook_flash - delta * 5.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var font: Font = Fx.ui_font
	# 搖桿：閒置時停在左下，按住時跟著手指；瞄準中改為黃色
	var jc := _joy_origin if _joy_idx != -1 else _joy_home()
	var jcol := Color(1.0, 0.9, 0.5) if aiming else Color(1, 1, 1)
	draw_circle(jc, JOY_R, Color(jcol, 0.10 if _joy_idx != -1 else 0.07))
	draw_arc(jc, JOY_R, 0.0, TAU, 48, Color(jcol, 0.42 if _joy_idx != -1 else 0.28), 2.5, true)
	var knob := _joy_pos if _joy_idx != -1 else jc
	draw_circle(knob, 28.0, Color(jcol, 0.55 if _joy_idx != -1 else 0.22))
	# 準心（瞄準中畫在畫面正中央）
	if aiming:
		var c := size / 2.0
		var ccol := Color(1, 1, 1, 0.9)
		if aim_status == "lock":
			ccol = Color(1.0, 0.85, 0.3)
		elif aim_status == "ok":
			ccol = Color(0.5, 1.0, 0.6)
		elif aim_status == "bad":
			ccol = Color(1.0, 0.35, 0.3)
		var gap := 10.0 if aim_status == "" else 16.0
		draw_line(c + Vector2(-gap - 14, 0), c + Vector2(-gap, 0), ccol, 2.5)
		draw_line(c + Vector2(gap, 0), c + Vector2(gap + 14, 0), ccol, 2.5)
		draw_line(c + Vector2(0, -gap - 14), c + Vector2(0, -gap), ccol, 2.5)
		draw_line(c + Vector2(0, gap), c + Vector2(0, gap + 14), ccol, 2.5)
		draw_circle(c, 2.5, ccol)
		if aim_status != "":
			draw_arc(c, gap + 4.0, 0.0, TAU, 32, Color(ccol, 0.6), 1.5, true)
	# 攻擊（刀＝紅；手裡劍＝紫，顯示數量）
	var ac := _atk_center()
	var shuriken := weapon_label == "劍"
	var acol := Color(0.45, 0.3, 0.6, 0.6 + 0.35 * _atk_flash) if shuriken else Color(0.72, 0.14, 0.12, 0.55 + 0.4 * _atk_flash)
	draw_circle(ac, ATK_R, acol)
	draw_arc(ac, ATK_R, 0.0, TAU, 64, Color(1, 0.92, 0.85, 0.9), 3.0, true)
	if font:
		if shuriken:
			draw_string(font, ac + Vector2(-ATK_R, 8.0), "手裡劍", HORIZONTAL_ALIGNMENT_CENTER, ATK_R * 2.0, 30, Color(1, 1, 1, 0.95))
			draw_string(font, ac + Vector2(-ATK_R, 34.0), "×%d" % shuriken_count, HORIZONTAL_ALIGNMENT_CENTER, ATK_R * 2.0, 18, Color(1, 1, 1, 0.85))
		else:
			draw_string(font, ac + Vector2(-ATK_R, 13.0), "攻擊", HORIZONTAL_ALIGNMENT_CENTER, ATK_R * 2.0, 36, Color(1, 1, 1, 0.95))
	# 武器切換小鍵
	var sc := _swap_center()
	draw_circle(sc, SWAP_R, Color(0.2, 0.2, 0.25, 0.8))
	draw_arc(sc, SWAP_R, 0.0, TAU, 32, Color(0.9, 0.9, 0.9, 0.8), 2.0, true)
	if font:
		draw_string(font, sc + Vector2(-SWAP_R, 9.0), "劍" if shuriken else "刀", HORIZONTAL_ALIGNMENT_CENTER, SWAP_R * 2.0, 24, Color(1, 1, 1, 0.95))
		draw_string(font, sc + Vector2(-SWAP_R - 10.0, SWAP_R + 16.0), "切換", HORIZONTAL_ALIGNMENT_CENTER, SWAP_R * 2.0 + 20.0, 13, Color(1, 1, 1, 0.6))
	# 閃
	var dc := _dash_center()
	draw_circle(dc, DASH_R, Color(0.2, 0.3, 0.55, 0.5 + 0.4 * _dash_flash))
	draw_arc(dc, DASH_R, 0.0, TAU, 48, Color(0.85, 0.9, 1, 0.85), 2.5, true)
	if font:
		draw_string(font, dc + Vector2(-DASH_R, 12.0), "閃", HORIZONTAL_ALIGNMENT_CENTER, DASH_R * 2.0, 34, Color(1, 1, 1, 0.95))
	# 鉤繩（按住瞄準）
	var hc := _hook_center()
	draw_circle(hc, HOOK_R, Color(0.75, 0.6, 0.2, 0.55 + 0.4 * _hook_flash))
	draw_arc(hc, HOOK_R, 0.0, TAU, 48, Color(1, 0.95, 0.8, 0.9), 2.5, true)
	if font:
		draw_string(font, hc + Vector2(-HOOK_R, 11.0), "鉤", HORIZONTAL_ALIGNMENT_CENTER, HOOK_R * 2.0, 32, Color(1, 1, 1, 0.95))
	# 格擋（按住時亮起）
	var bc := _block_center()
	draw_circle(bc, BLOCK_R, Color(0.18, 0.5, 0.32, 0.9 if _block_on else 0.5))
	draw_arc(bc, BLOCK_R, 0.0, TAU, 48, Color(0.85, 1, 0.9, 0.9), 2.5, true)
	if font:
		draw_string(font, bc + Vector2(-BLOCK_R, 10.0), "格擋", HORIZONTAL_ALIGNMENT_CENTER, BLOCK_R * 2.0, 28, Color(1, 1, 1, 0.95))
