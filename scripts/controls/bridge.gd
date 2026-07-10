# agent: composer-2.5 | 2026-07-10 | controls bridge autoload | 88ac42
extends Node

enum DebugMode { AUTO, FORCE_PC, FORCE_MOBILE }

signal debug_mode_changed

@export var debug_mode: DebugMode = DebugMode.FORCE_MOBILE:
	set(value):
		debug_mode = value
		debug_mode_changed.emit()

var _touch_hold := {
	"move_left": false,
	"move_right": false,
	"jump": false,
}
var _touch_just := {
	"jump": false,
	"attack": false,
}


func _physics_process(_delta: float) -> void:
	for action in _touch_just.keys():
		_touch_just[action] = false


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
	if is_mobile() and _touch_just.get(action, false):
		return true
	return Input.is_action_just_pressed(action)
