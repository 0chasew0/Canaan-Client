extends Node2D

# UI
@onready var standard_map = $MapLayer/StandardMap
@onready var resource_num_map_layer = $MapLayer/ResourceNumbers
@onready var harbor_map_layer = $MapLayer/Harbors
@onready var roll_dice_btn = $UILayer/Roll_Dice
@onready var chat_log = $UILayer/Chat/Chat_Log
@export var chat_log_font_size = 30
@onready var PLAYER_UI_BOX = $UILayer/Player1Background
@onready var BOT_1_UI_BOX = $UILayer/Player2Background
@onready var BOT_2_UI_BOX = $UILayer/Player3Background
@onready var BOT_3_UI_BOX = $UILayer/Player4Background
@onready var global_ui_resource_offset = 0
@onready var NUM_SUPPLY_TREE = 19
@onready var NUM_SUPPLY_SHEEP = 19
@onready var NUM_SUPPLY_BRICK = 19
@onready var NUM_SUPPLY_WHEAT = 19
@onready var NUM_SUPPLY_STONE = 19

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

# Debug vars
@export var DEBUG_map_vertex_offset = Vector2(905, 671) # For the map vertices
@onready var tile_positions_local = []
@onready var ALL_ROAD_MIDPOINTS = [] # Stores all road midpoints

@onready var ELIGIBLE_SETTLEMENT_VERTICES = [] # Contains a list of eligible vertices for settlement placement. This is shared between all players
@onready var ELIGIBLE_ROAD_VERTICES_SETUP = []

# Signals
signal selection_finished # Used for returning control back to a main function after a user selects an action or they timeout from that action
signal end_turn # Used for signaling that a player or bots turn is over, usually used in the main game loop

func _ready() -> void:
	
	var PLAYER = load("res://player.gd")
	for i in range(PLAYER_COUNT):
		if i == 0: # In multiplayer, this should check for whether this is a bot or player
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
	
	await initialize_ui_boxes()
	randomize() # Initializes randomizer, only call this once
	var tile_positions = generate_rand_standard_map() # Map data contains coordinates of all cells of the map
	tile_positions_local = tile_map_coords_to_local_coords(standard_map, tile_positions)
	
	global_vertices = await generate_tile_vertices(tile_positions, standard_map)
	ELIGIBLE_SETTLEMENT_VERTICES = global_vertices.duplicate() # At the beginning of the game, all vertices are eligible
	ELIGIBLE_ROAD_VERTICES_SETUP = global_vertices.duplicate()
	init_settlement_buttons(global_vertices)
	
	# Initialize Robber
	await initialize_robber(standard_map, tile_positions)
	
	# Initialize UI button states
	#await activate_or_deactivate_ui_buttons(p)
	
	# Initialize chat box setting(s)
	chat_log.append_text("[font_size=%s]Welcome to Canaan!" % chat_log_font_size)
	
	# Initialize road array
	for i in range(PLAYER_COUNT):
		ALL_OWNED_ROADS.append([])
	
	# Main game loop for a client
	await roll_for_who_goes_first()
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
		
	chat_log.append_text("[font_size=%s]\nAll players done placing settlements and roads." % chat_log_font_size)
	
	for player in ALL_PLAYERS:
		player.vp = 2
		
	CLIENT.vp = 2
	
	# Make this more dynamic
	PLAYER_UI_BOX.get_node("VP").text = "[font_size=18][center]Victory Points: 2"
	BOT_1_UI_BOX.get_node("VP").text = "[font_size=18][center]Victory Points: 2"
	BOT_2_UI_BOX.get_node("VP").text = "[font_size=18][center]Victory Points: 2"
	BOT_3_UI_BOX.get_node("VP").text = "[font_size=18][center]Victory Points: 2"
	
	main_game_loop(tile_positions, standard_map)
	
