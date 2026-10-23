extends Node
## 進度存檔（user://progress.cfg）：念珠、卷軸、已過關卡、最佳評價。
## 念珠：每關忍殺大將得一枚，+10 最大 HP（最多四枚）。
## 卷軸：每關藏一卷，撿到立刻生效，但要走到檢查點才寫進存檔（死亡回溯就重撿）。
##   shuriken7  手裡劍 5 → 7 枚
##   ration2    口糧可攜帶 1 → 2 份（血滿時撿到會帶著，血量低於三成自動吃）
##   hook_fly   飛鉤：鉤住 6 公尺外的敵人時，是你飛過去而不是把他拉過來
## 沒有貨幣、沒有商店、沒有等級。

signal changed

const SAVE_PATH := "user://progress.cfg"
const SAVE_VERSION := 1
const MAX_BEADS := 4
const SCROLLS := {
	"shuriken7": "手裡劍 ×7",
	"ration2": "口糧可帶兩份",
	"hook_fly": "飛鉤",
}

var beads := 0
var scrolls: Dictionary = {}
var cleared: Dictionary = {}
var best_rank: Dictionary = {}
## 撿到但還沒走到檢查點的卷軸
var _pending: Array = []


func _ready() -> void:
	load_save()


func max_hp() -> int:
	return 100 + 10 * beads


func has_scroll(id: String) -> bool:
	return scrolls.has(id) or _pending.has(id)


func shuriken_max() -> int:
	return 7 if has_scroll("shuriken7") else 5


func ration_max() -> int:
	return 2 if has_scroll("ration2") else 1


func add_bead() -> void:
	if beads >= MAX_BEADS:
		return
	beads += 1
	save()
	changed.emit()


## 撿到卷軸：立刻生效，到檢查點才存
func pickup_scroll(id: String) -> void:
	if has_scroll(id):
		return
	_pending.append(id)
	changed.emit()


func commit_pending() -> void:
	if _pending.is_empty():
		return
	for id in _pending:
		scrolls[id] = true
	_pending.clear()
	save()


func drop_pending() -> void:
	_pending.clear()
	changed.emit()


func mark_cleared(level: String, rank: String) -> void:
	cleared[level] = true
	const ORDER := ["C", "B", "A", "S", "影"]
	var old: String = best_rank.get(level, "")
	if old == "" or ORDER.find(rank) > ORDER.find(old):
		best_rank[level] = rank
	save()


func scroll_count() -> int:
	return scrolls.size()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "save_version", SAVE_VERSION)
	cf.set_value("progress", "beads", beads)
	cf.set_value("progress", "scrolls", scrolls.keys())
	cf.set_value("progress", "cleared", cleared.keys())
	cf.set_value("progress", "best_rank", best_rank)
	cf.save(SAVE_PATH)


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	beads = clampi(int(cf.get_value("progress", "beads", 0)), 0, MAX_BEADS)
	scrolls.clear()
	for id in cf.get_value("progress", "scrolls", []):
		if SCROLLS.has(String(id)):
			scrolls[String(id)] = true
	cleared.clear()
	for l in cf.get_value("progress", "cleared", []):
		cleared[String(l)] = true
	best_rank = cf.get_value("progress", "best_rank", {})


func reset() -> void:
	beads = 0
	scrolls.clear()
	cleared.clear()
	best_rank.clear()
	_pending.clear()
	save()
	changed.emit()
