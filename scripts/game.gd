extends Node2D

# Game.gd
# Main scene coordinator. Manages UI, gameplay resets, and rope linkages.

@export var rope_scene: PackedScene = preload("res://scenes/rope.tscn")

@onready var network_manager = $NetworkManager
@onready var level_generator = $LevelGenerator
@onready var players_container = $Players
@onready var ropes_container = $Ropes

# UI References
@onready var menu_panel = $UI/MenuPanel
@onready var status_label = $UI/MenuPanel/StatusLabel
@onready var ip_input = $UI/MenuPanel/IPInput
@onready var touch_hud = $UI/TouchHUD

# HUD / Score variables
var score_label: Label = null
var highscore_label: Label = null
var current_score: int = 0
var highscore: int = 0
var max_depth_reached: float = 100.0
var is_game_over: bool = false
var highscore_to_beat: int = 0
var confetti_triggered_this_run: bool = false
var ingame_menu_panel: Panel = null

# Lobby Code / Quick Play variables
var current_room_code: String = ""
var room_code_label: Label = null
var quick_play_timer: Timer = null
var is_quick_playing: bool = false
var quick_play_btn: Button = null
var join_submit_btn: Button = null
var join_back_btn: Button = null
var paste_btn: Button = null
var main_title_label: TextureRect = null

# Voice Chat UI variables
var mic_btn: Button = null
var mute_others_btn: Button = null
var mute_others: bool = false


# Visual Redesign Variables
var clouds_list: Array[Node2D] = []

# Lobby UI variables
var lobby_select_panel: Panel = null
var lobby_wait_panel: Panel = null
var lobby_code_label: Label = null
var lobby_status_label: Label = null
var lobby_slots_container: VBoxContainer = null
var lobby_is_active: bool = false
var target_player_count: int = 2

# Touch Gestures Variables
var touch_id: int = -1
var touch_start_pos: Vector2 = Vector2.ZERO
var touch_dir: float = 0.0
var touch_pull: bool = false

func _ready() -> void:
	# Initialize Quick Play Timer
	quick_play_timer = Timer.new()
	quick_play_timer.name = "QuickPlayTimer"
	quick_play_timer.one_shot = true
	quick_play_timer.wait_time = 1.0
	quick_play_timer.timeout.connect(_on_quick_play_timeout)
	add_child(quick_play_timer)

	_create_background()
	_create_game_over_ui()
	_create_hud_ui()
	_create_ingame_menu_ui()
	_restyle_main_menu()
	_create_lobby_ui()
	
	network_manager.player_list_changed.connect(_on_players_changed)
	network_manager.connection_status_changed.connect(_on_connection_status_changed)
	
	_set_gameplay_ui_active(false)
	
	# Hide joystick and pull button permanently for gesture inputs
	var joystick = touch_hud.get_node_or_null("Joystick")
	if joystick:
		joystick.visible = false
	var pull_btn = touch_hud.get_node_or_null("PullButton")
	if pull_btn:
		pull_btn.visible = false
		
	if DisplayServer.get_name() == "headless":
		print("Dedicated Server: Headless mode detected. Auto-starting WebSocket Server...")
		network_manager.host_game(network_manager.MAX_PLAYERS, 10555)
		return

func _create_background() -> void:
	# Don't create background in headless mode to avoid rendering resource warnings
	if DisplayServer.get_name() == "headless":
		return
		
	var parallax_bg = ParallaxBackground.new()
	parallax_bg.name = "BackgroundParallax"
	add_child(parallax_bg)
	
	# Layer 1: Gradient (Fixed, motion_scale = 0)
	var layer_grad = ParallaxLayer.new()
	layer_grad.name = "LayerGradient"
	layer_grad.motion_scale = Vector2(0, 0)
	parallax_bg.add_child(layer_grad)
	
	var tex_rect = TextureRect.new()
	tex_rect.name = "BackgroundTexture"
	tex_rect.size = Vector2(1170, 2532)
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color("#ff5e97"), # Fall Guys Hot Pink
		Color("#b388ff")  # Bubbly Pastel Purple
	])
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0.5, 0.0)
	grad_tex.fill_to = Vector2(0.5, 1.0)
	tex_rect.texture = grad_tex
	layer_grad.add_child(tex_rect)
	
	var screen_width = 1170.0
	var screen_height = 2532.0
	
	# Layer 2: Pastel Hills (motion_scale = (0.1, 0.0))
	var layer_hills = ParallaxLayer.new()
	layer_hills.name = "LayerHills"
	layer_hills.motion_scale = Vector2(0.1, 0.0)
	parallax_bg.add_child(layer_hills)
	
	# Overlapping hills at the bottom of the screen
	_create_hill(layer_hills, screen_width * 0.15, 800.0, 450.0, Color("#e98df5"), screen_height) # back-left magenta
	_create_hill(layer_hills, screen_width * 0.85, 750.0, 420.0, Color("#fca6d3"), screen_height) # back-right light peach pink
	_create_hill(layer_hills, screen_width * 0.45, 700.0, 360.0, Color("#b68df5"), screen_height) # mid-center lavender purple
	_create_hill(layer_hills, screen_width * 0.75, 600.0, 300.0, Color("#69cbfc"), screen_height) # mid-right sky blue
	_create_hill(layer_hills, screen_width * 0.25, 650.0, 250.0, Color("#f55f9e"), screen_height) # foreground vibrant pink
	
	# Layer 3: Drifting Clouds (motion_scale = (0.05, 0.0))
	var layer_clouds = ParallaxLayer.new()
	layer_clouds.name = "LayerClouds"
	layer_clouds.motion_scale = Vector2(0.05, 0.0)
	parallax_bg.add_child(layer_clouds)
	
	# Spawn drifting clouds
	var cloud1 = _create_cloud(layer_clouds, Vector2(screen_width * 0.2, screen_height * 0.25))
	var cloud2 = _create_cloud(layer_clouds, Vector2(screen_width * 0.8, screen_height * 0.4))
	var cloud3 = _create_cloud(layer_clouds, Vector2(screen_width * 0.5, screen_height * 0.15))
	var cloud4 = _create_cloud(layer_clouds, Vector2(screen_width * 0.9, screen_height * 0.2))
	
	clouds_list = [cloud1, cloud2, cloud3, cloud4]

func _create_hill(parent: Node2D, center_x: float, width: float, height: float, color: Color, screen_height: float) -> Polygon2D:
	var hill = Polygon2D.new()
	var points = PackedVector2Array()
	var segments = 32
	
	# Bottom left
	points.append(Vector2(center_x - width/2.0, screen_height + 50))
	# Cosine top
	for i in range(segments + 1):
		var t = -1.0 + 2.0 * float(i) / segments
		var px = center_x + t * (width / 2.0)
		var py = screen_height - height * 0.5 * (1.0 + cos(PI * t))
		points.append(Vector2(px, py))
	# Bottom right
	points.append(Vector2(center_x + width/2.0, screen_height + 50))
	
	hill.polygon = points
	hill.color = color
	parent.add_child(hill)
	
	# Add polka dots
	var dots_offsets = [
		Vector2(-width * 0.25, height * 0.3),
		Vector2(-width * 0.1, height * 0.6),
		Vector2(0.0, height * 0.25),
		Vector2(width * 0.15, height * 0.5),
		Vector2(width * 0.3, height * 0.3)
	]
	for offset in dots_offsets:
		var dot = Polygon2D.new()
		var dot_pts = PackedVector2Array()
		for i in range(12):
			var angle = float(i) * 2.0 * PI / 12.0
			dot_pts.append(Vector2(cos(angle) * 12.0, sin(angle) * 12.0))
		dot.polygon = dot_pts
		dot.color = Color(1.0, 1.0, 1.0, 0.15)
		dot.position = Vector2(center_x + offset.x, screen_height - offset.y)
		hill.add_child(dot)
		
	return hill

func _create_cloud(parent: Node2D, start_pos: Vector2) -> Node2D:
	var cloud = Node2D.new()
	cloud.position = start_pos
	
	var c1 = Polygon2D.new()
	c1.polygon = _get_circle_points(25.0)
	c1.color = Color(1.0, 1.0, 1.0, 0.75)
	c1.position = Vector2(-30, 10)
	cloud.add_child(c1)
	
	var c2 = Polygon2D.new()
	c2.polygon = _get_circle_points(25.0)
	c2.color = Color(1.0, 1.0, 1.0, 0.75)
	c2.position = Vector2(30, 10)
	cloud.add_child(c2)
	
	var c3 = Polygon2D.new()
	c3.polygon = _get_circle_points(35.0)
	c3.color = Color(1.0, 1.0, 1.0, 0.75)
	c3.position = Vector2(0, 0)
	cloud.add_child(c3)
	
	var c4 = Polygon2D.new()
	c4.polygon = PackedVector2Array([
		Vector2(-40, 10),
		Vector2(40, 10),
		Vector2(40, 25),
		Vector2(-40, 25)
	])
	c4.color = Color(1.0, 1.0, 1.0, 0.75)
	cloud.add_child(c4)
	
	parent.add_child(cloud)
	return cloud

func _get_circle_points(radius: float, segments: int = 16) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments):
		var angle = float(i) * 2.0 * PI / segments
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points

## --- Connection Handlers ---

func host_session() -> void:
	clear_game_session()
	if status_label:
		status_label.text = "Connecting to the world..."
		status_label.visible = true
	await get_tree().process_frame
	
	# Generate a random 6-character room code
	var code = generate_random_room_code()
	current_room_code = code
	
	# Check if we should connect to localhost for testing
	var target_url = "deep-down-server.onrender.com"
	if ip_input and (ip_input.text.strip_edges().to_lower() == "localhost" or ip_input.text.strip_edges() == "127.0.0.1"):
		target_url = "127.0.0.1"
		# Prepend to the room code to let join_session_with_code know it's local
		code = "localhost-" + code
		
	var success = await join_session_with_code(code, false)
	if not success:
		if status_label:
			status_label.text = "Échec du démarrage de l'hébergement."

func join_session() -> void:
	var ip = ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	join_session_with_code(ip)

