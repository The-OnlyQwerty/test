import "dotenv/config";
import express from "express";
import {
	Client,
	GatewayIntentBits,
	REST,
	Routes,
	SlashCommandBuilder,
} from "discord.js";

const requiredEnv = [
	"DISCORD_BOT_TOKEN",
	"DISCORD_CLIENT_ID",
	"BRIDGE_SHARED_SECRET",
];

for (const name of requiredEnv) {
	if (!process.env[name]) {
		throw new Error(`Missing required env var: ${name}`);
	}
}

const app = express();
app.use(express.json());

let nextJobId = 1;
const jobs = [];
const serverPresence = new Map();
const JOB_RESULT_TIMEOUT_MS = 20000;
const JOB_RESULT_POLL_MS = 500;
const auditChannelId = String(process.env.DISCORD_AUDIT_CHANNEL_ID || "").trim();
const allowedRoleIds = new Set(
	(process.env.DISCORD_ALLOWED_ROLE_IDS || "")
		.split(",")
		.map((value) => value.trim())
		.filter(Boolean)
);

function isAuthorizedInteraction(interaction) {
	if (allowedRoleIds.size === 0) {
		return true;
	}

	const roles = interaction.member?.roles;
	if (!roles) {
		return false;
	}

	const memberRoleIds = Array.isArray(roles)
		? roles
		: Array.isArray(roles.cache)
			? roles.cache.map((role) => role.id)
			: roles.cache
				? [...roles.cache.keys()]
				: [];

	return memberRoleIds.some((roleId) => allowedRoleIds.has(String(roleId)));
}

function createJob(type, payload, targetRole, requestedBy) {
	const job = {
		id: String(nextJobId++),
		type,
		payload,
		targetRole: targetRole || "any",
		requestedBy,
		status: "pending",
		createdAt: new Date().toISOString(),
		completedAt: null,
		result: null,
	};
	jobs.push(job);
	return job;
}

function formatJobResult(job) {
	const scope = job.targetServerJobId ? `server \`${job.targetServerJobId}\`` : `scope \`${job.targetRole}\``;
	if (job.status === "completed") {
		return `Job \`${job.id}\` completed on ${scope}: ${job.result || "ok"}.`;
	}
	if (job.status === "failed") {
		return `Job \`${job.id}\` failed on ${scope}: ${job.result || "unknown error"}.`;
	}
	if (job.status === "claimed") {
		return `Job \`${job.id}\` was claimed by Roblox but did not finish within ${Math.floor(JOB_RESULT_TIMEOUT_MS / 1000)}s.`;
	}
	return `Job \`${job.id}\` is still pending after ${Math.floor(JOB_RESULT_TIMEOUT_MS / 1000)}s.`;
}

function summarizePayload(payload) {
	if (!payload || typeof payload !== "object") {
		return "none";
	}

	const parts = [];
	for (const [key, value] of Object.entries(payload)) {
		if (value === undefined || value === null || value === "") {
			continue;
		}
		parts.push(`${key}=${String(value)}`);
	}

	return parts.length > 0 ? parts.join(", ") : "none";
}

async function sendAuditLog(lines) {
	if (!auditChannelId || !client.isReady()) {
		return;
	}

	try {
		const channel = await client.channels.fetch(auditChannelId);
		if (!channel || typeof channel.send !== "function") {
			return;
		}
		await channel.send({
			content: lines.join("\n"),
		});
	} catch (error) {
		console.error("Failed to send audit log:", error);
	}
}

async function waitForJobResult(job, timeoutMs = JOB_RESULT_TIMEOUT_MS) {
	const startedAt = Date.now();
	while (Date.now() - startedAt < timeoutMs) {
		if (job.status === "completed" || job.status === "failed") {
			return job;
		}
		await new Promise((resolve) => setTimeout(resolve, JOB_RESULT_POLL_MS));
	}
	return job;
}

