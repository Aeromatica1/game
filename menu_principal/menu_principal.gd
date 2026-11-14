extends Control

func _ready() -> void:
	Supabase.restore_session()
