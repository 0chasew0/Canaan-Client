extends Node


@onready var game_scene_mp = preload("res://scenes/multiplayer/mp_canaan.tscn")
@onready var game_scene_sp = preload("res://scenes/canaan.tscn")

const DEV = true

var peer = ENetMultiplayerPeer.new()
var url : String = "209.38.137.131"
const PORT = 9009

var _players_spawn_node

var connected_peer_ids = []
var PLAYER_COUNT = 0

func _ready():
	if DEV == true:
		url = "127.0.0.1"
	
# Creates a server, then adds this client as a player
func _on_host_btn_pressed() -> void:
	disable_connection_buttons()
	peer.create_server(9009)
	print("Creating server...")
	multiplayer.multiplayer_peer = peer
	print("Server is up and running.")
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	connected_peer_ids.append(peer.get_unique_id())
	$Lobby/Players.show()
	$Lobby/Player_Name.show()
	$Lobby/Players.text = "[font_size=40][center][color=black]Players Connected: %s" % str(connected_peer_ids)
	$Lobby/Player_Name.text = "[font_size=30][center][color=black]Player Name: Host (Player 1)"
	
	_players_spawn_node = $Players

func _on_join_btn_pressed() -> void:
	disable_connection_buttons()
	peer.create_client(url, PORT)
	multiplayer.multiplayer_peer = peer
	await get_tree().create_timer(1).timeout
	$Lobby/Players.show()
	$Lobby/Player_Name.show()

func _on_peer_connected(new_peer_id : int) -> void:
	print("Player " + str(new_peer_id) + " is joining...")
	await get_tree().create_timer(1).timeout
	
	connected_peer_ids.append(new_peer_id)
	
	print("Player " + str(new_peer_id) + " joined.")
	rpc("_sync_player_list", connected_peer_ids)
	
	
	send_data_to_peers(connected_peer_ids, new_peer_id)

func _on_peer_disconnected(leaving_peer_id : int) -> void:
	print("Player " + str(leaving_peer_id) + " disconnected.")
	connected_peer_ids.remove_at(connected_peer_ids.find(leaving_peer_id))
	print(connected_peer_ids)
	rpc("_sync_player_list", connected_peer_ids)
	
func _on_disconnect_btn_pressed():
	if multiplayer.is_server():
		rpc("kick_all_peers_to_menu")
		for p in connected_peer_ids:
			multiplayer.multiplayer_peer.disconnect_peer(1)
		await get_tree().create_timer(1).timeout
		peer.close()
		print("Shut down server since this is the host client.")
		connected_peer_ids.clear()
		$Lobby/Players.hide()
		$Lobby/Player_Name.hide()
		enable_connection_buttons()
	else:
		multiplayer.multiplayer_peer.disconnect_peer(1)
		await get_tree().create_timer(1).timeout
		$Lobby/Players.hide()
		$Lobby/Player_Name.hide()
		enable_connection_buttons()

@rpc("call_remote")
func kick_all_peers_to_menu():
	$Lobby/Players.hide()
	$Lobby/Player_Name.hide()
	enable_connection_buttons()

@rpc("any_peer", "call_local")
func _sync_player_list(updated_connected_peer_ids):
	connected_peer_ids = updated_connected_peer_ids
	$Lobby/Players.text = "[font_size=40][center][color=black]Players Connected: %s" % str(connected_peer_ids)

@rpc("call_remote")
func get_data_from_host(data, peer_id):
	$Lobby/Player_Name.text = "[font_size=30][center][color=black]Player Name: Player %s" % peer_id

func send_data_to_peers(data, peer_id):
	rpc_id(peer_id, "get_data_from_host", data, peer_id)
	
	
func disable_connection_buttons() -> void:
	$Lobby/HostBtn.hide()
	$Lobby/JoinBtn.hide()
	$Lobby/DisconnectBtn.show()
	if multiplayer.is_server():
		$Lobby/StartBtn.show()	
	
func enable_connection_buttons() -> void:
	$Lobby/HostBtn.show()
	$Lobby/JoinBtn.show()
	$Lobby/DisconnectBtn.hide()
	$Lobby/StartBtn.hide()

func _on_canaan_4_player_pressed() -> void:
	$GameSelect.hide()
	$Lobby.show() # For multiplayer
	

# Add main game scene to peers
#@rpc("call_remote")
#func instantiate_game_for_peers():
	#
	#$Lobby.hide()
	
func _on_start_btn_pressed() -> void:
	var NUM_PLAYERS = len(connected_peer_ids)
	var NUM_BOTS = 4 - len(connected_peer_ids)
	#var game_instance = game_scene_mp.instantiate()
	#add_child(game_instance)
	$Lobby.hide()
	
	var game_instance = game_scene_mp.instantiate()
	_players_spawn_node.add_child(game_instance, true)

	#rpc("instantiate_game_for_peers")
