extends Node2D

# UI
@onready var standard_map = $MapLayer/StandardMap
@onready var resource_num_map_layer = $MapLayer/ResourceNumbers
@onready var harbor_map_layer = $MapLayer/Harbors
@onready var roll_dice_btn = $UILayer/Roll_Dice
@onready var chat_log = $UILayer/Chat/Chat_Log
@export var chat_log_font_size = 30

# Game state variables
@onready var global_vertices = null
@onready var VP = 0
@onready var NUM_PLAYERS = 4 # Server side variable
@onready var GLOBAL_TURN_NUM = 1 # Server side variable, all clients will have the same value
@onready var PLAYER_NUM = 1 # Client/server side variable, unique to this client
@onready var PLAYER_TURN_NUM = 1 # What turn does this player go on
@onready var DIE_ROLL_NUM = 0 # Client variable, gets sent to server
@onready var is_roll_for_turn = true
@onready var is_initial_settlements = true
@onready var PLAYER_SETTLEMENTS = [] # Holds the positions of all settlements this player owns
@onready var PLAYER_ROAD_GRAPHS = [] # Holds the positions of all connected points branching out from a settlement/city
									  # example: [[(0,0), (0,1), (0,2)], [()], []] 
@onready var PLAYER_COUNT = 4 # Will never be less than 2, and for now, more than 4
@onready var PLAYER_LAST_VERTEX_SELECTED = null
@onready var PLAYER_LAST_NODE_SELECTED = null

# Debug vars
@export var DEBUG_map_vertex_offset = Vector2(905, 671) # For the map vertices

# Server side simulated variables
@onready var BOT_1_PLAYER_NUM = 2
@onready var BOT_2_PLAYER_NUM = 3
@onready var BOT_3_PLAYER_NUM = 4
@onready var BOT_1_DIE_ROLL_NUM = 0
@onready var BOT_2_DIE_ROLL_NUM = 0
@onready var BOT_3_DIE_ROLL_NUM = 0
@onready var BOT_1_TURN_NUM = 2
@onready var BOT_2_TURN_NUM = 3
@onready var BOT_3_TURN_NUM = 4
@onready var BOT_1_SETTLEMENTS = []
@onready var BOT_2_SETTLEMENTS = []
@onready var BOT_3_SETTLEMENTS = []
@onready var BOT_1_LAST_VERTEX_SELECTED = null
@onready var BOT_1_LAST_NODE_SELECTED = null
@onready var BOT_2_LAST_VERTEX_SELECTED = null
@onready var BOT_2_LAST_NODE_SELECTED = null
@onready var BOT_3_LAST_VERTEX_SELECTED = null
@onready var BOT_3_LAST_NODE_SELECTED = null
@onready var ELIGIBLE_SETTLEMENT_VERTICES = [] # Contains a list of eligible vertices for settlement placement. This is shared between all players
@onready var ELIGIBLE_ROAD_VERTICES = [] # Contains a list of eligible vertices to connect a road from an original vertex. For example -- a settlement may be on a vertex and prevent settlement placement but a road could still be placed by another player that "touches" that settlement

# Signals
signal selection_finished # Used for returning control back to a main function after a user selects an action or they timeout from that action
signal end_turn # Used for signaling that a player or bots turn is over, usually used in the main game loop

