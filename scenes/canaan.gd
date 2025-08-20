extends Node2D

# UI
@onready var standard_map = $MapLayer/StandardMap
@onready var resource_num_map_layer = $MapLayer/ResourceNumbers
@onready var harbor_map_layer = $MapLayer/Harbors
@onready var roll_dice_btn = $UILayer/Roll_Dice
@onready var chat_log = $UILayer/Chat/Chat_Log
@export var chat_log_font_size = 30
@onready var UI_BOX_1 = $UILayer/Player1Background
@onready var UI_BOX_2 = $UILayer/Player2Background
@onready var UI_BOX_3 = $UILayer/Player3Background
@onready var UI_BOX_4 = $UILayer/Player4Background
@onready var global_ui_resource_offset = 0
@onready var NUM_SUPPLY_TREE = 19
@onready var NUM_SUPPLY_SHEEP = 19
@onready var NUM_SUPPLY_BRICK = 19
@onready var NUM_SUPPLY_WHEAT = 19
@onready var NUM_SUPPLY_STONE = 19
@onready var NUM_SUPPLY_DEV_CARD = 25
@export var global_road_ui_offset = Vector2(-25, 7.5)
@export var global_road_ui_btn_offset = Vector2(-10, -3.5)

# Game state variables
@onready var ALL_PLAYERS = []
@onready var global_vertices = null
@onready var NUM_PLAYERS = 4 # Server side variable
@onready var GLOBAL_TURN_NUM = 1 # Server side variable, all clients will have the same value
@onready var DIE_ROLL_NUM = 0 # Client variable, gets sent to server
@onready var is_roll_for_turn = true
@onready var is_initial_settlements = true
@onready var PLAYER_COUNT = 4 # Will never be less than 2, and for now, more than 4
@onready var ROBBER_POSITION = null
@onready var ALL_OWNED_ROADS = []
@onready var ALL_PLAYERS_TURN_NUMS = {}
@onready var CLIENT = null
@onready var CLIENT_INDEX = null
@onready var DEVELOPMENT_CARDS = []

@onready var tile_positions_local = []
@onready var tile_positions = []
@onready var global_harbor_positions = []
@onready var local_harbor_positions = []
# Debug vars
@export var DEBUG_map_vertex_offset = Vector2(905, 671) # For the map vertices
@onready var ALL_ROAD_MIDPOINTS = [] # Stores all road midpoints

@onready var ELIGIBLE_SETTLEMENT_VERTICES = [] # Contains a list of eligible vertices for settlement placement. This is shared between all players
@onready var ELIGIBLE_ROAD_VERTICES_SETUP = []
@onready var global_player_trades = []
@onready var global_player_with_largest_army = null
@onready var global_player_with_longest_road = null

# Signals
signal selection_finished # Used for returning control back to a main function after a user selects an action or they timeout from that action
signal end_turn # Used for signaling that a player or bots turn is over, usually used in the main game loop
signal robber_done # Used for returning control back to main game loop

func _ready() -> void:
	
	var PLAYER = load("res://player.gd")
	var colors = ["#ffcc00", "#f3f3f3", "#1ea7e1", "#e86a17"]
	for i in range(PLAYER_COUNT):
		if i == 0: # In multiplayer, this should check for whether this is a bot or player
			var PLAYER_OBJ = PLAYER.new()
			PLAYER_OBJ._name = "Player 1"
			PLAYER_OBJ.type = "Player"
			PLAYER_OBJ.id = i+1
			PLAYER_OBJ.color = colors[i]
			ALL_PLAYERS.append(PLAYER_OBJ)
			CLIENT = PLAYER_OBJ
		else:
			var BOT = PLAYER.new()
			BOT._name = ("Bot %s" % str(i))
			BOT.type = "Bot"
			BOT.color = colors[i]
			BOT.id = i+1
			ALL_PLAYERS.append(BOT)
	
	await initialize_ui_boxes()
	randomize() # Initializes randomizer, only call this once
	tile_positions = generate_rand_standard_map() # Map data contains coordinates of all cells of the map
	tile_positions_local = tile_map_coords_to_local_coords(standard_map, tile_positions, false)
	local_harbor_positions = tile_map_coords_to_local_coords(harbor_map_layer, global_harbor_positions, true)
	
	#for pos in local_harbor_positions:
		#var debug_icon = $MapLayer/Possible_Placement_Settlement.duplicate()
		#$MapLayer.add_child(debug_icon)
		#debug_icon.show()
		#debug_icon.position = pos
	
	global_vertices = await generate_tile_vertices(tile_positions, standard_map)
	ELIGIBLE_SETTLEMENT_VERTICES = global_vertices.duplicate() # At the beginning of the game, all vertices are eligible
	ELIGIBLE_ROAD_VERTICES_SETUP = global_vertices.duplicate()
	init_settlement_buttons(global_vertices)
	
	# Initialize Robber
	await initialize_robber(standard_map, tile_positions)
	
	# Initialize UI button states
	await ui_disable_all_buttons()
	
	# Initialize chat box setting(s)
	chat_log.append_text("[font_size=%s]Welcome to Canaan!\n" % chat_log_font_size)
	
	# Initialize road array
	for i in range(PLAYER_COUNT):
		ALL_OWNED_ROADS.append([])
		
	# Initialize development cards
	await initialize_development_cards()
	
	# Main game loop for a client
	await roll_for_who_goes_first()
	roll_dice_btn.disabled = true
	# Place initial settlements and roads for all players
	# First round
	for p in ALL_PLAYERS:
		place_initial_settlements_and_roads(p)
		await end_turn
	# Second round (goes in reverse order according to the rules of Catan)
	for i in range(ALL_PLAYERS.size()-1, -1, -1):
		place_initial_settlements_and_roads(ALL_PLAYERS[i])
		await end_turn
	
	generate_initial_resources(standard_map, tile_positions, tile_positions_local)
		
	chat_log.append_text("All players done placing settlements and roads.\n")
	
	for player in ALL_PLAYERS:
		player.vp = 2
		
	CLIENT.vp = 2
	
	for player in ALL_PLAYERS:
		ui_update_vp(player)
	
	main_game_loop(tile_positions, standard_map)
	
func main_game_loop(tile_positions, standard_map):
	# Bot functionality added for testing
	for i in range(100): # Turn limit?
		for p in ALL_PLAYERS:
			if p.type == "Player":
				# Turn Initializers
				roll_dice_btn.disabled = false
				roll_dice_btn.text = "Roll Dice"
				await ui_disable_all_buttons()
				chat_log.append_text("Player turn!\n")
				p.dev_card_played_this_turn = false
				#roll_dice_btn.disabled = false
				
				# Can play any development card before rolling dice
				await activate_development_card_btns()
				
				# Check for win
				
				await roll_dice_btn.pressed # Wait for user to roll dice before continuing
				p.dice_roll_result = _on_roll_dice_pressed()
				chat_log.append_text("%s rolled a %s. \n" % [p._name, p.dice_roll_result])
				roll_dice_btn.disabled = true
				
				# Generate resources for EACH player based on dice result, unless a 7 is rolled
				# For friendly robber, check that no player has VP > 2, else do robber as normal
				if p.dice_roll_result == 7:
					#for player in ALL_PLAYERS:
						#if player.vp < 3:
							#continue
						#else:
							#activate_robber(p)
					await activate_robber(p)
				
				DEBUG_assert_resources_are_in_sync()
					
				await generate_resources_for_all_players(p.dice_roll_result, tile_positions_local, tile_positions, standard_map)
				await activate_or_deactivate_ui_buttons()
				
				DEBUG_assert_resources_are_in_sync()
				
				# When player is done with turn
				#await roll_dice_btn.pressed
				await $UILayer/End_Turn_Btn_Background/End_Turn_Button.pressed
				
				#  !! Reset certain variables after player's turn is done
				for j in range(0, len(global_player_trades)):
					$UILayer.remove_child(global_player_trades[j])
					global_player_trades[j].queue_free()
				global_player_trades.clear()
				

			else:
				# Disable all buttons when it's not the client's turn
				# Simulate dice roll
				p.dev_card_played_this_turn = false
				p.dice_roll_result = _on_roll_dice_pressed()
				chat_log.append_text("%s rolled a %s.\n" % [p._name, p.dice_roll_result])
				if p.dice_roll_result == 7:
					#for player in ALL_PLAYERS:
						#if player.vp < 3:
							#continue
						#else:
							#activate_robber(p)
					await activate_robber(p)
					#print("robber done")
					
				DEBUG_assert_resources_are_in_sync()
					
				await generate_resources_for_all_players(p.dice_roll_result, tile_positions_local, tile_positions, standard_map)
				
				DEBUG_assert_resources_are_in_sync()
				
				bot_decision_loop(p)
				
				DEBUG_assert_resources_are_in_sync()
			
		
func DEBUG_assert_resources_are_in_sync():
	var total_resources_for_all_players = 0
	var total_resources_in_supply = 0
	for player in ALL_PLAYERS:
		total_resources_for_all_players += player.total_resources
	var resources = ["Tree", "Brick", "Wheat", "Stone", "Sheep"]
	total_resources_in_supply = NUM_SUPPLY_BRICK + NUM_SUPPLY_SHEEP + NUM_SUPPLY_STONE + NUM_SUPPLY_TREE + NUM_SUPPLY_WHEAT
	assert(total_resources_in_supply + total_resources_for_all_players == 95, "resources are out of sync! total resources between players and supply: " + str(total_resources_for_all_players + total_resources_in_supply) + ". Amount it should be: 95.")

func initialize_ui_boxes() -> void:
	var index = 1
	for p in ALL_PLAYERS:
		get_node("UILayer/Player%sBackground/PlayerName" % index).text = "[font_size=18][center][b]%s" % p._name
		get_node("UILayer/Player%sBackground" % index).color = p.color
		index += 1
	


func initialize_robber(map_data, tile_positions):
	# Find desert tile and place robber there
	for i in range(len(tile_positions)):
		var id = map_data.get_cell_source_id(tile_positions[i])
		if id == 6: # 6 = desert
			var local_coords_for_center_of_tile = tile_positions_local[i]
			$MapLayer/Robber.position = local_coords_for_center_of_tile + Vector2(-32, -32)
			ROBBER_POSITION = local_coords_for_center_of_tile
			break
	return

func initialize_development_cards():
	var num_of_each_development_card = {
		"Knight": 14,
		"Monopoly": 2,
		"Road": 2,
		"Invention": 2,
		"VP": 5
	}
	
	var dev_card_to_index_mapping = {
		0: "Knight",
		1: "Monopoly",
		2: "Road",
		3: "Invention",
		4: "VP"
	}
	for i in range(25):
		var rand_dev_card_name
		while true:
			rand_dev_card_name = dev_card_to_index_mapping[randi_range(0, 4)]
			var rand_dev_card_amt = num_of_each_development_card[rand_dev_card_name]
			if rand_dev_card_amt == 0:
				continue
			else:
				num_of_each_development_card[rand_dev_card_name] -= 1
				break
		DEVELOPMENT_CARDS.append(rand_dev_card_name)
	DEVELOPMENT_CARDS.shuffle()

# A client will only roll once
func roll_for_who_goes_first():
	# Determine who goes first by rolling for it
	# Upate player_turn var from server?
	chat_log.append_text("Roll for turn order!\n")
	
	var turn_order = []
	for player in ALL_PLAYERS:
		if player.type == "Player":
			await roll_dice_btn.pressed # Wait for user to roll dice before continuing
			player.dice_roll_result = _on_roll_dice_pressed()
			turn_order.append([player.dice_roll_result, player])
			
			# Update the chat log
			var fmt_str = "Player %s rolled a %s\n"
			var act_str = fmt_str % [player.id, player.dice_roll_result]
			chat_log.append_text(act_str)
		else:
			player.dice_roll_result = _on_roll_dice_pressed()
			turn_order.append([player.dice_roll_result, player])
			var fmt_str = "Player %s rolled a %s\n"
			var act_str = fmt_str % [player.id, player.dice_roll_result]
			chat_log.append_text(act_str)
		GLOBAL_TURN_NUM += 1
		
		
	turn_order.sort_custom(custom_sort_for_first_roll)
	

	for i in ALL_PLAYERS.size():
		ALL_PLAYERS[i] = turn_order[i][1]
		if ALL_PLAYERS[i].type == "Player":
			CLIENT_INDEX = i
		# Store bot indexes too?

	for i in ALL_PLAYERS.size():
		var fmt_str = "%s %s goes %s!\n"
		var act_str = fmt_str % [ALL_PLAYERS[i].type, ALL_PLAYERS[i].id, i+1]
		chat_log.append_text(act_str)
		
	is_roll_for_turn = false
	GLOBAL_TURN_NUM = 1

func custom_sort_for_first_roll(a: Array, b: Array):
	if a[0] > b[0]:
		return true
	elif a[0] == b[0]:
		return false
	return false

func _on_bank_trade_button_pressed() -> void:
	# Pop up (or hide) UI, set variables
	$UILayer/Bank_Trade_Popup.visible = !$UILayer/Bank_Trade_Popup.visible
	if $UILayer/Bank_Trade_Popup.visible == false:
		CLIENT.chosen_resources_trade = []
		CLIENT.chosen_resources_bank_trade = []
		for node in $UILayer/Bank_Trade_Popup/Dynamic_Player_Area.get_children():
			$UILayer/Bank_Trade_Popup/Dynamic_Player_Area.remove_child(node)
			node.queue_free()
		for node in $UILayer/Bank_Trade_Popup/Dynamic_Bank_Area.get_children():
			$UILayer/Bank_Trade_Popup/Dynamic_Bank_Area.remove_child(node)
			node.queue_free()
		
		$UILayer/Bank_Trade_Popup/Divider4/Invalid_Trade_Text.hide()
		
		activate_or_deactivate_ui_buttons()
	else: # Cleanup: Use some loops here
		ui_disable_all_buttons(["Bank_Trade_Button"])
		
		get_node("UILayer/Bank_Trade_Popup/Brick_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Brick"]
		get_node("UILayer/Bank_Trade_Popup/Sheep_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Sheep"]
		get_node("UILayer/Bank_Trade_Popup/Stone_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Stone"]
		get_node("UILayer/Bank_Trade_Popup/Wheat_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Wheat"]
		get_node("UILayer/Bank_Trade_Popup/Tree_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Tree"]
		
		get_node("UILayer/Bank_Trade_Popup/Brick_Bank/Num_Remaining").text = "[font_size=30][center][b]%s" % NUM_SUPPLY_BRICK
		get_node("UILayer/Bank_Trade_Popup/Sheep_Bank/Num_Remaining").text = "[font_size=30][center][b]%s" % NUM_SUPPLY_SHEEP
		get_node("UILayer/Bank_Trade_Popup/Stone_Bank/Num_Remaining").text = "[font_size=30][center][b]%s" % NUM_SUPPLY_STONE
		get_node("UILayer/Bank_Trade_Popup/Wheat_Bank/Num_Remaining").text = "[font_size=30][center][b]%s" % NUM_SUPPLY_WHEAT
		get_node("UILayer/Bank_Trade_Popup/Tree_Bank/Num_Remaining").text = "[font_size=30][center][b]%s" % NUM_SUPPLY_TREE
		
		$UILayer/Bank_Trade_Popup/Brick_Player.visible = true
		$UILayer/Bank_Trade_Popup/Sheep_Player.visible = true
		$UILayer/Bank_Trade_Popup/Stone_Player.visible = true
		$UILayer/Bank_Trade_Popup/Wheat_Player.visible = true 
		$UILayer/Bank_Trade_Popup/Tree_Player.visible = true

		$UILayer/Bank_Trade_Popup/Brick_Player/Brick_Player_Btn.visible = false if CLIENT.resources["Brick"] == 0 else true
		$UILayer/Bank_Trade_Popup/Sheep_Player/Sheep_Player_Btn.visible = false if CLIENT.resources["Sheep"] == 0 else true
		$UILayer/Bank_Trade_Popup/Stone_Player/Stone_Player_Btn.visible = false if CLIENT.resources["Stone"] == 0 else true
		$UILayer/Bank_Trade_Popup/Wheat_Player/Wheat_Player_Btn.visible = false if CLIENT.resources["Wheat"] == 0 else true
		$UILayer/Bank_Trade_Popup/Tree_Player/Tree_Player_Btn.visible = false if CLIENT.resources["Tree"] == 0 else true
			
		$UILayer/Bank_Trade_Popup/Brick_Bank.visible = true
		$UILayer/Bank_Trade_Popup/Sheep_Bank.visible = true
		$UILayer/Bank_Trade_Popup/Stone_Bank.visible = true
		$UILayer/Bank_Trade_Popup/Wheat_Bank.visible = true
		$UILayer/Bank_Trade_Popup/Tree_Bank.visible = true
		
		$UILayer/Bank_Trade_Popup/Brick_Bank/Brick_Bank_Btn.visible = false if NUM_SUPPLY_BRICK == 0 else true
		$UILayer/Bank_Trade_Popup/Sheep_Bank/Sheep_Bank_Btn.visible = false if NUM_SUPPLY_SHEEP == 0 else true
		$UILayer/Bank_Trade_Popup/Stone_Bank/Stone_Bank_Btn.visible = false if NUM_SUPPLY_STONE == 0 else true
		$UILayer/Bank_Trade_Popup/Wheat_Bank/Wheat_Bank_Btn.visible = false if NUM_SUPPLY_WHEAT == 0 else true
		$UILayer/Bank_Trade_Popup/Tree_Bank/Tree_Bank_Btn.visible = false if NUM_SUPPLY_TREE == 0 else true

func _on_BANK_TRADE_stone_player_btn_pressed() -> void:
	await bank_trade_add_resource_to_player_area("Stone")

func _on_BANK_TRADE_tree_player_btn_pressed() -> void:
	await bank_trade_add_resource_to_player_area("Tree")

func _on_BANK_TRADE_wheat_player_btn_pressed() -> void:
	await bank_trade_add_resource_to_player_area("Wheat")

func _on_BANK_TRADE_sheep_player_btn_pressed() -> void:
	await bank_trade_add_resource_to_player_area("Sheep")

func _on_BANK_TRADE_brick_player_btn_pressed() -> void:
	await bank_trade_add_resource_to_player_area("Brick")

func _on_BANK_TRADE_sheep_bank_btn_pressed() -> void:
	await bank_trade_add_resource_to_bank_area("Sheep")

func _on_BANK_TRADE_brick_bank_btn_pressed() -> void:
	await bank_trade_add_resource_to_bank_area("Brick")

func _on_BANK_TRADE_tree_bank_btn_pressed() -> void:
	await bank_trade_add_resource_to_bank_area("Tree")

func _on_BANK_TRADE_stone_bank_btn_pressed() -> void:
	await bank_trade_add_resource_to_bank_area("Stone")

func _on_BANK_TRADE_wheat_bank_btn_pressed() -> void:
	await bank_trade_add_resource_to_bank_area("Wheat")

