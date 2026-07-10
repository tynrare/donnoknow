# agent: composer-2.5 | 2026-07-10 | controls bridge autoload | 88ac42
extends Node

enum DebugMode { AUTO, FORCE_PC, FORCE_MOBILE }

signal debug_mode_changed
signal on_platform_changed(on_platform: bool)
signal on_ladder_changed(on_ladder: bool)

@export var debug_mode: DebugMode = DebugMode.FORCE_MOBILE:
	set(value):
		debug_mode = value
		debug_mode_changed.emit()


func _ready() -> void:
	process_physics_priority = 1

var _touch_hold := {
	"move_left": false,
	"move_right": false,
	"jump": false,
	"down": false,
}
var _touch_hold_prev := {
	"move_left": false,
	"move_right": false,
	"jump": false,
	"down": false,
}
var _on_platform := false
var _on_ladder := false
var _touch_just := {
	"jump": false,
	"attack": false,
}


func _physics_process(_delta: float) -> void:
	for action in _touch_just.keys():
		_touch_just[action] = false
	for action in _touch_hold.keys():
		_touch_hold_prev[action] = _touch_hold[action]


func is_mobile() -> bool:
	match debug_mode:
		DebugMode.FORCE_MOBILE:
			return true
		DebugMode.FORCE_PC:
			return false
		_:
			return DisplayServer.is_touchscreen_available() \
				or OS.has_feature("mobile") \
				or OS.has_feature("android") \
				or OS.has_feature("ios")


func set_hold(action: String, pressed: bool) -> void:
	if _touch_hold.has(action):
		_touch_hold[action] = pressed


func trigger(action: String) -> void:
	if _touch_just.has(action):
		_touch_just[action] = true


func move_x() -> float:
	var x := 0.0
	if is_pressed("move_left"):
		x -= 1.0
	if is_pressed("move_right"):
		x += 1.0
	return x


func is_pressed(action: String) -> bool:
	if is_mobile() and _touch_hold.get(action, false):
		return true
	return Input.is_action_pressed(action)


func just_pressed(action: String) -> bool:
	# agent: composer-2.5 | 2026-07-10 | keyboard just_pressed fallback | 3757ff
	if is_mobile():
		if _touch_just.get(action, false):
			return true
		if _touch_hold.has(action) and _touch_hold[action] and not _touch_hold_prev.get(action, false):
			return true
	return Input.is_action_just_pressed(action)


# agent: composer-2.5 | 2026-07-10 | down action can drop | 65cc63
func set_on_platform(on_platform: bool) -> void:
	if _on_platform == on_platform:
		return
	_on_platform = on_platform
	on_platform_changed.emit(on_platform)


func is_on_platform() -> bool:
	return _on_platform


# agent: composer-2.5 | 2026-07-10 | on ladder bridge signal | 351605
func set_on_ladder(on_ladder: bool) -> void:
	if _on_ladder == on_ladder:
		return
	_on_ladder = on_ladder
	on_ladder_changed.emit(on_ladder)


func is_on_ladder() -> bool:
	return _on_ladder
