import { app } from "@azure/functions";
import { caller } from "../auth";
import { items, type ItemDoc } from "../db";
import { handler, json, body, HttpError } from "../http";
import type { Visibility, ShareSwitches } from "../visibility";

interface Change {
  record: Record<string, unknown> & { id: string; updatedAt: string; deletedAt?: string | null };
  visibility?: Visibility;
  share?: ShareSwitches;
}

/**
 * Two-way backup. The app sends what changed since its last sync and gets
 * back everything changed elsewhere since `since` (a server timestamp it got
 * from the previous call). The newest `updatedAt` wins per item; deletions
 * travel as items with `deletedAt` set.
 */
app.http("sync", {
  methods: ["POST"], route: "sync", authLevel: "anonymous",
  handler: handler(async (request) => {
    const me = await caller(request);
    const input = await body<{ since?: number; changes?: Change[] }>(request);
    const since = Number(input.since ?? 0);
    const changes = input.changes ?? [];
    if (changes.length > 500) throw new HttpError(413, "Send at most 500 changes at a time.");

    const start = Date.now();
    let applied = 0;
    for (const change of changes) {
      const id = String(change.record?.id ?? "");
      if (!/^[0-9a-fA-F-]{36}$/.test(id) || !change.record.updatedAt) continue;
      let existing: ItemDoc | undefined;
      try { existing = (await items.item(id, me.id).read<ItemDoc>()).resource; } catch { existing = undefined; }
      if (existing && existing.record.updatedAt >= change.record.updatedAt) {
        // Same edit, new sharing setting: update who can see it, nothing else.
        const visibility = change.visibility ?? existing.visibility;
        const share = change.share ?? existing.share;
        if (visibility !== existing.visibility || JSON.stringify(share) !== JSON.stringify(existing.share)) {
          await items.items.upsert({ ...existing, visibility, share, serverTime: Date.now() });
          applied++;
        }
        continue;
      }
      const doc: ItemDoc = {
        id, userId: me.id, record: change.record,
        visibility: change.visibility ?? existing?.visibility ?? "private",
        share: change.share ?? existing?.share,
        serverTime: Date.now(),
      };
      await items.items.upsert(doc);
      applied++;
    }

    // Everything newer than the caller's cursor, including what other devices wrote.
    const { resources } = await items.items
      .query<ItemDoc>({
        query: "SELECT * FROM c WHERE c.userId = @u AND c.serverTime > @since",
        parameters: [{ name: "@u", value: me.id }, { name: "@since", value: since }],
      }, { partitionKey: me.id })
      .fetchAll();

    return json({
      applied,
      changes: resources.map((d) => ({ record: d.record, visibility: d.visibility, share: d.share })),
      // A little before now, so writes landing during this call are fetched next time.
      cursor: start - 1000,
    });
  }),
});
