extends Node
## Feel：手感參數中心。
## 所有打擊感數值集中在這裡；調校面板即時修改，可存檔（user://feel.cfg）、
## 套用預設、複製成文字貼給 AI。遊戲內任何「時間/力道」都該從這裡讀，不要寫死。

signal params_changed
signal shake_requested(amp: float, dur: float)
signal flash_requested(color: Color, dur: float)
## 頓幀期間每幀發出目前的時間流速，讓火花等效果能用真實時間繼續動
signal time_scale_changed(ts: float)
## 方向性鏡頭踢擊（往砍的方向頂一下再彈回），比亂數震動更像「撞上東西」
signal kick_requested(dir: Vector3, amount: float)

const SAVE_PATH := "user://feel.cfg"

## key: [顯示名稱, 最小, 最大, 步進, 預設]
const PARAMS := {
	"ui_scale": ["介面大小", 0.8, 2.4, 0.05, 1.0],
	"look_sens": ["視角靈敏度", 0.4, 2.0, 0.05, 1.0],
	"volume": ["音量", 0.0, 1.0, 0.05, 1.0],
	"lefty": ["左撇子（0/1）", 0.0, 1.0, 1.0, 0.0],
	"hints": ["輔助文字（0/1）", 0.0, 1.0, 1.0, 0.0],
	"cam_pull": ["牆擋住時鏡頭拉近（0＝牆變半透明）", 0.0, 1.0, 1.0, 1.0],
	"cones": ["顯示敵人視野扇形（0/1）", 0.0, 1.0, 1.0, 0.0],
	"windup_ms": ["出刀前置 ms", 20.0, 400.0, 5.0, 140.0],
	"active_ms": ["命中窗 ms", 40.0, 250.0, 5.0, 120.0],
	"recovery_ms": ["收刀硬直 ms", 60.0, 600.0, 5.0, 260.0],
	"hitstop_ms": ["頓幀 ms", 0.0, 250.0, 5.0, 70.0],
	"hitstop_scale": ["頓幀時間倍率", 0.01, 0.5, 0.01, 0.05],
	"hitstop_hold": ["頓幀凍結比例", 0.0, 1.0, 0.05, 0.4],
	"parry_ms": ["彈反窗口 ms", 80.0, 400.0, 10.0, 220.0],
	"shake_amp": ["鏡頭震幅", 0.0, 0.8, 0.01, 0.18],
	"shake_ms": ["鏡頭震動 ms", 40.0, 500.0, 5.0, 160.0],
	"knockback": ["擊退力道", 0.0, 10.0, 0.1, 3.5],
	"lunge": ["出刀前衝", 0.0, 6.0, 0.1, 1.8],
	"hit_flash_ms": ["受擊閃白 ms", 0.0, 250.0, 5.0, 80.0],
	"sfx_delay_ms": ["音效延遲 ms", 0.0, 120.0, 2.0, 0.0],
	"cam_fov": ["鏡頭視角", 35.0, 90.0, 1.0, 55.0],
	"trail_alpha": ["刀光濃度", 0.0, 1.0, 0.05, 0.85],
	"dmg_scale": ["傷害數字大小", 0.5, 2.5, 0.05, 1.0],
}

## 盲選用預設：先別看數值，輪流套用去砍，哪個「爽」再回頭看。
const PRESETS := {
	"甲・利落": {"windup_ms": 110.0, "active_ms": 110.0, "recovery_ms": 220.0, "hitstop_ms": 60.0, "hitstop_scale": 0.05, "shake_amp": 0.22, "shake_ms": 140.0, "knockback": 3.0, "lunge": 2.0},
	"乙・沉重": {"windup_ms": 170.0, "active_ms": 130.0, "recovery_ms": 320.0, "hitstop_ms": 120.0, "hitstop_scale": 0.04, "hitstop_hold": 0.35, "shake_amp": 0.35, "shake_ms": 220.0, "knockback": 6.0, "lunge": 1.2},
	"丙・流暢": {"windup_ms": 90.0, "active_ms": 100.0, "recovery_ms": 170.0, "hitstop_ms": 35.0, "hitstop_scale": 0.1, "hitstop_hold": 0.5, "shake_amp": 0.1, "shake_ms": 100.0, "knockback": 2.0, "lunge": 2.6},
	"丁・電影": {"windup_ms": 150.0, "active_ms": 120.0, "recovery_ms": 280.0, "hitstop_ms": 170.0, "hitstop_scale": 0.01, "hitstop_hold": 0.3, "shake_amp": 0.08, "shake_ms": 300.0, "knockback": 4.0, "lunge": 1.5},
	"戊・無料": {"hitstop_ms": 0.0, "shake_amp": 0.0, "hit_flash_ms": 0.0, "knockback": 0.5, "trail_alpha": 0.0, "lunge": 0.0},
}

## 手機介面倍率：用螢幕「短邊」算（短邊 463 px → 1.0 倍，iPhone 橫放約 1.3），直立時短邊是寬度，
## 按鍵相對寬度就跟橫放時相對高度一樣大。「介面大小」滑桿是在這個自動值上再乘。
const UI_REF_SHORT := 553.0

var p: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	params_changed.connect(_apply_ui_scale)
	reset_defaults()
	load_cfg()
	_setup_input_map()
	# 轉向（直立↔橫放）時重算倍率
	get_tree().root.size_changed.connect(_apply_ui_scale)