func main_game_loop(tile_positions, standard_map):
	GLOBAL_TURN_NUM = 1
	
	# Bot functionality added for testing
	for i in range(100): # Turn limit?
		for p in ALL_PLAYERS:
			if p.type == "Player":
				# Turn Initializers
				await activate_or_deactivate_ui_buttons()
				print("player turn")
				roll_dice_btn.disabled = false
				
				# Can play one development card before rolling dice
				
				# Check for win
				
				await roll_dice_btn.pressed # Wait for user to roll dice before continuing
				p.dice_roll_result = _on_roll_dice_pressed()
				chat_log.append_text("[font_size=%s]\n%s rolled a %s." % [chat_log_font_size, p._name, p.dice_roll_result])
				roll_dice_btn.disabled = true
				
				# Generate resources for EACH player based on dice result, unless a 7 is rolled
				# For friendly robber, check that no player has VP > 2, else do robber as normal
				if p.dice_roll_result == 7:
					for player in ALL_PLAYERS:
						if player.vp < 3:
							continue
						else:
							activate_robber()
							
				await generate_resources_for_all_players(p.dice_roll_result, tile_positions_local, tile_positions, standard_map)
				await activate_or_deactivate_ui_buttons()
				
				# When player is done with turn
				await $UILayer/End_Turn_Btn_Background/End_Turn_Button.pressed

			else:
				print("bot turn")
				# Disable all buttons when it's not the client's turn
				# Simulate dice roll
				p.dice_roll_result = _on_roll_dice_pressed()
				chat_log.append_text("[font_size=%s]\n%s rolled a %s." % [chat_log_font_size, p._name, p.dice_roll_result])
				if p.dice_roll_result == 7:
					for player in ALL_PLAYERS:
						if player.vp < 3:
							continue
						else:
							activate_robber()
				await generate_resources_for_all_players(p.dice_roll_result, tile_positions_local, tile_positions, standard_map)
				
				bot_decision_loop(p)
				


func initialize_ui_boxes() -> void:
	PLAYER_UI_BOX.get_node("PlayerName").text = "[font_size=18][center][b]Player"
	BOT_1_UI_BOX.get_node("PlayerName").text = "[font_size=18][center][b]Bot 1"
	BOT_2_UI_BOX.get_node("PlayerName").text = "[font_size=18][center][b]Bot 2"
	BOT_3_UI_BOX.get_node("PlayerName").text = "[font_size=18][center][b]Bot 3"

# Debug func
#func _draw():
	#for x in tile_positions_local:
		#draw_circle(x, 5, Color(Color.RED), 5.0)

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
			
# A client will only roll once
func roll_for_who_goes_first():
	# Determine who goes first by rolling for it
	# Upate player_turn var from server?
	chat_log.append_text("[font_size=%s]\nRoll for turn order!" % chat_log_font_size)
	
	var turn_order = []
	for player in ALL_PLAYERS:
		if player.type == "Player":
			await roll_dice_btn.pressed # Wait for user to roll dice before continuing
			player.dice_roll_result = _on_roll_dice_pressed()
			turn_order.append([player.dice_roll_result, player])
			
			# Update the chat log
			var fmt_str = "[font_size=%s]\nPlayer %s rolled a %s"
			var act_str = fmt_str % [chat_log_font_size, player.id, player.dice_roll_result]
			chat_log.append_text(act_str)
		else:
			player.dice_roll_result = _on_roll_dice_pressed()
			turn_order.append([player.dice_roll_result, player])
			var fmt_str = "[font_size=%s]\nPlayer %s rolled a %s"
			var act_str = fmt_str % [chat_log_font_size, player.id, player.dice_roll_result]
			chat_log.append_text(act_str)
		GLOBAL_TURN_NUM += 1
		
		
	turn_order.sort_custom(custom_sort_for_first_roll)
	

	for i in ALL_PLAYERS.size():
		ALL_PLAYERS[i] = turn_order[i][1]
		if ALL_PLAYERS[i].type == "Player":
			CLIENT_INDEX = i
		# Store bot indexes too?

	
	chat_log.append_text("\n")
	for i in ALL_PLAYERS.size():
		var fmt_str = "[font_size=%s]\n%s %s goes %s!"
		var act_str = fmt_str % [chat_log_font_size, ALL_PLAYERS[i].type, ALL_PLAYERS[i].id, i+1]
		chat_log.append_text(act_str)
		
	is_roll_for_turn = false
	GLOBAL_TURN_NUM = 1

