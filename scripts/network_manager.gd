extends Node

# NetworkManager.gd
# Handles connection lifecycle, player spawning, and high-level networking state.

signal player_list_changed
signal connection_status_changed(status: String)

const DEFAULT_PORT = 10555
const MAX_PLAYERS = 3

# Network State
var multiplayer_peer: WebSocketMultiplayerPeer = null
var players: Dictionary = {} # client_id: Player node reference
var local_player_id: int = 1
var public_ip: String = ""

# Dedicated Server Room State (Only used on Server)
var active_room_code: String = ""
var is_room_game_started: bool = false

# Shared configuration
var start_seed: int = 0
var is_public_lobby: bool = false

@export var player_scene: PackedScene = preload("res://scenes/player.tscn")

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Programmatic spawner to sync player spawning to clients automatically
	var spawner = MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../../Players")
	spawner.add_spawnable_scene("res://scenes/player.tscn")
	add_child(spawner)

## --- Connection Management ---

func host_game(max_players: int = MAX_PLAYERS, port: int = DEFAULT_PORT) -> Error:
	multiplayer_peer = WebSocketMultiplayerPeer.new()
	
	# If running headlessly on Render, read the PORT environment variable.
	var final_port = port
	if DisplayServer.get_name() == "headless":
		var env_port = OS.get_environment("PORT")
		if env_port != "":
			final_port = env_port.to_int()
			print("Dedicated Server: Read Render PORT env var: ", final_port)
			
	var err = multiplayer_peer.create_server(final_port)
	if err != OK:
		connection_status_changed.emit("Échec du démarrage du serveur WebSocket.")
		return err
	
	multiplayer.multiplayer_peer = multiplayer_peer
	local_player_id = 1
	start_seed = Time.get_ticks_msec()
	
	if DisplayServer.get_name() != "headless":
		# Spawn host player (if not a dedicated server)
		_spawn_player(1)
		connection_status_changed.emit("Serveur WebSocket local démarré.")
	else:
		print("Dedicated Server: WebSocket server started on port ", final_port)
		connection_status_changed.emit("Serveur dédié en ligne.")
		
	return OK

func join_game(url: String, port: int = DEFAULT_PORT) -> Error:
	multiplayer_peer = WebSocketMultiplayerPeer.new()
	
	# Determine target URL
	var target_url = url.strip_edges()
	
	# Format URL properly
	if not target_url.begins_with("ws://") and not target_url.begins_with("wss://"):
		if target_url.split(".").size() == 4 or target_url == "localhost" or target_url == "127.0.0.1":
			target_url = "ws://" + target_url + ":" + str(port)
		else:
			target_url = "wss://" + target_url
			
	print("Connecting to WebSocket URL: ", target_url)
	var err = multiplayer_peer.create_client(target_url)
	if err != OK:
		connection_status_changed.emit("Échec de l'initialisation du client WebSocket.")
		return err
	
	multiplayer.multiplayer_peer = multiplayer_peer
	local_player_id = multiplayer.get_unique_id()
	
	var game_node = get_node_or_null("/root/Game")
	if game_node and game_node.is_quick_playing:
		connection_status_changed.emit("Connexion au monde...")
	else:
		connection_status_changed.emit("Connexion au salon en cours...")
	return OK

func disconnect_game() -> void:
	if multiplayer_peer and multiplayer.is_server():
		clear_public_lobby_ip()
	if multiplayer_peer:
		multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	connection_status_changed.emit("Déconnecté.")

## --- Matchmaker & HTTP Registry ---

const MATCHMAKER_APP_KEY = "se2p1tdx"
const MATCHMAKER_KEY = "active_lobby"

# Helpers to convert IP address to integer string and vice-versa
# to prevent dots in the URL path breaking IIS/ASP.NET routing.
func ip_to_int_str(ip: String) -> String:
	var parts = ip.split(".")
	if parts.size() != 4:
		return "0"
	var val = (int(parts[0]) << 24) + (int(parts[1]) << 16) + (int(parts[2]) << 8) + int(parts[3])
	return str(val)

func int_str_to_ip(val_str: String) -> String:
	var clean_str = val_str.replace("\"", "").strip_edges()
	var val = clean_str.to_int()
	if val <= 0:
		return ""
	var octet1 = (val >> 24) & 255
	var octet2 = (val >> 16) & 255
	var octet3 = (val >> 8) & 255
	var octet4 = val & 255
	return "%d.%d.%d.%d" % [octet1, octet2, octet3, octet4]

