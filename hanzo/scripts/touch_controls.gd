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

## 按鍵尺寸（邏輯像素，手機再乘 ui_scale 1.3）：攻擊最大，其餘排在它周圍的菱形，「換」塞在菱形中央
const JOY_R := 66.0
const ATK_R := 54.0
const DASH_R := 38.0
const BLOCK_R := 38.0
const HOOK_R := 36.0
const SWAP_R := 19.0
## 計數器（手裡劍數量）變動時彈一下
var _count_pop := 0.0

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


## 直立（高 > 寬）：畫面窄，鍵位往右下角收緊、往上疊；橫放：攤開成菱形
func _portrait() -> bool:
	return size.y > size.x


func _joy_home() -> Vector2:
	if _portrait():
		return _mx(Vector2(110.0, size.y - 150.0))
	return _mx(Vector2(135.0, size.y - 135.0))


## 鍵位：攻擊在右下角，閃在左、格擋在上、鉤在左上（菱形），換在菱形中央。
## 離角落稍遠一點，拇指自然彎曲就按得到，也避開 iPhone 圓角與手勢區
func _atk_center() -> Vector2:
	if _portrait():
		return _mx(Vector2(size.x - 78.0, size.y - 115.0))
	return _mx(Vector2(size.x - 105.0, size.y - 105.0))


func _dash_center() -> Vector2:
	if _portrait():
		return _mx(Vector2(size.x - 200.0, size.y - 80.0))
	return _mx(Vector2(size.x - 248.0, size.y - 72.0))


func _block_center() -> Vector2:
	if _portrait():
		return _mx(Vector2(size.x - 72.0, size.y - 245.0))
	return _mx(Vector2(size.x - 96.0, size.y - 242.0))


func _hook_center() -> Vector2:
	if _portrait():
		return _mx(Vector2(size.x - 195.0, size.y - 205.0))
	return _mx(Vector2(size.x - 246.0, size.y - 198.0))


## 「換」：攻擊鍵右上角的小徽章（壓在大圓邊上），直立橫放都一樣
func _swap_center() -> Vector2:
	var a := _atk_center()
	var dx := -ATK_R * 0.72 if _lefty() else ATK_R * 0.72
	return a + Vector2(dx, -ATK_R * 0.72)


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
	_touch_ms.clear()
	_set_block(false)


## 看門狗：某根手指 6 秒沒有任何事件（真的按著一定會有微小的拖曳事件），視為放開事件遺失
var _touch_ms := {}
const STALE_MS := 6000


func _touch_seen(idx: int) -> void:
	_touch_ms[idx] = Time.get_ticks_msec()


func _watchdog() -> void:
	var now := Time.get_ticks_msec()
	for idx in _touch_ms.keys():
		if now - int(_touch_ms[idx]) < STALE_MS:
			continue
		_touch_ms.erase(idx)
		if idx == _joy_idx:
			_joy_idx = -1
			move_vector = Vector2.ZERO
		if idx == _look_idx:
			_look_idx = -1
		if _btn_touch.has(idx):
			_release_role(_btn_touch[idx])
			_btn_touch.erase(idx)
			_btn_last.erase(idx)


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
			_touch_seen(t.index)
		else:
			_touch_ms.erase(t.index)
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
		_touch_seen(d.index)
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
	_count_pop = maxf(_count_pop - delta * 3.0, 0.0)
	_watchdog()


## 手裡劍數量變了（撿回、卷軸）：數字彈一下，取代「手裡劍 +1」飄字
func set_shuriken_count(n: int) -> void:
	if n != shuriken_count:
		_count_pop = 1.0
	shuriken_count = n
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
			var cs := 15 + int(8.0 * _count_pop)
			draw_string(font, ac + Vector2(-ATK_R, 6.0), "手裡劍", HORIZONTAL_ALIGNMENT_CENTER, ATK_R * 2.0, 24, Color(1, 1, 1, 0.95))
			draw_string(font, ac + Vector2(-ATK_R, 30.0), "×%d" % shuriken_count, HORIZONTAL_ALIGNMENT_CENTER, ATK_R * 2.0, cs, Color(1, 1, 0.8 + 0.2 * (1.0 - _count_pop), 0.9))
		else:
			draw_string(font, ac + Vector2(-ATK_R, 11.0), "攻擊", HORIZONTAL_ALIGNMENT_CENTER, ATK_R * 2.0, 30, Color(1, 1, 1, 0.95))
	# 武器切換徽章（攻擊鍵右上角）：顯示「會換成什麼」——刀模式時畫手裡劍、手裡劍模式時畫刀
	var sc := _swap_center()
	draw_circle(sc, SWAP_R, Color(0.9, 0.9, 0.92, 0.85))
	draw_arc(sc, SWAP_R, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 1.5, true)
	if shuriken:
		# 小刀：一條斜線＋短護手
		draw_line(sc + Vector2(-7, 7), sc + Vector2(7, -7), Color(0.15, 0.15, 0.2), 2.5)
		draw_line(sc + Vector2(-5, -1), sc + Vector2(0, 4), Color(0.15, 0.15, 0.2), 2.0)
	else:
		# 小手裡劍：四芒
		for i in range(4):
			var a0 := i * PI / 2.0 + PI / 4.0
			draw_line(sc, sc + Vector2(cos(a0), sin(a0)) * 8.0, Color(0.15, 0.15, 0.2), 2.5)
		draw_circle(sc, 2.5, Color(0.15, 0.15, 0.2))
	# 閃
	var dc := _dash_center()
	draw_circle(dc, DASH_R, Color(0.2, 0.3, 0.55, 0.5 + 0.4 * _dash_flash))
	draw_arc(dc, DASH_R, 0.0, TAU, 48, Color(0.85, 0.9, 1, 0.85), 2.5, true)
	if dash_cd > 0.0:
		_draw_cd(dc, DASH_R, dash_cd, 0.8, font, 24)
	elif font:
		draw_string(font, dc + Vector2(-DASH_R, 10.0), "閃", HORIZONTAL_ALIGNMENT_CENTER, DASH_R * 2.0, 28, Color(1, 1, 1, 0.95))
	# 鉤繩（按住瞄準）；拉人冷卻中顯示倒數（鉤牆頂／屋頂不受冷卻限制）
	var hc := _hook_center()
	draw_circle(hc, HOOK_R, Color(0.75, 0.6, 0.2, 0.55 + 0.4 * _hook_flash))
	draw_arc(hc, HOOK_R, 0.0, TAU, 48, Color(1, 0.95, 0.8, 0.9), 2.5, true)
	if hook_cd > 0.0:
		_draw_cd(hc, HOOK_R, hook_cd, 4.0, font, 22)
	elif font:
		draw_string(font, hc + Vector2(-HOOK_R, 9.0), "鉤", HORIZONTAL_ALIGNMENT_CENTER, HOOK_R * 2.0, 26, Color(1, 1, 1, 0.95))
	# 格擋（按住時亮起）
	var bc := _block_center()
	draw_circle(bc, BLOCK_R, Color(0.18, 0.5, 0.32, 0.9 if _block_on else 0.5))
	draw_arc(bc, BLOCK_R, 0.0, TAU, 48, Color(0.85, 1, 0.9, 0.9), 2.5, true)
	if font:
		draw_string(font, bc + Vector2(-BLOCK_R, 8.0), "格擋", HORIZONTAL_ALIGNMENT_CENTER, BLOCK_R * 2.0, 24, Color(1, 1, 1, 0.95))
