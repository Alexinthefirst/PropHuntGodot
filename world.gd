extends Node3D # Or Node2D.

var PlayerScene = preload("res://player/player.tscn")

const SPAWN_RANDOM := 5.0

func _ready():
	# Preconfigure game.
	#Lobby.player_loaded.rpc_id(1) # Tell the server that this peer has loaded.
	
	if not multiplayer.is_server():
		print("Not server")
		return
	
	multiplayer.peer_connected.connect(add_player)
	
	for id in multiplayer.get_peers():
		print("ADDED")
		add_player(id)
	
	if not OS.has_feature("dedicated_server"):
		add_player(1)
		pass

func add_player(id):
	var char = PlayerScene.instantiate()
	var pos := Vector2.from_angle(randf() * 2 * PI)
	char.position = Vector3(pos.x * SPAWN_RANDOM * randf(), 0, pos.y * SPAWN_RANDOM * randf())
	char.name = str(id)
	char.player_id = id
	$Players.add_child(char, true)


# Called only on the server.
func start_game():
	if !multiplayer.is_server():
		return
	
	print("Starting with " + str($Players.get_child_count()) + " players...")
	
	for player in $Players.get_children():
		player.change_role.rpc(1) # set all players to prop, then start
		player.health = 4
	
	# Randomly select Hunter
	var rand_player = $Players.get_child(randi_range(0, $Players.get_child_count() - 1))
	rand_player.change_role.rpc()