func fetch_public_ip() -> String:
	var http = HTTPRequest.new()
	add_child(http)
	
	var apis = [
		"https://api.ipify.org",
		"https://icanhazip.com",
		"https://ifconfig.me/ip"
	]
	
	for url in apis:
		print("Attempting to fetch public IP from: ", url)
		var err = http.request(url)
		if err == OK:
			var result = await http.request_completed
			var response_code = result[1]
			var body = result[3]
			if response_code == 200:
				var ip = body.get_string_from_utf8().strip_edges()
				if ip.split(".").size() == 4:
					http.queue_free()
					return ip
		else:
			print("Request to ", url, " failed: ", err)
			
	http.queue_free()
	return ""

func fetch_public_lobby_ip() -> String:
	var http = HTTPRequest.new()
	add_child(http)
	var url = "https://keyvalue.immanuel.co/api/KeyVal/GetValue/" + MATCHMAKER_APP_KEY + "/" + MATCHMAKER_KEY
	print("Fetching public lobby room code from keyvalue.immanuel.co...")
	var err = http.request(url, ["User-Agent: Mozilla/5.0"])
	if err != OK:
		http.queue_free()
		return ""
	var result = await http.request_completed
	var response_code = result[1]
	var body = result[3]
	http.queue_free()
	
	if response_code == 200:
		var val_str = body.get_string_from_utf8().strip_edges()
		var clean_str = val_str.replace("\"", "").strip_edges()
		if clean_str != "0" and clean_str != "":
			print("Found active public lobby room code: ", clean_str)
			return clean_str
	print("No active public lobby room code found (response code: ", response_code, ")")
	return ""

func register_public_lobby_ip(room_code: String) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	var url = "https://keyvalue.immanuel.co/api/KeyVal/UpdateValue/" + MATCHMAKER_APP_KEY + "/" + MATCHMAKER_KEY + "/" + room_code
	var headers = [
		"User-Agent: Mozilla/5.0",
		"Content-Length: 0"
	]
	print("Registering public lobby room code in keyvalue.immanuel.co: ", room_code)
	var err = http.request(url, headers, HTTPClient.METHOD_POST)
	if err != OK:
		http.queue_free()
		return
	await http.request_completed
	http.queue_free()

func clear_public_lobby_ip() -> void:
	var http = HTTPRequest.new()
	add_child(http)
	var url = "https://keyvalue.immanuel.co/api/KeyVal/UpdateValue/" + MATCHMAKER_APP_KEY + "/" + MATCHMAKER_KEY + "/0"
	var headers = [
		"User-Agent: Mozilla/5.0",
		"Content-Length: 0"
	]
	print("Clearing public lobby from keyvalue.immanuel.co...")
	var err = http.request(url, headers, HTTPClient.METHOD_POST)
	if err != OK:
		http.queue_free()
		return
	await http.request_completed
	http.queue_free()

## --- Player Spawning ---

func _spawn_player(id: int) -> void:
	if not multiplayer.is_server():
		return
		
	# Instantiating the player node
	var player_instance = player_scene.instantiate()
	player_instance.name = str(id)
	player_instance.player_index = players.size() + 1
	player_instance.set_multiplayer_authority(id)

	
	# Spawn position (offset slightly to avoid overlap)
	var spawn_pos = Vector2(500 + (id * 80), 100)

	player_instance.position = spawn_pos
	
	# Add to scene tree under a "Players" container
	var players_container = get_node_or_null("/root/Game/Players")
	if players_container:
		players_container.add_child(player_instance)
		players[id] = player_instance
		player_list_changed.emit()
		
		# Sync new player details and seed to the clients
		_sync_game_state_to_clients.call_deferred()

func _despawn_player(id: int) -> void:
	if not multiplayer.is_server():
		return
		
	if players.has(id):
		var player_instance = players[id]
		if is_instance_valid(player_instance):
			if player_instance.is_in_group("players"):
				player_instance.remove_from_group("players")
			if player_instance.get_parent():
				player_instance.get_parent().remove_child(player_instance)
			player_instance.queue_free()
		players.erase(id)
		player_list_changed.emit()