func join_session_with_code(code: String, is_qp: bool = false) -> bool:
	is_quick_playing = is_qp
	if quick_play_timer:
		quick_play_timer.stop()
		
	var clean_code = code.strip_edges().to_upper()
	
	# Determine target URL and clean code
	var target_url = "deep-down-server.onrender.com"
	if clean_code.begins_with("LOCALHOST-") or clean_code == "LOCALHOST" or clean_code == "127.0.0.1":
		target_url = "127.0.0.1"
		clean_code = clean_code.replace("LOCALHOST-", "")
		
	current_room_code = clean_code
	
	# Disable join controls during connection
	_set_join_controls_disabled(true)
	clear_game_session()
	
	if status_label:
		status_label.text = "Connecting to the world..."
		
	var success = await attempt_connection(target_url, 15.0)
	if success:
		_set_join_controls_disabled(false)
		if menu_panel:
			menu_panel.visible = false
		if lobby_wait_panel:
			lobby_wait_panel.visible = true
		if lobby_code_label:
			if is_quick_playing:
				lobby_code_label.text = "SALON PUBLIC (RAPIDE)"
			else:
				lobby_code_label.text = "CODE DE SALON : " + current_room_code
		lobby_is_active = true
		_update_hud_room_code()
		return true
	else:
		_set_join_controls_disabled(false)
		if status_label:
			status_label.text = "Connexion échouée."
		return false

func attempt_connection(ip: String, timeout_seconds: float) -> bool:
	var target_ip = ip
	var is_mobile = OS.get_name() == "iOS" or OS.get_name() == "Android"
	
	# Skip local address enumeration on mobile to avoid triggering iOS Local Network Permission prompts
	if not is_mobile:
		if target_ip == "localhost" or target_ip in IP.get_local_addresses() or (network_manager.public_ip != "" and target_ip == network_manager.public_ip):
			print("Local machine loopback detected. Mapping to 127.0.0.1.")
			target_ip = "127.0.0.1"
	else:
		if target_ip == "localhost" or target_ip == "127.0.0.1":
			print("Mobile localhost detected. Mapping to 127.0.0.1.")
			target_ip = "127.0.0.1"
		
	# Disable join controls during this specific connection attempt
	_set_join_controls_disabled(true)
	clear_game_session()
	
	if status_label:
		status_label.text = "Connecting to the world..."
		
	var err = network_manager.join_game(target_ip)
	if err != OK:
		return false
		
	var start_time = Time.get_ticks_msec()
	var timeout_ms = timeout_seconds * 1000.0
	
	while true:
		if not multiplayer.multiplayer_peer:
			return false
		var status = multiplayer.multiplayer_peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			return true
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return false
			
		if Time.get_ticks_msec() - start_time > timeout_ms:
			print("Connection to ", ip, " timed out after ", timeout_seconds, "s")
			network_manager.disconnect_game()
			return false
			
		await get_tree().process_frame
	return false

func _set_menu_buttons_disabled(disabled: bool) -> void:
	if quick_play_btn:
		quick_play_btn.visible = not disabled
	var host_btn = menu_panel.get_node_or_null("HostButton") as Button
	if host_btn:
		host_btn.visible = not disabled
	var join_btn = menu_panel.get_node_or_null("JoinButton") as Button
	if join_btn:
		join_btn.visible = not disabled
	var solo_btn = menu_panel.get_node_or_null("SoloButton") as Button
	if solo_btn:
		solo_btn.visible = not disabled

func _set_join_controls_disabled(disabled: bool) -> void:
	if ip_input:
		ip_input.editable = not disabled
	if join_submit_btn:
		join_submit_btn.disabled = disabled
	if join_back_btn:
		join_back_btn.disabled = disabled
	if not is_quick_playing or disabled:
		_set_menu_buttons_disabled(disabled)

func start_quick_play() -> void:
	if status_label:
		status_label.text = "Connecting to the world..."
	is_quick_playing = true
	_set_menu_buttons_disabled(true)
	
	# In the dedicated server model, both quick play clients connect to the "QUICKPLAY" room code
	print("Quick Play: Attempting to join public QUICKPLAY lobby...")
	var success = await join_session_with_code("QUICKPLAY", true)
	if success:
		print("Quick Play: Connected to QUICKPLAY lobby successfully!")
	else:
		print("Quick Play: Connection failed or timed out.")
		_set_menu_buttons_disabled(false)
		if status_label:
			status_label.text = "Impossible de se connecter au serveur."

func _on_quick_play_timeout() -> void:
	if is_quick_playing:
		print("Quick Play: Connection timed out.")
		network_manager.disconnect_game()
		is_quick_playing = false
		_set_menu_buttons_disabled(false)
		if status_label:
			status_label.text = "Délai de connexion dépassé."
	else:
		if status_label:
			status_label.text = "Échec du démarrage de l'hébergement."

func get_host_ip() -> String:
	if OS.get_name() == "iOS" or OS.get_name() == "Android":
		return "127.0.0.1"
		
	var interfaces = IP.get_local_interfaces()
	var best_ip = ""
	var best_rank = -1
	
	for iface in interfaces:
		var name = iface.get("name", "").to_lower()
		var friendly = iface.get("friendly", "").to_lower()
		var addresses = iface.get("addresses", [])
		
		# Skip loopback, tunnel, VPN, virtual machine, and bridge interfaces
		if name.begins_with("utun") or name.begins_with("tun") or name.begins_with("tap") or name.begins_with("gif") or name.begins_with("stf") or name.begins_with("bridge") or name.begins_with("awdl") or name.begins_with("llw") or name.begins_with("lo") or name.contains("vpn") or name.contains("docker") or name.contains("vbox") or name.contains("virtual"):
			continue
			
		for ip in addresses:
			if ip == "127.0.0.1" or ip.begins_with("fe80") or ip.begins_with("169.254") or ip.split(".").size() != 4:
				continue
				
			# Rank the IP:
			# Rank 3: Physical Wi-Fi or Ethernet (starts with 'en' on macOS, 'wlan'/'eth' on Linux/Android)
			# Rank 2: Friendly name mentions Wi-Fi, Ethernet, LAN, or Local Area
			# Rank 1: Other IPv4
			var rank = 1
			if name.begins_with("en") or name.begins_with("wlan") or name.begins_with("eth"):
				rank = 3
			elif "wi-fi" in friendly or "ethernet" in friendly or "lan" in friendly:
				rank = 2
				
			if rank > best_rank:
				best_rank = rank
				best_ip = ip
				
	if best_ip != "":
		return best_ip
		
	# Fallback to old behavior if no interface found
	var fallback_addresses = IP.get_local_addresses()
	for ip in fallback_addresses:
		if ip.contains(":") or ip == "127.0.0.1" or ip == "localhost":
			continue
		var parts = ip.split(".")
		if parts.size() == 4:
			if int(parts[0]) == 192:
				return ip
	for ip in fallback_addresses:
		if ip.contains(":") or ip == "127.0.0.1" or ip == "localhost":
			continue
		var parts = ip.split(".")
		if parts.size() == 4:
			var first = int(parts[0])
			if first == 10 or first == 172:
				return ip
	for ip in fallback_addresses:
		if ip.contains(":") or ip == "127.0.0.1" or ip == "localhost":
			continue
		if ip.split(".").size() == 4:
			return ip
	return "127.0.0.1"

func get_host_ip_raw() -> String:
	var interfaces = IP.get_local_interfaces()
	var best_ip = ""
	var best_rank = -1
	
	for iface in interfaces:
		var name = iface.get("name", "").to_lower()
		var friendly = iface.get("friendly", "").to_lower()
		var addresses = iface.get("addresses", [])
		
		# Skip loopback, tunnel, VPN, virtual machine, and bridge interfaces
		if name.begins_with("utun") or name.begins_with("tun") or name.begins_with("tap") or name.begins_with("gif") or name.begins_with("stf") or name.begins_with("bridge") or name.begins_with("awdl") or name.begins_with("llw") or name.begins_with("lo") or name.contains("vpn") or name.contains("docker") or name.contains("vbox") or name.contains("virtual"):
			continue
			
		for ip in addresses:
			if ip == "127.0.0.1" or ip.begins_with("fe80") or ip.begins_with("169.254") or ip.split(".").size() != 4:
				continue
				
			# Rank the IP:
			# Rank 3: Physical Wi-Fi or Ethernet (starts with 'en' on macOS, 'wlan'/'eth' on Linux/Android)
			# Rank 2: Friendly name mentions Wi-Fi, Ethernet, LAN, or Local Area
			# Rank 1: Other IPv4
			var rank = 1
			if name.begins_with("en") or name.begins_with("wlan") or name.begins_with("eth"):
				rank = 3
			elif "wi-fi" in friendly or "ethernet" in friendly or "lan" in friendly:
				rank = 2
				
			if rank > best_rank:
				best_rank = rank
				best_ip = ip
				
	if best_ip != "":
		return best_ip
		
	# Fallback to old behavior if no interface found
	var fallback_addresses = IP.get_local_addresses()
	for ip in fallback_addresses:
		if ip.contains(":") or ip == "127.0.0.1" or ip == "localhost":
			continue
		var parts = ip.split(".")
		if parts.size() == 4:
			if int(parts[0]) == 192:
				return ip
	for ip in fallback_addresses:
		if ip.contains(":") or ip == "127.0.0.1" or ip == "localhost":
			continue
		var parts = ip.split(".")
		if parts.size() == 4:
			var first = int(parts[0])
			if first == 10 or first == 172:
				return ip
	for ip in fallback_addresses:
		if ip.contains(":") or ip == "127.0.0.1" or ip == "localhost":
			continue
		if ip.split(".").size() == 4:
			return ip
	return "127.0.0.1"

func ip_to_code(ip: String) -> String:
	var parts = ip.split(".")
	if parts.size() != 4:
		return ""
	var val: int = 0
	for i in range(4):
		val = (val << 8) | clamp(int(parts[i]), 0, 255)
	
	var chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var code = ""
	while val > 0:
		var remainder = val % 36
		code = chars[remainder] + code
		val = val / 36
	return code

func code_to_ip(code: String) -> String:
	var chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var val: int = 0
	code = code.to_upper().strip_edges()
	if code == "":
		return ""
	for i in range(code.length()):
		var c = code[i]
		var idx = chars.find(c)
		if idx == -1:
			return ""
		val = val * 36 + idx
	
	var a = (val >> 24) & 0xFF
	var b = (val >> 16) & 0xFF
	var c_part = (val >> 8) & 0xFF
	var d = val & 0xFF
	return "%d.%d.%d.%d" % [a, b, c_part, d]

