import { app } from "@azure/functions";
import { caller, optionalCaller } from "../auth";
import { usernames, relationships, profiles, type RelationshipDoc } from "../db";
import { handler, json, HttpError } from "../http";
import { profileByUsername, relationOf, relationship, saveRelationship, visibleItems, publicProfile } from "../social";

async function target(name: string | undefined) {
  const profile = name ? await profileByUsername(name) : null;
  if (!profile) throw new HttpError(404, "No one by that username.");
  return profile;
}

/** Someone's shelf, as you're allowed to see it. */
app.http("getUser", {
  methods: ["GET"], route: "users/{username}", authLevel: "anonymous",
  handler: handler(async (request) => {
    const viewer = await optionalCaller(request);
    const owner = await target(request.params.username);
    const relation = await relationOf(viewer?.id ?? null, owner.id);
    const mine = viewer && viewer.id !== owner.id ? await relationship(viewer.id, owner.id) : null;
    const theirs = viewer && viewer.id !== owner.id ? await relationship(owner.id, viewer.id) : null;
    return json({
      profile: publicProfile(owner),
      relation,
      following: mine?.following ?? false,
      friend: mine?.friend === "accepted" ? "friends"
        : mine?.friend === "requested" ? "requested"
        : theirs?.friend === "requested" ? "incoming" : "none",
      items: await visibleItems(owner.id, relation),
    });
  }),
});

/** The public profile page: no sign-in, public items only. */
app.http("getPublic", {
  methods: ["GET"], route: "public/{username}", authLevel: "anonymous",
  handler: handler(async (request) => {
    const owner = await target(request.params.username);
    const response = json({ profile: publicProfile(owner), items: await visibleItems(owner.id, "anonymous", 200) });
    response.headers = { "Cache-Control": "public, max-age=300" };   // CORS is set on the Functions app
    return response;
  }),
});

/** Usernames starting with what you've typed. */
app.http("search", {
  methods: ["GET"], route: "search", authLevel: "anonymous",
  handler: handler(async (request) => {
    await caller(request);
    const q = (request.query.get("q") ?? "").trim().replace(/^@/, "").toLowerCase();
    if (q.length < 2) return json({ results: [] });
    const { resources } = await usernames.items
      .query<{ id: string }>({ query: "SELECT TOP 20 c.id FROM c WHERE STARTSWITH(c.id, @q)", parameters: [{ name: "@q", value: q }] })
      .fetchAll();
    const results = [];
    for (const r of resources) {
      const p = await profileByUsername(r.id);
      if (p) results.push(publicProfile(p));
    }
    return json({ results });
  }),
});

/** Follow: see their public shelf in your feed. Anyone can follow anyone. */
app.http("follow", {
  methods: ["POST", "DELETE"], route: "users/{username}/follow", authLevel: "anonymous",
  handler: handler(async (request) => {
    const me = await caller(request);
    const owner = await target(request.params.username);
    if (owner.id === me.id) throw new HttpError(400, "That's you.");
    const rel = await saveRelationship(me.id, owner.id, { following: request.method === "POST" });
    return json({ following: rel.following });
  }),
});

/**
 * Friends: a request one way, accepted from the other. POST requests (or
 * accepts one they sent you); DELETE cancels, declines or unfriends.
 */
app.http("friend", {
  methods: ["POST", "DELETE"], route: "users/{username}/friend", authLevel: "anonymous",
  handler: handler(async (request) => {
    const me = await caller(request);
    const other = await target(request.params.username);
    if (other.id === me.id) throw new HttpError(400, "That's you.");

    if (request.method === "DELETE") {
      await saveRelationship(me.id, other.id, { friend: "none" });
      await saveRelationship(other.id, me.id, { friend: "none" });
      return json({ friend: "none" });
    }
    const theirs = await relationship(other.id, me.id);
    if (theirs?.friend === "requested" || theirs?.friend === "accepted") {
      // They asked first: becoming friends also means following each other.
      await saveRelationship(me.id, other.id, { friend: "accepted", following: true });
      await saveRelationship(other.id, me.id, { friend: "accepted", following: true });
      return json({ friend: "friends" });
    }
    await saveRelationship(me.id, other.id, { friend: "requested", following: true });
    return json({ friend: "requested" });
  }),
});

/** Friend requests waiting for you. */
app.http("friendRequests", {
  methods: ["GET"], route: "friends/requests", authLevel: "anonymous",
  handler: handler(async (request) => {
    const me = await caller(request);
    // Requests are stored under the sender, so this is a cross-partition read.
    const { resources } = await relationships.items
      .query<RelationshipDoc>({ query: "SELECT * FROM c WHERE c.toId = @me AND c.friend = 'requested'", parameters: [{ name: "@me", value: me.id }] })
      .fetchAll();
    const people = [];
    for (const r of resources) {
      const { resource } = await profiles.item(r.fromId, r.fromId).read();
      if (resource) people.push(publicProfile(resource));
    }
    return json({ requests: people });
  }),
});

/** The people you follow and your friends, for the sidebar. */
app.http("myPeople", {
  methods: ["GET"], route: "me/people", authLevel: "anonymous",
  handler: handler(async (request) => {
    const me = await caller(request);
    const { resources } = await relationships.items
      .query<RelationshipDoc>({
        query: "SELECT * FROM c WHERE c.fromId = @me AND (c.following = true OR c.friend = 'accepted' OR c.friend = 'requested')",
        parameters: [{ name: "@me", value: me.id }],
      }, { partitionKey: me.id })
      .fetchAll();
    const people = [];
    for (const r of resources) {
      const { resource } = await profiles.item(r.toId, r.toId).read();
      if (resource) people.push({ ...publicProfile(resource), following: r.following, friend: r.friend === "accepted" ? "friends" : r.friend });
    }
    people.sort((a, b) => a.displayName.localeCompare(b.displayName));
    return json({ people });
  }),
});