func _ready() -> void:
	randomize() # Initializes randomizer, only call this once
	var tile_positions = generate_rand_standard_map() # Map data contains coordinates of all cells of the map
	
	global_vertices = generate_tile_vertices(tile_positions, standard_map)
	ELIGIBLE_SETTLEMENT_VERTICES = global_vertices # At the beginning of the game, all vertices are eligible
	_draw()
	init_settlement_buttons(global_vertices)
	
	# Initialize chat box setting(s)
	chat_log.append_text("[font_size=%s]Welcome to Canaan!" % chat_log_font_size)
	
	## Main game loop for a client
	#while true:
		#pass
	await roll_for_who_goes_first()
	# Place initial settlements and roads for all players
	# First round
	for i in range(PLAYER_COUNT):
		await place_initial_settlements_and_roads(GLOBAL_TURN_NUM)
		GLOBAL_TURN_NUM += 1
		if GLOBAL_TURN_NUM > PLAYER_COUNT:
			GLOBAL_TURN_NUM = PLAYER_COUNT
			break
	# Second round
	for i in range(PLAYER_COUNT):

		await place_initial_settlements_and_roads(GLOBAL_TURN_NUM)
		GLOBAL_TURN_NUM -= 1
		if GLOBAL_TURN_NUM < 1:
			GLOBAL_TURN_NUM = 1
			break
	chat_log.append_text("[font_size=%s]\nAll players done placing settlements and roads." % chat_log_font_size)

# Debug func
func _draw():
	for x in ELIGIBLE_SETTLEMENT_VERTICES:
		draw_circle(x, 5, Color(Color.RED), 5.0)

func add_player_to_game():
	# Determine if player is bot or real
	# For now, bots (4 of them)
	pass

# A client will only roll once
func roll_for_who_goes_first():
	# Determine who goes first by rolling for it
	# Upate player_turn var from server?
	chat_log.append_text("[font_size=%s]\nRoll for turn order!" % chat_log_font_size)
	
	var turn_order: Array[Vector2i] = []
	for i in range(1, NUM_PLAYERS + 1): # This will end up as server code
		# Server: hide all dice button presses for all other players who aren't rolling
		# Bots will automatically roll dice
		
		# If it is this client's turn
		if PLAYER_NUM == GLOBAL_TURN_NUM:
			await roll_dice_btn.pressed # Wait for user to roll dice before continuing
			DIE_ROLL_NUM = _on_roll_dice_pressed()
			turn_order.append(Vector2i(DIE_ROLL_NUM, PLAYER_NUM))
			
			# Update the chat log
			var fmt_str = "[font_size=%s]\nPlayer %s rolled a %s"
			var act_str = fmt_str % [chat_log_font_size, PLAYER_NUM, DIE_ROLL_NUM]
			chat_log.append_text(act_str)
		elif BOT_1_PLAYER_NUM == GLOBAL_TURN_NUM: # Server: either a bot will roll or a player. For now, only bots, so simulate their rolls
			BOT_1_DIE_ROLL_NUM = _on_roll_dice_pressed()
			turn_order.append(Vector2i(BOT_1_DIE_ROLL_NUM, BOT_1_PLAYER_NUM))
			var fmt_str = "[font_size=%s]\nPlayer %s rolled a %s"
			var act_str = fmt_str % [chat_log_font_size, BOT_1_PLAYER_NUM, BOT_1_DIE_ROLL_NUM]
			chat_log.append_text(act_str)
		elif BOT_2_PLAYER_NUM == GLOBAL_TURN_NUM:
			BOT_2_DIE_ROLL_NUM = _on_roll_dice_pressed()
			turn_order.append(Vector2i(BOT_2_DIE_ROLL_NUM, BOT_2_PLAYER_NUM))
			var fmt_str = "[font_size=%s]\nPlayer %s rolled a %s"
			var act_str = fmt_str % [chat_log_font_size, BOT_2_PLAYER_NUM, BOT_2_DIE_ROLL_NUM]
			chat_log.append_text(act_str)
		elif BOT_3_PLAYER_NUM == GLOBAL_TURN_NUM: 
			BOT_3_DIE_ROLL_NUM = _on_roll_dice_pressed()
			turn_order.append(Vector2i(BOT_3_DIE_ROLL_NUM, BOT_3_PLAYER_NUM))
			var fmt_str = "[font_size=%s]\nPlayer %s rolled a %s"
			var act_str = fmt_str % [chat_log_font_size, BOT_3_PLAYER_NUM, BOT_3_DIE_ROLL_NUM]
			chat_log.append_text(act_str)
		GLOBAL_TURN_NUM += 1
		
	turn_order.sort_custom(custom_sort_for_first_roll)
	
	# turn_order[i].y will be a players_id, so assign player turn nums from that
	for i in range(len(turn_order)):
		if turn_order[i].y == PLAYER_NUM:
			PLAYER_TURN_NUM = i+1
		elif turn_order[i].y == BOT_1_TURN_NUM:
			BOT_1_TURN_NUM = i+1
		elif turn_order[i].y == BOT_2_TURN_NUM:
			BOT_2_TURN_NUM = i+1
		elif turn_order[i].y == BOT_3_TURN_NUM:
			BOT_3_TURN_NUM = i+1
	
	chat_log.append_text("\n")
	for i in range(len(turn_order)):
		var placement_str = ""
		if i == 0:
			placement_str = "first"
		elif i == 1:
			placement_str = "second"
		elif i == 2:
			placement_str = "third"
		elif i == 3:
			placement_str = "fourth"
		var fmt_str = "[font_size=%s]\nPlayer %s goes %s!"
		var act_str = fmt_str % [chat_log_font_size, turn_order[i].y, placement_str]
		chat_log.append_text(act_str)
		
	is_roll_for_turn = false
	GLOBAL_TURN_NUM = 1