func generate_random_room_code() -> String:
	var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var code = ""
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(6):
		code += chars[rng.randi() % chars.length()]
	return code

func _update_hud_room_code() -> void:
	if room_code_label:
		# Only display the room code in the in-game HUD for the server/host
		if current_room_code != "" and multiplayer.multiplayer_peer != null and multiplayer.is_server():
			room_code_label.text = "CODE: " + current_room_code
			room_code_label.visible = true
		else:
			room_code_label.visible = false

func _style_button(btn: Button, bg_color_hex: String, font_size: int = 24) -> void:
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.9))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	
	# Rounded bold font for candy/bubbly look
	var rounded_font = SystemFont.new()
	rounded_font.font_names = PackedStringArray(["SF Pro Rounded", "Nunito", "Avenir Next Rounded", "Avenir Next", "Helvetica Neue"])
	rounded_font.font_weight = 800
	btn.add_theme_font_override("font", rounded_font)
	
	var scale_factor = float(font_size) / 24.0
	btn.add_theme_constant_override("outline_size", int(5 * scale_factor))
	
	var base_color = Color(bg_color_hex)
	# Pill-shaped: corner radius = half button height (will be clamped by Godot)
	var radius = int(80 * scale_factor)
	var border_side = int(6 * scale_factor)
	var border_bottom = int(12 * scale_factor)
	var border_top = int(2 * scale_factor)
	
	# Horizontal & vertical padding relative to button face
	var padding_inside = int(8 * scale_factor)
	var margin_side = int(32 * scale_factor)
	
	# Handle custom icon child to allow perfect text centering
	var icon_tex = btn.icon
	var old_icon = btn.get_node_or_null("CustomIcon")
	if old_icon:
		old_icon.name = "OldCustomIcon"
		old_icon.queue_free()
		
	if icon_tex:
		btn.icon = null # Clear built-in icon so text centers relative to whole button width
		
		var tex_rect = TextureRect.new()
		tex_rect.name = "CustomIcon"
		tex_rect.texture = icon_tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# Proportional size: 55% of the button face height
		var btn_h = btn.size.y if btn.size.y > 0.0 else 170.0
		var visible_height = btn_h - border_bottom
		var icon_size = int(visible_height * 0.55)
		tex_rect.size = Vector2(icon_size, icon_size)
		
		# Position: left-aligned with nudge if there is text, centered if icon-only
		var icon_x = int(32 * scale_factor) if btn.text != "" else int((btn.size.x - icon_size) / 2.0)
		var icon_y = int((visible_height - icon_size) / 2.0)
		tex_rect.position = Vector2(icon_x, icon_y)
		btn.add_child(tex_rect)
		
		# Connect press shift callbacks (safely checking if already connected)
		var shift_y = int(2 * scale_factor)
		
		# Disconnect old bindings if they exist to avoid accumulation
		for conn in btn.button_down.get_connections():
			if conn.callable.get_method() == "_on_btn_down":
				btn.button_down.disconnect(conn.callable)
		for conn in btn.button_up.get_connections():
			if conn.callable.get_method() == "_on_btn_up":
				btn.button_up.disconnect(conn.callable)
				
		btn.button_down.connect(_on_btn_down.bind(tex_rect, shift_y))
		btn.button_up.connect(_on_btn_up.bind(tex_rect, shift_y))
	
	# ── Normal: Vibrant bg + thick bottom/side borders for 3D depth ──
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = base_color.lightened(0.05)
	style_normal.corner_radius_top_left = radius
	style_normal.corner_radius_top_right = radius
	style_normal.corner_radius_bottom_left = radius
	style_normal.corner_radius_bottom_right = radius
	style_normal.border_width_left = border_side
	style_normal.border_width_right = border_side
	style_normal.border_width_top = border_top
	style_normal.border_width_bottom = border_bottom
	style_normal.border_color = base_color.darkened(0.35)
	style_normal.content_margin_top = border_top + padding_inside
	style_normal.content_margin_bottom = border_bottom + padding_inside
	style_normal.content_margin_left = margin_side
	style_normal.content_margin_right = margin_side
	style_normal.shadow_color = Color(0, 0, 0, 0.18)
	style_normal.shadow_size = int(6 * scale_factor)
	style_normal.shadow_offset = Vector2(0, int(4 * scale_factor))
	
	# ── Hover: Slightly brighter ──
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = base_color.lightened(0.15)
	style_hover.corner_radius_top_left = radius
	style_hover.corner_radius_top_right = radius
	style_hover.corner_radius_bottom_left = radius
	style_hover.corner_radius_bottom_right = radius
	style_hover.border_width_left = border_side
	style_hover.border_width_right = border_side
	style_hover.border_width_top = border_top
	style_hover.border_width_bottom = border_bottom
	style_hover.border_color = base_color.darkened(0.3)
	style_hover.content_margin_top = border_top + padding_inside
	style_hover.content_margin_bottom = border_bottom + padding_inside
	style_hover.content_margin_left = margin_side
	style_hover.content_margin_right = margin_side
	style_hover.shadow_color = Color(0, 0, 0, 0.22)
	style_hover.shadow_size = int(8 * scale_factor)
	style_hover.shadow_offset = Vector2(0, int(5 * scale_factor))
	
	# ── Pressed: Button sinks down, border shrinks ──
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = base_color.darkened(0.05)
	style_pressed.corner_radius_top_left = radius
	style_pressed.corner_radius_top_right = radius
	style_pressed.corner_radius_bottom_left = radius
	style_pressed.corner_radius_bottom_right = radius
	style_pressed.border_width_left = border_side
	style_pressed.border_width_right = border_side
	
	var border_pressed_top = int(4 * scale_factor)
	var border_pressed_bottom = int(3 * scale_factor)
	style_pressed.border_width_top = border_pressed_top
	style_pressed.border_width_bottom = border_pressed_bottom
	style_pressed.border_color = base_color.darkened(0.4)
	
	style_pressed.content_margin_top = border_pressed_top + padding_inside
	style_pressed.content_margin_bottom = border_pressed_bottom + padding_inside
	style_pressed.content_margin_left = margin_side
	style_pressed.content_margin_right = margin_side
	style_pressed.shadow_color = Color(0, 0, 0, 0.1)
	style_pressed.shadow_size = int(2 * scale_factor)
	style_pressed.shadow_offset = Vector2(0, int(1 * scale_factor))
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _on_btn_down(tex_rect: TextureRect, shift_y: int) -> void:
	if is_instance_valid(tex_rect):
		tex_rect.position.y += shift_y

func _on_btn_up(tex_rect: TextureRect, shift_y: int) -> void:
	if is_instance_valid(tex_rect):
		tex_rect.position.y -= shift_y

func _restyle_main_menu() -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	var viewport_size = menu_panel.get_viewport_rect().size
	menu_panel.size = Vector2(1080, 1100)
	
	# Move the menu panel down closer to the bottom
	menu_panel.position.x = (viewport_size.x - menu_panel.size.x) / 2.0
	menu_panel.position.y = viewport_size.y - menu_panel.size.y - 80.0
	
	# Dynamically position and size the custom logo in the remaining space above the card
	if main_title_label:
		var top_boundary = 160.0 # Safe area below iPhone notch
		var bottom_boundary = menu_panel.position.y - 40.0
		var available_height = max(100.0, bottom_boundary - top_boundary)
		
		# Proportional square logo size (max 1000px, which is 50% larger than previous 675px)
		var logo_height = min(available_height, 1000.0)
		main_title_label.size = Vector2(logo_height, logo_height)
		main_title_label.position.x = (viewport_size.x - logo_height) / 2.0
		main_title_label.position.y = top_boundary + (available_height - logo_height) / 2.0
	
	# Transparent panel – buttons float on the gradient background
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0, 0, 0, 0)
	menu_panel.add_theme_stylebox_override("panel", card_style)
	
	var title = menu_panel.get_node_or_null("TitleLabel") as Label
	if title:
		title.visible = false
		
	if status_label:
		status_label.text = ""
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.size = Vector2(920, 80)
		status_label.position = Vector2(80, 20)
		status_label.add_theme_font_size_override("font_size", 44)
		status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# ── Candy-colored main menu buttons ──
	var btn_width = 920
	var btn_height = 170
	var btn_x = 80
	var btn_spacing = 210  # More breathing room
	var btn_start_y = 120
	
	quick_play_btn = Button.new()
	quick_play_btn.name = "QuickPlayButton"
	quick_play_btn.text = "JOUER"
	quick_play_btn.icon = load("res://assets/icons/play_fill.png")
	quick_play_btn.expand_icon = true
	quick_play_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	quick_play_btn.size = Vector2(btn_width, btn_height)
	quick_play_btn.position = Vector2(btn_x, btn_start_y)
	_style_button(quick_play_btn, "#FFB800", 52)  # Golden yellow
	quick_play_btn.pressed.connect(start_quick_play)
	menu_panel.add_child(quick_play_btn)
	
	var host_btn = menu_panel.get_node_or_null("HostButton") as Button
	if host_btn:
		host_btn.text = "HÉBERGER"
		host_btn.icon = load("res://assets/icons/house_fill.png")
		host_btn.expand_icon = true
		host_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		host_btn.size = Vector2(btn_width, btn_height)
		host_btn.position = Vector2(btn_x, btn_start_y + btn_spacing)
		_style_button(host_btn, "#FF2D78", 52)  # Hot pink
		for connection in host_btn.pressed.get_connections():
			host_btn.pressed.disconnect(connection.callable)
		host_btn.pressed.connect(_on_host_clicked)
		
	var join_btn = menu_panel.get_node_or_null("JoinButton") as Button
	if join_btn:
		join_btn.text = "REJOINDRE"
		join_btn.icon = load("res://assets/icons/person_2_fill.png")
		join_btn.expand_icon = true
		join_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		join_btn.size = Vector2(btn_width, btn_height)
		join_btn.position = Vector2(btn_x, btn_start_y + btn_spacing * 2)
		_style_button(join_btn, "#00AAFF", 52)  # Sky blue
		for connection in join_btn.pressed.get_connections():
			join_btn.pressed.disconnect(connection.callable)
		join_btn.pressed.connect(_on_join_clicked)
		
	var solo_btn = menu_panel.get_node_or_null("SoloButton") as Button
	if solo_btn:
		solo_btn.text = "SOLO / TEST"
		solo_btn.icon = load("res://assets/icons/gearshape_fill.png")
		solo_btn.expand_icon = true
		solo_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		solo_btn.size = Vector2(btn_width, btn_height)
		solo_btn.position = Vector2(btn_x, btn_start_y + btn_spacing * 3)
		_style_button(solo_btn, "#AA55FF", 52)  # Vivid purple
		for connection in solo_btn.pressed.get_connections():
			solo_btn.pressed.disconnect(connection.callable)
		solo_btn.pressed.connect(start_solo_test)
		
	if ip_input:
		ip_input.visible = false
		ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
		ip_input.size = Vector2(700, 160)
		ip_input.position = Vector2(80, 260)
		ip_input.add_theme_font_size_override("font_size", 56)
		ip_input.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		ip_input.placeholder_text = "CODE DE SALON"
		
		var ip_style = StyleBoxFlat.new()
		ip_style.bg_color = Color(0, 0, 0, 0.35)
		ip_style.corner_radius_top_left = 80
		ip_style.corner_radius_top_right = 80
		ip_style.corner_radius_bottom_left = 80
		ip_style.corner_radius_bottom_right = 80
		ip_style.border_width_left = 6
		ip_style.border_width_top = 2
		ip_style.border_width_right = 6
		ip_style.border_width_bottom = 10
		ip_style.border_color = Color(0, 0, 0, 0.25)
		ip_input.add_theme_stylebox_override("normal", ip_style)
		ip_input.add_theme_stylebox_override("focus", ip_style)
		
	paste_btn = Button.new()
	paste_btn.name = "PasteButton"
	paste_btn.text = ""
	paste_btn.tooltip_text = "Coller depuis le presse-papiers"
	var paste_tex = load("res://assets/clipboard_paste.png")
	paste_btn.icon = paste_tex
	paste_btn.expand_icon = true
	_style_button(paste_btn, "#AA55FF", 56)
	paste_btn.size = Vector2(200, 160)
	paste_btn.position = Vector2(800, 260)
	paste_btn.visible = false
	paste_btn.pressed.connect(_on_paste_pressed)
	menu_panel.add_child(paste_btn)
		
	join_submit_btn = Button.new()
	join_submit_btn.name = "JoinSubmitButton"
	join_submit_btn.text = "VALIDER"
	join_submit_btn.icon = load("res://assets/icons/play_fill.png")
	join_submit_btn.expand_icon = true
	join_submit_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	join_submit_btn.size = Vector2(920, 170)
	join_submit_btn.position = Vector2(80, 480)
	join_submit_btn.visible = false
	_style_button(join_submit_btn, "#00E676", 48)
	join_submit_btn.pressed.connect(_on_join_submit_pressed)
	menu_panel.add_child(join_submit_btn)
	
	join_back_btn = Button.new()
	join_back_btn.name = "JoinBackButton"
	join_back_btn.text = "RETOUR"
	join_back_btn.icon = load("res://assets/icons/chevron_left.png")
	join_back_btn.expand_icon = true
	join_back_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	join_back_btn.size = Vector2(920, 170)
	join_back_btn.position = Vector2(80, 700)
	join_back_btn.visible = false
	_style_button(join_back_btn, "#FF2D78", 48)
	join_back_btn.pressed.connect(_on_join_back_pressed)
	menu_panel.add_child(join_back_btn)