func custom_sort_for_first_roll(a: Array, b: Array):
	if a[0] > b[0]:
		return true
	elif a[0] == b[0]:
		return false
	return false

# A normal turn
	# Roll dice, roll_dice() -> send result to server
		# If server returns robber, robber()
		# Else if server returns non-7 roll, generate_resources() -> check if tile is robbed
	# Trade/Build/Play Development Card
		# Trade with bank, trade_bank()
		# Trade with other players, trade_players() -> send trade to server
		# Build road, build_road() -> check for longest road (and win)
		# Build settlement, build_settlement() -> check for win
		# Build city, build_city() -> check for win
		# Buy development card, build_development()
			# If VP card, check for win
		# Play development card
			# Knight, play_knight() -> check for largest army (and win)
			# Road, play_road() -> check for longest road (and win)
			# Year of Plenty, play_year_of_plenty()
			# Monopoly, play_monopoly()
	
	# All functions require a sync to the server!

# TODO
func activate_robber():
	pass

# Sets certain UI buttons/elements as "active"/"not disabled" if the player meets the resource requirement for them,
# indicating that they can afford the respective thing (settlement, city, road, development card, etc.)
# Call this anytime after a player modifies their resources in any way (dice roll, dev card, trading, etc.)
func activate_or_deactivate_ui_buttons():
	# Road
	var build_road_button_state = false if CLIENT.resources["Brick"] >= 1 and CLIENT.resources["Tree"] >= 1 else true
	$UILayer/Build_Road_Btn_Background/Build_Road_Button.disabled = build_road_button_state
	$UILayer/Build_Road_Btn_Background/Disabled_Mask.visible = build_road_button_state
	
	# Settlement
	var build_settlement_button_state = false if CLIENT.resources["Brick"] >= 1 and CLIENT.resources["Tree"] >= 1 and CLIENT.resources["Wheat"] >= 1 and CLIENT.resources["Sheep"] >= 1 else true
	$UILayer/Build_Settlement_Btn_Background/Build_Settlement_Button.disabled = build_settlement_button_state
	$UILayer/Build_Settlement_Btn_Background/Disabled_Mask.visible = build_settlement_button_state
	
	# City
	var build_city_button_state = false if CLIENT.resources["Wheat"] >= 2 and CLIENT.resources["Stone"] >= 3 else true
	$UILayer/Build_City_Btn_Background/Build_City_Button.disabled = build_city_button_state
	$UILayer/Build_City_Btn_Background/Disabled_Mask.visible = build_city_button_state
	
	# Development Card
	var buy_dev_card_button_state = false if CLIENT.resources["Wheat"] >= 1 and CLIENT.resources["Stone"] >= 1 and CLIENT.resources["Sheep"] >= 1 else true
	$UILayer/Buy_Development_Card_Background/Buy_Development_Card_Button.disabled = buy_dev_card_button_state
	$UILayer/Buy_Development_Card_Background/Disabled_Mask.visible = buy_dev_card_button_state
	
	# Bank Trade
	var bank_trade_button_state = false if CLIENT.resources["Brick"] >= 4 or CLIENT.resources["Tree"] >= 4 or CLIENT.resources["Sheep"] >= 4 or CLIENT.resources["Wheat"] >= 4 or CLIENT.resources["Stone"] >= 4 else true
	$UILayer/Bank_Trade_Btn_Background/Trade_Button.disabled = bank_trade_button_state
	$UILayer/Bank_Trade_Btn_Background/Disabled_Mask.visible = bank_trade_button_state
	
	# Players can offer up trades where they don't offer anything, so that button will always be active/enabled

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

func bot_decision_loop(player):
	# Figure out which bot this is, based on global_turn_num

	# If resource met and no viable settlement/city placements, then build road
	bot_build_road(player)
		
	# else, prioritize building a city then settlement
		
	# use development cards if needed
	# go for longest road if close

func bot_build_road(player):
	var read_ALL_ROAD_MIDPOINTS = ALL_ROAD_MIDPOINTS.duplicate(true)
	
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
			var placement_account_for_offset = (all_possible_road_placements[j] + Vector2(-10, -3.5))
			if placement_account_for_offset in ALL_OWNED_ROADS[i]:
				elements_to_remove.append(all_possible_road_placements[j])
	for i in range(len(elements_to_remove)):
		if elements_to_remove[i] in all_possible_road_placements:
			all_possible_road_placements.remove_at(all_possible_road_placements.find(elements_to_remove[i]))
		
		