func custom_sort_for_first_roll(a, b):
	if a.x > b.x:
		return true
	elif a.x == b.x:
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

# A client will only do this once when it is their turn, bot functionality is added here for testing
func place_initial_settlements_and_roads(GLOBAL_TURN_NUM):
	
	# If it is the client's turn and the client is not a bot
	if GLOBAL_TURN_NUM == PLAYER_TURN_NUM:
		var fmt_str = "[font_size=%s]\nPlayer %s place a settlement and road."
		var act_str = fmt_str % [chat_log_font_size, PLAYER_NUM]
		chat_log.append_text(act_str)
		print("player turn")
		
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
		var settlement_pos = PLAYER_SETTLEMENTS.back()
		init_possible_road_placements(settlement_pos)
		await selection_finished

		var i = 2
		for node in get_node("MapLayer").get_children():
			if node.name == "Possible_Placement_Road%s" % i:
				i+=1
				node.queue_free()
		emit_signal("end_turn")
		return
		
	# If the client is a bot
	elif GLOBAL_TURN_NUM == BOT_1_TURN_NUM:
		var fmt_str = "[font_size=%s]\nBot %s place a settlement and road."
		var act_str = fmt_str % [chat_log_font_size, BOT_1_PLAYER_NUM]
		chat_log.append_text(act_str)
		print("Bot 1 turn")
		
		await bot_place_initial_settlement(GLOBAL_TURN_NUM, BOT_1_SETTLEMENTS)
		
		print("bot 1 turn done")
		emit_signal("end_turn")
	elif GLOBAL_TURN_NUM == BOT_2_TURN_NUM:
		var fmt_str = "[font_size=%s]\nBot %s place a settlement and road."
		var act_str = fmt_str % [chat_log_font_size, BOT_2_PLAYER_NUM]
		chat_log.append_text(act_str)
		print("Bot 2 turn")
		
		await bot_place_initial_settlement(GLOBAL_TURN_NUM, BOT_2_SETTLEMENTS)
		
		print("bot 2 turn done")
		emit_signal("end_turn")
	elif GLOBAL_TURN_NUM == BOT_3_TURN_NUM:
		var fmt_str = "[font_size=%s]\nBot %s place a settlement and road."
		var act_str = fmt_str % [chat_log_font_size, BOT_3_PLAYER_NUM]
		chat_log.append_text(act_str)
		print("Bot 3 turn")

		await bot_place_initial_settlement(GLOBAL_TURN_NUM, BOT_3_SETTLEMENTS)
		
		print("bot 3 turn done")
		emit_signal("end_turn")
		