@rpc("authority", "call_local", "reliable")
func setup_client_game(seed_val: int) -> void:
	start_seed = seed_val
	# Seed the local random generator for deterministic procedural map generation
	seed(start_seed)
	connection_status_changed.emit("Game synchronized. Seed: " + str(seed_val))
	
	var game_node = get_node_or_null("/root/Game")
	if game_node:
		if game_node.is_quick_playing:
			print("Quick Play: Registered and synchronized successfully!")
			game_node.is_quick_playing = false
			if game_node.quick_play_timer:
				game_node.quick_play_timer.stop()

func _sync_game_state_to_clients() -> void:
	if not multiplayer.is_server():
		return
	setup_client_game.rpc(start_seed)

## --- Multiplayer API Callbacks ---

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	if multiplayer.is_server():
		connection_status_changed.emit("Player " + str(id) + " connected. Waiting for registration...")

@rpc("any_peer", "call_local", "reliable")
func register_client(is_quick_play: bool, room_code: String = "") -> void:
	if not multiplayer.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	var code = room_code.strip_edges().to_upper()
	if is_quick_play:
		code = "QUICKPLAY"
		
	print("Registering client: ", sender_id, " | QuickPlay: ", is_quick_play, " | RoomCode: ", code)
	
	# If running as a dedicated server, we enforce room matching
	if DisplayServer.get_name() == "headless":
		if active_room_code == "":
			# First player to register sets the active room code
			active_room_code = code
			is_room_game_started = false
			print("Dedicated Server: Room created/set to: ", active_room_code)
		elif code != active_room_code:
			# Room mismatch: reject connection
			print("Dedicated Server: Rejecting client ", sender_id, " due to room mismatch (expected ", active_room_code, ", got ", code, ")")
			if multiplayer_peer:
				multiplayer_peer.disconnect_peer(sender_id)
			return
		elif is_room_game_started:
			# Game already started: reject connection
			print("Dedicated Server: Rejecting client ", sender_id, " because game in room ", active_room_code, " has already started.")
			if multiplayer_peer:
				multiplayer_peer.disconnect_peer(sender_id)
			return
			
	# Spawn the new player on the server
	_spawn_player(sender_id)
	
	# Handle lobby updates or restart
	var game_node = get_node_or_null("/root/Game")
	if game_node:
		if game_node.lobby_is_active:
			var player_ids = players.keys()
			player_ids.sort()
			game_node.update_lobby_ui.rpc(player_ids, game_node.target_player_count)
			
			# If we have reached the target player count, start the game!
			if player_ids.size() >= game_node.target_player_count:
				is_room_game_started = true
				if is_public_lobby:
					clear_public_lobby_ip()
				game_node.start_game_from_lobby.rpc()
		else:
			game_node.reset_players_to_start.rpc()

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if multiplayer.is_server():
		connection_status_changed.emit("Player " + str(id) + " disconnected.")
		_despawn_player(id)
		
		# Dedicated Server: if no clients are left, clear the active room code
		if DisplayServer.get_name() == "headless":
			if multiplayer.get_peers().size() == 0:
				active_room_code = ""
				is_room_game_started = false
				print("Dedicated Server: All clients disconnected. Resetting room state.")
		
		# If no clients are left and the game has started, disconnect the host
		var game_node = get_node_or_null("/root/Game")
		if game_node and not game_node.lobby_is_active:
			if multiplayer.get_peers().size() == 0:
				print("All clients left. Disconnecting host.")
				game_node.reset_game()

func _on_connected_to_server() -> void:
	local_player_id = multiplayer.get_unique_id()
	connection_status_changed.emit("Connecté au serveur !")
	
	# Register with the server
	var game_node = get_node_or_null("/root/Game")
	var is_qp = false
	var room_code = ""
	if game_node:
		is_qp = game_node.is_quick_playing
		room_code = game_node.current_room_code
	register_client.rpc(is_qp, room_code)

func _on_connection_failed() -> void:
	connection_status_changed.emit("Connexion échouée.")
	multiplayer.multiplayer_peer = null
	
func _on_server_disconnected() -> void:
	connection_status_changed.emit("Serveur déconnecté.")
	players.clear()
	multiplayer.multiplayer_peer = null
	
	# Reload main menu or clear game state
	var game_node = get_node_or_null("/root/Game")
	if game_node:
		game_node.reset_game()
