extends HBoxContainer

@onready var name_label = $NameLabel
@onready var count_label = $CountLabel
@onready var lock_button = $LockButton

var resource_key : String
var manager

func setup(key:String, display:String, mgr):
    resource_key = key
    manager = mgr
    name_label.text = display
    lock_button.pressed.connect(toggle_lock)

func update_display(value:int, locked:bool):
    count_label.text = str(value)
    lock_button.text = "🔒" if locked else ""

func toggle_lock():
    manager.toggle_lock(resource_key)