func _on_join_clicked() -> void:
	if quick_play_btn: quick_play_btn.visible = false
	var host_btn = menu_panel.get_node_or_null("HostButton")
	if host_btn: host_btn.visible = false
	var join_btn = menu_panel.get_node_or_null("JoinButton")
	if join_btn: join_btn.visible = false
	var solo_btn = menu_panel.get_node_or_null("SoloButton")
	if solo_btn: solo_btn.visible = false
	
	if ip_input:
		ip_input.text = ""
		ip_input.visible = true
	if paste_btn:
		paste_btn.visible = true
	if join_submit_btn: join_submit_btn.visible = true
	if join_back_btn: join_back_btn.visible = true
	if status_label:
		status_label.text = "Entrez le code de salon à rejoindre."

func _on_join_back_pressed() -> void:
	if ip_input: ip_input.visible = false
	if paste_btn: paste_btn.visible = false
	if join_submit_btn: join_submit_btn.visible = false
	if join_back_btn: join_back_btn.visible = false
	
	if quick_play_btn: quick_play_btn.visible = true
	var host_btn = menu_panel.get_node_or_null("HostButton")
	if host_btn: host_btn.visible = true
	var join_btn = menu_panel.get_node_or_null("JoinButton")
	if join_btn: join_btn.visible = true
	var solo_btn = menu_panel.get_node_or_null("SoloButton")
	if solo_btn: solo_btn.visible = true
	if status_label:
		status_label.text = ""

func _on_join_submit_pressed() -> void:
	if ip_input:
		var code = ip_input.text.strip_edges()
		if code == "":
			if status_label:
				status_label.text = "Veuillez entrer un code de salon."
			return
		join_session_with_code(code)

func _on_paste_pressed() -> void:
	var text = DisplayServer.clipboard_get().strip_edges()
	if text != "":
		if ip_input:
			ip_input.text = text
		if status_label:
			status_label.text = "Code collé !"
			status_label.visible = true
			await get_tree().create_timer(1.5).timeout
			if status_label.text == "Code collé !":
				status_label.text = ""

func _on_copy_pressed() -> void:
	if current_room_code != "":
		DisplayServer.clipboard_set(current_room_code)
		var copy_btn = lobby_wait_panel.find_child("CopyButton", true, false) as Button
		if copy_btn:
			copy_btn.icon = null
			var custom_icon = copy_btn.get_node_or_null("CustomIcon")
			if custom_icon:
				custom_icon.visible = false
			copy_btn.text = " COPIÉ ! "
			copy_btn.disabled = true
			await get_tree().create_timer(1.5).timeout
			if is_instance_valid(copy_btn):
				copy_btn.text = ""
				copy_btn.icon = load("res://assets/doc_on_doc.png")
				_style_button(copy_btn, "#FFB800", 32)
				copy_btn.disabled = false

func start_solo_test() -> void:
	clear_game_session()
	if level_generator:
		level_generator.reset_generator()
	_set_gameplay_ui_active(true)
	
	var is_headless = DisplayServer.get_name() == "headless"
	
	# Spawn local controllable player 1
	var p1 = network_manager.player_scene.instantiate()
	p1.name = "1"
	p1.player_index = 1
	p1.global_position = Vector2(500, 140) if is_headless else Vector2(500, 100)
	p1.is_dummy = false
	players_container.add_child(p1)
	
	# Spawn controllable player 2
	var p2 = network_manager.player_scene.instantiate()
	p2.name = "2"
	p2.player_index = 2
	p2.global_position = Vector2(500, 80) if is_headless else Vector2(580, 100)
	p2.is_dummy = false
	players_container.add_child(p2)

	# Spawn dummy player 3
	var p3 = network_manager.player_scene.instantiate()
	p3.name = "3"
	p3.player_index = 3
	p3.global_position = Vector2(500, 20) if is_headless else Vector2(660, 100)
	p3.is_dummy = true
	players_container.add_child(p3)

	# Spawn dummy player 4
	var p4 = network_manager.player_scene.instantiate()
	p4.name = "4"
	p4.player_index = 4
	p4.global_position = Vector2(500, -40) if is_headless else Vector2(740, 100)
	p4.is_dummy = true
	players_container.add_child(p4)
	
	# Connect P1 and P2 with Rope 1
	var rope1 = rope_scene.instantiate()
	ropes_container.add_child(rope1)
	rope1.initialize(p1, p2)
	p1.ropes.append(rope1)
	p2.ropes.append(rope1)

	# Connect P2 and P3 with Rope 2
	var rope2 = rope_scene.instantiate()
	ropes_container.add_child(rope2)
	rope2.initialize(p2, p3)
	p2.ropes.append(rope2)
	p3.ropes.append(rope2)

	# Connect P3 and P4 with Rope 3
	var rope3 = rope_scene.instantiate()
	ropes_container.add_child(rope3)
	rope3.initialize(p3, p4)
	p3.ropes.append(rope3)
	p4.ropes.append(rope3)
	
	print("Solo sandbox initialized: 4 Players linked in a daisy chain.")
	
	if is_headless:
		_run_headless_test.call_deferred(p1, p2, p3, p4)

func _run_headless_test(p1: CharacterBody2D, p2: CharacterBody2D, p3: CharacterBody2D, p4: CharacterBody2D) -> void:
	print("[TEST] Starting headless stacking physics test for 4 players...")
	
	# Wait for 30 physics frames to let them settle on the floor
	for i in range(30):
		await get_tree().physics_frame
		
	print("[TEST] Settled positions:")
	print("  P1: ", p1.global_position)
	print("  P2: ", p2.global_position)
	print("  P3: ", p3.global_position)
	print("  P4: ", p4.global_position)
	
	# Verify that Player 2 is stacked on Player 1
	if not p1.is_player_on_top(p2):
		print("[TEST FAIL] Player 2 is not detected as stacked on Player 1!")
		get_tree().quit(1)
		return
		
	# Verify that Player 3 is stacked on Player 2
	if not p2.is_player_on_top(p3):
		print("[TEST FAIL] Player 3 is not detected as stacked on Player 2!")
		get_tree().quit(1)
		return

	# Verify that Player 4 is stacked on Player 3
	if not p3.is_player_on_top(p4):
		print("[TEST FAIL] Player 4 is not detected as stacked on Player 3!")
		get_tree().quit(1)
		return
		
	# Now let's simulate Player 1 walking to the right for 30 frames
	print("[TEST] Simulating Player 1 moving right...")
	var initial_offset_p2 = p2.global_position - p1.global_position
	var initial_offset_p3 = p3.global_position - p1.global_position
	var initial_offset_p4 = p4.global_position - p1.global_position
	
	var success = true
	for i in range(30):
		# Force Player 1 horizontal velocity directly (moving right)
		p1.velocity.x = 200.0
		# Other players have 0 input velocity (just feels gravity and stacking/carrying forces)
		p2.velocity.x = 0.0
		p3.velocity.x = 0.0
		p4.velocity.x = 0.0
		
		await get_tree().physics_frame
		
		# Check relative horizontal positions
		var current_dx_p2 = p2.global_position.x - p1.global_position.x
		var delta_offset_p2 = abs(current_dx_p2 - initial_offset_p2.x)
		
		var current_dx_p3 = p3.global_position.x - p1.global_position.x
		var delta_offset_p3 = abs(current_dx_p3 - initial_offset_p3.x)

		var current_dx_p4 = p4.global_position.x - p1.global_position.x
		var delta_offset_p4 = abs(current_dx_p4 - initial_offset_p4.x)
		
		print("[TEST Tick %d]" % i)
		print("  P1: %s" % p1.global_position)
		print("  P2: %s | Drift: %.3f" % [p2.global_position, delta_offset_p2])
		print("  P3: %s | Drift: %.3f" % [p3.global_position, delta_offset_p3])
		print("  P4: %s | Drift: %.3f" % [p4.global_position, delta_offset_p4])
		
		# If the relative offset changed by more than 0.1 pixel, it's a fail (sliding/lag)
		if delta_offset_p2 > 0.1 or delta_offset_p3 > 0.1 or delta_offset_p4 > 0.1:
			print("[TEST FAIL] Sliding detected! Drift P2: %.3f, P3: %.3f, P4: %.3f" % [delta_offset_p2, delta_offset_p3, delta_offset_p4])
			success = false
			break
			
	if success:
		print("[TEST SUCCESS] Stacking physics verified. All 4 players carried perfectly with zero relative drift!")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _set_gameplay_ui_active(active: bool) -> void:
	if menu_panel:
		menu_panel.visible = not active
	if touch_hud:
		touch_hud.visible = active
		
	if score_label:
		score_label.visible = active
	if highscore_label:
		highscore_label.visible = active
	if main_title_label:
		main_title_label.visible = not active
	if players_container:
		players_container.visible = active