## 自動倍率：手機依短邊；桌機 1.0。
## 注意 stretch（canvas_items，基準 1280×720）本身會先按 min(w/1280, h/720) 縮放，直立時這個值只有橫放的一半，
## 所以要先除掉它，再讓「按鍵佔短邊的比例」兩種方向一致（短邊 553 px → 實際 1.0 倍，iPhone 橫放約 1.09）。
func auto_ui_scale() -> float:
	if not is_mobile():
		return 1.0
	var s: Vector2 = get_tree().root.size
	if s.x <= 0.0 or s.y <= 0.0:
		return 1.3
	var stretch := minf(s.x / 1280.0, s.y / 720.0)
	var target := minf(s.x, s.y) / UI_REF_SHORT
	return clampf(target / maxf(stretch, 0.01), 1.0, 3.0)


## 手機（iOS / Android，含 Safari 網頁版）或命令列加 --mobile 時視為手機
func is_mobile() -> bool:
	if "--mobile" in OS.get_cmdline_user_args():
		return true
	for f in ["web_ios", "web_android", "ios", "android"]:
		if OS.has_feature(f):
			return true
	return false


func reset_defaults() -> void:
	for k in PARAMS:
		p[k] = PARAMS[k][4]
	params_changed.emit()


func _apply_ui_scale() -> void:
	var root := get_tree().root
	if root:
		root.content_scale_factor = get_p("ui_scale") * auto_ui_scale()
	var v := get_p("volume")
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.001)


func get_p(k: String) -> float:
	return float(p[k])


## 以秒回傳毫秒參數
func sec(k: String) -> float:
	return get_p(k) / 1000.0


func set_p(k: String, v: float) -> void:
	var spec: Array = PARAMS[k]
	p[k] = clampf(v, spec[1], spec[2])
	params_changed.emit()


func apply_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		return
	var keep := {}
	for k in ["ui_scale", "look_sens", "volume", "lefty", "hints", "cam_pull", "cones"]:
		keep[k] = get_p(k)
	for k in PARAMS:
		p[k] = PARAMS[k][4]
	for k in keep:
		p[k] = keep[k]
	var over: Dictionary = PRESETS[preset_name]
	for k in over:
		p[k] = over[k]
	params_changed.emit()


## 頓幀：前 hitstop_hold 比例的時間把流速壓到 hitstop_scale（近乎凍結），
## 剩下的時間平滑加速回 1.0 —— 「先凍、再滑出」讀起來是撞擊，不是停格。
## 全程用真實時間推進；連續命中時只延長結束時間，不重算起點。
var _stopping := false
var _stop_start_ms := 0
var _stop_end_ms := 0
var _stop_scale := 0.05


func hitstop(mult: float = 1.0) -> void:
	var ms := int(get_p("hitstop_ms") * mult)
	if ms <= 0:
		return
	var now := Time.get_ticks_msec()
	if not _stopping:
		_stop_start_ms = now
	_stop_end_ms = maxi(_stop_end_ms, now + ms)
	_stop_scale = get_p("hitstop_scale")
	_stopping = true
	_tick_hitstop(now)


func _process(_delta: float) -> void:
	if _stopping:
		_tick_hitstop(Time.get_ticks_msec())


func _tick_hitstop(now: int) -> void:
	if now >= _stop_end_ms:
		_stopping = false
		Engine.time_scale = 1.0
		time_scale_changed.emit(1.0)
		return
	var total := maxi(_stop_end_ms - _stop_start_ms, 1)
	var t := float(now - _stop_start_ms) / float(total)
	var hold := get_p("hitstop_hold")
	var k := 0.0 if t < hold else smoothstep(0.0, 1.0, (t - hold) / maxf(1.0 - hold, 0.001))
	var ts := lerpf(_stop_scale, 1.0, k)
	Engine.time_scale = ts
	time_scale_changed.emit(ts)


func shake(mult: float = 1.0) -> void:
	shake_requested.emit(get_p("shake_amp") * mult, sec("shake_ms"))


func flash(color: Color, dur: float) -> void:
	flash_requested.emit(color, dur)


func kick(dir: Vector3, amount: float) -> void:
	kick_requested.emit(dir, amount)


## 手機震動（毫秒）：敵人起疑輕震、被發現重震。iOS 玩家常靜音，這是不靠聲音的狀態廣播。
## 桌機／網頁桌面沒有震動器，呼叫是空操作。
var _haptic_until_ms := 0


func haptic(ms: int) -> void:
	if ms <= 0 or not is_mobile():
		return
	var now := Time.get_ticks_msec()
	if now < _haptic_until_ms:
		return
	_haptic_until_ms = now + ms + 40
	Input.vibrate_handheld(ms)


func save_cfg() -> void:
	var cf := ConfigFile.new()
	for k in p:
		cf.set_value("feel", k, p[k])
	cf.save(SAVE_PATH)


func load_cfg() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for k in PARAMS:
		if cf.has_section_key("feel", k):
			p[k] = float(cf.get_value("feel", k))
	# 舊存檔的介面大小是絕對倍率（1.6／1.3），現在改成相對倍率，歸 1.0
	if is_mobile() and (absf(get_p("ui_scale") - 1.6) < 0.01 or absf(get_p("ui_scale") - 1.3) < 0.01):
		p["ui_scale"] = 1.0
	params_changed.emit()


## 給「複製數值」用：貼給 AI 就能重現同一組手感。
func to_text() -> String:
	var lines := PackedStringArray()
	for k in PARAMS:
		lines.append("%s=%s" % [k, str(p[k])])
	return "\n".join(lines)


func _setup_input_map() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("attack", [KEY_J, KEY_SPACE])
	_add_action("dash", [KEY_K, KEY_SHIFT])
	_add_action("block", [KEY_L, KEY_CTRL])
	_add_action("throw", [KEY_U, KEY_F])
	_add_action("weapon_toggle", [KEY_R])
	_add_action("look_left", [KEY_Q])
	_add_action("look_right", [KEY_E])
	_add_action("toggle_panel", [KEY_P, KEY_TAB])


func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
