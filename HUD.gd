extends Control

func _ready():
	Lobby.player_connected.connect(_on_player_connected)
	var newLabel = Label.new()
	newLabel.text = Lobby.player_info["name"] + " (You)"
	$HBoxContainer/Panel/ConnectedPlayers.add_child(newLabel)

func _on_player_connected(peer_id, player_info):
	var newLabel = Label.new()
	if ($HBoxContainer/Panel/ConnectedPlayers.get_child_count() > 1):
		newLabel.text = player_info["name"]
	$HBoxContainer/Panel/ConnectedPlayers.add_child(newLabel)

func set_life(life):
	$HBoxContainer/HealthBar.value = life * 25

func set_role(role):
	if role == 1: # Prop
		$RoleLabel.text = "ROLE: PROP"
	else:
		$RoleLabel.text = "ROLE: HUNTER"