func clear_game_session() -> void:
	# Clear all players and ropes
	for child in players_container.get_children():
		if child.is_in_group("players"):
			child.remove_from_group("players")
		players_container.remove_child(child)
		child.queue_free()
	for child in ropes_container.get_children():
		ropes_container.remove_child(child)
		child.queue_free()
		
	# Reset score/depth state
	max_depth_reached = 100.0
	current_score = 0
	if score_label:
		score_label.text = "0"
	confetti_triggered_this_run = false
	is_game_over = false

func reset_game() -> void:
	if ingame_menu_panel:
		ingame_menu_panel.visible = false
	if lobby_select_panel:
		lobby_select_panel.visible = false
	if lobby_wait_panel:
		lobby_wait_panel.visible = false
	lobby_is_active = false
		
	clear_game_session()
	network_manager.disconnect_game()
	_set_gameplay_ui_active(false)
	if status_label:
		status_label.text = ""
	
	current_room_code = ""
	is_quick_playing = false
	_set_menu_buttons_disabled(false)
	if quick_play_timer:
		quick_play_timer.stop()
	_update_hud_room_code()
	_on_join_back_pressed()

func _on_connection_status_changed(status: String) -> void:
	if status_label:
		status_label.text = status
		
	if is_quick_playing:
		if status == "Connection failed." or status == "Server disconnected." or status == "Disconnected." or status == "Connexion échouée." or status == "Serveur déconnecté.":
			print("Quick Play: Connection failed or disconnected. Resetting.")
			if quick_play_timer:
				quick_play_timer.stop()
			is_quick_playing = false
			network_manager.disconnect_game()
			_set_menu_buttons_disabled(false)
			if status_label:
				status_label.text = "La connexion a échoué."

## --- Rope Initialization & Synchronization ---

func _on_players_changed() -> void:
	if not multiplayer.is_server():
		return
		
	# Gather all connected player IDs in sorted order
	var player_ids = network_manager.players.keys()
	player_ids.sort()
	
	if lobby_is_active:
		if player_ids.size() >= target_player_count:
			# Start the game!
			if network_manager.is_public_lobby:
				network_manager.clear_public_lobby_ip()
			start_game_from_lobby.rpc()
		else:
			# Update lobby UI for everyone
			update_lobby_ui.rpc(player_ids, target_player_count)
	else:
		# If the game has already started, update the ropes
		setup_ropes.rpc(player_ids)

@rpc("authority", "call_local", "reliable")
func setup_ropes(player_ids: Array) -> void:
	# Check if all players in player_ids actually exist on the client yet!
	var all_exist = true
	for id in player_ids:
		var player = players_container.get_node_or_null(str(id))
		if not is_instance_valid(player):
			all_exist = false
			break
			
	if not all_exist:
		# If some players do not exist yet, defer this call by one frame to let MultiplayerSpawner spawn them
		call_deferred("setup_ropes", player_ids)
		return

	# Clear old ropes
	for child in ropes_container.get_children():
		child.queue_free()
		
	# Clear each player's ropes array
	for player in players_container.get_children():
		if player is PlayerController:
			player.ropes.clear()
			
	# Update player indices and visuals first
	for i in range(player_ids.size()):
		var id = player_ids[i]
		var player = players_container.get_node_or_null(str(id))
		if is_instance_valid(player) and player is PlayerController:
			player.player_index = i + 1
			player._update_player_visuals()
			
	# Re-link player controllers with fresh ropes
	for i in range(player_ids.size() - 1):
		var id_a = player_ids[i]
		var id_b = player_ids[i+1]
		
		# Find Player Nodes (using node names matching player ids)
		var player_a = players_container.get_node_or_null(str(id_a))
		var player_b = players_container.get_node_or_null(str(id_b))
		
		if is_instance_valid(player_a) and is_instance_valid(player_b):
			# Instantiate rope
			var rope_inst = rope_scene.instantiate()
			ropes_container.add_child(rope_inst)
			rope_inst.initialize(player_a, player_b)
			
			# Assign rope references to player controllers
			player_a.ropes.append(rope_inst)
			player_b.ropes.append(rope_inst)
			
			print("Rope initialized between Player ", id_a, " and Player ", id_b)

## --- Gameplay Loop & Hazard Management ---

var game_over_panel: Panel = null

func _create_game_over_ui() -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	var ui_node = get_node("UI")
	if not ui_node:
		return
		
	game_over_panel = Panel.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.visible = false
	game_over_panel.size = Vector2(1000, 640)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.45)
	style_box.corner_radius_top_left = 80
	style_box.corner_radius_top_right = 80
	style_box.corner_radius_bottom_left = 80
	style_box.corner_radius_bottom_right = 80
	game_over_panel.add_theme_stylebox_override("panel", style_box)
	
	# GameOver Label
	var title = Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = Vector2(1000, 160)
	title.position = Vector2(0, 80)
	title.add_theme_color_override("font_color", Color("#FF2D78"))
	title.add_theme_font_size_override("font_size", 112)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("outline_size", 8)
	
	var title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["SF Pro Rounded", "Nunito", "Avenir Next Rounded", "Avenir Next", "Helvetica Neue"])
	title_font.font_weight = 900
	title.add_theme_font_override("font", title_font)
	game_over_panel.add_child(title)
	
	# Retry Button – candy style
	var retry_btn = Button.new()
	retry_btn.text = "RETRY"
	retry_btn.icon = load("res://assets/icons/play_fill.png")
	retry_btn.expand_icon = true
	retry_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	retry_btn.size = Vector2(600, 180)
	retry_btn.position = Vector2(200, 360)
	_style_button(retry_btn, "#FFB800", 64)
	retry_btn.add_theme_font_override("font", title_font)
	
	retry_btn.pressed.connect(_on_retry_pressed)
	game_over_panel.add_child(retry_btn)
	
	ui_node.add_child(game_over_panel)
	var viewport_size = game_over_panel.get_viewport_rect().size
	game_over_panel.position = (viewport_size - game_over_panel.size) / 2.0

func _on_retry_pressed() -> void:
	if multiplayer.multiplayer_peer == null:
		request_retry()
	else:
		request_retry.rpc()

@rpc("any_peer", "call_local", "reliable")
func request_retry() -> void:
	if multiplayer.multiplayer_peer == null:
		reset_players_to_start()
		return
		
	if multiplayer.is_server():
		reset_players_to_start.rpc()

func spawn_blood_splatter(pos: Vector2) -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	var particles = CPUParticles2D.new()
	particles.global_position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 32
	particles.lifetime = 0.8
	particles.explosiveness = 0.9
	particles.spread = 180.0
	particles.initial_velocity_min = 120.0
	particles.initial_velocity_max = 240.0
	particles.gravity = Vector2(0, 450) # pull down
	particles.color = Color("#ff1744") # Red
	particles.scale_amount_min = 4.0
	particles.scale_amount_max = 8.0
	
	add_child(particles)
	
	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(particles.queue_free)

func spawn_confetti() -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	var ui_node = get_node_or_null("UI")
	var parent_node = ui_node if ui_node else self
	
	var viewport_size = get_viewport_rect().size
	var colors = [
		Color("#ff1744"), # Red
		Color("#ffd54f"), # Yellow
		Color("#00e676"), # Green
		Color("#29b6f6"), # Cyan
		Color("#d500f9"), # Purple/Magenta
		Color("#ff9100")  # Orange
	]
	
	# 5 positions across the screen width to rain confetti everywhere
	var spawn_ratios = [0.1, 0.3, 0.5, 0.7, 0.9]
	
	for ratio in spawn_ratios:
		var start_x = ratio * viewport_size.x
		var base_pos = Vector2(start_x, 50.0) # Shoot from high up near the top of the screen
		
		# Spawn 2 emitters with different colors at each position
		for i in range(2):
			var particles = CPUParticles2D.new()
			particles.global_position = base_pos + Vector2(randf_range(-15, 15), randf_range(-15, 15))
			particles.emitting = true
			particles.one_shot = true
			particles.amount = 35 # 35 particles per emitter (350 total, ~2.5x more than before)
			particles.lifetime = 3.0 # longer lifetime so they fall all the way down
			particles.explosiveness = 0.7
			particles.direction = Vector2(0, 1) # Shoot downwards
			particles.spread = 90.0 # Wide cone downwards
			particles.initial_velocity_min = 150.0
			particles.initial_velocity_max = 350.0
			particles.gravity = Vector2(0, 300.0) # gravity pulls them down
			
			# Rectangular confetti shape
			particles.scale_amount_min = 8.0
			particles.scale_amount_max = 16.0
			
			# Set a distinct color for this emitter
			particles.color = colors[randi() % colors.size()]
			
			parent_node.add_child(particles)
			var timer = get_tree().create_timer(3.5)
			timer.timeout.connect(particles.queue_free)