# Should only be allowed to be pressed if correct resources have been met, see activate_or_deactive_ui_buttons()
func _on_build_road_button_pressed() -> void:
	print("Build road button pressed.")
	
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
			var placement_account_for_offset = (all_possible_road_placements[j] + Vector2(-10, -3.5))
			if placement_account_for_offset in ALL_OWNED_ROADS[i]:
				elements_to_remove.append(all_possible_road_placements[j])
	for i in range(len(elements_to_remove)):
		if elements_to_remove[i] in all_possible_road_placements:
			all_possible_road_placements.remove_at(all_possible_road_placements.find(elements_to_remove[i]))
	
	# Display the UI elements
	for vertex in all_possible_road_placements:
		var road_ui_btn_offset = Vector2(-10, -3.5)
		
		var curr_UI_element = $MapLayer/Possible_Placement_Road.duplicate()
		$MapLayer.add_child(curr_UI_element, true)
		curr_UI_element.show()
		curr_UI_element.position = vertex + road_ui_btn_offset

		curr_UI_element.pressed.connect(road_placement_pressed.bind(curr_UI_element, vertex))
	
	await selection_finished
	
	# Remove UI elements
	var i = 2
	for node in get_node("MapLayer").get_children():
		if node.name == "Possible_Placement_Road%s" % i:
			i+=1
			node.queue_free()
			
	# Remove resources from player and from resource bar
	CLIENT.resources["Tree"] -= 1
	CLIENT.resources["Brick"] -= 1
	
	ui_remove_from_resource_bar("Tree")
	ui_remove_from_resource_bar("Brick")
	
	ui_add_resource_to_supply("Tree")
	ui_add_resource_to_supply("Brick")
	
	activate_or_deactivate_ui_buttons()
	
func road_placement_pressed(midpoint_btn_node, road_midpoint):
	# When the midpoint button is pressed -- show a road between the two points and add that point as a road to this player
	var road_ui_offset = Vector2(-25, 7.5)
	
	var ui_element_for_road = $MapLayer/Player1_Road.duplicate()
	$MapLayer.add_child(ui_element_for_road)
	ui_element_for_road.show()
	ui_element_for_road.pivot_offset = Vector2(ui_element_for_road.size.x / 2, ui_element_for_road.size.y / 2)
	ui_element_for_road.position = midpoint_btn_node.position + road_ui_offset # Place road at midpoint then rotate
	
	CLIENT.roads.append(midpoint_btn_node.position)
	ALL_OWNED_ROADS[CLIENT_INDEX] = CLIENT.roads
	
	check_for_longest_road()
	
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
	
	emit_signal("selection_finished")

# Should only be allowed to be pressed if correct resources have been met, see activate_or_deactive_ui_buttons()
func _on_build_settlement_button_pressed() -> void:
	print("build settlement button pressed")
	
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
	CLIENT.resources["Brick"] -= 1
	CLIENT.resources["Wheat"] -= 1
	CLIENT.resources["Sheep"] -= 1
	
	ui_remove_from_resource_bar("Tree")
	ui_remove_from_resource_bar("Brick")
	ui_remove_from_resource_bar("Wheat")
	ui_remove_from_resource_bar("Sheep")
	
	ui_add_resource_to_supply("Tree")
	ui_add_resource_to_supply("Brick")
	ui_add_resource_to_supply("Wheat")
	ui_add_resource_to_supply("Sheep")
	
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
	
	# Add settlement (position) to player, save selections, will need after placing road to remove
	CLIENT.settlements.append(vertex)
	CLIENT.last_vertex_selected = vertex
	CLIENT.last_node_selected = node
	CLIENT.vp += 1
	ui_update_vp()
	
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
	ui_remove_from_resource_bar("Stone")
	ui_add_resource_to_supply("Stone")
	CLIENT.resources["Stone"] -= 1
	ui_remove_from_resource_bar("Stone")
	ui_add_resource_to_supply("Stone")
	CLIENT.resources["Stone"] -= 1
	ui_remove_from_resource_bar("Stone")
	ui_add_resource_to_supply("Stone")
	CLIENT.resources["Wheat"] -= 1
	ui_remove_from_resource_bar("Wheat")
	ui_add_resource_to_supply("Wheat")
	CLIENT.resources["Wheat"] -= 1
	ui_remove_from_resource_bar("Wheat")
	ui_add_resource_to_supply("Wheat")
	
	activate_or_deactivate_ui_buttons()

