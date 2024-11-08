extends Node2D

func _ready() -> void:
	randomize() # Initializes randomizer, only call this once

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#roll_dice()
	
func roll_dice() -> int:
	return randi_range(1,6)

func _on_roll_dice_pressed() -> void:
	var result_1 = roll_dice()
	var result_2 = roll_dice()
	if result_1 + result_2 == 7:
		$CanvasLayer/Roll_Dice.text = "ROBBER!"
	else:
		$CanvasLayer/Roll_Dice.text = "Rolled a " + str(result_1 + result_2) + " (" + str(result_1) + "," + str(result_2) + ")"
