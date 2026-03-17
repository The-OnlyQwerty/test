local Constants = {}

Constants.MAX_TARGET_DISTANCE = 18
Constants.M1_RESET_TIME = 1.1
Constants.M1_STUN_TIME = 0.35
Constants.BLOCK_DAMAGE_REDUCTION = 0.75
Constants.DASH_COOLDOWN = 1.25
Constants.DASH_SPEED = 72
Constants.DASH_TIME = 0.18
Constants.DEFAULT_WALKSPEED = 16
Constants.BLOCK_WALKSPEED = 8
Constants.BLOCK_COOLDOWN = 1.5
Constants.MENU_ATTRIBUTE = "MenuOpen"
Constants.LOADING_ATTRIBUTE = "LoadingDone"
Constants.HITBOX_ATTRIBUTE = "HitboxesVisible"
Constants.HITBOX_DEBUG_TOGGLE_KEY = Enum.KeyCode.H
Constants.DEBUG_HITBOX_ADMINS = {}
Constants.MANA_REGEN_PER_SECOND = 22
Constants.STAMINA_REGEN_PER_SECOND = 18
Constants.DASH_STAMINA_COST = 16
Constants.LOCK_ON_FOV = 78
Constants.DEFAULT_FOV = 70
Constants.CAMERA_LOCKED_DISTANCE = 10
Constants.CAMERA_LOCKED_HEIGHT = 3.2
Constants.CAMERA_LOCKED_RIGHT_SHIFT = 4.5
Constants.MENU_MUSIC_ID = 136525550209736
Constants.MENU_MUSIC_VOLUME = 0.45
Constants.DUEL_REQUEST_TIMEOUT = 20
Constants.DUEL_COUNTDOWN = 3
Constants.DUEL_RETURN_DELAY = 4
Constants.DUEL_RESPAWN_INVULN = 2
Constants.MAIN_MAP_RETURN_POSITION = Vector3.new(0, 8, 64)
Constants.MAIN_GAME_PLACE_ID = 110569857364964
Constants.TRAINING_SERVER_ATTRIBUTE = "TrainingServer"
Constants.TRAINING_SERVER_PLACE_IDS = {
	82861222450068,
}
Constants.BRIDGE_BASE_URL = "https://displayed-casey-england-bolt.trycloudflare.com"
Constants.BRIDGE_SHARED_SECRET = "judgement_divided_bridge_9f4a2c71_secure"
Constants.BRIDGE_POLL_INTERVAL = 2
Constants.BRIDGE_HEARTBEAT_INTERVAL = 5
Constants.ADMIN_USER_IDS = {
	4527372044,
	103145521,
	2488202610,
}
Constants.ADMIN_PANEL_KEY = Enum.KeyCode.P

return Constants