async function queueJobAndRespond(interaction, type, payload, targetRole, requestedBy, responseTextBuilder) {
	await interaction.deferReply();
	const job = createJob(type, payload, targetRole, requestedBy);
	await sendAuditLog([
		"**JD Audit**",
		`Action: queued \`${job.type}\``,
		`Job: \`${job.id}\``,
		`By: ${requestedBy.tag} (\`${requestedBy.discordUserId}\`)`,
		`Server: \`${targetRole}\``,
		`Payload: ${summarizePayload(payload)}`,
	]);
	if (typeof responseTextBuilder === "function") {
		responseTextBuilder(job);
	}
	await waitForJobResult(job);
	await sendAuditLog([
		"**JD Audit**",
		`Action: result for \`${job.type}\``,
		`Job: \`${job.id}\``,
		`Status: \`${job.status}\``,
		`Result: ${job.result || "none"}`,
		`Claimed By: \`${job.claimedBy?.jobId || "unclaimed"}\``,
		`Completed By: \`${job.completedBy?.serverJobId || "n/a"}\``,
	]);
	await interaction.editReply(formatJobResult(job));
	return job;
}

async function waitForExistingJobAndRespond(interaction, job, targetRole, requestedBy) {
	await interaction.deferReply();
	await sendAuditLog([
		"**JD Audit**",
		`Action: queued \`${job.type}\``,
		`Job: \`${job.id}\``,
		`By: ${requestedBy.tag} (\`${requestedBy.discordUserId}\`)`,
		`Server: \`${targetRole}\``,
		`Target Server Job: \`${job.targetServerJobId || "none"}\``,
		`Payload: ${summarizePayload(job.payload)}`,
	]);
	await waitForJobResult(job);
	await sendAuditLog([
		"**JD Audit**",
		`Action: result for \`${job.type}\``,
		`Job: \`${job.id}\``,
		`Status: \`${job.status}\``,
		`Result: ${job.result || "none"}`,
		`Claimed By: \`${job.claimedBy?.jobId || "unclaimed"}\``,
		`Completed By: \`${job.completedBy?.serverJobId || "n/a"}\``,
	]);
	await interaction.editReply(formatJobResult(job));
	return job;
}

function normalizeName(value) {
	return String(value || "").trim().toLowerCase();
}

function cleanupPresence() {
	const cutoff = Date.now() - 30000;
	for (const [jobId, presence] of serverPresence.entries()) {
		if ((presence.lastSeenAt || 0) < cutoff) {
			serverPresence.delete(jobId);
		}
	}
}

function findPresenceForPlayer(targetName, targetRole) {
	cleanupPresence();
	const needle = normalizeName(targetName);
	if (!needle) {
		return null;
	}

	for (const presence of serverPresence.values()) {
		if (targetRole !== "any" && presence.role !== targetRole) {
			continue;
		}

		const match = (presence.players || []).find((player) => {
			return normalizeName(player.name) === needle || normalizeName(player.displayName) === needle;
		});

		if (match) {
			return {
				presence,
				player: match,
			};
		}
	}

	return null;
}

function authRoblox(req, res, next) {
	if (req.header("x-bridge-secret") !== process.env.BRIDGE_SHARED_SECRET) {
		res.status(401).json({ error: "unauthorized" });
		return;
	}
	next();
}

app.get("/health", (_req, res) => {
	res.json({ ok: true });
});

app.get("/api/roblox/jobs", authRoblox, (req, res) => {
	const role = req.query.role || "any";
	const serverJobId = String(req.query.jobId || "");
	const pendingJobs = jobs.filter((job) => {
		const roleMatch = job.targetRole === "any" || job.targetRole === role;
		const serverMatch = !job.targetServerJobId || job.targetServerJobId === serverJobId;
		return job.status === "pending" && roleMatch && serverMatch;
	});

	for (const job of pendingJobs) {
		job.status = "claimed";
		job.claimedBy = {
			placeId: String(req.query.placeId || ""),
			jobId: String(req.query.jobId || ""),
			role: String(role),
		};
	}

	res.json({
		jobs: pendingJobs,
	});
});