func player_hit_spike(player: PlayerController, knockback_velocity: Vector2 = Vector2.ZERO) -> void:
	if is_game_over:
		return
		
	# Vibrate device if this is the player we control
	if is_instance_valid(player) and player.is_multiplayer_authority():
		Input.vibrate_handheld(300)
		
	# If offline, trigger locally
	if multiplayer.multiplayer_peer == null:
		trigger_game_over(player.global_position, player.name, knockback_velocity)
	else:
		# Online: RPC report to the server
		report_player_hit.rpc(player.name, player.global_position, knockback_velocity)

@rpc("any_peer", "call_local", "reliable")
func report_player_hit(player_name: String, hit_position: Vector2, knockback_velocity: Vector2) -> void:
	if not multiplayer.is_server():
		return
		
	if is_game_over:
		return
		
	# Server broadcasts the authoritative game over to all clients
	trigger_game_over.rpc(hit_position, player_name, knockback_velocity)

@rpc("authority", "call_local", "reliable")
func trigger_game_over(hit_position: Vector2, hit_player_name: String = "", knockback_velocity: Vector2 = Vector2.ZERO) -> void:
	if is_game_over:
		return
	is_game_over = true
	
	# 1. Spawn blood particles
	spawn_blood_splatter(hit_position)
	
	# 2. Disable player inputs (keep physics running in background)
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if is_instance_valid(player):
			player.controls_enabled = false
			if player.name == hit_player_name and knockback_velocity != Vector2.ZERO:
				player.velocity = knockback_velocity
			
	# 3. Wait 1.0 second, then show UI
	await get_tree().create_timer(1.0).timeout
	if game_over_panel:
		var viewport_size = game_over_panel.get_viewport_rect().size
		game_over_panel.position = (viewport_size - game_over_panel.size) / 2.0
		game_over_panel.visible = true

@rpc("authority", "call_local", "reliable")
func reset_players_to_start() -> void:
	is_game_over = false
	highscore_to_beat = highscore
	confetti_triggered_this_run = false
	# Reset score variables
	current_score = 0
	max_depth_reached = 100.0
	if score_label:
		score_label.text = "0"
		
	if game_over_panel:
		game_over_panel.visible = false
		
	# Reset the level generator chunks to the beginning
	if level_generator:
		level_generator.reset_generator()
		
	var players = get_tree().get_nodes_in_group("players")
	
	# Move players back to start and re-enable inputs
	for player in players:
		if is_instance_valid(player):
			var index = player.player_index
			player.global_position = Vector2(500 + ((index - 1) * 80), 100)
			player.velocity = Vector2.ZERO
			player.controls_enabled = true
			
			# Clear prediction buffers to prevent desync replay
			if player.is_multiplayer_authority():
				player.input_buffer.clear()
				player.state_buffer.clear()
				player.current_tick = 0
				
	# Re-initialize all ropes to snap back into position
	for child in ropes_container.get_children():
		if child is RopePhysics:
			child._initialize_rope()

func _physics_process(_delta: float) -> void:
	# Only the host/server computes the score
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	# Do not count score in game over screen
	if game_over_panel and game_over_panel.visible:
		return
		
	var players = get_tree().get_nodes_in_group("players")
	if players.size() == 0:
		return
		
	var deepest_y = -INF
	for player in players:
		if is_instance_valid(player):
			deepest_y = max(deepest_y, player.global_position.y)
			
	if deepest_y > max_depth_reached:
		max_depth_reached = deepest_y
		# 1 point per 100 pixels descended
		var score = max(0, int((max_depth_reached - 100.0) / 100.0))
		if score > current_score:
			if multiplayer.multiplayer_peer == null:
				_update_score_locally(score)
			else:
				update_score.rpc(score)

@rpc("authority", "call_local", "reliable")
func update_score(new_score: int) -> void:
	_update_score_locally(new_score)

func _update_score_locally(new_score: int) -> void:
	current_score = new_score
	if score_label:
		score_label.text = str(current_score)
		
	if current_score > highscore:
		highscore = current_score
		if highscore_label:
			highscore_label.text = "BEST: " + str(highscore)
		
		# Trigger confetti only once when beating a previous non-zero highscore
		if highscore_to_beat > 0 and current_score > highscore_to_beat and not confetti_triggered_this_run:
			confetti_triggered_this_run = true
			spawn_confetti()

func _create_hud_ui() -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	var ui_node = get_node("UI")
	if not ui_node:
		return

	# Main Title Logo at the top (shown only on main menu, outside the card)
	main_title_label = TextureRect.new()
	main_title_label.name = "MainTitleLabel"
	main_title_label.texture = load("res://logo.png")
	main_title_label.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main_title_label.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Size and position the logo nicely in the space above the main menu card
	main_title_label.size = Vector2(1200, 675)
	main_title_label.position = Vector2(-15, 50)
	
	ui_node.add_child(main_title_label)
		
	var hud_container = VBoxContainer.new()
	hud_container.name = "HUDContainer"
	hud_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Anchor top-center, lower it to clear the notch
	hud_container.anchor_left = 0.5
	hud_container.anchor_top = 0.0
	hud_container.anchor_right = 0.5
	hud_container.anchor_bottom = 0.0
	hud_container.size = Vector2(800, 600)
	hud_container.position.x = -400.0
	hud_container.position.y = 120.0
	hud_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	
	# Current Score Label
	score_label = Label.new()
	score_label.text = "0"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 252)
	score_label.add_theme_color_override("font_color", Color(1, 1, 1, 1)) # White
	score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1)) # Thick black outline
	score_label.add_theme_constant_override("outline_size", 36)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	score_label.add_theme_constant_override("shadow_offset_x", 18)
	score_label.add_theme_constant_override("shadow_offset_y", 18)
	hud_container.add_child(score_label)
	
	# Highscore Label
	highscore_label = Label.new()
	highscore_label.text = "BEST: 0"
	highscore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	highscore_label.add_theme_font_size_override("font_size", 108)
	highscore_label.add_theme_color_override("font_color", Color("#ffd54f")) # Fall Guys Yellow
	highscore_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1)) # Thick black outline
	highscore_label.add_theme_constant_override("outline_size", 20)
	highscore_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	highscore_label.add_theme_constant_override("shadow_offset_x", 12)
	highscore_label.add_theme_constant_override("shadow_offset_y", 12)
	hud_container.add_child(highscore_label)
	
	ui_node.add_child(hud_container)
	hud_container.position = Vector2((ui_node.get_parent().get_viewport_rect().size.x - hud_container.size.x) / 2.0, 120.0)
	
	# Pause / Menu Button at top-left (flat icon without background)
	var pause_btn = Button.new()
	pause_btn.name = "PauseButton"
	pause_btn.text = "☰"
	pause_btn.size = Vector2(200, 200)
	pause_btn.position = Vector2(40, 110)
	pause_btn.add_theme_font_size_override("font_size", 112)
	
	# Flat styling with StyleBoxEmpty
	var empty_style = StyleBoxEmpty.new()
	pause_btn.add_theme_stylebox_override("normal", empty_style)
	pause_btn.add_theme_stylebox_override("hover", empty_style)
	pause_btn.add_theme_stylebox_override("pressed", empty_style)
	pause_btn.add_theme_stylebox_override("focus", empty_style)
	
	# Color overrides for a premium feel
	pause_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85)) # semi-transparent white
	pause_btn.add_theme_color_override("font_hover_color", Color("#00e5ff")) # cyan highlight
	pause_btn.add_theme_color_override("font_pressed_color", Color("#00e5ff"))
	
	pause_btn.pressed.connect(_on_pause_pressed)
	touch_hud.add_child(pause_btn)
	
	# Room Code Label in top-right (shifted left to make room for mic button)
	room_code_label = Label.new()
	room_code_label.name = "RoomCodeLabel"
	room_code_label.text = ""
	room_code_label.visible = false
	room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	room_code_label.size = Vector2(400, 80)
	var viewport_width = ui_node.get_parent().get_viewport_rect().size.x
	room_code_label.position = Vector2(viewport_width - 600, 145)
	room_code_label.add_theme_font_size_override("font_size", 44)
	room_code_label.add_theme_color_override("font_color", Color("#b388ff")) # Fall Guys Purple
	room_code_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1)) # Black outline
	room_code_label.add_theme_constant_override("outline_size", 12)
	touch_hud.add_child(room_code_label)

	# Microphone Toggle Button (HUD) - Positioned in the top-right corner with 150x150 touch area
	mic_btn = Button.new()
	mic_btn.name = "MicButton"
	mic_btn.size = Vector2(150, 150)
	mic_btn.position = Vector2(viewport_width - 190, 110)
	mic_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_mic_button(false)
	mic_btn.pressed.connect(_on_mic_toggle_pressed)
	touch_hud.add_child(mic_btn)


