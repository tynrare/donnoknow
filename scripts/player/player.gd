# agent: composer-2.5 | 2026-07-10 | player movement physics | 7e6152
extends CharacterBody2D

const SPEED := 80.0
const JUMP_V := -180.0
const GRAVITY := 600.0

@onready var _sprite: Sprite2D = $Sprite2D


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	velocity.x = ControlsBridge.move_x() * SPEED

	if ControlsBridge.is_pressed("jump") and is_on_floor():
		velocity.y = JUMP_V

	if ControlsBridge.just_pressed("attack"):
		_attack()

	var move_x := ControlsBridge.move_x()
	if move_x != 0.0:
		_sprite.flip_h = move_x < 0.0

	move_and_slide()


func _attack() -> void:
	pass