func init_possible_road_placements(settlement_pos) -> void:
	# Given a single point -- find all possible road placements branching from it using distance formula
	# TODO: take into account own player and other players roads/settlements/cities
	
	var road_ui_btn_offset = Vector2(-10, -3.5)
	
	for vertex in ELIGIBLE_SETTLEMENT_VERTICES:
		var distance = sqrt(((vertex.x - settlement_pos.x)**2) + ((vertex.y - settlement_pos.y)**2))
		if distance > 45 and distance < 95:
			# Find midpoint to place UI element
			var midpoint = Vector2(((vertex.x + settlement_pos.x) / 2), ((vertex.y + settlement_pos.y) / 2))
			var curr_UI_element = $MapLayer/Possible_Placement_Road.duplicate()
			$MapLayer.add_child(curr_UI_element, true)
			curr_UI_element.show()
			curr_UI_element.position = midpoint + road_ui_btn_offset
			# Passed vertex here is the vertex that connects the settlement vertex to the next vertex
			curr_UI_element.pressed.connect(road_placement_pressed.bind(curr_UI_element, GLOBAL_TURN_NUM, vertex, settlement_pos))

func road_placement_pressed(midpoint_btn_node, GLOBAL_TURN_NUM, connected_vertex, settlement_vertex):
	
	# When the midpoint button is pressed -- show a road between the two points and add those two points as a road to this player
	var road_ui_offset = Vector2(-25, 7.5)
	var ui_element_for_road = $MapLayer/Player1_Road.duplicate()
	$MapLayer.add_child(ui_element_for_road)
	ui_element_for_road.show()
	ui_element_for_road.pivot_offset = Vector2(ui_element_for_road.size.x / 2, ui_element_for_road.size.y / 2)
	ui_element_for_road.position = midpoint_btn_node.position + road_ui_offset # Place road at midpoint then rotate
	
	# Use slope and arctan between two points to calculate how to rotate the UI element
	var slope = ((connected_vertex.y - settlement_vertex.y) / (connected_vertex.x - settlement_vertex.x))
	var degrees = rad_to_deg(atan(slope))
	ui_element_for_road.rotation_degrees = degrees
	
	
	update_eligible_settlement_vertices(PLAYER_LAST_VERTEX_SELECTED, PLAYER_LAST_NODE_SELECTED)
	
	emit_signal("selection_finished")

func bot_place_initial_road(settlement_pos, GLOBAL_TURN_NUM) -> void:
	var eligible_road_placements = []
	for vertex in ELIGIBLE_SETTLEMENT_VERTICES:
		var distance = sqrt(((vertex.x - settlement_pos.x)**2) + ((vertex.y - settlement_pos.y)**2))
		if distance > 50 and distance < 75: # May need to slightly adjust this range
			# Find midpoint to place UI element
			eligible_road_placements.append(vertex)
	var rand_num = randi_range(0, len(eligible_road_placements)-1)
	var chosen_road = eligible_road_placements[rand_num]
	var midpoint = Vector2(((chosen_road.x + settlement_pos.x) / 2), ((chosen_road.y + settlement_pos.y) / 2))
	
	var road_ui_offset = Vector2(-25, 7.5) + Vector2(-10, -3.5)
	var ui_element_for_road = $MapLayer/Player1_Road.duplicate()
	$MapLayer.add_child(ui_element_for_road)
	ui_element_for_road.show()
	ui_element_for_road.pivot_offset = Vector2(ui_element_for_road.size.x / 2, ui_element_for_road.size.y / 2)
	ui_element_for_road.position = midpoint + road_ui_offset # Place road at midpoint then rotate
	
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
		curr_UI_element.tooltip_text = str(vertex + settlement_placement_offset) # DEBUG!
		curr_UI_element.hide()
		curr_UI_element.position = vertex + settlement_placement_offset
		curr_UI_element.pressed.connect(settlement_placement_pressed.bind(curr_UI_element.name, GLOBAL_TURN_NUM, vertex))