func _create_ingame_menu_ui() -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	var ui_node = get_node("UI")
	if not ui_node:
		return
		
	ingame_menu_panel = Panel.new()
	ingame_menu_panel.name = "InGameMenuPanel"
	ingame_menu_panel.visible = false
	ingame_menu_panel.size = Vector2(1000, 1020)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.45)
	style_box.corner_radius_top_left = 80
	style_box.corner_radius_top_right = 80
	style_box.corner_radius_bottom_left = 80
	style_box.corner_radius_bottom_right = 80
	ingame_menu_panel.add_theme_stylebox_override("panel", style_box)
	
	# Title
	var title = Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = Vector2(1000, 160)
	title.position = Vector2(0, 60)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	title.add_theme_constant_override("outline_size", 6)
	ingame_menu_panel.add_child(title)
	
	# 1. Resume Button
	var resume_btn = Button.new()
	resume_btn.text = "CONTINUER"
	resume_btn.icon = load("res://assets/icons/play_fill.png")
	resume_btn.expand_icon = true
	resume_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	resume_btn.size = Vector2(800, 150)
	resume_btn.position = Vector2(100, 260)
	_style_button(resume_btn, "#00E676", 52)  # Green
	resume_btn.pressed.connect(_on_resume_pressed)
	ingame_menu_panel.add_child(resume_btn)
	
	# 2. Restart Button
	var restart_btn = Button.new()
	restart_btn.text = "RECOMMENCER"
	restart_btn.icon = load("res://assets/icons/arrow_counterclockwise.png")
	restart_btn.expand_icon = true
	restart_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	restart_btn.size = Vector2(800, 150)
	restart_btn.position = Vector2(100, 450)
	_style_button(restart_btn, "#FFB800", 52)  # Golden yellow
	restart_btn.pressed.connect(_on_ingame_restart_pressed)
	ingame_menu_panel.add_child(restart_btn)
	
	# 3. Mute Others Button
	mute_others_btn = Button.new()
	mute_others_btn.size = Vector2(800, 150)
	mute_others_btn.position = Vector2(100, 640)
	_update_mute_others_button()
	mute_others_btn.pressed.connect(_on_mute_others_pressed)
	ingame_menu_panel.add_child(mute_others_btn)
	
	# 4. Main Menu Button
	var mainmenu_btn = Button.new()
	mainmenu_btn.text = "MENU PRINCIPAL"
	mainmenu_btn.icon = load("res://assets/icons/house_fill.png")
	mainmenu_btn.expand_icon = true
	mainmenu_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mainmenu_btn.size = Vector2(800, 150)
	mainmenu_btn.position = Vector2(100, 830)
	_style_button(mainmenu_btn, "#FF2D78", 52)  # Hot pink
	mainmenu_btn.pressed.connect(_on_quit_to_main_menu_pressed)
	ingame_menu_panel.add_child(mainmenu_btn)
	
	ui_node.add_child(ingame_menu_panel)
	var viewport_size = ingame_menu_panel.get_viewport_rect().size
	ingame_menu_panel.position = (viewport_size - ingame_menu_panel.size) / 2.0

func _on_pause_pressed() -> void:
	if is_game_over:
		return
	if ingame_menu_panel:
		# Center it first in case screen resized
		var viewport_size = ingame_menu_panel.get_viewport_rect().size
		ingame_menu_panel.position = (viewport_size - ingame_menu_panel.size) / 2.0
		ingame_menu_panel.visible = true
		
	# Disable player controls
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if is_instance_valid(player):
			player.controls_enabled = false

func _on_resume_pressed() -> void:
	if ingame_menu_panel:
		ingame_menu_panel.visible = false
		
	# Re-enable player controls
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if is_instance_valid(player):
			player.controls_enabled = true

func _on_ingame_restart_pressed() -> void:
	if ingame_menu_panel:
		ingame_menu_panel.visible = false
	_on_retry_pressed()

func _on_quit_to_main_menu_pressed() -> void:
	if ingame_menu_panel:
		ingame_menu_panel.visible = false
	reset_game()

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	# Update level generator visibility (hide platforms/walls when on main menu, lobby panels, or lobby is active)
	if level_generator:
		var is_on_menu = (menu_panel.visible if menu_panel else false) or \
						 (lobby_select_panel.visible if lobby_select_panel else false) or \
						 (lobby_wait_panel.visible if lobby_wait_panel else false) or \
						 lobby_is_active
		level_generator.visible = not is_on_menu
		
	# 1. Animate drifting clouds
	var screen_width = get_viewport_rect().size.x
	if screen_width <= 0.0:
		screen_width = 1170.0
		
	for cloud in clouds_list:
		if is_instance_valid(cloud):
			cloud.position.x += 15.0 * delta
			if cloud.position.x > screen_width + 120.0:
				cloud.position.x = -120.0
				



func _input(event: InputEvent) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if menu_panel and menu_panel.visible:
		return
		
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_id == -1:
				touch_id = event.index
				touch_start_pos = event.position
				touch_dir = 0.0
		elif event.index == touch_id:
			var dist = event.position.distance_to(touch_start_pos)
			if dist < 25.0:
				touch_pull = true
			touch_id = -1
			touch_dir = 0.0
			
	elif event is InputEventScreenDrag:
		if event.index == touch_id:
			var drag_offset = event.position - touch_start_pos
			# Max drag distance of 120 pixels for full speed
			touch_dir = clamp(drag_offset.x / 120.0, -1.0, 1.0)


func _create_lobby_ui() -> void:
	var ui_node = get_node("UI")
	if not ui_node:
		return
		
	var viewport_size = get_viewport_rect().size
	if viewport_size.x <= 0.0:
		viewport_size = Vector2(1170, 2532) # fallback
		
	# 1. Lobby Select Panel (Number of players)
	lobby_select_panel = Panel.new()
	lobby_select_panel.name = "LobbySelectPanel"
	lobby_select_panel.visible = false
	lobby_select_panel.size = Vector2(1080, 1100)
	lobby_select_panel.position = Vector2((viewport_size.x - lobby_select_panel.size.x) / 2.0, viewport_size.y - lobby_select_panel.size.y - 80.0)
	
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0, 0, 0, 0)
	lobby_select_panel.add_theme_stylebox_override("panel", card_style)
	ui_node.add_child(lobby_select_panel)
	
	var select_title = Label.new()
	select_title.text = "CONFIGURER LA PARTIE"
	select_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_title.size = Vector2(920, 80)
	select_title.position = Vector2(80, 40)
	select_title.add_theme_font_size_override("font_size", 54)
	select_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	select_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	select_title.add_theme_constant_override("outline_size", 6)
	lobby_select_panel.add_child(select_title)
	
	var select_label = Label.new()
	select_label.name = "SelectLabel"
	select_label.text = "Choisissez le nombre de joueurs total :"
	select_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_label.size = Vector2(920, 80)
	select_label.position = Vector2(80, 140)
	select_label.add_theme_font_size_override("font_size", 44)
	select_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
	select_label.add_theme_constant_override("outline_size", 4)
	lobby_select_panel.add_child(select_label)
	
	# Buttons for 2, 3, 4 players
	var btn_2 = Button.new()
	btn_2.text = "2 JOUEURS"
	btn_2.icon = load("res://assets/icons/person_2_fill.png")
	btn_2.expand_icon = true
	btn_2.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_2.size = Vector2(920, 160)
	btn_2.position = Vector2(80, 260)
	_style_button(btn_2, "#00E676", 52)
	btn_2.pressed.connect(func(): _on_player_count_selected(2))
	lobby_select_panel.add_child(btn_2)
	
	var btn_3 = Button.new()
	btn_3.text = "3 JOUEURS"
	btn_3.icon = load("res://assets/icons/person_2_fill.png")
	btn_3.expand_icon = true
	btn_3.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_3.size = Vector2(920, 160)
	btn_3.position = Vector2(80, 460)
	_style_button(btn_3, "#00AAFF", 52)
	btn_3.pressed.connect(func(): _on_player_count_selected(3))
	lobby_select_panel.add_child(btn_3)
	
	var btn_4 = Button.new()
	btn_4.text = "4 JOUEURS"
	btn_4.icon = load("res://assets/icons/person_2_fill.png")
	btn_4.expand_icon = true
	btn_4.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_4.size = Vector2(920, 160)
	btn_4.position = Vector2(80, 660)
	_style_button(btn_4, "#AA55FF", 52)
	btn_4.pressed.connect(func(): _on_player_count_selected(4))
	lobby_select_panel.add_child(btn_4)
	
	var btn_back = Button.new()
	btn_back.text = "RETOUR"
	btn_back.icon = load("res://assets/icons/chevron_left.png")
	btn_back.expand_icon = true
	btn_back.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_back.size = Vector2(920, 150)
	btn_back.position = Vector2(80, 870)
	_style_button(btn_back, "#FF2D78", 48)
	btn_back.pressed.connect(_on_lobby_select_back_pressed)
	lobby_select_panel.add_child(btn_back)
	
	# 2. Lobby Wait Panel
	lobby_wait_panel = Panel.new()
	lobby_wait_panel.name = "LobbyWaitPanel"
	lobby_wait_panel.visible = false
	lobby_wait_panel.size = Vector2(1080, 1020)
	lobby_wait_panel.position = Vector2((viewport_size.x - lobby_wait_panel.size.x) / 2.0, viewport_size.y - lobby_wait_panel.size.y - 80.0)
	
	var wait_style = StyleBoxFlat.new()
	wait_style.bg_color = Color(0, 0, 0, 0.45)
	wait_style.corner_radius_top_left = 80
	wait_style.corner_radius_top_right = 80
	wait_style.corner_radius_bottom_left = 80
	wait_style.corner_radius_bottom_right = 80
	lobby_wait_panel.add_theme_stylebox_override("panel", wait_style)
	ui_node.add_child(lobby_wait_panel)
	
	var wait_title = Label.new()
	wait_title.text = "SALON D'ATTENTE"
	wait_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_title.size = Vector2(920, 80)
	wait_title.position = Vector2(80, 60)
	wait_title.add_theme_font_size_override("font_size", 54)
	wait_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	wait_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	wait_title.add_theme_constant_override("outline_size", 6)
	lobby_wait_panel.add_child(wait_title)
	
	var code_hbox = HBoxContainer.new()
	code_hbox.name = "CodeHBox"
	code_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	code_hbox.size = Vector2(920, 80)
	code_hbox.position = Vector2(80, 150)
	lobby_wait_panel.add_child(code_hbox)
	
	lobby_code_label = Label.new()
	lobby_code_label.text = "CODE DE SALON : ----"
	lobby_code_label.add_theme_font_size_override("font_size", 48)
	lobby_code_label.add_theme_color_override("font_color", Color("#FFB800"))
	lobby_code_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	lobby_code_label.add_theme_constant_override("outline_size", 4)
	code_hbox.add_child(lobby_code_label)
	
	var copy_btn = Button.new()
	copy_btn.name = "CopyButton"
	copy_btn.text = ""
	var copy_tex = load("res://assets/doc_on_doc.png")
	copy_btn.icon = copy_tex
	copy_btn.expand_icon = true
	copy_btn.tooltip_text = "Copier le code de salon"
	_style_button(copy_btn, "#FFB800", 32)
	copy_btn.custom_minimum_size = Vector2(80, 60)
	copy_btn.pressed.connect(_on_copy_pressed)
	code_hbox.add_child(copy_btn)
	
	lobby_slots_container = VBoxContainer.new()
	lobby_slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	lobby_slots_container.size = Vector2(920, 480)
	lobby_slots_container.position = Vector2(80, 250)
	lobby_wait_panel.add_child(lobby_slots_container)
	
	lobby_status_label = Label.new()
	lobby_status_label.text = "En attente des joueurs..."
	lobby_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_status_label.size = Vector2(920, 60)
	lobby_status_label.position = Vector2(80, 750)
	lobby_status_label.add_theme_font_size_override("font_size", 38)
	lobby_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	lobby_wait_panel.add_child(lobby_status_label)
	
	var btn_leave = Button.new()
	btn_leave.text = "QUITTER LE SALON"
	btn_leave.icon = load("res://assets/icons/chevron_left.png")
	btn_leave.expand_icon = true
	btn_leave.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_leave.size = Vector2(920, 140)
	btn_leave.position = Vector2(80, 840)
	_style_button(btn_leave, "#FF2D78", 48)
	btn_leave.pressed.connect(_on_lobby_leave_pressed)
	lobby_wait_panel.add_child(btn_leave)