app.post("/api/roblox/heartbeat", authRoblox, (req, res) => {
	cleanupPresence();
	const jobId = String(req.body.jobId || "");
	if (!jobId) {
		res.status(400).json({ error: "missing jobId" });
		return;
	}

	serverPresence.set(jobId, {
		jobId,
		placeId: String(req.body.placeId || ""),
		role: String(req.body.role || "any"),
		players: Array.isArray(req.body.players) ? req.body.players : [],
		lastSeenAt: Date.now(),
	});

	res.json({ ok: true });
});

app.post("/api/roblox/jobs/:id/complete", authRoblox, (req, res) => {
	const job = jobs.find((entry) => entry.id === req.params.id);
	if (!job) {
		res.status(404).json({ error: "job not found" });
		return;
	}

	job.status = req.body.success ? "completed" : "failed";
	job.result = req.body.result || null;
	job.completedAt = new Date().toISOString();
	job.completedBy = {
		placeId: req.body.placeId || null,
		serverJobId: req.body.serverJobId || null,
	};

	res.json({ ok: true });
});

app.get("/api/jobs", (_req, res) => {
	cleanupPresence();
	res.json({
		jobs,
		servers: [...serverPresence.values()],
	});
});

const commands = [
	new SlashCommandBuilder()
		.setName("announce")
		.setDescription("Send an in-game announcement")
		.addStringOption((option) =>
			option.setName("message").setDescription("Announcement text").setRequired(true)
		)
		.addStringOption((option) =>
			option
				.setName("server")
				.setDescription("Which game server should receive this")
				.addChoices(
					{ name: "Any", value: "any" },
					{ name: "Main", value: "main" },
					{ name: "Training", value: "training" }
				)
		),
	new SlashCommandBuilder()
		.setName("setkills")
		.setDescription("Set a player's kill count")
		.addStringOption((option) =>
			option.setName("username").setDescription("Roblox username/display name").setRequired(true)
		)
		.addIntegerOption((option) =>
			option.setName("amount").setDescription("Kill amount").setRequired(true)
		)
		.addStringOption((option) =>
			option
				.setName("server")
				.setDescription("Which game server should receive this")
				.addChoices(
					{ name: "Any", value: "any" },
					{ name: "Main", value: "main" },
					{ name: "Training", value: "training" }
				)
		),
	new SlashCommandBuilder()
		.setName("buff")
		.setDescription("Buff a player's stat")
		.addStringOption((option) =>
			option.setName("username").setDescription("Roblox username/display name").setRequired(true)
		)
		.addStringOption((option) =>
			option
				.setName("stat")
				.setDescription("Stat to change")
				.setRequired(true)
				.addChoices(
					{ name: "Attack", value: "Attack" },
					{ name: "Defense", value: "Defense" },
					{ name: "Health", value: "Health" },
					{ name: "Mana", value: "Mana" },
					{ name: "Stamina", value: "Stamina" }
				)
		)
		.addIntegerOption((option) =>
			option.setName("amount").setDescription("New stat value").setRequired(true)
		)
		.addStringOption((option) =>
			option
				.setName("server")
				.setDescription("Which game server should receive this")
				.addChoices(
					{ name: "Any", value: "any" },
					{ name: "Main", value: "main" },
					{ name: "Training", value: "training" }
				)
		),
	new SlashCommandBuilder()
		.setName("heal")
		.setDescription("Heal a player")
		.addStringOption((option) =>
			option.setName("username").setDescription("Roblox username/display name").setRequired(true)
		)
		.addIntegerOption((option) =>
			option.setName("amount").setDescription("Optional heal amount; leave empty for full heal").setRequired(false)
		)
		.addStringOption((option) =>
			option
				.setName("server")
				.setDescription("Which game server should receive this")
				.addChoices(
					{ name: "Any", value: "any" },
					{ name: "Main", value: "main" },
					{ name: "Training", value: "training" }
				)
		),
	new SlashCommandBuilder()
		.setName("kick")
		.setDescription("Kick a player from the game")
		.addStringOption((option) =>
			option.setName("username").setDescription("Roblox username/display name").setRequired(true)
		)
		.addStringOption((option) =>
			option.setName("reason").setDescription("Kick reason").setRequired(false)
		)
		.addStringOption((option) =>
			option
				.setName("server")
				.setDescription("Which game server should receive this")
				.addChoices(
					{ name: "Any", value: "any" },
					{ name: "Main", value: "main" },
					{ name: "Training", value: "training" }
				)
		),
	new SlashCommandBuilder()
		.setName("returntomap")
		.setDescription("Return a player to the main map spawn")
		.addStringOption((option) =>
			option.setName("username").setDescription("Roblox username/display name").setRequired(true)
		)
		.addStringOption((option) =>
			option
				.setName("server")
				.setDescription("Which game server should receive this")
				.addChoices(
					{ name: "Any", value: "any" },
					{ name: "Main", value: "main" },
					{ name: "Training", value: "training" }
				)
		),
	new SlashCommandBuilder()
		.setName("duel")
		.setDescription("Force-start a duel")
		.addStringOption((option) =>
			option.setName("challenger_username").setDescription("Roblox username/display name of challenger").setRequired(true)
		)
		.addStringOption((option) =>
			option.setName("opponent_username").setDescription("Roblox username/display name of opponent, or type dummy").setRequired(true)
		)
		.addStringOption((option) =>
			option
				.setName("server")
				.setDescription("Which game server should receive this")
				.addChoices(
					{ name: "Any", value: "any" },
					{ name: "Main", value: "main" },
					{ name: "Training", value: "training" }
				)
		),
	new SlashCommandBuilder()
		.setName("shutdownserver")
		.setDescription("Shutdown a game server by kicking all players")
		.addStringOption((option) =>
			option.setName("reason").setDescription("Shutdown message shown to players").setRequired(false)
		)
		.addStringOption((option) =>
			option
				.setName("server")
				.setDescription("Which game server should receive this")
				.addChoices(
					{ name: "Any", value: "any" },
					{ name: "Main", value: "main" },
					{ name: "Training", value: "training" }
				)
		),
];

