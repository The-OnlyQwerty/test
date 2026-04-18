local Constants = {}

Constants.MAX_TARGET_DISTANCE = 18
Constants.M1_RESET_TIME = 1.1
Constants.COMBAT_IDLE_TIMEOUT = 60
Constants.M1_STUN_TIME = 0.35
Constants.BLOCK_DAMAGE_REDUCTION = 0.75
Constants.DASH_COOLDOWN = 1.25
Constants.DASH_SPEED = 72
Constants.DASH_TIME = 0.18
Constants.DEFAULT_WALKSPEED = 16
Constants.RUN_WALKSPEED = 24
Constants.BLOCK_WALKSPEED = 8
Constants.BLOCK_COOLDOWN = 0.7
Constants.BLOCK_BREAK_STUN = 2
Constants.PERFECT_BLOCK_WINDOW = 0.18
Constants.PERFECT_BLOCK_STUN = 1.5
Constants.PERFECT_BLOCK_KNOCKBACK = 42
Constants.PVP_DAMAGE_MULTIPLIER = 0.6
Constants.KNOCKBACK_FORCE = 70000
Constants.KNOCKBACK_DURATION_MIN = 0.08
Constants.KNOCKBACK_DURATION_MAX = 0.22
Constants.KNOCKBACK_VERTICAL_SCALE = 0.18
Constants.KNOCKBACK_LAUNCH_VERTICAL_SCALE = 0.45
Constants.KNOCKBACK_VERTICAL_CAP = 32
Constants.FINAL_M1_KNOCKBACK = 56
Constants.KNOCKBACK_AIR_ANIMATION_ID = 99524807914301
Constants.KNOCKBACK_SLIDE_ANIMATION_ID = 136446815323979
Constants.KNOCKBACK_LANDING_MIN_TIME = 0.16
Constants.KNOCKBACK_LANDING_TIMEOUT = 2.1
Constants.KNOCKBACK_LANDING_Y_THRESHOLD = 10
Constants.KNOCKBACK_SLIDE_DURATION_FULL_MANA = 2
Constants.KNOCKBACK_SLIDE_DURATION_EMPTY_MANA = 4
Constants.KNOCKBACK_SLIDE_SPEED_SCALE = 0.35
Constants.KNOCKBACK_SLIDE_SPEED_MIN = 8
Constants.KNOCKBACK_SLIDE_SPEED_MAX = 24
Constants.NAOYA_FRAME_MARK_MAX = 3
Constants.NAOYA_FRAME_MARK_DURATION = 10
Constants.NAOYA_FRAME_FREEZE_DURATION = 2
Constants.SAMURAI_BLEED_MARK_MAX = 3
Constants.SAMURAI_BLEED_MARK_DURATION = 10
Constants.SAMURAI_BLEED_TICK_INTERVAL = 0.5
Constants.SAMURAI_BLEED_TICKS_PER_MARK = 2.5
Constants.SAMURAI_BLEED_DAMAGE_PER_TICK = 2
Constants.MENU_ATTRIBUTE = "MenuOpen"
Constants.GLOBAL_MUSIC_OVERRIDE_ATTRIBUTE = "GlobalMusicOverrideActive"
Constants.AWAITING_CHARACTER_ATTRIBUTE = "AwaitingCharacterSelect"
Constants.LOADING_ATTRIBUTE = "LoadingDone"
Constants.HITBOX_ATTRIBUTE = "HitboxesVisible"
Constants.TESTER_ACCESS_ATTRIBUTE = "TesterAccess"
Constants.TESTER_GROUP_ID = 0
Constants.TESTER_GROUP_ROLE_NAME = "Tester"
Constants.HITBOX_DEBUG_TOGGLE_KEY = Enum.KeyCode.H
Constants.DEBUG_HITBOX_ADMINS = {}
Constants.SANS_DODGE_DEBUG = false
Constants.MANA_REGEN_PER_SECOND = 8
Constants.STAMINA_REGEN_PER_SECOND = 6
Constants.RUN_STAMINA_DRAIN_PER_SECOND = 10
Constants.DASH_STAMINA_COST = 16
Constants.DOUBLE_TAP_DASH_WINDOW = 0.3
Constants.LOCK_ON_FOV = 78
Constants.DEFAULT_FOV = 70
Constants.CAMERA_LOCKED_DISTANCE = 10
Constants.CAMERA_LOCKED_HEIGHT = 3.2
Constants.CAMERA_LOCKED_RIGHT_SHIFT = 4.5
Constants.MENU_MUSIC_ID = 136525550209736
Constants.MENU_MUSIC_VOLUME = 0.45
Constants.BATTLE_MUSIC_ID = 107441664438773
Constants.BATTLE_MUSIC_VOLUME = 0.42
Constants.TENSE_BATTLE_MUSIC_ID = 85500611489769
Constants.TENSE_BATTLE_MUSIC_VOLUME = 0.46
Constants.TRAINING_MUSIC_ID = 140676812396849
Constants.TRAINING_MUSIC_VOLUME = 0.42
Constants.CHARACTER_THEME_VOLUME = 0.5
Constants.CHARACTER_THEME_NOTIFICATION_TIME = 3.6
Constants.CHARACTER_THEME_IDS = {
	Sans = 84691560956380,
	Magnus = 0,
	Samurai = 0,
	Naoya = 0,
}
Constants.CHARACTER_THEME_METADATA = {
	Sans = {
		SongName = "MEGALOVANIA [2026]",
		CreatorName = "acedd",
	},
}
Constants.SKIN_THEME_IDS = {
	Magnus = {
		BlackSilence = {
			Neutral = 133710371639576,
			Phase1 = 127641955671544,
			Phase2 = 74773589694284,
			Phase2Part2 = 97253954436045,
			Phase3 = 108908876148182,
		},
	},
}
Constants.SKIN_THEME_METADATA = {
	Magnus = {
		BlackSilence = {
			Neutral = {
				SongName = "Roland01",
				CreatorName = "Studio EIM",
			},
			Phase1 = {
				SongName = "Roland02",
				CreatorName = "Studio EIM",
			},
			Phase2 = {
				SongName = "Roland03",
				CreatorName = "Studio EIM",
			},
			Phase3 = {
				SongName = "Gone Angels",
				CreatorName = "Mili",
			},
		},
	},
}
Constants.BLACK_SILENCE_PHASE_TWO_HEALTH = 144
Constants.BLACK_SILENCE_PHASE_THREE_HEALTH = 88
Constants.BLACK_SILENCE_FINAL_PHASE_IFRAME_TIME = 1.35
Constants.BLACK_SILENCE_FINAL_PHASE_LOCK_TIME = 1.1
Constants.BLACK_SILENCE_FINAL_PHASE_DASH_SPEED = 52
Constants.BLACK_SILENCE_FINAL_PHASE_ANIMATION_ID = 0
Constants.GAMEPLAY_MUSIC_FADE_TIME = 0.4
Constants.DUEL_REQUEST_TIMEOUT = 20
Constants.DUEL_COUNTDOWN = 3
Constants.DUEL_RETURN_DELAY = 4
Constants.DUEL_RESPAWN_INVULN = 2
Constants.RANKED_START_RATING = 1000
Constants.RANKED_K_FACTOR = 24
Constants.RANK_TIERS = {
	{Name = "Bronze", MinRating = 0},
	{Name = "Silver", MinRating = 900},
	{Name = "Gold", MinRating = 1100},
	{Name = "Platinum", MinRating = 1300},
	{Name = "Diamond", MinRating = 1500},
	{Name = "Master", MinRating = 1700},
}
Constants.RANKED_QUEUE_ENTRY_TTL = 120
Constants.RANKED_ASSIGNMENT_TTL = 60
Constants.RANKED_MATCH_LOCK_SECONDS = 8
Constants.RANKED_MATCHMAKING_INTERVAL = 3
Constants.RANKED_ASSIGNMENT_POLL_INTERVAL = 2
Constants.RANKED_LEADERBOARD_REFRESH_INTERVAL = 30
Constants.MAIN_MAP_RETURN_POSITION = Vector3.new(0, 8, 64)
Constants.MAIN_GAME_PLACE_ID = 110569857364964
Constants.RANKED_QUEUE_PLACE_ID = 92675232156549
Constants.TRAINING_SERVER_ATTRIBUTE = "TrainingServer"
Constants.TRAINING_SERVER_PLACE_IDS = {
	82861222450068,
}
Constants.BRIDGE_BASE_URL = "https://judgement-divided.onrender.com"
Constants.BRIDGE_SHARED_SECRET = "judgement_divided_bridge_9f4a2c71_secure"
Constants.BRIDGE_POLL_INTERVAL = 2
Constants.BRIDGE_HEARTBEAT_INTERVAL = 5
Constants.ADMIN_USER_IDS = {
	4527372044,
	103145521,
	2488202610,
	2583906719,
}
Constants.ADMIN_PANEL_KEY = Enum.KeyCode.P

function Constants.GetRankTierName(rating)
	local numericRating = tonumber(rating) or Constants.RANKED_START_RATING
	local tierName = Constants.RANK_TIERS[1].Name

	for _, tier in ipairs(Constants.RANK_TIERS) do
		if numericRating >= tier.MinRating then
			tierName = tier.Name
		else
			break
		end
	end

	return tierName
end

return Constants
