extends Node2D

@onready var standard_map = $MapLayer/StandardMap
@onready var roll_dice_btn = $UILayer/Roll_Dice
@onready var global_vertices = null
@onready var VP = 0

func _ready() -> void:
	randomize() # Initializes randomizer, only call this once
	var tile_positions = generate_rand_standard_map() # Map data contains coordinates of all cells of the map
	
	global_vertices = generate_tile_vertices(tile_positions, standard_map)

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

func check_win():
	if VP >= 10:
		end_game()

func end_game():
	pass
	
func build_city():
	
	pass
	
func build_road():
	
	pass

# Debug func
func _draw():
	for x in global_vertices:
		draw_circle(x, 5, Color(Color.RED), 5.0)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#generate_rand_standard_map()
	#delta = delta / 12
	
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
			global_vertices.append(world_pos + vertex + Vector2(200,550))
	return global_vertices

func roll_dice() -> int:
	return randi_range(1,6)

func _on_roll_dice_pressed() -> void:
	var result_1 = roll_dice()
	var result_2 = roll_dice()
	if result_1 + result_2 == 7:
		roll_dice_btn.text = "ROBBER!"
	else:
		roll_dice_btn.text = "Rolled a " + str(result_1 + result_2) + " (" + str(result_1) + "," + str(result_2) + ")"

# TODO: Add ports and numbers on tiles to map generation
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
	
	var possible_placements: Array[Vector2i] = [
		Vector2i(-2, -3), Vector2i(-1, -3), Vector2i(0, -3),
		Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
		Vector2i(-3, -1), Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1)
	]
	
	var possible_placements_read: Array[Vector2i] = [
		Vector2i(-2, -3), Vector2i(-1, -3), Vector2i(0, -3),
		Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
		Vector2i(-3, -1), Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1)
	]
	
	# Place tiles randomly, removing the selections from the list of possible placements each time
	# And assigning a random resource number, also removing from the list of possibilities each time
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
	standard_map.set_cell(possible_placements[0], 6, Vector2i(0,0))
	
	return possible_placements_read