const client = new Client({
	intents: [GatewayIntentBits.Guilds],
});

client.once("ready", async () => {
	const rest = new REST({ version: "10" }).setToken(process.env.DISCORD_BOT_TOKEN);
	const route = process.env.DISCORD_GUILD_ID
		? Routes.applicationGuildCommands(process.env.DISCORD_CLIENT_ID, process.env.DISCORD_GUILD_ID)
		: Routes.applicationCommands(process.env.DISCORD_CLIENT_ID);

	await rest.put(route, {
		body: commands.map((command) => command.toJSON()),
	});

	console.log(`Discord bot ready as ${client.user.tag}`);
});

client.on("interactionCreate", async (interaction) => {
	if (!interaction.isChatInputCommand()) {
		return;
	}

	if (!isAuthorizedInteraction(interaction)) {
		await sendAuditLog([
			"**JD Audit**",
			"Action: unauthorized command attempt",
			`By: ${interaction.user.tag} (\`${interaction.user.id}\`)`,
			`Command: \`${interaction.commandName}\``,
		]);
		await interaction.reply({
			content: "You do not have permission to use bridge commands.",
			ephemeral: true,
		});
		return;
	}

	const targetRole = interaction.options.getString("server") || "any";
	const requestedBy = {
		discordUserId: interaction.user.id,
		tag: interaction.user.tag,
	};

	if (interaction.commandName === "announce") {
		const message = interaction.options.getString("message", true);
		await queueJobAndRespond(interaction, "announce", { message }, targetRole, requestedBy);
		return;
	}

	if (interaction.commandName === "setkills") {
		const targetUsername = interaction.options.getString("username", true);
		const amount = interaction.options.getInteger("amount", true);
		const targetPresence = findPresenceForPlayer(targetUsername, targetRole);
		if (!targetPresence) {
			await interaction.reply(`Could not find \`${targetUsername}\` online in \`${targetRole}\`.`);
			return;
		}
		const job = createJob("setkills", { targetUsername, amount }, targetRole, requestedBy);
		job.targetServerJobId = targetPresence.presence.jobId;
		await waitForExistingJobAndRespond(interaction, job, targetRole, requestedBy);
		return;
	}

	if (interaction.commandName === "buff") {
		const targetUsername = interaction.options.getString("username", true);
		const stat = interaction.options.getString("stat", true);
		const amount = interaction.options.getInteger("amount", true);
		const targetPresence = findPresenceForPlayer(targetUsername, targetRole);
		if (!targetPresence) {
			await interaction.reply(`Could not find \`${targetUsername}\` online in \`${targetRole}\`.`);
			return;
		}
		const job = createJob("buff", { targetUsername, stat, amount }, targetRole, requestedBy);
		job.targetServerJobId = targetPresence.presence.jobId;
		await waitForExistingJobAndRespond(interaction, job, targetRole, requestedBy);
		return;
	}

	if (interaction.commandName === "heal") {
		const targetUsername = interaction.options.getString("username", true);
		const amount = interaction.options.getInteger("amount", false);
		const targetPresence = findPresenceForPlayer(targetUsername, targetRole);
		if (!targetPresence) {
			await interaction.reply(`Could not find \`${targetUsername}\` online in \`${targetRole}\`.`);
			return;
		}
		const job = createJob("heal", { targetUsername, amount }, targetRole, requestedBy);
		job.targetServerJobId = targetPresence.presence.jobId;
		await waitForExistingJobAndRespond(interaction, job, targetRole, requestedBy);
		return;
	}

	if (interaction.commandName === "kick") {
		const targetUsername = interaction.options.getString("username", true);
		const reason = interaction.options.getString("reason", false);
		const targetPresence = findPresenceForPlayer(targetUsername, targetRole);
		if (!targetPresence) {
			await interaction.reply(`Could not find \`${targetUsername}\` online in \`${targetRole}\`.`);
			return;
		}
		const job = createJob("kick", { targetUsername, reason }, targetRole, requestedBy);
		job.targetServerJobId = targetPresence.presence.jobId;
		await waitForExistingJobAndRespond(interaction, job, targetRole, requestedBy);
		return;
	}

	if (interaction.commandName === "returntomap") {
		const targetUsername = interaction.options.getString("username", true);
		const targetPresence = findPresenceForPlayer(targetUsername, targetRole);
		if (!targetPresence) {
			await interaction.reply(`Could not find \`${targetUsername}\` online in \`${targetRole}\`.`);
			return;
		}
		const job = createJob("return_to_main", { targetUsername }, targetRole, requestedBy);
		job.targetServerJobId = targetPresence.presence.jobId;
		await waitForExistingJobAndRespond(interaction, job, targetRole, requestedBy);
		return;
	}

	if (interaction.commandName === "duel") {
		const challengerUsername = interaction.options.getString("challenger_username", true);
		const opponentInput = interaction.options.getString("opponent_username", true);
		const challengerPresence = findPresenceForPlayer(challengerUsername, targetRole);
		if (!challengerPresence) {
			await interaction.reply(`Could not find challenger \`${challengerUsername}\` online in \`${targetRole}\`.`);
			return;
		}
		const payload = {
			challengerUsername,
		};
		let targetServerJobId = challengerPresence.presence.jobId;

		if (opponentInput.toLowerCase() === "dummy") {
			payload.opponent = "dummy";
		} else {
			const opponentPresence = findPresenceForPlayer(opponentInput, targetRole);
			if (!opponentPresence) {
				await interaction.reply(`Could not find opponent \`${opponentInput}\` online in \`${targetRole}\`.`);
				return;
			}
			if (opponentPresence.presence.jobId !== challengerPresence.presence.jobId) {
				await interaction.reply("Both duel players must be in the same live server.");
				return;
			}
			payload.opponentUsername = opponentInput;
		}

		const job = createJob("duel", payload, targetRole, requestedBy);
		job.targetServerJobId = targetServerJobId;
		await waitForExistingJobAndRespond(interaction, job, targetRole, requestedBy);
		return;
	}

	if (interaction.commandName === "shutdownserver") {
		const reason = interaction.options.getString("reason", false);
		await queueJobAndRespond(interaction, "shutdownserver", { reason }, targetRole, requestedBy);
	}
});

const port = Number(process.env.PORT || 3000);
app.listen(port, () => {
	console.log(`Bridge API listening on ${port}`);
});

client.login(process.env.DISCORD_BOT_TOKEN);
