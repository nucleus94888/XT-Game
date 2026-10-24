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
## 冷卻中的按鍵改顯示倒數秒數（HUD 每幀更新）
var dash_cd := 0.0
var hook_cd := 0.0
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


## 放掉所有手指：暫停／覆蓋層期間收不到放開事件（touch 是 PAUSABLE），
## 或 Safari 被系統手勢、通知搶走觸控時，手指狀態會殘留 → 搖桿一直走、格擋一直按、瞄準放不開，只能重新整理。
## 進出暫停與失去焦點時呼叫，把一切歸零。
func reset_touches() -> void:
	_joy_idx = -1
	_look_idx = -1
	move_vector = Vector2.ZERO
	for idx in _btn_touch.keys():
		_release_role(_btn_touch[idx])
	_btn_touch.clear()
	_btn_last.clear()
	_set_block(false)


func _release_role(role: String) -> void:
	if role == "block":
		_set_block(false)
	elif role == "attack":
		attack_up.emit()
	elif role == "hook":
		hook_up.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset_touches()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			# 同一個手指編號又「按下」＝上一次的放開事件掉了，先把舊狀態放掉（自我修復）
			if t.index == _joy_idx:
				_joy_idx = -1
				move_vector = Vector2.ZERO
			if t.index == _look_idx:
				_look_idx = -1
			if _btn_touch.has(t.index):
				_release_role(_btn_touch[t.index])
				_btn_touch.erase(t.index)
				_btn_last.erase(t.index)
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
			# 搖桿區：左下角（寬 42%、下 62%）；上半部與右側是轉視角
			var in_x: bool = (t.position.x > size.x * 0.58) if _lefty() else (t.position.x < size.x * 0.42)
			var joy_side: bool = in_x and t.position.y > size.y * 0.38
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


## 冷卻倒數：按鍵中央改成秒數，外圈畫剩餘比例
func _draw_cd(c: Vector2, r: float, left: float, total: float, font: Font, size: int) -> void:
	draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.35))
	var k := clampf(left / maxf(total, 0.01), 0.0, 1.0)
	draw_arc(c, r - 3.0, -PI / 2.0, -PI / 2.0 + TAU * k, 48, Color(1, 1, 1, 0.8), 3.0, true)
	if font:
		draw_string(font, c + Vector2(-r, size * 0.36), "%.1f" % left, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size, Color(1, 1, 1, 0.95))


func _draw() -> void:
	var font: Font = Fx.ui_font
	# 搖桿：閒置時停在左下，按住時跟著手指；瞄準中改為黃色
	var jc := _joy_origin if _joy_idx != -1 else _joy_home()
	var jcol := Color(1.0, 0.9, 0.5) if aiming else Color(1, 1, 1)
	draw_circle(jc, JOY_R, Color(jcol, 0.10 if _joy_idx != -1 else 0.07))
	draw_arc(jc, JOY_R, 0.0, TAU, 48, Color(jcol, 0.42 if _joy_idx != -1 else 0.28), 2.5, true)
	var knob := _joy_pos if _joy_idx != -1 else jc
	draw_circle(knob, 28.0, Color(jcol, 0.55 if _joy_idx != -1 else 0.22))
	# 準心（瞄準中畫在畫面正中央）：單純白色十字，不另外標示能不能鉤／有沒有鎖定
	if aiming:
		var c := size / 2.0
		var ccol := Color(1, 1, 1, 0.9)
		var gap := 10.0
		draw_line(c + Vector2(-gap - 14, 0), c + Vector2(-gap, 0), ccol, 2.5)
		draw_line(c + Vector2(gap, 0), c + Vector2(gap + 14, 0), ccol, 2.5)
		draw_line(c + Vector2(0, -gap - 14), c + Vector2(0, -gap), ccol, 2.5)
		draw_line(c + Vector2(0, gap), c + Vector2(0, gap + 14), ccol, 2.5)
		draw_circle(c, 2.5, ccol)
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
		draw_string(font, sc + Vector2(-SWAP_R, 9.0), "換", HORIZONTAL_ALIGNMENT_CENTER, SWAP_R * 2.0, 24, Color(1, 1, 1, 0.95))
	# 閃
	var dc := _dash_center()
	draw_circle(dc, DASH_R, Color(0.2, 0.3, 0.55, 0.5 + 0.4 * _dash_flash))
	draw_arc(dc, DASH_R, 0.0, TAU, 48, Color(0.85, 0.9, 1, 0.85), 2.5, true)
	if dash_cd > 0.0:
		_draw_cd(dc, DASH_R, dash_cd, 0.8, font, 30)
	elif font:
		draw_string(font, dc + Vector2(-DASH_R, 12.0), "閃", HORIZONTAL_ALIGNMENT_CENTER, DASH_R * 2.0, 34, Color(1, 1, 1, 0.95))
	# 鉤繩（按住瞄準）；拉人冷卻中顯示倒數（鉤牆頂／屋頂不受冷卻限制）
	var hc := _hook_center()
	draw_circle(hc, HOOK_R, Color(0.75, 0.6, 0.2, 0.55 + 0.4 * _hook_flash))
	draw_arc(hc, HOOK_R, 0.0, TAU, 48, Color(1, 0.95, 0.8, 0.9), 2.5, true)
	if hook_cd > 0.0:
		_draw_cd(hc, HOOK_R, hook_cd, 4.0, font, 26)
	elif font:
		draw_string(font, hc + Vector2(-HOOK_R, 11.0), "鉤", HORIZONTAL_ALIGNMENT_CENTER, HOOK_R * 2.0, 32, Color(1, 1, 1, 0.95))
	# 格擋（按住時亮起）
	var bc := _block_center()
	draw_circle(bc, BLOCK_R, Color(0.18, 0.5, 0.32, 0.9 if _block_on else 0.5))
	draw_arc(bc, BLOCK_R, 0.0, TAU, 48, Color(0.85, 1, 0.9, 0.9), 2.5, true)
	if font:
		draw_string(font, bc + Vector2(-BLOCK_R, 10.0), "格擋", HORIZONTAL_ALIGNMENT_CENTER, BLOCK_R * 2.0, 28, Color(1, 1, 1, 0.95))
