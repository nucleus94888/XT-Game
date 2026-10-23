extends CanvasLayer
## HUD：命中 / 連段 / 擊破統計、HP 條、大字宣告、受擊閃光、手感面板開關。

@onready var stats: Label = $Stats
@onready var hp_bar: ProgressBar = $HpBar
@onready var announce: Label = $Announce
@onready var flash: ColorRect = $Flash
@onready var fps: Label = $Fps
@onready var gear: Button = $GearBtn
@onready var panel: Control = $TuningPanel
@onready var touch: Control = $TouchControls

var hits := 0
var combo := 0
var best_combo := 0
var kills := 0
var _combo_t := 0.0
var _flash_tw: Tween
var _last_ms := 0
var _worst_ms := 0
var _worst_shown := 0
var _worst_t := 1.0


func _ready() -> void:
	Feel.flash_requested.connect(_on_flash)
	gear.pressed.connect(toggle_panel)
	panel.visible = false
	var blockers: Array[Control] = [panel, gear]
	touch.blockers = blockers
	_refresh()


func toggle_panel() -> void:
	panel.visible = not panel.visible
	gear.visible = not panel.visible


func _process_panel_state() -> void:
	gear.visible = not panel.visible


func add_hit(heavy: bool) -> void:
	hits += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	_combo_t = 1.8
	_refresh()
	if heavy:
		_pop(stats, 1.25)


func add_kill() -> void:
	kills += 1
	_refresh()
	say("擊破！", Color(1.0, 0.85, 0.4))


func set_hp(v: int) -> void:
	hp_bar.value = v


func say(text: String, color: Color = Color.WHITE) -> void:
	announce.text = text
	announce.modulate = color
	announce.pivot_offset = announce.size / 2.0
	announce.scale = Vector2.ONE * 1.6
	var tw := announce.create_tween()
	tw.tween_property(announce, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(announce, "modulate:a", 0.0, 0.3)


func _on_flash(color: Color, dur: float) -> void:
	flash.color = color
	if _flash_tw:
		_flash_tw.kill()
	_flash_tw = flash.create_tween()
	_flash_tw.tween_property(flash, "color:a", 0.0, dur)


func _process(delta: float) -> void:
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			combo = 0
			_refresh()
	# 以真實時間量最長一幀（頓幀不算），用來分辨「故意的頓幀」與「真的卡」
	var now := Time.get_ticks_msec()
	if _last_ms > 0:
		_worst_ms = maxi(_worst_ms, now - _last_ms)
	_last_ms = now
	_worst_t -= delta
	if _worst_t <= 0.0:
		_worst_t = 1.0
		_worst_shown = _worst_ms
		_worst_ms = 0
	fps.text = "%d fps　最長一幀 %d ms" % [Engine.get_frames_per_second(), _worst_shown]
	_process_panel_state()


func _refresh() -> void:
	stats.text = "命中 %d　連段 %d（最高 %d）　擊破 %d" % [hits, combo, best_combo, kills]


func _pop(c: Control, s: float) -> void:
	c.pivot_offset = Vector2(0.0, c.size.y / 2.0)
	c.scale = Vector2.ONE * s
	c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
