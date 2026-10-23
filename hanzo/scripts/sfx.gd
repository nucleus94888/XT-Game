extends Node
## Sfx：音效庫。
## audio/synth/  → 為「刀砍稻草人」專門合成（tools/sfx/gen.mjs）：揮空破風、砍進乾草、稻草爆開
## audio/kenney/ → Kenney CC0（LICENSE-kenney-CC0.txt）：木樁、衣物、受傷
## 每組用 AudioStreamRandomizer 隨機挑變化、隨機微調音高，連按不會聽到同一聲。

## 名稱 → 檔案路徑清單
const SETS := {
	"swing": ["synth/swing_1.wav", "synth/swing_2.wav", "synth/swing_3.wav"],
	"hit": ["synth/straw_light_1.wav", "synth/straw_light_2.wav", "synth/straw_light_3.wav"],
	"heavy": ["synth/straw_heavy_1.wav", "synth/straw_heavy_2.wav", "synth/straw_heavy_3.wav"],
	"heavy_wood": ["kenney/impactWood_medium_000.ogg", "kenney/impactWood_medium_001.ogg", "kenney/impactWood_medium_002.ogg"],
	"dash": ["kenney/cloth1.ogg", "kenney/cloth2.ogg", "kenney/cloth3.ogg"],
	"hurt": ["kenney/impactSoft_heavy_000.ogg", "kenney/impactSoft_heavy_001.ogg", "kenney/impactSoft_heavy_002.ogg"],
	"break": ["synth/straw_break.wav"],
	"break_wood": ["kenney/impactWood_heavy_000.ogg", "kenney/impactWood_heavy_001.ogg", "kenney/impactWood_heavy_002.ogg"],
}

var _cache := {}


func make(set_name: String, pitch_spread: float = 1.08, vol_spread_db: float = 1.5) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = pitch_spread
	r.random_volume_offset_db = vol_spread_db
	var i := 0
	for path in SETS[set_name]:
		var s := _load(path)
		if s:
			r.add_stream(i, s)
			i += 1
	return r


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load("res://audio/" + path)
	return _cache[path]


## 建一個已接好音效的播放器並掛到 parent 下
func player(parent: Node, set_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = make(set_name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	return p
