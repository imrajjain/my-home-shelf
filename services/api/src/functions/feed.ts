import { app } from "@azure/functions";
import { caller } from "../auth";
import { relationships, profiles, type RelationshipDoc, type Profile } from "../db";
import { handler, json } from "../http";
import { visibleItems, publicProfile } from "../social";

/**
 * What friends and the people you follow have finished lately: friends'
 * shared items, and followed people's public ones, newest first.
 */
app.http("feed", {
  methods: ["GET"], route: "feed", authLevel: "anonymous",
  handler: handler(async (request) => {
    const me = await caller(request);
    const { resources: rels } = await relationships.items
      .query<RelationshipDoc>({
        query: "SELECT * FROM c WHERE c.fromId = @me AND (c.following = true OR c.friend = 'accepted')",
        parameters: [{ name: "@me", value: me.id }],
      }, { partitionKey: me.id })
      .fetchAll();

    const entries: { person: ReturnType<typeof publicProfile>; item: Record<string, unknown> }[] = [];
    for (const rel of rels.slice(0, 50)) {
      const { resource: person } = await profiles.item(rel.toId, rel.toId).read<Profile>();
      if (!person) continue;
      const relation = rel.friend === "accepted" ? "friend" : "follower";
      for (const item of await visibleItems(rel.toId, relation, 40)) {
        if (item.status === "done" && item.finishedAt) entries.push({ person: publicProfile(person), item });
      }
    }
    entries.sort((a, b) => String(b.item.finishedAt).localeCompare(String(a.item.finishedAt)));
    return json({ entries: entries.slice(0, 60) });
  }),
});
