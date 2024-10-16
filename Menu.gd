extends Control

func _ready():
	#get_tree().paused = true
	multiplayer.server_relay = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_create_pressed():
	print("Create pressed")
	Lobby.create_game()
	self.visible = false
	#get_parent().get_node("HUD").visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	start_game()


func _on_join_pressed():
	Lobby.join_game($VBoxContainer/HBoxContainer/IPAddress.text)
	self.visible = false
	#get_parent().get_node("HUD").visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	start_game()


func _on_name_box_text_set():
	Lobby.player_info["name"] = $VBoxContainer/NameBox.text
	print(Lobby.player_info["name"])


func start_game():
	get_tree().paused = false
	if multiplayer.is_server():
		change_level.call_deferred(load("res://world.tscn"))

# Call this function deferred and only on the main authority (server).
func change_level(scene: PackedScene):
	# Remove old level if any.
	var level = get_parent().get_node("Level")
	for c in level.get_children():
		level.remove_child(c)
		c.queue_free()
	# Add new level.
	get_parent().get_node("Level").add_child(scene.instantiate())


# The server can restart the level by pressing Home.
func _input(event):
	if not multiplayer.is_server():
		return
	if event.is_action("ui_home") and Input.is_action_just_pressed("ui_home"):
		change_level.call_deferred(load("res://level.tscn"))
