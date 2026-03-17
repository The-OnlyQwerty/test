# Discord Bridge Setup

This project now includes a starter Discord-to-Roblox bridge in `backend/`.

## What it does

- Discord slash commands create jobs in the backend
- Roblox servers poll the backend for pending jobs
- Roblox servers also heartbeat their active player list
- Roblox executes only whitelisted actions

Supported job types:

- `announce`
- `setkills`
- `buff`

## Backend setup

1. Open `backend/.env.example`
2. Copy it to `.env`
3. Fill in:
   - `DISCORD_BOT_TOKEN`
   - `DISCORD_CLIENT_ID`
   - `DISCORD_GUILD_ID` (recommended during testing)
   - `DISCORD_ALLOWED_ROLE_IDS`
   - `DISCORD_AUDIT_CHANNEL_ID` (optional)
   - `BRIDGE_SHARED_SECRET`
   - `PORT`

4. Install packages:
   - `cd backend`
   - `npm install`

5. Start the bridge:
   - `npm start`

The API will start on `http://localhost:3000` unless you change `PORT`.

### Restricting Discord roles

Set `DISCORD_ALLOWED_ROLE_IDS` in `.env` to a comma-separated list of Discord role IDs allowed to use the bridge commands.

Example:

```env
DISCORD_ALLOWED_ROLE_IDS=123456789012345678,987654321098765432
```

If you leave it blank, everyone who can see the bot commands in that server can use them.

To get a role ID:

1. Enable Discord Developer Mode
2. Right-click the role in Server Settings
3. Copy the role ID

### Audit log channel

Set `DISCORD_AUDIT_CHANNEL_ID` in `.env` to a Discord text channel ID if you want all JD bridge command usage logged.

The audit log includes:

- who ran the command
- the job id and payload
- which server it targeted
- whether Roblox completed, failed, or timed out

## Roblox setup

In `src/ReplicatedStorage/Shared/Constants.lua`, set:

- `Constants.BRIDGE_BASE_URL = "http://YOUR_BACKEND_HOST:3000"`
- `Constants.BRIDGE_SHARED_SECRET = "same secret as backend"`

If you test locally with Studio, you may need to use a tunnel such as ngrok or host the backend on a reachable machine.

Also make sure `HttpService` is enabled in Roblox Game Settings.

## Discord commands

- `/announce message:<text> server:<any|main|training>`
- `/setkills username:<roblox username> amount:<number> server:<any|main|training>`
- `/buff username:<roblox username> stat:<Attack|Defense|Health|Mana|Stamina> amount:<number> server:<any|main|training>`
- `/heal username:<roblox username> amount:<optional> server:<any|main|training>`
- `/kick username:<roblox username> reason:<optional> server:<any|main|training>`
- `/returntomap username:<roblox username> server:<any|main|training>`
- `/duel challenger_username:<roblox username> opponent_username:<roblox username or dummy> server:<any|main|training>`
- `/shutdownserver reason:<optional> server:<any|main|training>`

### Command results

- Discord commands now wait briefly for Roblox to execute the job
- if the game finishes the job within about 20 seconds, Discord will show `completed` or `failed`
- if the server claims the job but takes too long, Discord will report that it timed out while waiting
- if the server never claims the job, Discord will report that it is still pending

## Important limitations

- all player-targeted commands require the relevant players to be online in the targeted server
- player-targeted jobs are routed to the exact live server that most recently heartbeated that player
- `announce` and `shutdownserver` still target a server role (`main`/`training`/`any`) rather than a specific player-hosting server
- this starter uses an in-memory queue, so queued jobs are lost if the backend restarts
- role checks are env-based and do not yet distinguish per-command permissions

## Recommended next upgrades

- persist jobs in SQLite/Postgres/Redis
- restrict Discord commands to approved roles
- add command result logging back into Discord
- add more whitelisted in-game actions
