# agent: composer-2.5 | 2026-07-10 | UI layout fit design scale | 24816e
extends Control

const BTN_PATHS := {
	"move_left": "MobileControls/BottomBar/Row/LeftPad/BtnLeft",
	"move_right": "MobileControls/BottomBar/Row/LeftPad/BtnRight",
	"jump": "MobileControls/BottomBar/Row/RightPad/BtnJump",
	"attack": "MobileControls/BottomBar/Row/RightPad/BtnAttack",
}


func _ready() -> void:
	ControlsBridge.debug_mode_changed.connect(_sync_visibility)
	_sync_visibility()
	_wire_hold(BTN_PATHS.move_left, "move_left")
	_wire_hold(BTN_PATHS.move_right, "move_right")
	_wire_hold(BTN_PATHS.jump, "jump")
	_wire_trigger(BTN_PATHS.attack, "attack")


func _sync_visibility() -> void:
	$MobileControls.visible = ControlsBridge.is_mobile()


func _wire_hold(path: String, action: String) -> void:
	var btn := get_node(path) as BaseButton
	btn.button_down.connect(func(): ControlsBridge.set_hold(action, true))
	btn.button_up.connect(func(): ControlsBridge.set_hold(action, false))


func _wire_trigger(path: String, action: String) -> void:
	var btn := get_node(path) as BaseButton
	btn.pressed.connect(func(): ControlsBridge.trigger(action))