# Should only fire if logic from place_initial_settlements() is correct
func settlement_placement_pressed(id, global_turn_num, vertex_selection):
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
	print(selected_node_position)
	
	# Add settlement (position) to player, save selections, will need after placing road to remove
	PLAYER_SETTLEMENTS.append(vertex_selection)
	PLAYER_LAST_VERTEX_SELECTED = vertex_selection
	PLAYER_LAST_NODE_SELECTED = selected_node
	
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
	PLAYER_SETTLEMENTS.append(selected_node_position)
	
	# Update eligible vertices
	var selected_node
	for node in get_node("MapLayer").get_children(): # node.position is offset
		if "TextureButton" in node.name:
			if node.position == (selected_node_position + Vector2(-12, -9)):
				selected_node = node
	
	update_eligible_settlement_vertices(selected_node_position, selected_node)
	
	# Return to main function
	emit_signal("selection_finished")

# Use Global turn num to match texture to correct bot (player too?)
func bot_place_initial_settlement(GLOBAL_TURN_NUM, BOT_SETTLEMENT_ARRAY) -> void:
	var rand_index = randi_range(0, len(ELIGIBLE_SETTLEMENT_VERTICES)-1)
	# Add random settlement as UI element
	var offset_position = Vector2(-15, -15) + Vector2(-12, -9)
	var selected_node_position = ELIGIBLE_SETTLEMENT_VERTICES[rand_index]
	var ui_element_for_selected_settlement = $MapLayer/Player1_Settlement.duplicate()
	$MapLayer.add_child(ui_element_for_selected_settlement)
	ui_element_for_selected_settlement.show()
	ui_element_for_selected_settlement.position = selected_node_position + offset_position
	print(selected_node_position)
	
	# Add settlement to bot
	BOT_SETTLEMENT_ARRAY.append(selected_node_position)
	
	var selected_node
	for node in get_node("MapLayer").get_children(): # node.position is offset by Vector2(-12, -9)
		if "TextureButton" in node.name:
			var distance = sqrt(((node.position.x - (selected_node_position + Vector2(-12, -9)).x)**2) + ((node.position.y - (selected_node_position + Vector2(-12, -9)).y)**2))
			#print(distance)
			if distance < 5:
				selected_node = node
				break
	
	bot_place_initial_road(selected_node_position, GLOBAL_TURN_NUM)
	update_eligible_settlement_vertices(selected_node_position, selected_node)
	
	await get_tree().create_timer(2).timeout
	
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
	
	print(ELIGIBLE_SETTLEMENT_VERTICES)
	
	return

func generate_resources():
	pass

# Triggers when a Player selects to build a settlement only
func build_settlement():
	# Add checks for:
		# Vertex is not currently occupied by another settlement?
		# Player has required resources?
		# Settlement placement follows distance rule?
		# Settlement is connected to road owned by correct player?
		# This isn't turn 0 or 1? (Setup phase)
		
	# If successfully built, increment VP and add settlement (visually and to player) and check for win
	pass
	
func build_city():
	pass
	
func build_road():
	pass

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
			global_vertices.append(world_pos + vertex + DEBUG_map_vertex_offset)
	
	global_vertices.sort()
	
	## Deduplicate array
	var elements_to_remove = []
	for i in range(len(global_vertices)):
		for j in range(i+1, len(global_vertices)):
			var distance = get_distance(global_vertices[i], global_vertices[j])
			if distance < 10:
				elements_to_remove.append(global_vertices[j])
	
	#remove the elements...
	for i in range(len(elements_to_remove)):
		if elements_to_remove[i] in global_vertices:
			global_vertices.remove_at(global_vertices.find(elements_to_remove[i]))
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

	
	return possible_placements_read
	
func check_win():
	if VP >= 10:
		end_game()

func end_game():
	pass