func _update_lobby_slots_ui(player_ids: Array, target_count: int) -> void:
	if not lobby_slots_container:
		return
		
	# Clear old slots
	for child in lobby_slots_container.get_children():
		child.queue_free()
		
	for i in range(target_count):
		var slot_panel = PanelContainer.new()
		var slot_style = StyleBoxFlat.new()
		slot_style.bg_color = Color("#2a2b36")
		slot_style.corner_radius_top_left = 16
		slot_style.corner_radius_top_right = 16
		slot_style.corner_radius_bottom_left = 16
		slot_style.corner_radius_bottom_right = 16
		slot_panel.add_theme_stylebox_override("panel", slot_style)
		
		slot_panel.custom_minimum_size = Vector2(920, 80)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 30)
		margin.add_theme_constant_override("margin_right", 30)
		slot_panel.add_child(margin)
		
		var hbox = HBoxContainer.new()
		margin.add_child(hbox)
		
		var slot_label = Label.new()
		slot_label.add_theme_font_size_override("font_size", 36)
		hbox.add_child(slot_label)
		
		if i < player_ids.size():
			var pid = player_ids[i]
			if pid == 1:
				slot_label.text = "Joueur 1 : Hote (Connecte)"
				slot_label.add_theme_color_override("font_color", Color("#00e676"))
			else:
				slot_label.text = "Joueur " + str(i + 1) + " : Client (Connecte)"
				slot_label.add_theme_color_override("font_color", Color("#00e5ff"))
		else:
			slot_label.text = "Joueur " + str(i + 1) + " : En attente..."
			slot_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
			
		lobby_slots_container.add_child(slot_panel)
		
	if lobby_status_label:
		lobby_status_label.text = "En attente des joueurs (%d/%d)..." % [player_ids.size(), target_count]

func _on_host_clicked() -> void:
	if menu_panel:
		menu_panel.visible = false
	if lobby_select_panel:
		lobby_select_panel.visible = true

func _on_player_count_selected(count: int) -> void:
	target_player_count = count
	
	# Keep the lobby select panel visible and show connecting status on it
	if lobby_select_panel:
		var lbl = lobby_select_panel.find_child("SelectLabel", true, false) as Label
		if lbl:
			lbl.text = "Connecting to the world..."
		for child in lobby_select_panel.get_children():
			if child is Button:
				child.disabled = true
				
	clear_game_session()
	lobby_is_active = true
	network_manager.is_public_lobby = false
	
	# Wait one frame to let the label draw the text!
	await get_tree().process_frame
	
	var err = await network_manager.host_game(count)
	if err == OK:
		var host_ip = network_manager.public_ip
		if host_ip == "":
			# If IP resolution failed, restore lobby select panel state and fail
			if lobby_select_panel:
				lobby_select_panel.visible = false
				var lbl = lobby_select_panel.find_child("SelectLabel", true, false) as Label
				if lbl:
					lbl.text = "Choisissez le nombre de joueurs total :"
				for child in lobby_select_panel.get_children():
					if child is Button:
						child.disabled = false
			if status_label:
				status_label.text = "Impossible de récupérer l'adresse IP publique."
			reset_game()
			return
			
		# Hide the lobby select panel since we succeeded
		if lobby_select_panel:
			lobby_select_panel.visible = false
			var lbl = lobby_select_panel.find_child("SelectLabel", true, false) as Label
			if lbl:
				lbl.text = "Choisissez le nombre de joueurs total :"
			for child in lobby_select_panel.get_children():
				if child is Button:
					child.disabled = false
					
		if menu_panel:
			menu_panel.visible = false
		if status_label:
			status_label.text = ""
			
		current_room_code = ip_to_code(host_ip)
		
		if lobby_wait_panel:
			lobby_wait_panel.visible = true
		if lobby_code_label:
			lobby_code_label.text = "CODE DE SALON : " + current_room_code
			
		var copy_btn = lobby_wait_panel.find_child("CopyButton", true, false) as Button
		if copy_btn:
			copy_btn.visible = true
			
		_update_lobby_slots_ui([1], count)
	else:
		# If hosting failed, restore lobby select panel and transition back to main menu
		if lobby_select_panel:
			lobby_select_panel.visible = false
			var lbl = lobby_select_panel.find_child("SelectLabel", true, false) as Label
			if lbl:
				lbl.text = "Choisissez le nombre de joueurs total :"
			for child in lobby_select_panel.get_children():
				if child is Button:
					child.disabled = false
					
		if menu_panel:
			menu_panel.visible = true
		if status_label:
			status_label.text = "Échec du démarrage de l'hébergement."

func _on_lobby_select_back_pressed() -> void:
	if lobby_select_panel:
		lobby_select_panel.visible = false
	if menu_panel:
		menu_panel.visible = true

func _on_lobby_leave_pressed() -> void:
	reset_game()

@rpc("authority", "call_local", "reliable")
func update_lobby_ui(player_ids: Array, target_count: int) -> void:
	target_player_count = target_count
	lobby_is_active = true
	if menu_panel:
		menu_panel.visible = false
	if lobby_select_panel:
		lobby_select_panel.visible = false
	if lobby_wait_panel:
		lobby_wait_panel.visible = true
	_update_lobby_slots_ui(player_ids, target_count)

@rpc("authority", "call_local", "reliable")
func start_game_from_lobby() -> void:
	lobby_is_active = false
	if lobby_wait_panel:
		lobby_wait_panel.visible = false
		
	_set_gameplay_ui_active(true)
	
	if multiplayer.is_server():
		var player_ids = network_manager.players.keys()
		player_ids.sort()
		setup_ropes.rpc(player_ids)
		reset_players_to_start.rpc()


## --- Voice Chat UI Handling ---

func _style_mic_button(active: bool) -> void:
	if not mic_btn:
		return
		
	# Clear text to use texture icon
	mic_btn.text = ""
	
	# Load PNG textures
	var tex = load("res://assets/mic_fill.png") if active else load("res://assets/mic_slash_fill.png")
	mic_btn.icon = tex
	mic_btn.expand_icon = true
	
	# Translucent dark slate background when muted, translucent green when active
	var bg_color = Color(0.12, 0.12, 0.16, 0.65)
	var border_color = Color(1.0, 0.32, 0.32, 0.8) # Red border for muted
	if active:
		bg_color = Color(0.0, 0.72, 0.36, 0.75)
		border_color = Color(0.2, 1.0, 0.5, 1.0) # Bright green border for active
		
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 30
	style_normal.corner_radius_top_right = 30
	style_normal.corner_radius_bottom_left = 30
	style_normal.corner_radius_bottom_right = 30
	style_normal.border_width_left = 4
	style_normal.border_width_top = 4
	style_normal.border_width_right = 4
	style_normal.border_width_bottom = 4
	style_normal.border_color = border_color
	
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = bg_color.lightened(0.1)
	style_hover.corner_radius_top_left = 30
	style_hover.corner_radius_top_right = 30
	style_hover.corner_radius_bottom_left = 30
	style_hover.corner_radius_bottom_right = 30
	style_hover.border_width_left = 4
	style_hover.border_width_top = 4
	style_hover.border_width_right = 4
	style_hover.border_width_bottom = 4
	style_hover.border_color = border_color.lightened(0.1)
	
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = bg_color.darkened(0.1)
	style_pressed.corner_radius_top_left = 30
	style_pressed.corner_radius_top_right = 30
	style_pressed.corner_radius_bottom_left = 30
	style_pressed.corner_radius_bottom_right = 30
	style_pressed.border_width_left = 4
	style_pressed.border_width_top = 4
	style_pressed.border_width_right = 4
	style_pressed.border_width_bottom = 4
	style_pressed.border_color = border_color.darkened(0.1)
	
	mic_btn.add_theme_stylebox_override("normal", style_normal)
	mic_btn.add_theme_stylebox_override("hover", style_hover)
	mic_btn.add_theme_stylebox_override("pressed", style_pressed)
	mic_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	# Tint the icon texture itself
	mic_btn.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 1))
	mic_btn.add_theme_color_override("icon_hover_color", Color(1, 1, 1, 0.95))
	mic_btn.add_theme_color_override("icon_pressed_color", Color(1, 1, 1, 0.85))

func _on_mic_toggle_pressed() -> void:
	var id = 1
	if multiplayer.multiplayer_peer != null:
		id = multiplayer.get_unique_id()
	print("[MIC] Button pressed! Target player ID: ", id)
	
	var local_player = get_node_or_null("Players/" + str(id))
	if local_player:
		print("[MIC] Found local player node: ", local_player.name)
		if local_player.has_method("toggle_microphone"):
			var is_active = local_player.toggle_microphone()
			_style_mic_button(is_active)
			print("[MIC] Microphone active toggled to: ", is_active)
		else:
			print("[MIC] Error: local player node does not have toggle_microphone method!")
	else:
		print("[MIC] Error: local player node not found under 'Players/", id, "'!")

func _update_mute_others_button() -> void:
	if not mute_others_btn:
		return
	if mute_others:
		mute_others_btn.text = "MICROS : COUPÉS"
		mute_others_btn.icon = load("res://assets/icons/speaker_slash_fill.png")
		mute_others_btn.expand_icon = true
		mute_others_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_button(mute_others_btn, "#FF2D78", 52) # Hot pink
	else:
		mute_others_btn.text = "MICROS : ACTIFS"
		mute_others_btn.icon = load("res://assets/icons/speaker_wave_2_fill.png")
		mute_others_btn.expand_icon = true
		mute_others_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_button(mute_others_btn, "#00AAFF", 52) # Sky blue

func _on_mute_others_pressed() -> void:
	mute_others = not mute_others
	_update_mute_others_button()
