extends Node2D
var ALL_PLAYERS = []
var CLIENT = null
var ALL_PLAYERS_INDEXES = []
var CLIENT_INDEX
func _ready() -> void:
	var PLAYER = load("res://player.gd")
	for i in range(4):
		if i == 0: # In server, this should check for whether this is a bot or player
			var PLAYER_OBJ = PLAYER.new()
			PLAYER_OBJ._name = "Player 1"
			PLAYER_OBJ.type = "Player"
			PLAYER_OBJ.id = i+1
			ALL_PLAYERS.append(PLAYER_OBJ)
			CLIENT = PLAYER_OBJ
		else:
			var BOT = PLAYER.new()
			BOT._name = ("Bot %s" % str(i))
			BOT.type = "Bot"
			BOT.id = i+1
			ALL_PLAYERS.append(BOT)
	
	roll_for_who_goes_first()

func roll_for_who_goes_first():
	# Determine who goes first by rolling for it
	# Upate player_turn var from server?
	
	var turn_order = []
	for player in ALL_PLAYERS:
		if player.type == "Player":
			player.dice_roll_result = randi_range(0, 12)
			turn_order.append([player.dice_roll_result, player, player._name])
		else:
			player.dice_roll_result = randi_range(0, 12)
			turn_order.append([player.dice_roll_result, player, player._name])
		
	turn_order.sort_custom(custom_sort_for_first_roll)
	print(turn_order)
	
	print(ALL_PLAYERS)
	for i in ALL_PLAYERS.size():
		ALL_PLAYERS[i] = turn_order[i][1]
		print(ALL_PLAYERS[i]._name)
		if ALL_PLAYERS[i].type == "Player":
			CLIENT_INDEX = i
		# Store bot indexes too ! ! ! ! ! ! !
	print(ALL_PLAYERS)
	print(CLIENT_INDEX)

func custom_sort_for_first_roll(a: Array, b: Array):
	if a[0] > b[0]:
		return true
	elif a[0] == b[0]:
		return false
	return false
