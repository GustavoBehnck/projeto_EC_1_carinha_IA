extends CharacterBody2D

const SPEED = 200.0

func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
   
	if direction:
		velocity = direction * SPEED
	else:
		velocity = Vector2.ZERO
		
	move_and_slide()
