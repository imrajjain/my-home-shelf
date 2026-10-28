import { app } from "@azure/functions";
import { caller } from "../auth";
import { profiles, usernames, isNotFound, isConflict, type Profile } from "../db";
import { handler, json, body, HttpError } from "../http";
import { normalizeUsername } from "../visibility";

/** Your own profile; 404 until you've picked a username. */
app.http("getMe", {
  methods: ["GET"], route: "me", authLevel: "anonymous",
  handler: handler(async (request) => {
    const me = await caller(request);
    try {
      const { resource } = await profiles.item(me.id, me.id).read<Profile>();
      if (resource) return json(resource);
    } catch (error) {
      if (!isNotFound(error)) throw error;
    }
    return json({ error: "Pick a username to finish setting up.", suggestedName: me.name ?? "" }, 404);
  }),
});

/** Creates or updates your profile; claiming a new username releases the old one. */
app.http("putMe", {
  methods: ["PUT"], route: "me", authLevel: "anonymous",
  handler: handler(async (request) => {
    const me = await caller(request);
    const input = await body<{ username?: string; displayName?: string; bio?: string; avatarURL?: string }>(request);

    let current: Profile | undefined;
    try { current = (await profiles.item(me.id, me.id).read<Profile>()).resource; } catch (error) { if (!isNotFound(error)) throw error; }

    let username = current?.username;
    if (input.username !== undefined) {
      const wanted = normalizeUsername(input.username);
      if (!wanted) throw new HttpError(400, "Usernames are 3–20 letters, numbers or underscores.");
      if (wanted !== current?.username) {
        // Creating the handle doc is what makes it unique: a second claim conflicts.
        try {
          await usernames.items.create({ id: wanted, userId: me.id });
        } catch (error) {
          if (isConflict(error)) throw new HttpError(409, `@${wanted} is taken.`);
          throw error;
        }
        if (current?.username) {
          await usernames.item(current.username, current.username).delete().catch(() => undefined);
        }
        username = wanted;
      }
    }
    if (!username) throw new HttpError(400, "Pick a username.");

    const profile: Profile = {
      id: me.id,
      username,
      displayName: (input.displayName ?? current?.displayName ?? me.name ?? username).slice(0, 60),
      bio: (input.bio ?? current?.bio ?? "").slice(0, 280),
      avatarURL: input.avatarURL ?? current?.avatarURL,
      createdAt: current?.createdAt ?? new Date().toISOString(),
    };
    await profiles.items.upsert(profile);
    return json(profile);
  }),
});
