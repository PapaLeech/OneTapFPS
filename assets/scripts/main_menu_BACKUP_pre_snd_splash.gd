extends Control

const GAME_SCENE := "res://levels/level_001.tscn"
const DOG_TAG_SCENE := preload("res://assets/ui/DogTag.tscn")
const BULLET_SLOT_SCENE := preload("res://ui/BulletSlot.tscn")
const MAX_LOBBY := 5
enum Mode { NONE, DEATHMATCH, SEARCH_AND_DESTROY }
enum ChatFocus { NONE, CHAT, TERMINAL }

var _lobby_players    : Array[String] = []
var _dog_tag_nodes    : Array = []
var _friend_slots     : Dictionary = {}
var _refreshing       : bool = false
var _active_mode      : Mode = Mode.NONE
var _timer            : SceneTreeTimer = null
var _count            : int = 3
var _quit_dialog_open : bool = false
var _chat_focus       : ChatFocus = ChatFocus.NONE
var _invite_sender    : String = ""
var _friends_header   : Label = null

# ─── Music playlist ──────────────────────────────────────────────────────────
const PLAYLIST := [
	"res://assets/audio/watermello-rock477138.mp3",
	"res://assets/audio/nastelbom-rock.mp3",
]
var _playlist_index : int = 0

# Invite notification nodes (built in code, hidden until an invite arrives)
var _invite_panel   : PanelContainer = null
var _invite_label   : Label = null
var _invite_accept  : Button = null
var _invite_decline : Button = null

@onready var _dm_btn             : PanelContainer = $CaseInner/Middle/DeathmatchBtn
@onready var _sd_btn             : PanelContainer = $CaseInner/Middle/SearchDestroyBtn
@onready var _dm_desc            : Label          = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Desc
@onready var _sd_desc            : Label          = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Desc
@onready var _dm_countdown       : HBoxContainer  = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown
@onready var _sd_countdown       : HBoxContainer  = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown
@onready var _dm_num             : Label          = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown/Num
@onready var _sd_num             : Label          = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown/Num
@onready var _dm_cancel          : Button         = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown/CancelBtn
@onready var _sd_cancel          : Button         = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown/CancelBtn
@onready var _play_btn           : Button         = $CaseInner/Middle/PlayBtn
@onready var _bg_texture         : TextureRect    = $Background
@onready var _settings_btn       : Button         = $SettingsBtn
@onready var _exit_btn           : Button         = $ExitBtn
@onready var _dog_tags_container : Control        = $CaseInner/Right/LobbyPanel/VBox/DogTags
@onready var _lobby_join_sound   : AudioStreamPlayer = $LobbyJoinSound2
@onready var _music_player       : AudioStreamPlayer = $MusicPlayer
@onready var _bullet_list        : VBoxContainer  = $CaseInner/Right/FriendsPanel/VBox/Scroll/BulletList
@onready var _join_btn           : Button         = $CaseInner/Right/LobbyPanel/VBox/BtnRow/JoinBtn
@onready var _leave_btn          : Button         = $CaseInner/Right/LobbyPanel/VBox/BtnRow/LeaveBtn
@onready var _chat_tab_btn       : Button         = $CaseInner/Left/ChatTerminalPanel/VBox/TabBar/ChatTab
@onready var _term_tab_btn       : Button         = $CaseInner/Left/ChatTerminalPanel/VBox/TabBar/TerminalTab
@onready var _chat_output        : RichTextLabel  = $CaseInner/Left/ChatTerminalPanel/VBox/ChatOutput
@onready var _term_output        : RichTextLabel  = $CaseInner/Left/ChatTerminalPanel/VBox/TerminalOutput
@onready var _input_line         : LineEdit       = $CaseInner/Left/ChatTerminalPanel/VBox/InputLine

# ─── Ready ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Skip all UI on dedicated server
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		return
	get_window().mode = Window.MODE_FULLSCREEN
	_bg_texture.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_style_mission_panel()
	_build_invite_panel()
	_dm_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_sd_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_dm_btn.gui_input.connect(func(e): _on_mode_clicked(e, Mode.DEATHMATCH))
	_sd_btn.gui_input.connect(func(e): _on_mode_clicked(e, Mode.SEARCH_AND_DESTROY))
	_dm_cancel.pressed.connect(_cancel_countdown)
	_sd_cancel.pressed.connect(_cancel_countdown)
	_play_btn.pressed.connect(func(): get_tree().change_scene_to_file(GAME_SCENE))
	_settings_btn.pressed.connect(_show_settings)
	_exit_btn.pressed.connect(func(): get_tree().quit())
	_dm_countdown.visible = false
	_sd_countdown.visible = false
	_style_lobby_buttons()
	_join_btn.pressed.connect(_on_join_pressed)
	_leave_btn.pressed.connect(_on_leave_pressed)
	_clear_placeholder_tags()
	_setup_chat_terminal()
	_setup_add_friend_button()
	_start_music()
	if not PresenceManager.has_username():
		_show_username_prompt()
	else:
		_go_online_and_fetch_friends()
	ClientToServer.invite_received.connect(_on_network_invite_received)
	ClientToServer.lobby_joined.connect(_on_lobby_joined)
	ClientToServer.invite_accepted.connect(_on_friend_accepted_invite)
	ClientToServer.lobby_match_starting.connect(_on_lobby_match_starting)

# BACKUP — pre snd_map_splash routing (Jun 2026)
# _on_lobby_joined was:
# func _on_lobby_joined() -> void:
# 	get_tree().change_scene_to_file("res://levels/map_splash.tscn")