# If the player presses on the resource they added up for trade, remove that resource and add it back to their resources
func bank_trade_remove_resource_from_player_area(node, resource):
	if int(node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) == 1:
		CLIENT.chosen_resources_trade = []
		
		# Add back this resource for the player's resources
		var num_remaining = int(get_node("UILayer/Bank_Trade_Popup/%s_Player/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) + 1
		get_node("UILayer/Bank_Trade_Popup/%s_Player/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
		
		for n in $UILayer/Bank_Trade_Popup.get_children():
			if "Player" in n.name and n.name != "Dynamic_Player_Area":
				n.show()
		
		$UILayer/Bank_Trade_Popup/Dynamic_Player_Area.remove_child(node)
		node.queue_free()
		
	else: # just decrease num_remaining in the player area, and increase the value for the player's resources
		var num_remaining = int(node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) - 1
		node.get_child(0).text = "[font_size=30][center][b]%s" % str(num_remaining)
		CLIENT.chosen_resources_trade.pop_at(0) # This is safe since we only have one type of resource in the array at a time
		
		# Increase
		num_remaining = int(get_node("UILayer/Bank_Trade_Popup/%s_Player/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) + 1
		get_node("UILayer/Bank_Trade_Popup/%s_Player/%s_Player_Btn" % [resource, resource]).show()
		get_node("UILayer/Bank_Trade_Popup/%s_Player/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)

func bank_trade_add_resource_to_player_area(resource):
	
	if $UILayer/Bank_Trade_Popup/Dynamic_Player_Area.get_child_count(true) == 0:
		var new_node = get_node("UILayer/Bank_Trade_Popup/%s_Player" % resource).duplicate(0) # Don't duplicate the signal
		new_node.get_child(1).pressed.connect(bank_trade_remove_resource_from_player_area.bind(new_node, resource))
		new_node.position = Vector2(195, 32)
		new_node.get_child(0).text = "[font_size=30][center][b]1"
		$UILayer/Bank_Trade_Popup/Dynamic_Player_Area.add_child(new_node)
	else: # If already there, just increase num_remaining
		var existing_node = $UILayer/Bank_Trade_Popup/Dynamic_Player_Area.get_child(0)
		var num_remaining = int(existing_node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) + 1
		existing_node.get_child(0).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	# Decrease num_remaining for the player's resources
	var num_remaining = int(get_node("UILayer/Bank_Trade_Popup/%s_Player/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) - 1
	if num_remaining == 0:
		get_node("UILayer/Bank_Trade_Popup/%s_Player/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
		get_node("UILayer/Bank_Trade_Popup/%s_Player/%s_Player_Btn" % [resource, resource]).hide()
	else:
		get_node("UILayer/Bank_Trade_Popup/%s_Player/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	CLIENT.chosen_resources_trade.append(resource)
	
	# Disable all other resources to be selected for the player (for now, the player can only make one trade at a time)
	for node in $UILayer/Bank_Trade_Popup.get_children():
		if resource in node.name:
			continue
		if "Player" in node.name and node.name != "Dynamic_Player_Area":
			node.hide()
	

# If the player presses on the resource they added up for trade, remove that resource and add it back to their resources
func bank_trade_remove_resource_from_bank_area(node, resource):
	if int(node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) == 1:
		CLIENT.chosen_resources_bank_trade = []
		
		# Add back this resource for the player's resources
		var num_remaining = int(get_node("UILayer/Bank_Trade_Popup/%s_Bank/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) + 1
		get_node("UILayer/Bank_Trade_Popup/%s_Bank/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
		
		for n in $UILayer/Bank_Trade_Popup.get_children():
			if "Bank" in n.name and n.name != "Dynamic_Bank_Area":
				n.show()
		
		$UILayer/Bank_Trade_Popup/Dynamic_Bank_Area.remove_child(node)
		node.queue_free()
		
	else: # just decrease num_remaining in the player area, and increase the value for the player's resources
		var num_remaining = int(node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) - 1
		node.get_child(0).text = "[font_size=30][center][b]%s" % str(num_remaining)
		CLIENT.chosen_resources_bank_trade.pop_at(0) # This is safe since we only have one type of resource in the array at a time
		
		# Increase
		num_remaining = int(get_node("UILayer/Bank_Trade_Popup/%s_Bank/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) + 1
		get_node("UILayer/Bank_Trade_Popup/%s_Bank/%s_Bank_Btn" % [resource, resource]).show()
		get_node("UILayer/Bank_Trade_Popup/%s_Bank/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)

func bank_trade_add_resource_to_bank_area(resource):
	
	if $UILayer/Bank_Trade_Popup/Dynamic_Bank_Area.get_child_count(true) == 0:
		var new_node = get_node("UILayer/Bank_Trade_Popup/%s_Bank" % resource).duplicate(0) # Don't duplicate the signal
		new_node.get_child(1).pressed.connect(bank_trade_remove_resource_from_bank_area.bind(new_node, resource))
		new_node.position = Vector2(195, 32)
		new_node.get_child(0).text = "[font_size=30][center][b]1"
		$UILayer/Bank_Trade_Popup/Dynamic_Bank_Area.add_child(new_node)
	else: # If already there, just increase num_remaining
		var existing_node = $UILayer/Bank_Trade_Popup/Dynamic_Bank_Area.get_child(0)
		var num_remaining = int(existing_node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) + 1
		existing_node.get_child(0).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	# Decrease num_remaining for the player's resources
	var num_remaining = int(get_node("UILayer/Bank_Trade_Popup/%s_Bank/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) - 1
	if num_remaining == 0:
		get_node("UILayer/Bank_Trade_Popup/%s_Bank/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
		get_node("UILayer/Bank_Trade_Popup/%s_Bank/%s_Bank_Btn" % [resource, resource]).hide()
	else:
		get_node("UILayer/Bank_Trade_Popup/%s_Bank/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	CLIENT.chosen_resources_bank_trade.append(resource)
	
	# Disable all other resources to be selected for the player (for now, the player can only make one trade at a time)
	for node in $UILayer/Bank_Trade_Popup.get_children():
		if resource in node.name:
			continue
		if "Bank" in node.name and node.name != "Dynamic_Bank_Area":
			node.hide()
	
	#print(CLIENT.chosen_resources_bank_trade)

func check_if_valid_bank_trade() -> bool:
	# Check that correct resources have been made for trade, taking into account bank supply numbers
	# Check for harbors/valid 3:1 or 2:1 trades
	
	if len(CLIENT.chosen_resources_trade) >= 2 and len(CLIENT.chosen_resources_bank_trade) >= 1:
		if len(CLIENT.harbors) > 0: # If they have harbors, take them into consideration when trading
			if "3:1" in CLIENT.harbors and len(CLIENT.chosen_resources_trade) >= 3:
				var player_resource = CLIENT.chosen_resources_trade[0]
				var loop_range = 3
				if player_resource in CLIENT.harbors: # This handles the case where the player has a 3:1 but also a 2:1 AND selected that resource to trade
					loop_range = 2
				for i in range(0, len(CLIENT.chosen_resources_trade), loop_range):
					if len(CLIENT.chosen_resources_bank_trade) >= 1:
						var left_trade = CLIENT.chosen_resources_trade.slice(i, i+loop_range)
						var right_trade = CLIENT.chosen_resources_bank_trade.pop_at(0)
						
						#print("left trade: ", CLIENT.chosen_resources_trade, " right trade: ", CLIENT.chosen_resources_bank_trade)
						
						for j in range(0, loop_range):
							CLIENT.resources[left_trade[0]] -= 1
							CLIENT.total_resources -= 1
							ui_remove_from_resource_bar(left_trade[0])
							ui_add_resource_to_supply(left_trade[0])
						
						CLIENT.resources[right_trade] += 1
						CLIENT.total_resources += 1
						ui_add_to_resource_bar(right_trade)
						ui_remove_resource_from_supply(right_trade)
						
				ui_update_resources(CLIENT)
				return true
			else: # 2:1, matching based on resource
				var player_resource = CLIENT.chosen_resources_trade[0]
				if player_resource in CLIENT.harbors:
					for i in range(0, len(CLIENT.chosen_resources_trade), 2):
						if len(CLIENT.chosen_resources_bank_trade) >= 1:
							var left_trade = CLIENT.chosen_resources_trade.slice(i, i+2)
							var right_trade = CLIENT.chosen_resources_bank_trade.pop_at(0)
							
							#print("left trade: ", CLIENT.chosen_resources_trade, " right trade: ", CLIENT.chosen_resources_bank_trade)
							
							for j in range(0, 2):
								CLIENT.resources[left_trade[0]] -= 1
								CLIENT.total_resources -= 1
								ui_remove_from_resource_bar(left_trade[0])
								ui_add_resource_to_supply(left_trade[0])
							
							CLIENT.resources[right_trade] += 1
							CLIENT.total_resources += 1
							ui_add_to_resource_bar(right_trade)
							ui_remove_resource_from_supply(right_trade)
							
					ui_update_resources(CLIENT)
					return true
				elif len(CLIENT.chosen_resources_trade) >= 4: # 4:1, 8:2, etc.
					for i in range(0, len(CLIENT.chosen_resources_trade), 4):
						if len(CLIENT.chosen_resources_bank_trade) >= 1:
							var left_trade = CLIENT.chosen_resources_trade.slice(i, i+4)
							var right_trade = CLIENT.chosen_resources_bank_trade.pop_at(0)
							
							#print("left trade: ", CLIENT.chosen_resources_trade, " right trade: ", CLIENT.chosen_resources_bank_trade)
							
							for j in range(0, 4):
								CLIENT.resources[left_trade[0]] -= 1
								CLIENT.total_resources -= 1
								ui_remove_from_resource_bar(left_trade[0])
								ui_add_resource_to_supply(left_trade[0])

							
							CLIENT.resources[right_trade] += 1
							CLIENT.total_resources += 1
							ui_add_to_resource_bar(right_trade)
							ui_remove_resource_from_supply(right_trade)
							
					ui_update_resources(CLIENT)
							
					return true
				else:
					return false
			
		elif len(CLIENT.chosen_resources_trade) >= 4: # 4:1, 8:2, etc.
			for i in range(0, len(CLIENT.chosen_resources_trade), 4):
				if len(CLIENT.chosen_resources_bank_trade) >= 1:
					var left_trade = CLIENT.chosen_resources_trade.slice(i, i+4)
					var right_trade = CLIENT.chosen_resources_bank_trade.pop_at(0)
					
					#print("left trade: ", CLIENT.chosen_resources_trade, " right trade: ", CLIENT.chosen_resources_bank_trade)
					
					for j in range(0, 4):
						CLIENT.resources[left_trade[0]] -= 1
						CLIENT.total_resources -= 1
						ui_remove_from_resource_bar(left_trade[0])
						ui_add_resource_to_supply(left_trade[0])

					
					CLIENT.resources[right_trade] += 1
					CLIENT.total_resources += 1
					ui_add_to_resource_bar(right_trade)
					ui_remove_resource_from_supply(right_trade)
					
			ui_update_resources(CLIENT)
					
			return true
				
		else:
			return false
			
	else:
		return false
	
	return false

func _on_finish_BANK_trade_btn_pressed() -> void:
	var is_valid_bank_trade = check_if_valid_bank_trade()
	if is_valid_bank_trade == false:
		$UILayer/Bank_Trade_Popup/Divider4.show()
	else:
		$UILayer/Bank_Trade_Popup/Divider4.hide()
		$UILayer/Bank_Trade_Popup.hide()
		
		CLIENT.chosen_resources_trade = []
		CLIENT.chosen_resources_bank_trade = []
		for node in $UILayer/Bank_Trade_Popup/Dynamic_Player_Area.get_children():
			$UILayer/Bank_Trade_Popup/Dynamic_Player_Area.remove_child(node)
			node.queue_free()
		for node in $UILayer/Bank_Trade_Popup/Dynamic_Bank_Area.get_children():
			$UILayer/Bank_Trade_Popup/Dynamic_Bank_Area.remove_child(node)
			node.queue_free()
			
		activate_or_deactivate_ui_buttons()

signal done_picking
func activate_robber(player):
	for p in ALL_PLAYERS:
		if p.total_resources > 7:
			var num_of_resources_to_discard = floor(p.total_resources / 2)
			#print(p._name, " total resources: ", p.total_resources)
			#print(p._name, " discarding ", num_of_resources_to_discard, " resources.")
			if p.type == "Bot":
				for i in range(num_of_resources_to_discard):
					if p.resources["Tree"] > 0:
						p.resources["Tree"] -= 1
						ui_add_resource_to_supply("Tree")
					elif p.resources["Brick"] > 0:
						p.resources["Brick"] -= 1
						ui_add_resource_to_supply("Brick")
					elif p.resources["Stone"] > 0:
						p.resources["Stone"] -= 1
						ui_add_resource_to_supply("Stone")
					elif p.resources["Wheat"] > 0:
						p.resources["Wheat"] -= 1
						ui_add_resource_to_supply("Wheat")
					elif p.resources["Sheep"] > 0:
						p.resources["Sheep"] -= 1
						ui_add_resource_to_supply("Sheep")
					p.total_resources -= 1
				ui_update_resources(p)
			else:
				ui_robber_discard_resources(p, num_of_resources_to_discard)
				await done_picking
				ui_update_resources(p)
		else:
			#print(p._name, " has ", p.total_resources, " resources, doesn't discard any.")
			pass
	
	# This player MUST move the robber
	if player.type == "Bot":
		# For now, just choose randomly
		var random_robber_pos
		while true:
			random_robber_pos = tile_positions_local.pick_random()
			if random_robber_pos == ROBBER_POSITION:
				continue
			else:
				break
		$MapLayer/Robber.position = random_robber_pos + Vector2(-32, -32)
		ROBBER_POSITION = random_robber_pos
		
		await bot_robber_steal(player, random_robber_pos)
	else:
		ui_robber_choose_new_location_client()
		await done_picking
	return

func ui_robber_discard_resources(player, num_resources_to_discard):
	
	var ID_TO_RESOURCE_MAPPING = {
		1: "Tree",
		2: "Sheep",
		3: "Brick",
		4: "Wheat",
		5: "Stone"
	}
	
	var UI_OFFSET_MAPPING = {
		1: 0,
		2: 60,
		3: 120,
		4: 180,
		5: 240
	}
	
	ui_disable_all_buttons()
	
	$"UILayer/Resource Bar/Robber_Discard".show()
	$"UILayer/Resource Bar/Robber_Discard".text = "[font_size=26][center]ROBBER! Discarded 0/%s resources." % num_resources_to_discard
	
	for j in range(num_resources_to_discard):
		for i in range(len(player.PLAYER_RESOURCE_BAR_POSITIONS)):
			# Dynamically create buttons on top of the resources as indicated by the player's resource bar positions
			# Then connect a signal when they press that specific button and handle removing the correct resource
			var curr_res = player.PLAYER_RESOURCE_BAR_POSITIONS[i]
			if curr_res != null:
			
				var resource_name = ID_TO_RESOURCE_MAPPING[curr_res]
				var UI_offset = UI_OFFSET_MAPPING[i+1]
				
				var copied_ui_resource = $"UILayer/Resource Bar/Resource_Discard_Btn".duplicate()
				$"UILayer/Resource Bar".add_child(copied_ui_resource, true)
				copied_ui_resource.position = Vector2(6.5 + UI_offset, 9.3)
				copied_ui_resource.z_index = 1
				copied_ui_resource.show()
				
				copied_ui_resource.pressed.connect(resource_discard_pressed.bind(resource_name, curr_res, player))
			
		await selection_finished
		await get_tree().create_timer(0.01).timeout
		$"UILayer/Resource Bar/Robber_Discard".text = "[font_size=26][center]ROBBER! Discarded %s/%s resources." % [j+1, num_resources_to_discard]
	
		# Cleanup # Remove UI elements
		var i = 2
		for node in get_node("UILayer/Resource Bar").get_children():
			if node.name == ("Resource_Discard_Btn%s" % str(i)):
				i+=1
				$"UILayer/Resource Bar".remove_child(node)
				node.queue_free()
			
	$"UILayer/Resource Bar/Robber_Discard".hide()
	
	emit_signal("done_picking")

func resource_discard_pressed(resource_name, resource_id, player):
	player.resources[resource_name] -= 1
	player.total_resources -= 1
	await ui_remove_from_resource_bar(resource_name)
	await ui_add_resource_to_supply(resource_name)
	
	ui_update_resources(player)
	
	emit_signal("selection_finished")

func bot_robber_steal(player, local_coords_for_center_of_tile):
	
	var rob_players = []
	for p in ALL_PLAYERS:
		if p._name == player._name:
			continue
		for settlement_pos in p.settlements:
			var distance = get_distance(local_coords_for_center_of_tile, settlement_pos)
			if distance < 75:
				# This player is eligible to be stolen from
				rob_players.append(p)
		for city_pos in p.cities:
			var distance = get_distance(local_coords_for_center_of_tile, city_pos)
			if distance < 75:
				# This player is eligible to be stolen from
				rob_players.append(p)
	
	if len(rob_players) > 1:
		var p = rob_players.pick_random()
		
		var viable_resources_to_steal = []
		if p.resources["Tree"] > 0:
			viable_resources_to_steal.append("Tree")
		if p.resources["Brick"] > 0:
			viable_resources_to_steal.append("Brick")
		if p.resources["Stone"] > 0:
			viable_resources_to_steal.append("Stone")
		if p.resources["Sheep"] > 0:
			viable_resources_to_steal.append("Sheep")
		if p.resources["Wheat"] > 0:
			viable_resources_to_steal.append("Wheat")
		
		if len(viable_resources_to_steal) == 0:
			return
		
		var random_resource = viable_resources_to_steal.pick_random()
		
		p.resources[random_resource] -= 1
		p.total_resources -= 1
		
		player.resources[random_resource] += 1
		player.total_resources += 1
		
		chat_log.append_text(player._name + " robbed a " + random_resource + " from " + p._name + "!\n")
		
		if p.type == "Player":
			ui_remove_from_resource_bar(random_resource)
			
		ui_update_resources(p)
		ui_update_resources(player)
		
	elif len(rob_players) == 1:
		var p = rob_players[0]
		
		var viable_resources_to_steal = []
		if p.resources["Tree"] > 0:
			viable_resources_to_steal.append("Tree")
		if p.resources["Brick"] > 0:
			viable_resources_to_steal.append("Brick")
		if p.resources["Stone"] > 0:
			viable_resources_to_steal.append("Stone")
		if p.resources["Sheep"] > 0:
			viable_resources_to_steal.append("Sheep")
		if p.resources["Wheat"] > 0:
			viable_resources_to_steal.append("Wheat")
		
		if len(viable_resources_to_steal) == 0:
			return
		
		var random_resource = viable_resources_to_steal.pick_random()
		
		p.resources[random_resource] -= 1
		p.total_resources -= 1
		
		player.resources[random_resource] += 1
		player.total_resources += 1
		
		chat_log.append_text(player._name + " robbed a " + random_resource + " from " + p._name + "!\n")
		
		if p.type == "Player":
			ui_remove_from_resource_bar(random_resource)
			
		ui_update_resources(p)
		ui_update_resources(player)
	else:
		#print("No one to rob from!")
		pass

func ui_robber_choose_new_location_client():
	
	for i in range(len(tile_positions)):
		var id = standard_map.get_cell_source_id(tile_positions[i])
		var local_coords_for_center_of_tile = tile_positions_local[i]
		
		# Create UI elements for all possible positions, which is everywhere except the current position
		if ROBBER_POSITION == local_coords_for_center_of_tile:
			continue

		var curr_UI_element = $MapLayer/Robber_Choose_Resource_Tile_Btn.duplicate()
		$MapLayer.add_child(curr_UI_element, true)
		curr_UI_element.show()
		curr_UI_element.position = local_coords_for_center_of_tile + Vector2(-33, -26)
		curr_UI_element.pressed.connect(ui_robber_new_location.bind(local_coords_for_center_of_tile))
		
	await done_picking
	
	emit_signal("done_picking")

func ui_robber_new_location(local_coords_for_center_of_tile):
	
	var i = 2
	for n in get_node("MapLayer").get_children():
		if n.name == ("Robber_Choose_Resource_Tile_Btn%s" % i):
			i+=1
			$MapLayer.remove_child(n)
			n.queue_free()
	
	$MapLayer/Robber.position = local_coords_for_center_of_tile + Vector2(-32, -32)
	ROBBER_POSITION = local_coords_for_center_of_tile
	
	# Check if anyone's settlements are adjacent to this new placement. If so, steal from them.. if multiple players, choose who to steal from first
	
	var rob_players = []
	for p in ALL_PLAYERS:
		# Update this code for multiplayer, this should just be something like "not the client" a.k.a person placing the robber..
		if p.type == "Player":
			continue
		else:
			for settlement_pos in p.settlements:
				var distance = get_distance(local_coords_for_center_of_tile, settlement_pos)
				if distance < 75:
					# This player is eligible to be stolen from
					rob_players.append(p)
			for city_pos in p.cities:
				var distance = get_distance(local_coords_for_center_of_tile, city_pos)
				if distance < 75:
					# This player is eligible to be stolen from
					rob_players.append(p)
					
	if len(rob_players) > 1:
		$MapLayer/Choose_Who_To_Rob_Container.position = local_coords_for_center_of_tile + Vector2(-100, -100)
		$MapLayer/Choose_Who_To_Rob_Container.show()
		
		for p in rob_players:
			if p._name == "Bot 1":
				$MapLayer/Choose_Who_To_Rob_Container/Bot1_Choose_To_Rob_Btn.show()
				$MapLayer/Choose_Who_To_Rob_Container/Bot1_Choose_To_Rob_Btn.pressed.connect(ui_choose_who_to_rob.bind(p))
			elif p._name == "Bot 2":
				$MapLayer/Choose_Who_To_Rob_Container/Bot2_Choose_To_Rob_Btn.show()
				$MapLayer/Choose_Who_To_Rob_Container/Bot2_Choose_To_Rob_Btn.pressed.connect(ui_choose_who_to_rob.bind(p))
			elif p._name == "Bot 3":
				$MapLayer/Choose_Who_To_Rob_Container/Bot3_Choose_To_Rob_Btn.show()
				$MapLayer/Choose_Who_To_Rob_Container/Bot3_Choose_To_Rob_Btn.pressed.connect(ui_choose_who_to_rob.bind(p))
		
		await done_picking
		
	
	# Randomly steal a resource from the only player you can steal from
	elif len(rob_players) == 1:
		var player = rob_players[0]
		
		var viable_resources_to_steal = []
		if player.resources["Tree"] > 0:
			viable_resources_to_steal.append("Tree")
		if player.resources["Brick"] > 0:
			viable_resources_to_steal.append("Brick")
		if player.resources["Stone"] > 0:
			viable_resources_to_steal.append("Stone")
		if player.resources["Sheep"] > 0:
			viable_resources_to_steal.append("Sheep")
		if player.resources["Wheat"] > 0:
			viable_resources_to_steal.append("Wheat")
		
		if len(viable_resources_to_steal) == 0:
			emit_signal("done_picking")
			return
		
		var random_resource = viable_resources_to_steal.pick_random()
		
		player.resources[random_resource] -= 1
		player.total_resources -= 1
		
		CLIENT.resources[random_resource] += 1
		CLIENT.total_resources += 1
		
		chat_log.append_text(CLIENT._name + " robbed a " + random_resource + " from " + player._name + "!\n")
		
		ui_update_resources(CLIENT)
		ui_update_resources(player)
		
		ui_add_to_resource_bar(random_resource)
	
	# No one is adjacent, don't steal
	else:
		#print("No one to steal from!")
		pass
		
	emit_signal("done_picking")

func ui_choose_who_to_rob(player):
	# Transfer random resource from player arg to the client
	
	for n in $MapLayer/Choose_Who_To_Rob_Container.get_children():
		n.hide()
	$MapLayer/Choose_Who_To_Rob_Container.hide()
	
	var viable_resources_to_steal = []
	if player.resources["Tree"] > 0:
		viable_resources_to_steal.append("Tree")
	if player.resources["Brick"] > 0:
		viable_resources_to_steal.append("Brick")
	if player.resources["Stone"] > 0:
		viable_resources_to_steal.append("Stone")
	if player.resources["Sheep"] > 0:
		viable_resources_to_steal.append("Sheep")
	if player.resources["Wheat"] > 0:
		viable_resources_to_steal.append("Wheat")
	
	if len(viable_resources_to_steal) == 0:
		emit_signal("done_picking")
		return
	
	var random_resource = viable_resources_to_steal.pick_random()
	
	player.resources[random_resource] -= 1
	player.total_resources -= 1
	
	CLIENT.resources[random_resource] += 1
	CLIENT.total_resources += 1
	
	ui_add_to_resource_bar(random_resource)
	
	chat_log.append_text(CLIENT._name + " robbed a " + random_resource + " from " +  player._name + "!\n")
	
	ui_update_resources(CLIENT)
	ui_update_resources(player)
	
	emit_signal("done_picking")

func activate_development_card_btns():
	for node in get_node("UILayer/Resource Bar").get_children():
		if node.name.contains("DevCard"):
			if node.name != "VP_DevCard":
				node.get_children()[1].show()

func ui_disable_all_buttons(exclude=[]): # Optionally, provide a list of buttons to NOT disable
	
	$UILayer/Build_City_Btn_Background/Build_City_Button.disabled = false if "Build_City_Button" in exclude else true
	$UILayer/Build_City_Btn_Background/Disabled_Mask.visible = false if "Build_City_Button" in exclude else true
	
	$UILayer/Build_Road_Btn_Background/Build_Road_Button.disabled = false if "Build_Road_Button" in exclude else true
	$UILayer/Build_Road_Btn_Background/Disabled_Mask.visible = false if "Build_Road_Button" in exclude else true
	
	$UILayer/Build_Settlement_Btn_Background/Build_Settlement_Button.disabled = false if "Build_Settlement_Button" in exclude else true
	$UILayer/Build_Settlement_Btn_Background/Disabled_Mask.visible = false if "Build_Settlement_Button" in exclude else true
	
	$UILayer/Buy_Development_Card_Background/Buy_Development_Card_Button.disabled = false if "Buy_Development_Card_Button" in exclude else true
	$UILayer/Buy_Development_Card_Background/Disabled_Mask.visible = false if "Buy_Development_Card_Button" in exclude else true
	
	$UILayer/Bank_Trade_Btn_Background/Bank_Trade_Button.disabled = false if "Bank_Trade_Button" in exclude else true
	$UILayer/Bank_Trade_Btn_Background/Disabled_Mask.visible = false if "Bank_Trade_Button" in exclude else true
	
	$UILayer/Player_Trade_Btn_Background/Player_Trade_Button.disabled = false if "Player_Trade_Button" in exclude else true
	$UILayer/Player_Trade_Btn_Background/Disabled_Mask.visible = false if "Player_Trade_Button" in exclude else true
	
	$UILayer/End_Turn_Btn_Background/End_Turn_Button.disabled = false if "End_Turn_Button" in exclude else true
	$UILayer/End_Turn_Btn_Background/Disabled_Mask.visible = false if "End_Turn_Button" in exclude else true
	
# Sets certain UI buttons/elements as "active"/"not disabled" if the player meets the resource requirement for them,
# indicating that they can afford the respective thing (settlement, city, road, development card, etc.)
# Call this anytime after a player modifies their resources in any way (dice roll, dev card, trading, etc.)
func activate_or_deactivate_ui_buttons():
	# Road
	var build_road_button_state = false if CLIENT.resources["Brick"] >= 1 and CLIENT.resources["Tree"] >= 1 and len(CLIENT.roads) <= 15 else true
	$UILayer/Build_Road_Btn_Background/Build_Road_Button.disabled = build_road_button_state
	$UILayer/Build_Road_Btn_Background/Disabled_Mask.visible = build_road_button_state
	
	# Settlement
	var build_settlement_button_state = false if CLIENT.resources["Brick"] >= 1 and CLIENT.resources["Tree"] >= 1 and CLIENT.resources["Wheat"] >= 1 and CLIENT.resources["Sheep"] >= 1 and len(CLIENT.settlements) <= 5 else true
	$UILayer/Build_Settlement_Btn_Background/Build_Settlement_Button.disabled = build_settlement_button_state
	$UILayer/Build_Settlement_Btn_Background/Disabled_Mask.visible = build_settlement_button_state
	
	# City
	var build_city_button_state = false if CLIENT.resources["Wheat"] >= 2 and CLIENT.resources["Stone"] >= 3 and len(CLIENT.cities) <= 4 else true
	$UILayer/Build_City_Btn_Background/Build_City_Button.disabled = build_city_button_state
	$UILayer/Build_City_Btn_Background/Disabled_Mask.visible = build_city_button_state
	
	# Development Card
	var buy_dev_card_button_state = false if CLIENT.resources["Wheat"] >= 1 and CLIENT.resources["Stone"] >= 1 and CLIENT.resources["Sheep"] >= 1 else true
	$UILayer/Buy_Development_Card_Background/Buy_Development_Card_Button.disabled = buy_dev_card_button_state
	$UILayer/Buy_Development_Card_Background/Disabled_Mask.visible = buy_dev_card_button_state
	
	# Bank Trade
	var bank_trade_button_state = false if CLIENT.resources["Brick"] >= 4 or CLIENT.resources["Tree"] >= 4 or CLIENT.resources["Sheep"] >= 4 or CLIENT.resources["Wheat"] >= 4 or CLIENT.resources["Stone"] >= 4 or ui_check_client_harbors_for_bank_trade_btn() else true
	$UILayer/Bank_Trade_Btn_Background/Bank_Trade_Button.disabled = bank_trade_button_state
	$UILayer/Bank_Trade_Btn_Background/Disabled_Mask.visible = bank_trade_button_state
	
	$UILayer/Player_Trade_Btn_Background/Player_Trade_Button.disabled = false
	$UILayer/Player_Trade_Btn_Background/Disabled_Mask.visible = false
	
	$UILayer/End_Turn_Btn_Background/End_Turn_Button.disabled = false 
	$UILayer/End_Turn_Btn_Background/Disabled_Mask.visible = false
	
func ui_check_client_harbors_for_bank_trade_btn() -> bool:
	# Returns true if the client has a harbor and the correct resources to match that harbor
	
	if len(CLIENT.harbors) == 0:
		return false
	if "3:1" in CLIENT.harbors and (CLIENT.resources["Wheat"] >= 3 or CLIENT.resources["Tree"] >= 3 or CLIENT.resources["Sheep"] >= 3 or CLIENT.resources["Stone"] >= 3 or CLIENT.resources["Brick"] >= 3):
		return true
	if "Sheep" in CLIENT.harbors and CLIENT.resources["Sheep"] >= 2:
		return true
	if "Tree" in CLIENT.harbors and CLIENT.resources["Tree"] >= 2:
		return true
	if "Brick" in CLIENT.harbors and CLIENT.resources["Brick"] >= 2:
		return true
	if "Wheat" in CLIENT.harbors and CLIENT.resources["Wheat"] >= 2:
		return true
	if "Stone" in CLIENT.harbors and CLIENT.resources["Stone"] >= 2:
		return true
	
	return false

func ui_add_resource_to_supply(resource):
	var RESOURCE_TO_ID_MAPPING = {
		"Tree": 1,
		"Sheep": 2,
		"Brick": 3,
		"Wheat": 4,
		"Stone": 5
	}
	
	if resource in RESOURCE_TO_ID_MAPPING:
		if resource == "Tree":
			if NUM_SUPPLY_TREE > 19:
				print("error adding resource to supply (greater than 19 in supply): ", resource)
				return false
			NUM_SUPPLY_TREE += 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_TREE
		elif resource == "Sheep":
			if NUM_SUPPLY_SHEEP > 19:
				print("error adding resource to supply (greater than 19 in supply): ", resource)
				return false
			NUM_SUPPLY_SHEEP += 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_SHEEP
		elif resource == "Brick":
			if NUM_SUPPLY_BRICK > 19:
				print("error adding resource to supply (greater than 19 in supply): ", resource)
				return false
			NUM_SUPPLY_BRICK += 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_BRICK
		elif resource == "Wheat":
			if NUM_SUPPLY_WHEAT > 19:
				print("error adding resource to supply (greater than 19 in supply): ", resource)
				return false
			NUM_SUPPLY_WHEAT += 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_WHEAT
		elif resource == "Stone":
			if NUM_SUPPLY_STONE > 19:
				print("error adding resource to supply (greater than 19 in supply): ", resource)
				return false
			NUM_SUPPLY_STONE += 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_STONE
	else:
		print("error adding resource to supply: ", resource)

func ui_remove_resource_from_supply(resource):
	var RESOURCE_TO_ID_MAPPING = {
		"Tree": 1,
		"Sheep": 2,
		"Brick": 3,
		"Wheat": 4,
		"Stone": 5
	}
	
	if resource == "Development_Card":
		get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_DEV_CARD
		return true
	
	var resource_id = RESOURCE_TO_ID_MAPPING[resource]

	if resource in RESOURCE_TO_ID_MAPPING:
		if resource == "Tree":
			if NUM_SUPPLY_TREE == 0:
				print("No more Trees left!")
				return false
			NUM_SUPPLY_TREE -= 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_TREE
		elif resource == "Sheep":
			if NUM_SUPPLY_SHEEP == 0:
				print("No more Sheeps left!")
				return false
			NUM_SUPPLY_SHEEP -= 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_SHEEP
		elif resource == "Brick":
			if NUM_SUPPLY_BRICK == 0:
				print("No more Bricks left!")
				return false
			NUM_SUPPLY_BRICK -= 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_BRICK
		elif resource == "Wheat":
			if NUM_SUPPLY_WHEAT == 0:
				print("No more Wheats left!")
				return false
			NUM_SUPPLY_WHEAT -= 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_WHEAT
		elif resource == "Stone":
			if NUM_SUPPLY_STONE == 0:
				print("No more Stones left!")
				return false
			NUM_SUPPLY_STONE -= 1
			get_node("UILayer/Supply/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % NUM_SUPPLY_STONE
		return true # If succesfully able to get this resource from the supply (it isn't empty)
	else:
		print("error removing resource from supply: ", resource)
	
func ui_update_vp(player) -> void:
	get_node("UILayer/Player%sBackground/VP" % player.id).text = "[font_size=18][center]Victory Points: %s" % player.vp

func ui_update_knights_played(player) -> void:
	get_node("UILayer/Player%sBackground/Knights_Played" % player.id).text = "[font_size=18][center]Knights: %s" % player.knights_played

func ui_update_resources(player) -> void:
	get_node("UILayer/Player%sBackground/Resource_Num" % player.id).text = "[font_size=18][center]Resources: %s" % player.total_resources

func ui_update_dev_cards(player) -> void:
	get_node("UILayer/Player%sBackground/Dev_Card_Num" % player.id).text = "[font_size=18][center]Dev Cards: %s" % player.total_dev_cards

func bot_decision_loop(player):
	# Figure out which bot this is, based on global_turn_num

	# If resource met and no viable settlement/city placements, then build road
	while true:
		
		if player.dev_card_played_this_turn == false:
			if player.dev_cards["Invention_DevCard"] > 0:
				chat_log.append_text(player._name + " used invention dev card\n")
				await bot_use_invention_dev_card(player)
				player.dev_cards["Invention_DevCard"] -= 1
				continue
			
			if player.dev_cards["Knight_DevCard"] > 0:
				chat_log.append_text(player._name + " used knight dev card\n")
				await bot_use_knight_dev_card(player)
				player.dev_cards["Knight_DevCard"] -= 1
				continue
			
			if player.dev_cards["Monopoly_DevCard"] > 0:
				chat_log.append_text(player._name + " used monopoly dev card\n")
				await bot_use_monopoly_dev_card(player)
				player.dev_cards["Monopoly_DevCard"] -= 1
				continue
				
			if player.dev_cards["Road_DevCard"] > 0:
				chat_log.append_text(player._name + " used road dev card\n")
				await bot_use_road_dev_card(player)
				player.dev_cards["Road_DevCard"] -= 1
				continue
		
		# City
		if player.resources["Wheat"] >= 2 and player.resources["Stone"] >= 3 and len(player.cities) <= 4:
			if bot_build_city(player):
				continue
			
		# Settlement
		if player.resources["Brick"] >= 1 and player.resources["Tree"] >= 1 and player.resources["Wheat"] >= 1 and player.resources["Sheep"] >= 1 and len(player.settlements) <= 5:
			if bot_build_settlement(player):
				continue
			
		# Road
		if player.resources["Tree"] >= 1 and player.resources["Brick"] >= 1 and len(player.roads) <= 15:
			if bot_build_road(player, false):
				continue
			
		# Development Card
		if player.resources["Wheat"] >= 1 and player.resources["Stone"] >= 1 and player.resources["Sheep"] >= 1:
			if bot_buy_dev_card(player):
				player.dev_card_played_this_turn = true
				continue
			
		# Bank Trade
		if player.resources["Brick"] >= 4 or player.resources["Tree"] >= 4 or player.resources["Sheep"] >= 4 or player.resources["Wheat"] >= 4 or player.resources["Stone"] >= 4:
			break
			
		# Player Trade
			
		else:
			break

		
	# else, prioritize building a city then settlement
		
	# use development cards if needed
	# go for longest road if close

func bot_build_city(player):
	#print(player._name, " attempting to build city.")
	var ui_element_for_selected_settlement = null
	if player._name == "Bot 1":
		ui_element_for_selected_settlement = $MapLayer/Bot1_City.duplicate()
	if player._name == "Bot 2":
		ui_element_for_selected_settlement = $MapLayer/Bot2_City.duplicate()
	if player._name == "Bot 3":
		ui_element_for_selected_settlement = $MapLayer/Bot3_City.duplicate()
	
	var rand_city_pos
	if (len(player.settlements) > 0):
		rand_city_pos = player.settlements.pick_random()
	else:
		#print("no settlements available to turn into cities for player: ", player._name)
		return false
	
	# remove the settlement UI texture
	var i = 2
	for n in get_node("MapLayer").get_children():
		if n.get_class() == "TextureRect":
			if n.position == (rand_city_pos + Vector2(-15, -15) + Vector2(-12, -9)):
				n.queue_free()
				
	player.settlements.remove_at(player.settlements.find(rand_city_pos))
	
	player.cities.append(rand_city_pos)
	player.vp += 1
	ui_update_vp(player)
	
	
	# Place the City UI element
	var offset_position = Vector2(-15, -15) + Vector2(-12, -9)
	$MapLayer.add_child(ui_element_for_selected_settlement)
	ui_element_for_selected_settlement.show()
	ui_element_for_selected_settlement.position = rand_city_pos + offset_position
	
	player.resources["Stone"] -= 1
	player.total_resources -= 1
	ui_add_resource_to_supply("Stone")
	player.resources["Stone"] -= 1
	player.total_resources -= 1
	ui_add_resource_to_supply("Stone")
	player.resources["Stone"] -= 1
	player.total_resources -= 1
	ui_add_resource_to_supply("Stone")
	player.resources["Wheat"] -= 1
	player.total_resources -= 1
	ui_add_resource_to_supply("Wheat")
	player.resources["Wheat"] -= 1
	player.total_resources -= 1
	ui_add_resource_to_supply("Wheat")
	
	ui_update_resources(player)
	
	check_win()
	
	return true
	emit_signal("selection_finished")
	
func bot_build_settlement(player):
	#print(player._name, " attempting to build settlement.")
	var ui_element_for_selected_settlement = null
	if player._name == "Bot 1":
		ui_element_for_selected_settlement = $MapLayer/Bot1_Settlement.duplicate()
	if player._name == "Bot 2":
		ui_element_for_selected_settlement = $MapLayer/Bot2_Settlement.duplicate()
	if player._name == "Bot 3":
		ui_element_for_selected_settlement = $MapLayer/Bot3_Settlement.duplicate()
		
	var possible_settlement_placements = []
	for i in range(len(ELIGIBLE_SETTLEMENT_VERTICES)):
		var curr_pos = ELIGIBLE_SETTLEMENT_VERTICES[i]
		for j in range(len(player.roads)):
			var distance = get_distance(curr_pos, player.roads[j])
			if distance > 20 and distance < 50:
				possible_settlement_placements.append(ELIGIBLE_SETTLEMENT_VERTICES[i])
	
	if len(possible_settlement_placements) == 0:
		return false
	
	var rand_settlement_pos = possible_settlement_placements.pick_random()
	
	var offset_position = Vector2(-15, -15) + Vector2(-12, -9)
	$MapLayer.add_child(ui_element_for_selected_settlement)
	ui_element_for_selected_settlement.show()
	ui_element_for_selected_settlement.position = rand_settlement_pos + offset_position
	
	# See if settlement is on harbor, if so, add what type it is to the player
	for i in range(len(local_harbor_positions)):
		if get_distance(local_harbor_positions[i], rand_settlement_pos) < 60:
			var source_id = harbor_map_layer.get_cell_source_id(global_harbor_positions[i])
			if source_id in [0, 1, 2, 3]:
				player.harbors.append("3:1")
				break
			elif source_id == 4:
				player.harbors.append("Brick")
				break
			elif source_id == 5:
				player.harbors.append("Sheep")
				break
			elif source_id == 6:
				player.harbors.append("Stone")
				break
			elif source_id == 7:
				player.harbors.append("Wheat")
				break
			elif source_id == 8:
				player.harbors.append("Tree")
				break
	#print(player._name, " harbors: ", player.harbors)
	
	# Add settlement to bot
	player.settlements.append(rand_settlement_pos)
	
	# Add settlement (position) to player, save selections, will need after placing road to remove
	player.last_vertex_selected = rand_settlement_pos
	player.last_node_selected = ui_element_for_selected_settlement
	player.vp += 1
	ui_update_vp(player)
	
	# Removes vertex itself and surrounding vertices due to distance rule
	var vertices_to_remove = []
	vertices_to_remove.append(rand_settlement_pos)
	for i in range(len(ELIGIBLE_SETTLEMENT_VERTICES)-1):
		var distance = sqrt(((rand_settlement_pos.x - ELIGIBLE_SETTLEMENT_VERTICES[i].x)**2) + ((rand_settlement_pos.y - ELIGIBLE_SETTLEMENT_VERTICES[i].y)**2))
		if distance < 90: # These are the closest vertices
				vertices_to_remove.append(ELIGIBLE_SETTLEMENT_VERTICES[i])
	for i in range(len(vertices_to_remove)):
		if vertices_to_remove[i] in ELIGIBLE_SETTLEMENT_VERTICES:
			ELIGIBLE_SETTLEMENT_VERTICES.remove_at(ELIGIBLE_SETTLEMENT_VERTICES.find(vertices_to_remove[i]))
	
	player.resources["Tree"] -= 1
	player.total_resources -= 1
	player.resources["Brick"] -= 1
	player.total_resources -= 1
	player.resources["Wheat"] -= 1
	player.total_resources -= 1
	player.resources["Sheep"] -= 1
	player.total_resources -= 1
	
	ui_add_resource_to_supply("Tree")
	ui_add_resource_to_supply("Brick")
	ui_add_resource_to_supply("Wheat")
	ui_add_resource_to_supply("Sheep")
	
	chat_log.append_text(player._name + "built settlement.\n")
	
	ui_update_resources(player)
	
	check_win()
	
	return true
	emit_signal("selection_finished")
	
func bot_build_road(player, devcard):
	chat_log.append_text(player._name + " built road.\n")
	var read_ALL_ROAD_MIDPOINTS = ALL_ROAD_MIDPOINTS.duplicate(true)
	
	var ui_element_for_road = null
	if player._name == "Bot 1":
		ui_element_for_road = $MapLayer/Bot1_Road.duplicate()
	if player._name == "Bot 2":
		ui_element_for_road = $MapLayer/Bot2_Road.duplicate()
	if player._name == "Bot 3":
		ui_element_for_road = $MapLayer/Bot3_Road.duplicate()
	
	# Can only build roads that connect to other player-owned roads
	# All possible positions for a player to place a road will be 
	
	var all_possible_road_placements = []
	for i in range(len(player.roads)):
		var curr_road_pos = player.roads[i]
		# Check curr road position against all possible positions
		for j in range(len(read_ALL_ROAD_MIDPOINTS)): # Find all road midpoints that could connect to the current road using dist formula
			var distance = sqrt(((curr_road_pos.x - read_ALL_ROAD_MIDPOINTS[j].x)**2) + ((curr_road_pos.y - read_ALL_ROAD_MIDPOINTS[j].y)**2))
			if distance > 45 and distance < 75:
				all_possible_road_placements.append(read_ALL_ROAD_MIDPOINTS[j])
	
	# Check that the possible placement vertices aren't owned by any player, if so, remove them
	var elements_to_remove = []
	for i in range(len(ALL_OWNED_ROADS)):
		for j in range(len(all_possible_road_placements)):
			var placement_account_for_offset = (all_possible_road_placements[j] + global_road_ui_btn_offset)
			if placement_account_for_offset in ALL_OWNED_ROADS[i]:
				elements_to_remove.append(all_possible_road_placements[j])
	for i in range(len(elements_to_remove)):
		if elements_to_remove[i] in all_possible_road_placements:
			all_possible_road_placements.remove_at(all_possible_road_placements.find(elements_to_remove[i]))
	
	# For now, bots choose a random road to build
	
	if len(all_possible_road_placements) == 0:
		return false
		
	var rand_road = all_possible_road_placements.pick_random()
	
	var road_ui_offset = global_road_ui_offset
	var rand_road_node_pos = rand_road + global_road_ui_btn_offset
	
	$MapLayer.add_child(ui_element_for_road)
	ui_element_for_road.show()
	ui_element_for_road.pivot_offset = Vector2(ui_element_for_road.size.x / 2, ui_element_for_road.size.y / 2)
	ui_element_for_road.position = rand_road_node_pos + road_ui_offset # Place road at midpoint then rotate
	
	player.roads.append(rand_road_node_pos)
	ALL_OWNED_ROADS[ALL_PLAYERS.find(player)] = player.roads
	
	print(player._name + "longest road: " + str(LongestRoadFinder.find_longest_road(player.roads)))
	
	# Use slope and arctan between two points to calculate how to rotate the UI element
	# To find the second point, find the closest settlement vertex to this road's midpoint
	var settlement_vertex = null
	var smallest_distance = 999999
	var closest_point = null
	for pos in global_vertices:
		var distance = sqrt(((pos.x - rand_road.x)**2) + ((pos.y - rand_road.y)**2))
		if distance < smallest_distance:
			smallest_distance = distance
			closest_point = pos
			
	var slope = ((rand_road.y - closest_point.y) / (rand_road.x - closest_point.x))
	var degrees = rad_to_deg(atan(slope))
	ui_element_for_road.rotation_degrees = degrees
	
	if degrees == 90 or degrees == -90:
		ui_element_for_road.position = Vector2(ui_element_for_road.position.x + 6.3, ui_element_for_road.position.y)
	
	
	if devcard == false:
		player.resources["Tree"] -= 1
		player.total_resources -= 1
		player.resources["Brick"] -= 1
		player.total_resources -= 1
		
		ui_add_resource_to_supply("Tree")
		ui_add_resource_to_supply("Brick")
		
		ui_update_resources(player)
	
	return true
	emit_signal("selection_finished")

func bot_buy_dev_card(player):
	
	var dev_card_name = DEVELOPMENT_CARDS.pop_at(0)
	
	player.total_dev_cards += 1
	ui_update_dev_cards(player)
	
	dev_card_name = dev_card_name + "_DevCard"
	
	chat_log.append_text(player._name + " bought a dev card.\n")
	
	player.dev_cards[dev_card_name] += 1
	
	if dev_card_name == "VP_DevCard":
		player.vp += 1
		check_win()
	
	player.resources["Stone"] -= 1
	player.total_resources -= 1
	ui_add_resource_to_supply("Stone")
	
	player.resources["Sheep"] -= 1
	player.total_resources -= 1
	ui_add_resource_to_supply("Sheep")
	
	player.resources["Wheat"] -= 1
	player.total_resources -= 1
	ui_add_resource_to_supply("Wheat")
	
	ui_remove_resource_from_supply("Development_Card")
	
	ui_update_resources(player)
	
	return true

func check_if_player_has_longest_road(player):
	# First person to reach longest road
	print(player._name + " longest road: ", player.longest_road)
	if global_player_with_longest_road == null and player.longest_road >= 5:
		global_player_with_longest_road = player
		global_player_with_longest_road.vp += 2
		chat_log.append_text(global_player_with_longest_road._name + " now has the longest road!\n")
		ui_update_vp(player)
	elif global_player_with_longest_road != null and player.longest_road > global_player_with_longest_road.longest_road:
		global_player_with_longest_road.vp -= 2
		global_player_with_longest_road = player
		global_player_with_longest_road.vp += 2
		chat_log.append_text(global_player_with_longest_road._name + " now has the longest road!\n")
		ui_update_vp(player)

func check_if_player_has_largest_army(player):
	# First person to reach largest army
	if global_player_with_largest_army == null and player.knights_played >= 3:
		global_player_with_largest_army = player
		global_player_with_largest_army.vp += 2
		chat_log.append_text(global_player_with_largest_army._name + " now has the largest army!\n")
	elif global_player_with_largest_army != null and player.knights_played > global_player_with_largest_army.knights_played:
		global_player_with_largest_army.vp -= 2
		global_player_with_largest_army = player
		global_player_with_largest_army.vp += 2
		chat_log.append_text(global_player_with_largest_army._name + " now has the largest army!\n")

func bot_use_knight_dev_card(player):
	# For now, just choose randomly
	
	player.knights_played += 1
	player.total_dev_cards -= 1
	ui_update_dev_cards(player)
	
	check_if_player_has_largest_army(player)
	
	ui_update_knights_played(player)
	
	var random_robber_pos
	while true:
		random_robber_pos = tile_positions_local.pick_random()
		if random_robber_pos == ROBBER_POSITION:
			continue
		else:
			break
	$MapLayer/Robber.position = random_robber_pos + Vector2(-32, -32)
	ROBBER_POSITION = random_robber_pos
	
	await bot_robber_steal(player, random_robber_pos)
	
	player.dev_card_played_this_turn = true

func bot_use_invention_dev_card(player):
	# Pick two random resources from the supply
	
	for i in range(2):
		if NUM_SUPPLY_BRICK > 0:
			player.resources["Brick"] += 1
			player.total_resources += 1
			ui_remove_resource_from_supply("Brick")
			continue
		elif NUM_SUPPLY_SHEEP > 0:
			player.resources["Sheep"] += 1
			player.total_resources += 1
			ui_remove_resource_from_supply("Sheep")
			continue
		elif NUM_SUPPLY_STONE > 0:
			player.resources["Stone"] += 1
			player.total_resources += 1
			ui_remove_resource_from_supply("Stone")
			continue
		elif NUM_SUPPLY_WHEAT > 0:
			player.resources["Wheat"] += 1
			player.total_resources += 1
			ui_remove_resource_from_supply("Wheat")
			continue
		elif NUM_SUPPLY_TREE > 0:
			player.resources["Tree"] += 1
			player.total_resources += 1
			ui_remove_resource_from_supply("Tree")
			continue
			
	player.dev_card_played_this_turn = true
	
	player.total_dev_cards -= 1
	ui_update_dev_cards(player)
	
	ui_update_resources(player)

func bot_use_monopoly_dev_card(player):
	var resources = ["Brick", "Tree", "Sheep", "Stone", "Wheat"]
	var random_resource = resources.pick_random()
	
	# Transfer all of resource_name to the passed player from all other players
	for p in ALL_PLAYERS:
		if p == player:
			continue
		else:
			var num_of_resource = p.resources[random_resource]
			p.resources[random_resource] = 0
			p.total_resources -= num_of_resource
			
			player.resources[random_resource] += num_of_resource
			player.total_resources += num_of_resource
	
	player.dev_card_played_this_turn = true
	
	player.total_dev_cards -= 1
	ui_update_dev_cards(player)
	
	ui_update_resources(player)

func bot_use_road_dev_card(player):
	
	await bot_build_road(player, true)
	await bot_build_road(player, true)
	
	player.total_dev_cards -= 1
	ui_update_dev_cards(player)
	
	player.dev_card_played_this_turn = true

func ui_remove_from_resource_bar_dev_card(dev_card_name):
	
	var UI_OFFSET_MAPPING = {
		1: 851,
		2: 791,
		3: 731,
		4: 671,
		5: 611
	}
	
	#print("player used dev card: ", dev_card_name)
	var num_of_dev_card = CLIENT.dev_cards[dev_card_name]

	if num_of_dev_card == 0: # Remove resource from bar completely
		#var resource_offset = null
		var index_of_element_to_remove = null
		get_node("UILayer/Resource Bar/%s/" % dev_card_name).queue_free()
		# Shift over all other elements if necessary
		for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS)):
			if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS[i] == dev_card_name:
				#resource_offset = UI_OFFSET_MAPPING[CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS[i]]
				index_of_element_to_remove = i
		# Reconstruct bar positions array, recalculate positions
		CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS = CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS.slice(0, index_of_element_to_remove) + CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS.slice(index_of_element_to_remove + 1, len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS)+1)
		CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS.append(null)
		
		#print(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)
		
		for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS)):
			if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS[i] == null:
				continue

			var curr_resource_node = get_node("UILayer/Resource Bar/%s/" % dev_card_name)
			var UI_offset = UI_OFFSET_MAPPING[i+1]
			curr_resource_node.position = Vector2(6.5 + UI_offset, 9.3)
			
	else: # Reduce number of resource in bar
		for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS)):
			if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS[i] == dev_card_name:
				get_node("UILayer/Resource Bar/%s/Amount" % dev_card_name).text = "[font_size=30][center][b]%s" % CLIENT.dev_cards[dev_card_name]
				return

func ui_add_to_resource_bar_dev_card(dev_card_name):
	var dev_card_node
	match dev_card_name:
		"Invention_DevCard":
			dev_card_node = get_node("UILayer/Invention_DevCard").duplicate(1)
		"Knight_DevCard":
			dev_card_node = get_node("UILayer/Knight_DevCard").duplicate(1)
		"Monopoly_DevCard":
			dev_card_node = get_node("UILayer/Monopoly_DevCard").duplicate(1)
		"Road_DevCard":
			dev_card_node = get_node("UILayer/Road_DevCard").duplicate(1)
		"VP_DevCard":
			dev_card_node = get_node("UILayer/VP_DevCard").duplicate(1)
		_:
			print("Dev Card not found!")
			return
	
	var UI_OFFSET_MAPPING = {
		1: 851,
		2: 791,
		3: 731,
		4: 671,
		5: 611
	}
	
	# Check to see if this resource is already on the resource bar first
	for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS)):
		if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS[i] == dev_card_name:
			get_node("UILayer/Resource Bar/%s/Amount" % dev_card_name).text = "[font_size=30][center][b]%s" % CLIENT.dev_cards[dev_card_name]
			return
			
	# If not, we need to add it to the bar
	for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS)):
		if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS[i] == null:
			CLIENT.PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS[i] = dev_card_name # This says "Tree" is in this position on the resource bar
			var copied_ui_resource = dev_card_node
			$"UILayer/Resource Bar".add_child(copied_ui_resource, true)
			var UI_offset = UI_OFFSET_MAPPING[i+1]
			copied_ui_resource.position = Vector2(-6.5 + UI_offset, 9.3)
			copied_ui_resource.z_index = 1
			copied_ui_resource.get_children()[0].text = "[font_size=30][center][b]%s" % CLIENT.dev_cards[dev_card_name]
			copied_ui_resource.show()
			return

func _on_buy_development_card_button_pressed() -> void:
	#print("development card button pressed")
	
	var dev_card_name = DEVELOPMENT_CARDS.pop_at(0)
	
	CLIENT.total_dev_cards += 1
	ui_update_dev_cards(CLIENT)
	
	dev_card_name = dev_card_name + "_DevCard"
	
	print("client got dev card: ", dev_card_name)
	
	CLIENT.dev_cards[dev_card_name] += 1
	
	if dev_card_name == "VP_DevCard":
		CLIENT.vp += 1
		check_win()
	
	CLIENT.resources["Stone"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Stone")
	ui_add_resource_to_supply("Stone")
	
	CLIENT.resources["Sheep"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Sheep")
	ui_add_resource_to_supply("Sheep")
	
	CLIENT.resources["Wheat"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Wheat")
	ui_add_resource_to_supply("Wheat")
	
	activate_or_deactivate_ui_buttons()
	
	# Match name to UI element, place on resource bar
	ui_add_to_resource_bar_dev_card(dev_card_name)
	
	ui_remove_resource_from_supply("Development_Card")
	
	ui_update_resources(CLIENT)

func ui_hide_all_dev_card_btns():
	for node in get_node("UILayer/Resource Bar").get_children():
		if node.name.contains("DevCard"):
			if node.name == "VP_DevCard":
				continue
			else:
				node.get_children()[1].hide()

func _on_knight_dev_card_pressed() -> void:
	
	if CLIENT.dev_card_played_this_turn == false:
		
		CLIENT.knights_played += 1
		ui_update_knights_played(CLIENT)
		
		check_if_player_has_largest_army(CLIENT)
		
		ui_hide_all_dev_card_btns()
		
		var dev_card_name = "Knight_DevCard"
		
		CLIENT.dev_cards[dev_card_name] -= 1
		
		ui_remove_from_resource_bar_dev_card(dev_card_name)
		
		$UILayer/Supply/Knight_DevCard_Text.show()
		
		await ui_robber_choose_new_location_client()
		
		$UILayer/Supply/Knight_DevCard_Text.hide()
		
		CLIENT.dev_card_played_this_turn = true
		
		CLIENT.total_dev_cards -= 1
		ui_update_dev_cards(CLIENT)
		
	else:
		return

func _on_monopoly_dev_card_pressed() -> void:
	
	if CLIENT.dev_card_played_this_turn == false:
		ui_hide_all_dev_card_btns()
		var dev_card_name = "Monopoly_DevCard"
		
		CLIENT.dev_cards[dev_card_name] -= 1
		
		$UILayer/Supply/Monopoly_DevCard_Text.show()
		
		var UI_offsets = {
			1: 4,
			2: 61,
			3: 119,
			4: 178,
			5: 237
		}
		
		var supply_resources_in_order = {
			1: "Brick",
			2: "Sheep",
			3: "Stone",
			4: "Tree",
			5: "Wheat"
		}
		
		for i in range(5):
			var copied_ui_resource = $"UILayer/Supply/Select_Resource_From_Supply_Btn".duplicate()
			$"UILayer/Supply".add_child(copied_ui_resource, true)
			copied_ui_resource.position = Vector2(UI_offsets[i+1], 27)
			copied_ui_resource.z_index = 1
			copied_ui_resource.show()
			
			copied_ui_resource.pressed.connect(monopoly_dev_card_choose_resource.bind(supply_resources_in_order[i+1]))
		
		CLIENT.total_dev_cards -= 1
		ui_update_dev_cards(CLIENT)
		
		await done_picking
		
		# Remove the buttons
		# Cleanup / Remove UI elements
		var i = 2
		for node in get_node("UILayer/Supply").get_children():
			if node.name == ("Select_Resource_From_Supply_Btn%s" % str(i)):
				i+=1
				$"UILayer/Supply".remove_child(node)
				node.queue_free()
		
		$UILayer/Supply/Monopoly_DevCard_Text.hide()
		ui_remove_from_resource_bar_dev_card(dev_card_name)
		
		CLIENT.dev_card_played_this_turn = true
		
	else:
		return
	
func monopoly_dev_card_choose_resource(resource_name):
	# Transfer all of resource_name to the CLIENT from all other players
	
	if CLIENT.dev_card_played_this_turn == false:
		for p in ALL_PLAYERS:
			if p == CLIENT:
				continue
			else:
				var num_of_resource = p.resources[resource_name]
				p.resources[resource_name] = 0
				p.total_resources -= num_of_resource
				
				CLIENT.resources[resource_name] += num_of_resource
				CLIENT.total_resources += num_of_resource
				
				for i in range(num_of_resource):
					ui_add_to_resource_bar(resource_name)
			ui_update_resources(p)
	
		CLIENT.total_dev_cards -= 1
		ui_update_dev_cards(CLIENT)
	
		emit_signal("done_picking")
	else:
		return

func _on_road_dev_card_pressed() -> void:
	
	if CLIENT.dev_card_played_this_turn == false:
		ui_hide_all_dev_card_btns()
		var dev_card_name = "Road_DevCard"
		
		CLIENT.dev_cards[dev_card_name] -= 1
		
		ui_remove_from_resource_bar_dev_card(dev_card_name)
		
		$UILayer/Supply/Road_DevCard_Text.show()
		
		_on_build_road_button_pressed(true)
		await done_picking
		_on_build_road_button_pressed(true)
		await done_picking
	
		$UILayer/Supply/Road_DevCard_Text.hide()
		
		CLIENT.dev_card_played_this_turn = true
		
		CLIENT.total_dev_cards -= 1
		ui_update_dev_cards(CLIENT)
		
	else:
		return

func _on_invention_dev_card_pressed() -> void:
	
	if CLIENT.dev_card_played_this_turn == false:
		ui_hide_all_dev_card_btns()
		# Take any two resources from the supply -- have user just click on the supply?
		
		var dev_card_name = "Invention_DevCard"
		
		CLIENT.dev_cards[dev_card_name] -= 1
		
		$UILayer/Supply/Invention_DevCard_Text.show()
		
		var UI_offsets = {
			1: 4,
			2: 61,
			3: 119,
			4: 178,
			5: 237
		}
		
		var supply_resources_in_order = {
			1: "Brick",
			2: "Sheep",
			3: "Stone",
			4: "Tree",
			5: "Wheat"
		}
		
		for i in range(5):
			var copied_ui_resource = $"UILayer/Supply/Select_Resource_From_Supply_Btn".duplicate()
			$"UILayer/Supply".add_child(copied_ui_resource, true)
			copied_ui_resource.position = Vector2(UI_offsets[i+1], 27)
			copied_ui_resource.z_index = 1
			copied_ui_resource.show()
			
			copied_ui_resource.pressed.connect(invention_dev_card_resource_from_supply_chosen.bind(supply_resources_in_order[i+1]))
		
		# The player gets two resources of any type of their choice
		await done_picking
		await done_picking
		
		# Remove the buttons
		# Cleanup / Remove UI elements
		var i = 2
		for node in get_node("UILayer/Supply").get_children():
			if node.name == ("Select_Resource_From_Supply_Btn%s" % str(i)):
				i+=1
				$"UILayer/Supply".remove_child(node)
				node.queue_free()
		
		$UILayer/Supply/Invention_DevCard_Text.hide()
		ui_remove_from_resource_bar_dev_card("Invention_DevCard")
		
		CLIENT.dev_card_played_this_turn = true
		
		CLIENT.total_dev_cards -= 1
		ui_update_dev_cards(CLIENT)
		
	else:
		return
	
func invention_dev_card_resource_from_supply_chosen(resource_name):
	CLIENT.resources[resource_name] += 1
	CLIENT.total_resources += 1
	
	ui_add_to_resource_bar(resource_name)
	ui_remove_resource_from_supply(resource_name)
	
	ui_update_resources(CLIENT)
	
	emit_signal("done_picking")

# Should only be allowed to be pressed if correct resources have been met, see activate_or_deactive_ui_buttons()
func _on_build_road_button_pressed(devcard=false) -> void:
	#print("Build road button pressed.")
	
	var read_ALL_ROAD_MIDPOINTS = ALL_ROAD_MIDPOINTS.duplicate(true)
	
	# Can only build roads that connect to other player-owned roads
	# All possible positions for a player to place a road will be 
	var all_possible_road_placements = []
	for i in range(len(CLIENT.roads)):
		var curr_road_pos = CLIENT.roads[i]
		# Check curr road position against all possible positions
		for j in range(len(read_ALL_ROAD_MIDPOINTS)): # Find all road midpoints that could connect to the current road using dist formula
			var distance = sqrt(((curr_road_pos.x - read_ALL_ROAD_MIDPOINTS[j].x)**2) + ((curr_road_pos.y - read_ALL_ROAD_MIDPOINTS[j].y)**2))
			if distance > 45 and distance < 75:
				all_possible_road_placements.append(read_ALL_ROAD_MIDPOINTS[j])
	
	# Check that the possible placement vertices aren't owned by any player, if so, remove them
	var elements_to_remove = []
	for i in range(len(ALL_OWNED_ROADS)):
		for j in range(len(all_possible_road_placements)):
			var placement_account_for_offset = (all_possible_road_placements[j] + global_road_ui_btn_offset)
			if placement_account_for_offset in ALL_OWNED_ROADS[i]:
				elements_to_remove.append(all_possible_road_placements[j])
	for i in range(len(elements_to_remove)):
		if elements_to_remove[i] in all_possible_road_placements:
			all_possible_road_placements.remove_at(all_possible_road_placements.find(elements_to_remove[i]))
	
	# Display the UI elements
	for vertex in all_possible_road_placements:
		var road_ui_btn_offset = global_road_ui_btn_offset
		
		var curr_UI_element = $MapLayer/Possible_Placement_Road.duplicate()
		$MapLayer.add_child(curr_UI_element, true)
		curr_UI_element.show()
		curr_UI_element.position = vertex + road_ui_btn_offset

		curr_UI_element.pressed.connect(road_placement_pressed.bind(curr_UI_element, vertex))
	
	await selection_finished
	
	# Remove UI elements
	var i = 2
	for node in get_node("MapLayer").get_children():
		if node.name == ("Possible_Placement_Road%s" % str(i)):
			i+=1
			$MapLayer.remove_child(node)
			node.queue_free()
			
	# Remove resources from player and from resource bar
	if devcard == false:
		CLIENT.resources["Tree"] -= 1
		CLIENT.total_resources -= 1
		ui_remove_from_resource_bar("Tree")
		ui_add_resource_to_supply("Tree")
		
		CLIENT.resources["Brick"] -= 1
		CLIENT.total_resources -= 1
		ui_remove_from_resource_bar("Brick")
		ui_add_resource_to_supply("Brick")
		
		ui_update_resources(CLIENT)
	
	activate_or_deactivate_ui_buttons()
	
	emit_signal("done_picking")
	
func road_placement_pressed(midpoint_btn_node, road_midpoint):
	# When the midpoint button is pressed -- show a road between the two points and add that point as a road to this player
	var road_ui_offset = global_road_ui_offset
	
	var ui_element_for_road = $MapLayer/Player1_Road.duplicate()
	$MapLayer.add_child(ui_element_for_road)
	ui_element_for_road.show()
	ui_element_for_road.pivot_offset = Vector2(ui_element_for_road.size.x / 2, ui_element_for_road.size.y / 2)
	ui_element_for_road.position = midpoint_btn_node.position + road_ui_offset # Place road at midpoint then rotate
	
	CLIENT.roads.append(midpoint_btn_node.position)
	ALL_OWNED_ROADS[CLIENT_INDEX] = CLIENT.roads
	
	print(CLIENT._name + "longest road: " + str(LongestRoadFinder.find_longest_road(CLIENT.roads)))
	
	# Use slope and arctan between two points to calculate how to rotate the UI element
	# To find the second point, find the closest settlement vertex to this road's midpoint
	var settlement_vertex = null
	var smallest_distance = 999999
	var closest_point = null
	for pos in global_vertices:
		var distance = sqrt(((pos.x - road_midpoint.x)**2) + ((pos.y - road_midpoint.y)**2))
		if distance < smallest_distance:
			smallest_distance = distance
			closest_point = pos
			
	var slope = ((road_midpoint.y - closest_point.y) / (road_midpoint.x - closest_point.x))
	var degrees = rad_to_deg(atan(slope))
	ui_element_for_road.rotation_degrees = degrees
	
	if degrees == 90 or degrees == -90:
		ui_element_for_road.position = Vector2(ui_element_for_road.position.x + 6.3, ui_element_for_road.position.y)
	
	emit_signal("selection_finished")

# Should only be allowed to be pressed if correct resources have been met, see activate_or_deactive_ui_buttons()
func _on_build_settlement_button_pressed() -> void:
	#print("build settlement button pressed")
	
	var possible_settlement_placements = []
	for i in range(len(ELIGIBLE_SETTLEMENT_VERTICES)):
		var curr_pos = ELIGIBLE_SETTLEMENT_VERTICES[i]
		for j in range(len(CLIENT.roads)):
			var distance = get_distance(curr_pos, CLIENT.roads[j])
			if distance > 20 and distance < 50:
				possible_settlement_placements.append(ELIGIBLE_SETTLEMENT_VERTICES[i])
	
	# Display the UI elements
	for vertex in possible_settlement_placements:
		var settlement_placement_offset = Vector2(-12, -9)
		
		var curr_UI_element = $MapLayer/Possible_Placement_Settlement.duplicate()
		$MapLayer.add_child(curr_UI_element, true)
		curr_UI_element.show()
		curr_UI_element.position = vertex + settlement_placement_offset

		curr_UI_element.pressed.connect(settlement_button_pressed.bind(curr_UI_element, vertex))
	
	await selection_finished
	
	# Remove resources from player and from resource bar
	CLIENT.resources["Tree"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Tree")
	ui_add_resource_to_supply("Tree")
	
	CLIENT.resources["Brick"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Brick")
	ui_add_resource_to_supply("Brick")
	
	CLIENT.resources["Wheat"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Wheat")
	ui_add_resource_to_supply("Wheat")
	
	CLIENT.resources["Sheep"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Sheep")
	ui_add_resource_to_supply("Sheep")
	
	ui_update_resources(CLIENT)
	
	activate_or_deactivate_ui_buttons()

func settlement_button_pressed(node, vertex):
	# Add settlement as UI element
	var offset_position = Vector2(-15, -15)
	#var selected_node = get_node("MapLayer/%s" % id)
	var selected_node_position = node.position
	var ui_element_for_selected_settlement = $MapLayer/Player1_Settlement.duplicate()
	$MapLayer.add_child(ui_element_for_selected_settlement)
	ui_element_for_selected_settlement.show()
	ui_element_for_selected_settlement.position = selected_node_position + offset_position
	
	# See if settlement is on harbor, if so, add what type it is to the player
	for i in range(len(local_harbor_positions)):
		if get_distance(local_harbor_positions[i], vertex) < 60:
			var source_id = harbor_map_layer.get_cell_source_id(global_harbor_positions[i])
			if source_id in [0, 1, 2, 3]:
				CLIENT.harbors.append("3:1")
				break
			elif source_id == 4:
				CLIENT.harbors.append("Brick")
				break
			elif source_id == 5:
				CLIENT.harbors.append("Sheep")
				break
			elif source_id == 6:
				CLIENT.harbors.append("Stone")
				break
			elif source_id == 7:
				CLIENT.harbors.append("Wheat")
				break
			elif source_id == 8:
				CLIENT.harbors.append("Tree")
				break
	#print(CLIENT._name, " harbors: ", CLIENT.harbors)
	
	# Add settlement (position) to player, save selections, will need after placing road to remove
	CLIENT.settlements.append(vertex)
	CLIENT.last_vertex_selected = vertex
	CLIENT.last_node_selected = node
	CLIENT.vp += 1
	ui_update_vp(CLIENT)
	
	# Removes vertex itself and surrounding vertices due to distance rule
	var vertices_to_remove = []
	vertices_to_remove.append(vertex)
	for i in range(len(ELIGIBLE_SETTLEMENT_VERTICES)-1):
		var distance = sqrt(((vertex.x - ELIGIBLE_SETTLEMENT_VERTICES[i].x)**2) + ((vertex.y - ELIGIBLE_SETTLEMENT_VERTICES[i].y)**2))
		if distance < 90: # These are the closest vertices
				vertices_to_remove.append(ELIGIBLE_SETTLEMENT_VERTICES[i])
	for i in range(len(vertices_to_remove)):
		if vertices_to_remove[i] in ELIGIBLE_SETTLEMENT_VERTICES:
			ELIGIBLE_SETTLEMENT_VERTICES.remove_at(ELIGIBLE_SETTLEMENT_VERTICES.find(vertices_to_remove[i]))
	
	# Remove UI elements
	var i = 2
	for n in get_node("MapLayer").get_children():
		if n.name == "Possible_Placement_Settlement%s" % i:
			i+=1
			n.queue_free()
	
	check_win()
	
	emit_signal("selection_finished")

func _on_build_city_button_pressed() -> void:
	# Show the possible places a player could build a city
	var settlement_placement_offset = Vector2(-12, -9)
	for i in range(len(CLIENT.settlements)):
		var curr_UI_element = $MapLayer/Possible_Placement_Settlement.duplicate()
		$MapLayer.add_child(curr_UI_element, true)
		curr_UI_element.show()
		curr_UI_element.position = CLIENT.settlements[i] + settlement_placement_offset
		curr_UI_element.pressed.connect(city_button_pressed.bind(curr_UI_element, CLIENT.settlements[i]))
	
	await selection_finished
	
	# Remove resources from player and from resource bar
	CLIENT.resources["Stone"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Stone")
	ui_add_resource_to_supply("Stone")
	
	CLIENT.resources["Stone"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Stone")
	ui_add_resource_to_supply("Stone")
	
	CLIENT.resources["Stone"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Stone")
	ui_add_resource_to_supply("Stone")
	
	CLIENT.resources["Wheat"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Wheat")
	ui_add_resource_to_supply("Wheat")
	
	CLIENT.resources["Wheat"] -= 1
	CLIENT.total_resources -= 1
	ui_remove_from_resource_bar("Wheat")
	ui_add_resource_to_supply("Wheat")
	
	ui_update_resources(CLIENT)
	
	activate_or_deactivate_ui_buttons()

func city_button_pressed(node, vertex):
	# Remove the settlement that is here, both in the UI and from the player's data
	CLIENT.settlements.remove_at(CLIENT.settlements.find(vertex))
	var i = 2
	for n in get_node("MapLayer").get_children():
		if n.get_class() == "TextureRect":
			if n.position == (vertex + Vector2(-15, -15) + Vector2(-12, -9)):
				n.queue_free()
	
	CLIENT.cities.append(vertex)
	CLIENT.vp += 1
	ui_update_vp(CLIENT)
	
	# Place the City UI element
	var offset_position = Vector2(-15, -15)
	var selected_node_position = node.position
	var ui_element_for_selected_settlement = $MapLayer/Player1_City.duplicate()
	$MapLayer.add_child(ui_element_for_selected_settlement)
	ui_element_for_selected_settlement.show()
	ui_element_for_selected_settlement.position = selected_node_position + offset_position
	
	# Remove other possible location's UI elements
	i = 2
	for n in get_node("MapLayer").get_children():
		if n.name == "Possible_Placement_Settlement%s" % i:
			i+=1
			n.queue_free()
			
	check_win()
	
	emit_signal("selection_finished")
	
func generate_resources_for_all_players(dice_result, tile_positions_local, tile_positions, map_data):
	
	# Maps the visual resource num to it's Atlas ID in the TileSet
	var RESOURCE_NUM_MAPPING = {
		1: 2,
		2: 3,
		3: 4,
		4: 5,
		5: 6,
		6: 8,
		7: 9,
		8: 10,
		9: 11,
		10: 12
	}
	
	var SOURCE_ID_TO_RESOURCE_MAPPING = {
		1: "Tree",
		2: "Sheep",
		3: "Brick",
		4: "Wheat",
		5: "Stone"
	}
	
	for p in ALL_PLAYERS:
		# Check each settlements adjacent tiles to see if they match the dice result
		# If real player
		if p.type == "Player":
			var resources = []
			for i in range(len(p.settlements)):
				for j in range(len(tile_positions_local)):
					if tile_positions_local[j] == ROBBER_POSITION:
						
						continue
					# Should be the three closest tiles, where pos is the center of the tile
					var distance = sqrt(((tile_positions_local[j].x - p.settlements[i].x)**2) + ((tile_positions_local[j].y - p.settlements[i].y)**2))
					if distance < 75:
						# Get the tiles atlas id and use the mapping
						var resource_num_source_id = resource_num_map_layer.get_cell_source_id(tile_positions[j])
						if resource_num_source_id == -1:
							continue
						if RESOURCE_NUM_MAPPING[resource_num_source_id] == dice_result:
							resources.append(map_data.get_cell_source_id(tile_positions[j]))
			# Do the same but for cities
			for i in range(len(p.cities)):
				for j in range(len(tile_positions_local)):
					if tile_positions_local[j] == ROBBER_POSITION:
						
						continue
					# Should be the three closest tiles, where pos is the center of the tile
					var distance = sqrt(((tile_positions_local[j].x - p.cities[i].x)**2) + ((tile_positions_local[j].y - p.cities[i].y)**2))
					if distance < 75:
						# Get the tiles atlas id and use the mapping
						var resource_num_source_id = resource_num_map_layer.get_cell_source_id(tile_positions[j])
						if resource_num_source_id == -1:
							continue
						if RESOURCE_NUM_MAPPING[resource_num_source_id] == dice_result:
							resources.append(map_data.get_cell_source_id(tile_positions[j]))
							resources.append(map_data.get_cell_source_id(tile_positions[j]))
							
			# Do a lookup to mapping dict and add to player's resource dict
			var UI_offset = global_ui_resource_offset
			for id in resources:
				if id == 6: # Skip desert tile
					continue
				var resource = SOURCE_ID_TO_RESOURCE_MAPPING[id]
				if ui_remove_resource_from_supply(resource) == true:
					p.resources[resource] += 1
					p.total_resources += 1
					ui_add_to_resource_bar(resource)
					
			ui_update_resources(p)
					
		elif p.type == "Bot":
			var resources = []
			for i in range(len(p.settlements)):
				for j in range(len(tile_positions_local)):
					if tile_positions_local[j] == ROBBER_POSITION:
						
						continue
					# Should be the three closest tiles, where pos is the center of the tile
					var distance = sqrt(((tile_positions_local[j].x - p.settlements[i].x)**2) + ((tile_positions_local[j].y - p.settlements[i].y)**2))
					if distance < 75:
						# Get the tiles atlas id and use the mapping
						var resource_num_source_id = resource_num_map_layer.get_cell_source_id(tile_positions[j])
						if resource_num_source_id == -1:
							continue
						if RESOURCE_NUM_MAPPING[resource_num_source_id] == dice_result:
							resources.append(map_data.get_cell_source_id(tile_positions[j]))
							
			for i in range(len(p.cities)):
				for j in range(len(tile_positions_local)):
					if tile_positions_local[j] == ROBBER_POSITION:
						
						continue
					# Should be the three closest tiles, where pos is the center of the tile
					var distance = sqrt(((tile_positions_local[j].x - p.cities[i].x)**2) + ((tile_positions_local[j].y - p.cities[i].y)**2))
					if distance < 75:
						# Get the tiles atlas id and use the mapping
						var resource_num_source_id = resource_num_map_layer.get_cell_source_id(tile_positions[j])
						if resource_num_source_id == -1:
							continue
						if RESOURCE_NUM_MAPPING[resource_num_source_id] == dice_result:
							resources.append(map_data.get_cell_source_id(tile_positions[j]))
							resources.append(map_data.get_cell_source_id(tile_positions[j]))
							
			# Do a lookup to mapping dict and add to player's resource dict
			for id in resources:
				if id == 6: # Skip desert tile
					continue
				var resource = SOURCE_ID_TO_RESOURCE_MAPPING[id]
				if ui_remove_resource_from_supply(resource) == true:
					p.resources[resource] += 1
					p.total_resources += 1
					
			ui_update_resources(p)
			
# Generate initial resources for the player, bot functionality added in for debug using global turn num
func generate_initial_resources(map_data, tile_positions, tile_positions_local):
	
	var SOURCE_ID_TO_RESOURCE_MAPPING = {
		1: "Tree",
		2: "Sheep",
		3: "Brick",
		4: "Wheat",
		5: "Stone"
	}
	
	for p in ALL_PLAYERS:
		if p.type == "Player":
			var RESOURCES = []
			var second_settlement_pos = p.settlements.back()
			for i in range(len(tile_positions_local)):
				# Should be the three closest tiles, where pos is the center of the tile
				var distance = sqrt(((tile_positions_local[i].x - second_settlement_pos.x)**2) + ((tile_positions_local[i].y - second_settlement_pos.y)**2))
				if distance < 75:
					RESOURCES.append(map_data.get_cell_source_id(tile_positions[i]))
			
			# Do a lookup to mapping dict and add to player's resource dict
			var UI_offset = 0
			for id in RESOURCES:
				if id == 6: # Skip desert tile
					continue
				var resource = SOURCE_ID_TO_RESOURCE_MAPPING[id]
				if ui_remove_resource_from_supply(resource) == true:
					p.resources[resource] += 1
					p.total_resources += 1
					ui_add_to_resource_bar(resource)
					
			ui_update_resources(p)
		
		# If the client is a bot
		elif p.type == "Bot":
			var RESOURCES = []
			var second_settlement_pos = p.settlements.back()
			for i in range(len(tile_positions_local)):
				# Should be the three closest tiles, where pos is the center of the tile
				var distance = sqrt(((tile_positions_local[i].x - second_settlement_pos.x)**2) + ((tile_positions_local[i].y - second_settlement_pos.y)**2))
				if distance < 75:
					RESOURCES.append(map_data.get_cell_source_id(tile_positions[i]))
			
			# Do a lookup to mapping dict and add to player's resource dict
			var UI_offset = 0
			for id in RESOURCES:
				if id == 6: # Skip desert tile
					continue
				var resource = SOURCE_ID_TO_RESOURCE_MAPPING[id]
				if ui_remove_resource_from_supply(resource) == true:
					p.resources[resource] += 1
					p.total_resources += 1
					
			ui_update_resources(p)
	
	emit_signal("end_turn")

func ui_add_to_resource_bar(resource):
	# Add UI elements depending on what resource it is, and if it already exists in the resource bar
	
	# Pos in PLAYER_RESOURCE_BAR_POSITIONS to UI offset amount
	var UI_OFFSET_MAPPING = {
		1: 0,
		2: 60,
		3: 120,
		4: 180,
		5: 240
	}
	
	var RESOURCE_TO_ID_MAPPING = {
		"Tree": 1,
		"Sheep": 2,
		"Brick": 3,
		"Wheat": 4,
		"Stone": 5
	}
	
	var resource_id = RESOURCE_TO_ID_MAPPING[resource]
	var UI_element = get_node("UILayer/Supply/%s" % resource)
	# Check where to place this element depending on other elements in the resource bar and if this resource is already in the resource bar
	
	# Check to see if this resource is already on the resource bar first
	for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)):
		if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS[i] == resource_id:
			get_node("UILayer/Resource Bar/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % CLIENT.resources[resource]
			return
			
	# If not, we need to add it to the bar
	for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)):
		if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS[i] == null:
			CLIENT.PLAYER_RESOURCE_BAR_POSITIONS[i] = resource_id # This says "Tree" is in this position on the resource bar
			var copied_ui_resource = UI_element.duplicate()
			$"UILayer/Resource Bar".add_child(copied_ui_resource, true)
			var UI_offset = UI_OFFSET_MAPPING[i+1]
			copied_ui_resource.position = Vector2(6.5 + UI_offset, 9.3)
			copied_ui_resource.z_index = 1
			copied_ui_resource.get_children()[0].text = "[font_size=30][center][b]%s" % CLIENT.resources[resource]
			return

func ui_remove_from_resource_bar(resource):
	var RESOURCE_TO_ID_MAPPING = {
		"Tree": 1,
		"Sheep": 2,
		"Brick": 3,
		"Wheat": 4,
		"Stone": 5
	}
	
	var UI_OFFSET_MAPPING = {
		1: 0,
		2: 60,
		3: 120,
		4: 180,
		5: 240
	}
	
	var ID_TO_RESOURCE_MAPPING = {
		1: "Tree",
		2: "Sheep",
		3: "Brick",
		4: "Wheat",
		5: "Stone"
	}
	#print("player discarded resource: ", resource)
	var num_of_resource = CLIENT.resources[resource]
	var resource_id = RESOURCE_TO_ID_MAPPING[resource]
	if num_of_resource == 0: # Remove resource from bar completely
		var resource_offset = null
		var index_of_element_to_remove = null
		get_node("UILayer/Resource Bar/%s/" % resource).queue_free()
		# Shift over all other elements if necessary
		for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)):
			if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS[i] == resource_id:
				resource_offset = UI_OFFSET_MAPPING[CLIENT.PLAYER_RESOURCE_BAR_POSITIONS[i]]
				index_of_element_to_remove = i
		# Reconstruct bar positions array, recalculate positions
		CLIENT.PLAYER_RESOURCE_BAR_POSITIONS = CLIENT.PLAYER_RESOURCE_BAR_POSITIONS.slice(0, index_of_element_to_remove) + CLIENT.PLAYER_RESOURCE_BAR_POSITIONS.slice(index_of_element_to_remove + 1, len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)+1)
		CLIENT.PLAYER_RESOURCE_BAR_POSITIONS.append(null)
		
		#print(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)
		
		for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)):
			if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS[i] == null:
				continue
			var curr_resource = ID_TO_RESOURCE_MAPPING[CLIENT.PLAYER_RESOURCE_BAR_POSITIONS[i]]
			var curr_resource_node = get_node("UILayer/Resource Bar/%s/" % curr_resource)
			var UI_offset = UI_OFFSET_MAPPING[i+1]
			curr_resource_node.position = Vector2(6.5 + UI_offset, 9.3)
			
	else: # Reduce number of resource in bar
		for i in range(len(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)):
			if CLIENT.PLAYER_RESOURCE_BAR_POSITIONS[i] == resource_id:
				get_node("UILayer/Resource Bar/%s/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % CLIENT.resources[resource]
				return

# Convert the tile map coords to a local coordinate space -- gets the center of the tile
func tile_map_coords_to_local_coords(tile_map, tile_positions, is_harbor) -> Array:
	var local_coords = []
	for pos in tile_positions:
		if is_harbor == false:
			local_coords.append(tile_map.map_to_local(pos) + DEBUG_map_vertex_offset)
		else:
			var tile_material = harbor_map_layer.get_cell_tile_data(pos).get_material()
			var angle = int(round(tile_material.get_shader_parameter("angle")))
			
			var angle_to_offset_mapping = {
				30: Vector2(15, 50),
				90: Vector2(50, -10),
				145: Vector2(10, -55),
				215: Vector2(-45, -55),
				270: Vector2(-70, -10),
				325: Vector2(-50, 50)
			}
			
			#print(angle_to_offset_mapping[angle])
			
			local_coords.append(tile_map.map_to_local(pos) + DEBUG_map_vertex_offset + angle_to_offset_mapping[angle])
	return local_coords

# A client will only do this once when it is their turn, bot functionality is added here for testing
func place_initial_settlements_and_roads(p):

	# If it is the client's turn and the client is not a bot
	if p.type == "Player":
		var fmt_str = "%s place a settlement and road.\n"
		var act_str = fmt_str % [p._name]
		chat_log.append_text(act_str)
		
		for node in get_tree().get_nodes_in_group("UI_settlement_buttons"):
			node.show()
		
		
		#$MapLayer/Player1_Settlement_Timer.start()
		await selection_finished # Wait for user input, else timer will timeout and do the same stuff as below
		#$MapLayer/Player1_Settlement_Timer.stop()
		
		# Hide settlment_placement_buttons
		for node in get_tree().get_nodes_in_group("UI_settlement_buttons"):
			node.hide()
		
		# Place a road
		# Roads in this init function will never branch from an existing road -- they will only extend from a settlement
		# Player settlements array should hold latest settlement position -- always use last one
		var settlement_pos = p.settlements.back()
		possible_road_placements_setup_phase(settlement_pos)
		await selection_finished

		var i = 2
		for node in get_node("MapLayer").get_children():
			if node.name == "Possible_Placement_Road%s" % i:
				i+=1
				node.queue_free()
		
		emit_signal("end_turn")
	
	# If the client is a bot
	elif p.type == "Bot":
		var fmt_str = "%s place a settlement and road.\n"
		var act_str = fmt_str % [p._name]
		chat_log.append_text(act_str)

		await bot_place_initial_settlement(p)
		
		emit_signal("end_turn")

func possible_road_placements_setup_phase(settlement_pos) -> void:
	# Given a single point -- find all possible road placements branching from it using distance formula
	
	var road_ui_btn_offset = global_road_ui_btn_offset
	
	for vertex in ALL_ROAD_MIDPOINTS:
		var distance = sqrt(((vertex.x - settlement_pos.x)**2) + ((vertex.y - settlement_pos.y)**2))
		if distance > 30 and distance < 40:
			var curr_UI_element = $MapLayer/Possible_Placement_Road.duplicate()
			$MapLayer.add_child(curr_UI_element, true)
			curr_UI_element.show()
			curr_UI_element.position = vertex + road_ui_btn_offset
			# Passed vertex here is the vertex that connects the settlement vertex to the next vertex
			curr_UI_element.pressed.connect(road_placement_pressed_setup_phase.bind(curr_UI_element, GLOBAL_TURN_NUM, vertex, settlement_pos))

func road_placement_pressed_setup_phase(midpoint_btn_node, GLOBAL_TURN_NUM, connected_vertex, settlement_vertex):
	
	# When the midpoint button is pressed -- show a road between the two points and add that point as a road to this player
	var road_ui_offset = global_road_ui_offset
	var ui_element_for_road = $MapLayer/Player1_Road.duplicate()
	$MapLayer.add_child(ui_element_for_road)
	ui_element_for_road.show()
	ui_element_for_road.pivot_offset = Vector2(ui_element_for_road.size.x / 2, ui_element_for_road.size.y / 2)
	ui_element_for_road.position = midpoint_btn_node.position + road_ui_offset # Place road at midpoint then rotate
	
	CLIENT.roads.append(midpoint_btn_node.position)
	ALL_OWNED_ROADS[CLIENT_INDEX] = CLIENT.roads
	
	# Use slope and arctan between two points to calculate how to rotate the UI element
	var slope = ((connected_vertex.y - settlement_vertex.y) / (connected_vertex.x - settlement_vertex.x))
	var degrees = rad_to_deg(atan(slope))
	
	#print(slope, degrees)
	
	if degrees == 90 or degrees == -90:
		ui_element_for_road.position = Vector2(ui_element_for_road.position.x + 6.3, ui_element_for_road.position.y)
	
	ui_element_for_road.rotation_degrees = degrees
	
	update_eligible_settlement_vertices(CLIENT.last_vertex_selected, CLIENT.last_node_selected)
	
	emit_signal("selection_finished")

func bot_place_initial_road(settlement_pos, player) -> void:
	
	var ui_element_for_road = null
	if player._name == "Bot 1":
		ui_element_for_road = $MapLayer/Bot1_Road.duplicate()
	if player._name == "Bot 2":
		ui_element_for_road = $MapLayer/Bot2_Road.duplicate()
	if player._name == "Bot 3":
		ui_element_for_road = $MapLayer/Bot3_Road.duplicate()
	
	var eligible_road_placements = []
	for vertex in ALL_ROAD_MIDPOINTS:
		var distance = sqrt(((vertex.x - settlement_pos.x)**2) + ((vertex.y - settlement_pos.y)**2))
		if distance > 30 and distance < 40: # May need to slightly adjust this range
			# Find midpoint to place UI element
			eligible_road_placements.append(vertex)
	var rand_num = randi_range(0, len(eligible_road_placements)-1)
	var chosen_road = eligible_road_placements[rand_num]
	
	player.roads.append(chosen_road + global_road_ui_btn_offset)
	ALL_OWNED_ROADS[ALL_PLAYERS.find(player)].append(chosen_road + global_road_ui_btn_offset)
	
	var road_ui_offset = global_road_ui_offset + global_road_ui_btn_offset
	$MapLayer.add_child(ui_element_for_road)
	ui_element_for_road.show()
	ui_element_for_road.pivot_offset = Vector2(ui_element_for_road.size.x / 2, ui_element_for_road.size.y / 2)
	ui_element_for_road.position = chosen_road + road_ui_offset # Place road at midpoint then rotate
	
	# Use slope and arctan between two points to calculate how to rotate the UI element
	var slope = ((chosen_road.y - settlement_pos.y) / (chosen_road.x - settlement_pos.x))
	var degrees = rad_to_deg(atan(slope))
	ui_element_for_road.rotation_degrees = degrees
	
	if degrees == 90 or degrees == -90:
		ui_element_for_road.position = Vector2(ui_element_for_road.position.x + 6.3, ui_element_for_road.position.y)

# Initialize settlement placement buttons group -- this is done once for each game!
# Afterwards, make changes to the group
func init_settlement_buttons(global_vertices):
	var settlement_placement_offset = Vector2(-12, -9)
	# Show the UI element for possible settlement placements
	var UI_elements = []
	for vertex in ELIGIBLE_SETTLEMENT_VERTICES:
		var curr_UI_element = $MapLayer/Possible_Placement_Settlement.duplicate()
		curr_UI_element.add_to_group("UI_settlement_buttons")
		UI_elements.append(curr_UI_element)
		$MapLayer.add_child(curr_UI_element)
		curr_UI_element.hide()
		curr_UI_element.position = vertex + settlement_placement_offset
		curr_UI_element.pressed.connect(settlement_placement_pressed_setup_phase.bind(curr_UI_element.name, vertex))

# Should only fire if logic from place_initial_settlements() is correct
func settlement_placement_pressed_setup_phase(id, vertex_selection):
	# increment VP
	# check for win
	
	# Add settlement as UI element
	var offset_position = Vector2(-15, -15)
	var selected_node = get_node("MapLayer/%s" % id)
	var selected_node_position = selected_node.position
	var ui_element_for_selected_settlement = $MapLayer/Player1_Settlement.duplicate()
	$MapLayer.add_child(ui_element_for_selected_settlement)
	ui_element_for_selected_settlement.show()
	ui_element_for_selected_settlement.position = selected_node_position + offset_position
	
	# See if settlement is on harbor, if so, add what type it is to the player
	for i in range(len(local_harbor_positions)):
		if get_distance(local_harbor_positions[i], vertex_selection) < 60:
			var source_id = harbor_map_layer.get_cell_source_id(global_harbor_positions[i])
			if source_id in [0, 1, 2, 3]:
				CLIENT.harbors.append("3:1")
				break
			elif source_id == 4:
				CLIENT.harbors.append("Brick")
				break
			elif source_id == 5:
				CLIENT.harbors.append("Sheep")
				break
			elif source_id == 6:
				CLIENT.harbors.append("Stone")
				break
			elif source_id == 7:
				CLIENT.harbors.append("Wheat")
				break
			elif source_id == 8:
				CLIENT.harbors.append("Tree")
				break
	#print(CLIENT._name, " harbors: ", CLIENT.harbors)
	
	# Add settlement (position) to player, save selections, will need after placing road to remove
	CLIENT.settlements.append(vertex_selection)
	CLIENT.last_vertex_selected = vertex_selection
	CLIENT.last_node_selected = selected_node
	
	emit_signal("selection_finished")

#func _on_player_1_settlement_timer_non_timeout() -> void:
	#$MapLayer/Player1_Settlement_Timer.stop()
	#print("Timer exited early due to settlement placement, returning to function...")

#func _on_player_1_settlement_timer_timeout() -> void:
	## If timer runs out place settlement randomly
	#$MapLayer/Player1_Settlement_Timer.stop()
	#print("Timer done, placing random settlement...")
	#
	#var rand_index = randi_range(0, len(ELIGIBLE_SETTLEMENT_VERTICES))
	## Add random settlement as UI element
	#var offset_position = Vector2(-15, -15)
	#var selected_node_position = ELIGIBLE_SETTLEMENT_VERTICES[rand_index]
	#var ui_element_for_selected_settlement = $MapLayer/Player1_Settlement.duplicate()
	#$MapLayer.add_child(ui_element_for_selected_settlement)
	#ui_element_for_selected_settlement.show()
	#ui_element_for_selected_settlement.position = selected_node_position + offset_position
	#
	## Add settlement to player
	#CLIENT.settlements.append(selected_node_position)
	#
	## Update eligible vertices
	#var selected_node
	#for node in get_node("MapLayer").get_children(): # node.position is offset
		#if "TextureButton" in node.name:
			#if node.position == (selected_node_position + Vector2(-12, -9)):
				#selected_node = node
	#
	#update_eligible_settlement_vertices(selected_node_position, selected_node)
	#
	## Return to main function
	#emit_signal("selection_finished")

func bot_place_initial_settlement(player) -> void:
	var ui_element_for_selected_settlement = null
	if player._name == "Bot 1":
		ui_element_for_selected_settlement = $MapLayer/Bot1_Settlement.duplicate()
	if player._name == "Bot 2":
		ui_element_for_selected_settlement = $MapLayer/Bot2_Settlement.duplicate()
	if player._name == "Bot 3":
		ui_element_for_selected_settlement = $MapLayer/Bot3_Settlement.duplicate()
		
	var rand_index = randi_range(0, len(ELIGIBLE_SETTLEMENT_VERTICES)-1)
	# Add random settlement as UI element
	var offset_position = Vector2(-15, -15) + Vector2(-12, -9)
	var selected_node_position = ELIGIBLE_SETTLEMENT_VERTICES[rand_index]
	$MapLayer.add_child(ui_element_for_selected_settlement)
	ui_element_for_selected_settlement.show()
	ui_element_for_selected_settlement.position = selected_node_position + offset_position
	
	# See if settlement is on harbor, if so, add what type it is to the player
	for i in range(len(local_harbor_positions)):
		if get_distance(local_harbor_positions[i], selected_node_position) < 60:
			var source_id = harbor_map_layer.get_cell_source_id(global_harbor_positions[i])
			if source_id in [0, 1, 2, 3]:
				player.harbors.append("3:1")
				break
			elif source_id == 4:
				player.harbors.append("Brick")
				break
			elif source_id == 5:
				player.harbors.append("Sheep")
				break
			elif source_id == 6:
				player.harbors.append("Stone")
				break
			elif source_id == 7:
				player.harbors.append("Wheat")
				break
			elif source_id == 8:
				player.harbors.append("Tree")
				break
	#print(player._name, " harbors: ", player.harbors)
	
	# Add settlement to bot
	player.settlements.append(selected_node_position)
	
	var selected_node
	for node in get_node("MapLayer").get_children(): # node.position is offset by Vector2(-12, -9)
		if "TextureButton" in node.name:
			var distance = sqrt(((node.position.x - (selected_node_position + Vector2(-12, -9)).x)**2) + ((node.position.y - (selected_node_position + Vector2(-12, -9)).y)**2))
			if distance < 5:
				selected_node = node
				break
	
	bot_place_initial_road(selected_node_position, player)
	update_eligible_settlement_vertices(selected_node_position, selected_node)
	
	await get_tree().create_timer(0.25).timeout
	
	emit_signal("selection_finished")

# Updates the global array for eligible vertices for settlement placement
func update_eligible_settlement_vertices(vertex, selected_node) -> void:
	
	# Removes vertex itself and surrounding vertices due to distance rule
	var vertices_to_remove = []
	vertices_to_remove.append(vertex)
	for i in range(len(ELIGIBLE_SETTLEMENT_VERTICES)-1):
		var distance = sqrt(((vertex.x - ELIGIBLE_SETTLEMENT_VERTICES[i].x)**2) + ((vertex.y - ELIGIBLE_SETTLEMENT_VERTICES[i].y)**2))
		if distance < 90: # These are the closest vertices
				vertices_to_remove.append(ELIGIBLE_SETTLEMENT_VERTICES[i])
	for i in range(len(vertices_to_remove)):
		if vertices_to_remove[i] in ELIGIBLE_SETTLEMENT_VERTICES:
			ELIGIBLE_SETTLEMENT_VERTICES.remove_at(ELIGIBLE_SETTLEMENT_VERTICES.find(vertices_to_remove[i]))
	
	# Removes the UI element
	selected_node.position = selected_node.position + Vector2(-12, -9)
	for x in get_tree().get_nodes_in_group("UI_settlement_buttons"):
		var distance = sqrt(((selected_node.position.x - x.position.x)**2) + ((selected_node.position.y - x.position.y)**2))
		if x == selected_node:
			x.remove_from_group("UI_settlement_buttons")
			selected_node.queue_free()
		elif distance < 90:
			x.remove_from_group("UI_settlement_buttons")
			selected_node.queue_free()
	
	return

# Debug func
#func _draw():
	#for x in global_vertices:
		#draw_circle(x, 5, Color(Color.RED), 5.0)

func generate_tile_vertices(tile_positions: Array[Vector2i], map_data: TileMapLayer):
	
	# Get radius of a tile in the tile set of the tile map
	var tile_set = map_data.tile_set
	var tile_size = tile_set.tile_size
	var radius = tile_size.y / 2
	
	var global_vertices = []
	var all_road_midpoints = []
	for i in range(len(tile_positions)):
		# Get the tile data
		var tile_data = map_data.get_cell_tile_data(tile_positions[i])
		var angle_offset = PI / 2.0
		var local_vertices = []
		for j in range(6):
			var angle = angle_offset + j * PI / 3.0
			var vertex = Vector2(radius * cos(angle), radius * sin(angle))
			local_vertices.append(vertex)
		
		var world_pos = map_data.map_to_local(tile_positions[i])
		
		for vertex in local_vertices:
			var trans_vertex = world_pos + vertex + DEBUG_map_vertex_offset
			global_vertices.append(world_pos + vertex + DEBUG_map_vertex_offset)
			
		# Generate road midpoints here using local_vertices then deduplicate ?!
		var local_road_midpoints = []
		for j in range(len(local_vertices)):
			var midpoint = 0.0
			if j == 5:
				var trans_vertex_1 = world_pos + local_vertices[j] + DEBUG_map_vertex_offset
				var trans_vertex_2 = world_pos + local_vertices[0] + DEBUG_map_vertex_offset
				midpoint = Vector2(((trans_vertex_1.x + trans_vertex_2.x) / 2), ((trans_vertex_2.y + trans_vertex_1.y) / 2))
			else:
				var trans_vertex_1 = world_pos + local_vertices[j] + DEBUG_map_vertex_offset
				var trans_vertex_2 = world_pos + local_vertices[j+1] + DEBUG_map_vertex_offset
				midpoint = Vector2(((trans_vertex_1.x + trans_vertex_2.x) / 2), ((trans_vertex_2.y + trans_vertex_1.y) / 2))
			all_road_midpoints.append(midpoint)
	
	global_vertices.sort()
	all_road_midpoints.sort()
	
	# Deduplicate global_vertices array
	var elements_to_remove = []
	for i in range(len(global_vertices)):
		for j in range(i+1, len(global_vertices)):
			var distance = get_distance(global_vertices[i], global_vertices[j])
			if distance < 10:
				elements_to_remove.append(global_vertices[j])
	# remove the elements...
	for i in range(len(elements_to_remove)):
		if elements_to_remove[i] in global_vertices:
			global_vertices.remove_at(global_vertices.find(elements_to_remove[i]))
	
	# Deduplicate all_road_midpoints array
	elements_to_remove = []
	for i in range(len(all_road_midpoints)):
		for j in range(i+1, len(all_road_midpoints)):
			var distance = get_distance(all_road_midpoints[i], all_road_midpoints[j])
			if distance < 10:
				elements_to_remove.append(all_road_midpoints[j])
	# remove the elements...
	for i in range(len(elements_to_remove)):
		if elements_to_remove[i] in all_road_midpoints:
			all_road_midpoints.remove_at(all_road_midpoints.find(elements_to_remove[i]))
	
	ALL_ROAD_MIDPOINTS = all_road_midpoints # Set the global var
	
	return global_vertices

func get_distance(point1: Vector2, point2: Vector2) -> float:
	return sqrt((point1.x - point2.x)**2 + (point1.y - point2.y)**2)

func roll_dice() -> int:
	return randi_range(1,6)

func _on_roll_dice_pressed() -> int:
	var result_1 = roll_dice()
	var result_2 = roll_dice()
	if result_1 + result_2 == 7:
		roll_dice_btn.text = "ROBBER!"
	else:
		roll_dice_btn.text = "Rolled a " + str(result_1 + result_2) + " (" + str(result_1) + "," + str(result_2) + ") \n"
	return result_1 + result_2

func generate_rand_standard_map() -> Array[Vector2i]:
	
	# Resource tile amounts
	var NUM_TREE_TILES = 4
	var NUM_SHEEP_TILES = 4
	var NUM_BRICK_TILES = 3
	var NUM_WHEAT_TILES = 4
	var NUM_STONE_TILES = 3
	var NUM_DESERT_TILES = 1
	var TOTAL_NUM_TILES = 19
	
	
	# Resource numbers
	var NUM_OF_TWO = 1
	var NUM_OF_THREE = 2
	var NUM_OF_FOUR = 2
	var NUM_OF_FIVE = 2
	var NUM_OF_SIX = 2
	var NUM_OF_EIGHT = 2
	var NUM_OF_NINE = 2
	var NUM_OF_TEN = 2
	var NUM_OF_ELEVEN = 2
	var NUM_OF_TWELVE = 1
	
	# The keys correspond to the Atlas ID's in the TileSet for the ResourceNumbers TileMapLayer
	var resource_allocations = {
		"1": 1,
		"2": 2,
		"3": 2,
		"4": 2,
		"5": 2,
		"6": 2,
		"7": 2,
		"8": 2,
		"9": 2,
		"10": 1
	}
	
	var possible_placements: Array[Vector2i] = [
		Vector2i(-2, -3), Vector2i(-1, -3), Vector2i(0, -3),
		Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
		Vector2i(-3, -1), Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1)
	]
	
	var possible_placements_for_resource = possible_placements.duplicate(true)
	var possible_placements_read = possible_placements.duplicate(true)
	var possible_placements_harbours = possible_placements.duplicate(true)
	
	# Place tiles randomly, removing the selections from the list of possible placements each time
	# And assigning a random resource number, also removing from the list of possibilities each time
	# and checking that two red tiles are not adjacent each other
	for i in range(NUM_TREE_TILES):
		var random_placement = randi_range(0, len(possible_placements) - 1)
		standard_map.set_cell(possible_placements[random_placement], 1, Vector2i(0,0))
		possible_placements.pop_at(random_placement)
		
	for i in range(NUM_SHEEP_TILES):
		var random_placement = randi_range(0, len(possible_placements) - 1)
		standard_map.set_cell(possible_placements[random_placement], 2, Vector2i(0,0))
		possible_placements.pop_at(random_placement)
	
	for i in range(NUM_BRICK_TILES):
		var random_placement = randi_range(0, len(possible_placements) - 1)
		standard_map.set_cell(possible_placements[random_placement], 3, Vector2i(0,0))
		possible_placements.pop_at(random_placement)
	
	for i in range(NUM_WHEAT_TILES):
		var random_placement = randi_range(0, len(possible_placements) - 1)
		standard_map.set_cell(possible_placements[random_placement], 4, Vector2i(0,0))
		possible_placements.pop_at(random_placement)
		
	for i in range(NUM_STONE_TILES):
		var random_placement = randi_range(0, len(possible_placements) - 1)
		standard_map.set_cell(possible_placements[random_placement], 5, Vector2i(0,0))
		possible_placements.pop_at(random_placement)
		
	# Set desert tile
	var desert_tile_placement = possible_placements[0]
	standard_map.set_cell(desert_tile_placement, 6, Vector2i(0,0))
	
	# Place a random resource number on this tile, checking that a red resource number (6 or 8)
	# is not adjacent to another red resource number & is not a desert tile
	
	# Place 6/8 first to avoid infinite loops
	for j in range(4): # There are 2 6's and 2 8's
		var random_placement = null
		var rand_resource_num = null
		while true:
			var retry = false
			random_placement = randi_range(0, len(possible_placements_for_resource) - 1)
			rand_resource_num = str(randi_range(5,6))

			# Skip if this is a desert tile
			if possible_placements_for_resource[random_placement] == desert_tile_placement:
				possible_placements_for_resource.pop_at(random_placement)
				continue
			
			if resource_allocations[rand_resource_num] > 0:
				# If a 6 or 8, check that it is not adjacent to another 6 or 8. If so, retry. If not, set cell
				var neighbor_cells = resource_num_map_layer.get_surrounding_cells(possible_placements_for_resource[random_placement])
				# For all neighbor cells, check that none of them are a 6/8
				for neighbor_coords in neighbor_cells:
					var atlas_id = resource_num_map_layer.get_cell_source_id(neighbor_coords)
					if atlas_id == 5 or atlas_id == 6:
						retry = true
						break
				if retry:
					continue
				resource_allocations[rand_resource_num] = resource_allocations[rand_resource_num] - 1
				resource_num_map_layer.set_cell(possible_placements_for_resource[random_placement], int(rand_resource_num), Vector2i(0,0))
				possible_placements_for_resource.pop_at(random_placement)
				break
			
	for i in range(len(possible_placements_for_resource)):
		var rand_resource_num = null
		var random_placement = randi_range(0, len(possible_placements_for_resource) - 1)
		
		# Skip if this is a desert tile
		if possible_placements_for_resource[random_placement] == desert_tile_placement:
			possible_placements_for_resource.pop_at(random_placement)
			continue
		
		while true:
			rand_resource_num = str(randi_range(1, 10))
			if resource_allocations[rand_resource_num] > 0:
				resource_allocations[rand_resource_num] = resource_allocations[rand_resource_num] - 1
				resource_num_map_layer.set_cell(possible_placements_for_resource[random_placement], int(rand_resource_num), Vector2i(0,0))
				possible_placements_for_resource.pop_at(random_placement)
				break
				
	# Place the harbors at exact points on the Harbor Layer
	var harbor_positions: Array[Vector2i] = [
		Vector2i(-2, -4), Vector2i(-3, -2), Vector2i(-3, 0), 
		Vector2i(-2, 2), Vector2i(0, 2), Vector2i(1, 1), 
		Vector2i(2, -1), Vector2i(1, -3), Vector2i(0, -4)
	]
	
	global_harbor_positions = harbor_positions
	
	# Not used
	var tiles_with_harbors: Array[Vector2i] = [
		Vector2i(-2, -3), Vector2i(-2, -2), Vector2i(-2, 0), 
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(1, 0), 
		Vector2i(1, -1), Vector2i(1, -2), Vector2i(-1, -3)
	]
	
	# Iterate through all tiles, see if there are any neighors at DIRECTION -- if not, a HARBOUR can be placed here
	# then, choose correct placement for this harbour (standard map only) -- change direction of harbour depending on what DIRECTION the edge is
	var directions = [
		TileSet.CellNeighbor.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
		TileSet.CellNeighbor.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
		TileSet.CellNeighbor.CELL_NEIGHBOR_LEFT_SIDE,
		TileSet.CellNeighbor.CELL_NEIGHBOR_RIGHT_SIDE,
		TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_LEFT_SIDE,
		TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_RIGHT_SIDE
	]
	var harbor_cells = {}
	for i in range(len(possible_placements_harbours)):
		
		# Sides of a pointy-topped hexagon
		
		
		for j in len(directions):
			var surrounding_cell = standard_map.get_neighbor_cell(possible_placements_harbours[i], directions[j])
			# Check if surrounding cell contains a tile
			# if not, add it to the list along with the direction
			if standard_map.get_cell_tile_data(surrounding_cell) == null:
				harbor_cells[surrounding_cell] = directions[j]
				
	
	var angle_mapping = {
		0: 270,
		2: 215,
		6: 145,
		8: 90,
		10: 30,
		14: 325
	}
	
	
	var harbor_angles: Array[int] = [
		10, 8, 8, 6, 2, 2, 0, 14, 14
	]
	
	var harbor_types: Array[int] = [
		1, 2, 3, 4, 5, 6, 7, 8
	]
	
	for i in range(len(harbor_positions)):
		# Choose a random harbor type and then remove it from the array so it can't be selected again
		if i > 0:
			var rand_harbor_selection = randi_range(0, len(harbor_types)-1)
			var harbor_type = harbor_types[rand_harbor_selection]
			harbor_types.pop_at(rand_harbor_selection)
			harbor_map_layer.set_cell(harbor_positions[i], harbor_type, Vector2i(0,0))
		else:
			harbor_map_layer.set_cell(harbor_positions[i], 0, Vector2i(0,0))
		# Grab direction for this position
		
		# Hardcoded angles for a standard map, the skeleton is still here for dynamic harbor angle decision making
		#var direction = harbor_cells[harbor_positions[i]]
		#var angle = angle_mapping[direction] # Returns an angle given a direction
		
		
		var angle = angle_mapping[harbor_angles[i]] # Should always be the same length as harbor_positions
		
		if i > 0:
			var tile_material = harbor_map_layer.get_cell_tile_data(harbor_positions[0]).get_material()
			var copied_material = tile_material.duplicate()
			
			copied_material.set_shader_parameter("angle", angle)
			
			harbor_map_layer.get_cell_tile_data(harbor_positions[i]).set_material(copied_material)
		else:
			var tile_material = harbor_map_layer.get_cell_tile_data(harbor_positions[i]).get_material()
			tile_material.set_shader_parameter("angle", angle)
	
	# Had to add this hack in after upgrade to 4.4
	var tile_material = harbor_map_layer.get_cell_tile_data(harbor_positions[0]).get_material()
	tile_material.set_shader_parameter("angle", 30.01)
	
	return possible_placements_read
	
func check_win():
	for p in ALL_PLAYERS:
		if p.vp > 10:
			end_game(p)

func end_game(player_who_won):
	ui_disable_all_buttons()
	$UILayer/End_Game_Screen.show()
	$UILayer/End_Game_Screen/Game_Over.text = """[font_size=50] [center] Game over!
												Winner: %s"""  % player_who_won._name
	print("Game over!")


func _on_player_trade_button_pressed() -> void:
	# Pop up (or hide) UI, set variables
	$UILayer/Player_Trade_Popup.visible = !$UILayer/Player_Trade_Popup.visible
	if $UILayer/Player_Trade_Popup.visible == false:
		CLIENT.chosen_resources_trade = []
		CLIENT.chosen_resources_player_trade = []
		for node in $UILayer/Player_Trade_Popup/Dynamic_Player_Area.get_children():
			$UILayer/Player_Trade_Popup/Dynamic_Player_Area.remove_child(node)
			node.queue_free()
		for node in $UILayer/Player_Trade_Popup/Dynamic_Bank_Area.get_children():
			$UILayer/Player_Trade_Popup/Dynamic_Bank_Area.remove_child(node)
			node.queue_free()
		
		$UILayer/Player_Trade_Popup/Divider4.hide()
		
		activate_or_deactivate_ui_buttons()
	else: # Cleanup: Use some loops here
		ui_disable_all_buttons(["Player_Trade_Button"])
		
		get_node("UILayer/Player_Trade_Popup/Brick_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Brick"]
		get_node("UILayer/Player_Trade_Popup/Sheep_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Sheep"]
		get_node("UILayer/Player_Trade_Popup/Stone_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Stone"]
		get_node("UILayer/Player_Trade_Popup/Wheat_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Wheat"]
		get_node("UILayer/Player_Trade_Popup/Tree_Player/Num_Remaining").text = "[font_size=30][center][b]%s" % CLIENT.resources["Tree"]
		
		$UILayer/Player_Trade_Popup/Brick_Player.visible = true
		$UILayer/Player_Trade_Popup/Sheep_Player.visible = true
		$UILayer/Player_Trade_Popup/Stone_Player.visible = true
		$UILayer/Player_Trade_Popup/Wheat_Player.visible = true 
		$UILayer/Player_Trade_Popup/Tree_Player.visible = true

		$UILayer/Player_Trade_Popup/Brick_Player/Brick_Player_Btn.visible = false if CLIENT.resources["Brick"] == 0 else true
		$UILayer/Player_Trade_Popup/Sheep_Player/Sheep_Player_Btn.visible = false if CLIENT.resources["Sheep"] == 0 else true
		$UILayer/Player_Trade_Popup/Stone_Player/Stone_Player_Btn.visible = false if CLIENT.resources["Stone"] == 0 else true
		$UILayer/Player_Trade_Popup/Wheat_Player/Wheat_Player_Btn.visible = false if CLIENT.resources["Wheat"] == 0 else true
		$UILayer/Player_Trade_Popup/Tree_Player/Tree_Player_Btn.visible = false if CLIENT.resources["Tree"] == 0 else true

func player_trade_add_resource_to_player_area(resource):
	
	if resource not in CLIENT.chosen_resources_trade: # Add resource to player area
		var new_node = get_node("UILayer/Player_Trade_Popup/%s_Player" % resource).duplicate(0) # Don't duplicate the signal
		new_node.get_child(1).pressed.connect(player_trade_remove_resource_from_player_area.bind(new_node, resource))
		new_node.position = Vector2(new_node.position.x, 32)
		new_node.get_child(0).text = "[font_size=30][center][b]1"
		$UILayer/Player_Trade_Popup/Dynamic_Player_Area.add_child(new_node)
	else: # If already there, just increase num_remaining
		var existing_node
		for node in $UILayer/Player_Trade_Popup/Dynamic_Player_Area.get_children(true):
			if resource in node.name:
				existing_node = node
				break
		#var existing_node = $UILayer/Player_Trade_Popup/Dynamic_Player_Area.get_child(0)
		var num_remaining = int(existing_node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) + 1
		existing_node.get_child(0).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	# Decrease num_remaining for the player's resources
	var num_remaining = int(get_node("UILayer/Player_Trade_Popup/%s_Player/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) - 1
	if num_remaining == 0:
		get_node("UILayer/Player_Trade_Popup/%s_Player/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
		get_node("UILayer/Player_Trade_Popup/%s_Player/%s_Player_Btn" % [resource, resource]).hide()
	else:
		get_node("UILayer/Player_Trade_Popup/%s_Player/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	CLIENT.chosen_resources_trade.append(resource)
	
	#print(CLIENT.chosen_resources_trade)
	
func player_trade_add_resource_to_bank_area(resource):
	
	if resource not in CLIENT.chosen_resources_player_trade:
		var new_node = get_node("UILayer/Player_Trade_Popup/%s_Bank" % resource).duplicate(0) # Don't duplicate the signal
		new_node.get_child(1).pressed.connect(player_trade_remove_resource_from_bank_area.bind(new_node, resource))
		new_node.get_child(0).text = "[font_size=30][center][b]1"
		new_node.get_child(0).show()
		$UILayer/Player_Trade_Popup/Dynamic_Bank_Area.add_child(new_node)
		new_node.position = Vector2(new_node.position.x - 454, 32)
	else: # If already there, just increase num_remaining
		var existing_node
		for node in $UILayer/Player_Trade_Popup/Dynamic_Bank_Area.get_children(true):
			if resource in node.name:
				existing_node = node
				break
		var num_remaining = int(existing_node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) + 1
		existing_node.get_child(0).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	# Decrease num_remaining for the player's resources
	var num_remaining = int(get_node("UILayer/Player_Trade_Popup/%s_Bank/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) - 1
	if num_remaining == 0:
		get_node("UILayer/Player_Trade_Popup/%s_Bank/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
		get_node("UILayer/Player_Trade_Popup/%s_Bank/%s_Bank_Btn" % [resource, resource]).hide()
	else:
		get_node("UILayer/Player_Trade_Popup/%s_Bank/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	CLIENT.chosen_resources_player_trade.append(resource)
	
	#print(CLIENT.chosen_resources_player_trade)
	
func player_trade_remove_resource_from_player_area(node, resource):
	if int(node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) == 1:
		
		# Add back this resource for the player's resources
		var num_remaining = int(get_node("UILayer/Player_Trade_Popup/%s_Player/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) + 1
		get_node("UILayer/Player_Trade_Popup/%s_Player/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
		
		var index_of_element_to_remove = CLIENT.chosen_resources_trade.find(resource)
		CLIENT.chosen_resources_trade.remove_at(index_of_element_to_remove)
		
		get_node("UILayer/Player_Trade_Popup/%s_Player/%s_Player_Btn" % [resource, resource]).show()
		
		$UILayer/Player_Trade_Popup/Dynamic_Player_Area.remove_child(node)
		node.queue_free()
		
	else: # just decrease num_remaining in the player area, and increase the value for the player's resources
		var num_remaining = int(node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) - 1
		node.get_child(0).text = "[font_size=30][center][b]%s" % str(num_remaining)
		var index_of_element_to_remove = CLIENT.chosen_resources_trade.find(resource)
		CLIENT.chosen_resources_trade.remove_at(index_of_element_to_remove)
		
		# Increase
		num_remaining = int(get_node("UILayer/Player_Trade_Popup/%s_Player/Num_Remaining" % resource).text.get_slice("[font_size=30][center][b]", 1)) + 1
		get_node("UILayer/Player_Trade_Popup/%s_Player/%s_Player_Btn" % [resource, resource]).show()
		get_node("UILayer/Player_Trade_Popup/%s_Player/Num_Remaining" % resource).text = "[font_size=30][center][b]%s" % str(num_remaining)
	
	#print(CLIENT.chosen_resources_trade)

func player_trade_remove_resource_from_bank_area(node, resource):
	if int(node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) == 1:
		
		var index_of_element_to_remove = CLIENT.chosen_resources_player_trade.find(resource)
		CLIENT.chosen_resources_player_trade.remove_at(index_of_element_to_remove)
		
		$UILayer/Player_Trade_Popup/Dynamic_Bank_Area.remove_child(node)
		node.queue_free()
		
	else: # just decrease num_remaining in the player area, and increase the value for the player's resources
		var num_remaining = int(node.get_child(0).text.get_slice("[font_size=30][center][b]", 1)) - 1
		node.get_child(0).text = "[font_size=30][center][b]%s" % str(num_remaining)
		var index_of_element_to_remove = CLIENT.chosen_resources_player_trade.find(resource)
		CLIENT.chosen_resources_player_trade.remove_at(index_of_element_to_remove)
		
	
	#print(CLIENT.chosen_resources_player_trade)

func _on_PLAYER_TRADE_brick_player_btn_pressed() -> void:
	await player_trade_add_resource_to_player_area("Brick")

func _on_PLAYER_TRADE_sheep_player_btn_pressed() -> void:
	await player_trade_add_resource_to_player_area("Sheep")

func _on_PLAYER_TRADE_stone_player_btn_pressed() -> void:
	await player_trade_add_resource_to_player_area("Stone")

func _on_PLAYER_TRADE_tree_player_btn_pressed() -> void:
	await player_trade_add_resource_to_player_area("Tree")

func _on_PLAYER_TRADE_wheat_player_btn_pressed() -> void:
	await player_trade_add_resource_to_player_area("Wheat")

func _on_PLAYER_TRADE_brick_bank_btn_pressed() -> void:
	await player_trade_add_resource_to_bank_area("Brick")

func _on_PLAYER_TRADE_sheep_bank_btn_pressed() -> void:
	await player_trade_add_resource_to_bank_area("Sheep")

func _on_PLAYER_TRADE_tree_bank_btn_pressed() -> void:
	await player_trade_add_resource_to_bank_area("Tree")

func _on_PLAYER_TRADE_wheat_bank_btn_pressed() -> void:
	await player_trade_add_resource_to_bank_area("Wheat")

func _on_PLAYER_TRADE_stone_bank_btn_pressed() -> void:
	await player_trade_add_resource_to_bank_area("Stone")

func _on_PLAYER_TRADE_finish_trade_btn_pressed() -> void:
	
	# Alert player they need to cancel or have a trade accepted to propose another trade. Max trades: 3
	if len(global_player_trades) == 3:
		$UILayer/Player_Trade_Popup/Divider4.show()
		return
	else:
		var new_trade = $UILayer/Player_Trade_Offer_Template.duplicate()
		
		new_trade.get_child(0).text = "[font_size=18][center]%s offered trade:" % CLIENT._name
		new_trade.name = "Player_Trade_Offer_%s" % str(len(global_player_trades) + 1)
		
		
		var new_trade_children = new_trade.get_children(true)
		for resource in CLIENT.chosen_resources_trade:
			for child in new_trade_children:
				if child.name == resource + "_Player":
					child.show()
					child.get_child(0).text = "[font_size=30][center][b]%s" % CLIENT.chosen_resources_trade.count(resource)
					break
					
		for resource in CLIENT.chosen_resources_player_trade:
			for child in new_trade_children:
				if child.name == resource + "_Bank":
					child.show()
					child.get_child(0).text = "[font_size=30][center][b]%s" % CLIENT.chosen_resources_player_trade.count(resource)
					break
		
		new_trade.show()
		
		new_trade.position = Vector2(new_trade.position.x, (297 + (235 * len(global_player_trades))))
		
		#var trade_counts = {
			#"Tree": CLIENT.chosen_resources_player_trade.count("Tree"),
			#"Stone": CLIENT.chosen_resources_player_trade.count("Stone"),
			#"Brick": CLIENT.chosen_resources_player_trade.count("Brick"),
			#"Wheat": CLIENT.chosen_resources_player_trade.count("Wheat"),
			#"Sheep": CLIENT.chosen_resources_player_trade.count("Sheep")
		#}
		
		var index = -1
		var valid_players_to_trade_with = []
		for player in ALL_PLAYERS:
			new_trade.get_child(index).get_child(2).text = player._name
			if player == CLIENT:
				new_trade.get_child(index).get_child(0).show() # Shows the decline button automatically
				valid_players_to_trade_with.append(null)
				index -= 1
				continue
			else:
				valid_players_to_trade_with.append(player)
				if CLIENT.chosen_resources_player_trade.is_empty():
					continue
				else:
					if player.resources.get("Tree") < CLIENT.chosen_resources_player_trade.count("Tree"):
						new_trade.get_child(index).get_child(0).show()
						var index_of_player = valid_players_to_trade_with.find(player)
						valid_players_to_trade_with[index_of_player] = null
						index -= 1
						continue
					if player.resources.get("Brick") < CLIENT.chosen_resources_player_trade.count("Brick"):
						new_trade.get_child(index).get_child(0).show()
						var index_of_player = valid_players_to_trade_with.find(player)
						valid_players_to_trade_with[index_of_player] = null
						index -= 1
						continue
					if player.resources.get("Stone") < CLIENT.chosen_resources_player_trade.count("Stone"):
						new_trade.get_child(index).get_child(0).show()
						var index_of_player = valid_players_to_trade_with.find(player)
						valid_players_to_trade_with[index_of_player] = null
						index -= 1
						continue
					if player.resources.get("Wheat") < CLIENT.chosen_resources_player_trade.count("Wheat"):
						new_trade.get_child(index).get_child(0).show()
						var index_of_player = valid_players_to_trade_with.find(player)
						valid_players_to_trade_with[index_of_player] = null
						index -= 1
						continue
					if player.resources.get("Sheep") < CLIENT.chosen_resources_player_trade.count("Sheep"):
						new_trade.get_child(index).get_child(0).show()
						var index_of_player = valid_players_to_trade_with.find(player)
						valid_players_to_trade_with[index_of_player] = null
						index -= 1
						continue
					else:
						index -= 1
						continue
					
			
		
		index = -1
		# Send trade to players. For bots, instantly decide via func
		for p in valid_players_to_trade_with:
			if p == null:
				index -= 1
				continue
			if p.type == "Bot":
				var decision = bot_accept_or_decline_player_trade_decision(p, CLIENT.chosen_resources_trade)
				if decision == true: # Show the accept button for the client
					new_trade.get_child(index).get_child(0).hide()
					new_trade.get_child(index).get_child(1).show()
					new_trade.get_child(index).get_child(1).pressed.connect(client_accept_player_trade_with_bot.bind(p, new_trade, CLIENT.chosen_resources_trade, CLIENT.chosen_resources_player_trade))
				else:
					new_trade.get_child(index).get_child(0).show()
				index -= 1
			else:
				pass
				# Multiplayer function!

		# -1 is Decline btn. -2 is Accept btn
		#new_trade.get_child(-1).pressed.connect(accept_player_trade.bind(CLIENT, CLIENT.chosen_resources_trade, CLIENT.chosen_resources_player_trade, new_trade))

		$UILayer.add_child(new_trade)
		global_player_trades.append(new_trade) # If there are existing trades, then different behavior to positioning will apply
		#print(global_player_trades)

func client_accept_player_trade_with_bot(bot_trading_with, trade_node, offered_resources, requested_resources):
	# Swap resources with player_trading_with, and remove the trade_node, adjusting global_player_trades and shifting UI elements if needed
	
	for resource in offered_resources:
		CLIENT.resources[resource] -= 1
		CLIENT.total_resources -= 1
		ui_remove_from_resource_bar(resource)
		
		bot_trading_with.resources[resource] += 1
		bot_trading_with.total_resources += 1
		
	for resource in requested_resources:
		CLIENT.resources[resource] += 1
		CLIENT.total_resources += 1
		ui_add_to_resource_bar(resource)
		
		bot_trading_with.resources[resource] -= 1
		bot_trading_with.total_resources -= 1
		
	global_player_trades.remove_at(global_player_trades.find(trade_node))
	
	$UILayer.remove_child(trade_node)
	trade_node.queue_free()
	
	# Check that other existing trades are still valid, and update their position if so
	var trade_nodes_to_remove = []
	for i in range(0, len(global_player_trades)):
		
		var node = global_player_trades[i]
		offered_resources = []
		for child in node.get_children():
			if "Player" in child.name and child.visible == true:
				for j in range(int(child.get_child(0).text.get_slice("[font_size=30][center][b]", 1))):
					offered_resources.append(child.name.get_slice("_Player", 0))
		
		if CLIENT.resources.get("Tree") < offered_resources.count("Tree"):
			trade_nodes_to_remove.append(node)
		if CLIENT.resources.get("Brick") < offered_resources.count("Brick"):
			trade_nodes_to_remove.append(node)
		if CLIENT.resources.get("Stone") < offered_resources.count("Stone"):
			trade_nodes_to_remove.append(node)
		if CLIENT.resources.get("Wheat") < offered_resources.count("Wheat"):
			trade_nodes_to_remove.append(node)
		if CLIENT.resources.get("Sheep") < offered_resources.count("Sheep"):
			trade_nodes_to_remove.append(node)
			
	for node in trade_nodes_to_remove:
		global_player_trades.remove_at(global_player_trades.find(node))
		$UILayer.remove_child(node)
		node.queue_free()
		
	# Reorder existing trades
	for i in range(0, len(global_player_trades)):
		global_player_trades[i].position = Vector2(global_player_trades[i].position.x, (297 + (235 * i)))
		
	# Refresh the popup with updated resources
	_on_player_trade_button_pressed() # Close it first
	_on_player_trade_button_pressed() # Reopen it
	
	ui_update_resources(CLIENT)
	ui_update_resources(bot_trading_with)

func bot_accept_or_decline_player_trade_decision(player, resources_being_offered: Array) -> bool:
	# TODO: Add some better decision making...
	# Would most likely follow a real player's decision making, weighing how much the trade would benefit each player, taking into consideration the VP of each player, how impactful the resources gained would be for being able to build new roads/cities/settlements, etc... this can get very complicated!
	
	var coin_flip = randi_range(0,1)
	if coin_flip == 0:
		return true
	return false

#func accept_player_trade(player, left_trade, right_trade, trade_node):
	#print(player + " accepted trade: " + trade_node.name + " ( " + left_trade + "for " + right_trade + " ) ")


func _on_debug_show_debug_info_pressed() -> void:
	$UILayer/DEBUG_show_debug_info/debug_info.visible = !$UILayer/DEBUG_show_debug_info/debug_info.visible
	if $UILayer/DEBUG_show_debug_info/debug_info.visible == true:
		$UILayer/DEBUG_show_debug_info.text = "Hide debug info"
	else:
		$UILayer/DEBUG_show_debug_info.text = "Show debug info"
	var debug_info_str = str(OS.get_distribution_name() + "\n" + OS.get_model_name() + "\n" + OS.get_name() + OS.get_processor_name() + "\n" + OS.get_version() + "\n" + OS.get_video_adapter_driver_info()[0] + "\n" + str(DisplayServer.screen_get_size(DisplayServer.get_primary_screen())) + "\n" + str(DisplayServer.window_get_size(DisplayServer.get_window_list()[0])))
	$UILayer/DEBUG_show_debug_info/debug_info.text = debug_info_str


func _on_back_to_menu_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_select.tscn")