func city_button_pressed(node, vertex):
	# Remove the settlement that is here, both in the UI and from the player's data
	print(len(CLIENT.settlements))
	CLIENT.settlements.remove_at(CLIENT.settlements.find(vertex))
	print(len(CLIENT.settlements))
	var i = 2
	for n in get_node("MapLayer").get_children():
		if n.get_class() == "TextureRect":
			if n.position == (vertex + Vector2(-15, -15) + Vector2(-12, -9)):
				n.queue_free()
	
	CLIENT.cities.append(vertex)
	CLIENT.vp += 1
	ui_update_vp()
	
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
			print("generate resource for player")
			var resources = []
			for i in range(len(p.settlements)):
				for j in range(len(tile_positions_local)):
					# Should be the three closest tiles, where pos is the center of the tile
					var distance = sqrt(((tile_positions_local[j].x - p.settlements[i].x)**2) + ((tile_positions_local[j].y - p.settlements[i].y)**2))
					if distance < 75:
						# Get the tiles atlas id and use the mapping
						var resource_num_source_id = resource_num_map_layer.get_cell_source_id(tile_positions[j])
						if resource_num_source_id == -1:
							continue
						if RESOURCE_NUM_MAPPING[resource_num_source_id] == dice_result:
							resources.append(map_data.get_cell_source_id(tile_positions[j]))
							
			# Do a lookup to mapping dict and add to player's resource dict
			var UI_offset = global_ui_resource_offset
			for id in resources:
				if id == 6: # Skip desert tile
					continue
				var resource = SOURCE_ID_TO_RESOURCE_MAPPING[id]
				if ui_remove_resource_from_supply(resource) == true:
					p.resources[resource] += 1
					ui_add_to_resource_bar(resource)
					
		elif p.type == "Bot":
			print("generate resource for bot: ", p._name)
			var resources = []
			for i in range(len(p.settlements)):
				for j in range(len(tile_positions_local)):
					# Should be the three closest tiles, where pos is the center of the tile
					var distance = sqrt(((tile_positions_local[j].x - p.settlements[i].x)**2) + ((tile_positions_local[j].y - p.settlements[i].y)**2))
					if distance < 75:
						# Get the tiles atlas id and use the mapping
						var resource_num_source_id = resource_num_map_layer.get_cell_source_id(tile_positions[j])
						if resource_num_source_id == -1:
							continue
						if RESOURCE_NUM_MAPPING[resource_num_source_id] == dice_result:
							resources.append(map_data.get_cell_source_id(tile_positions[j]))
							
			# Do a lookup to mapping dict and add to player's resource dict
			for id in resources:
				if id == 6: # Skip desert tile
					continue
				var resource = SOURCE_ID_TO_RESOURCE_MAPPING[id]
				if ui_remove_resource_from_supply(resource) == true:
					p.resources[resource] += 1
			print(p.resources)
			
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
					ui_add_to_resource_bar(resource)
		
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
		
		print(CLIENT.PLAYER_RESOURCE_BAR_POSITIONS)
		
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
func tile_map_coords_to_local_coords(tile_map, tile_positions) -> Array:
	var local_coords = []
	for pos in tile_positions:
		local_coords.append(tile_map.map_to_local(pos) + DEBUG_map_vertex_offset)
	return local_coords

# A client will only do this once when it is their turn, bot functionality is added here for testing
func place_initial_settlements_and_roads(p):
	

	# If it is the client's turn and the client is not a bot
	if p.type == "Player":
		var fmt_str = "[font_size=%s]\n%s place a settlement and road."
		var act_str = fmt_str % [chat_log_font_size, p._name]
		chat_log.append_text(act_str)
		
		for node in get_tree().get_nodes_in_group("UI_settlement_buttons"):
			node.show()
		
		# Await a timer timeout -- timeout the timer in settlement_placement_pressed() when a settlement is chosen before the timer runs out.
		# otherwise, if timer runs out before settlement is chosen, place settlement randomly for this player using GLOBAL_TURN_NUM
		$MapLayer/Player1_Settlement_Timer.start()
		await selection_finished # Wait for user input, else timer will timeout and do the same stuff as below
		$MapLayer/Player1_Settlement_Timer.stop()
		
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
		var fmt_str = "[font_size=%s]\n%s place a settlement and road."
		var act_str = fmt_str % [chat_log_font_size, p._name]
		chat_log.append_text(act_str)

		await bot_place_initial_settlement(p)
		
		emit_signal("end_turn")

func possible_road_placements_setup_phase(settlement_pos) -> void:
	# Given a single point -- find all possible road placements branching from it using distance formula
	
	var road_ui_btn_offset = Vector2(-10, -3.5)
	
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
	var road_ui_offset = Vector2(-25, 7.5)
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
	
	ALL_OWNED_ROADS[ALL_PLAYERS.find(player)].append(chosen_road + Vector2(-10, -3.5))
	
	var road_ui_offset = Vector2(-25, 7.5) + Vector2(-10, -3.5)
	$MapLayer.add_child(ui_element_for_road)
	ui_element_for_road.show()
	ui_element_for_road.pivot_offset = Vector2(ui_element_for_road.size.x / 2, ui_element_for_road.size.y / 2)
	ui_element_for_road.position = chosen_road + road_ui_offset # Place road at midpoint then rotate
	
	# Use slope and arctan between two points to calculate how to rotate the UI element
	var slope = ((chosen_road.y - settlement_pos.y) / (chosen_road.x - settlement_pos.x))
	var degrees = rad_to_deg(atan(slope))
	ui_element_for_road.rotation_degrees = degrees

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
		curr_UI_element.pressed.connect(settlement_placement_pressed_setup_phase.bind(curr_UI_element.name, GLOBAL_TURN_NUM, vertex))

# Should only fire if logic from place_initial_settlements() is correct
func settlement_placement_pressed_setup_phase(id, global_turn_num, vertex_selection):
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
	
	# Add settlement (position) to player, save selections, will need after placing road to remove
	CLIENT.settlements.append(vertex_selection)
	CLIENT.last_vertex_selected = vertex_selection
	CLIENT.last_node_selected = selected_node
	
	emit_signal("selection_finished")

func _on_player_1_settlement_timer_non_timeout() -> void:
	$MapLayer/Player1_Settlement_Timer.stop()
	print("Timer exited early due to settlement placement, returning to function...")

func _on_player_1_settlement_timer_timeout() -> void:
	# If timer runs out place settlement randomly
	$MapLayer/Player1_Settlement_Timer.stop()
	print("Timer done, placing random settlement...")
	
	var rand_index = randi_range(0, len(ELIGIBLE_SETTLEMENT_VERTICES))
	# Add random settlement as UI element
	var offset_position = Vector2(-15, -15)
	var selected_node_position = ELIGIBLE_SETTLEMENT_VERTICES[rand_index]
	var ui_element_for_selected_settlement = $MapLayer/Player1_Settlement.duplicate()
	$MapLayer.add_child(ui_element_for_selected_settlement)
	ui_element_for_selected_settlement.show()
	ui_element_for_selected_settlement.position = selected_node_position + offset_position
	
	# Add settlement to player
	CLIENT.settlements.append(selected_node_position)
	
	# Update eligible vertices
	var selected_node
	for node in get_node("MapLayer").get_children(): # node.position is offset
		if "TextureButton" in node.name:
			if node.position == (selected_node_position + Vector2(-12, -9)):
				selected_node = node
	
	update_eligible_settlement_vertices(selected_node_position, selected_node)
	
	# Return to main function
	emit_signal("selection_finished")

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
		roll_dice_btn.text = "Rolled a " + str(result_1 + result_2) + " (" + str(result_1) + "," + str(result_2) + ")"
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
			end_game()

func end_game():
	print("Game over!")
