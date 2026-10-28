import { profiles, usernames, items, relationships, isNotFound, type Profile, type ItemDoc, type RelationshipDoc } from "./db";
import { canSee, shareable, type Relation } from "./visibility";

/** The profile behind a username, or null. */
export async function profileByUsername(name: string): Promise<Profile | null> {
  try {
    const { resource: handle } = await usernames.item(name.toLowerCase(), name.toLowerCase()).read<{ userId: string }>();
    if (!handle) return null;
    const { resource } = await profiles.item(handle.userId, handle.userId).read<Profile>();
    return resource ?? null;
  } catch (error) {
    if (isNotFound(error)) return null;
    throw error;
  }
}

export async function relationship(fromId: string, toId: string): Promise<RelationshipDoc | null> {
  try {
    const { resource } = await relationships.item(`${fromId}:${toId}`, fromId).read<RelationshipDoc>();
    return resource ?? null;
  } catch (error) {
    if (isNotFound(error)) return null;
    throw error;
  }
}

export async function saveRelationship(fromId: string, toId: string, change: Partial<RelationshipDoc>): Promise<RelationshipDoc> {
  const current = (await relationship(fromId, toId)) ?? {
    id: `${fromId}:${toId}`, fromId, toId, following: false, friend: "none" as const, updatedAt: "",
  };
  const next = { ...current, ...change, updatedAt: new Date().toISOString() };
  await relationships.items.upsert(next);
  return next;
}

/** How `viewerId` (null when signed out) relates to `ownerId`. */
export async function relationOf(viewerId: string | null, ownerId: string): Promise<Relation> {
  if (!viewerId) return "anonymous";
  if (viewerId === ownerId) return "owner";
  const rel = await relationship(viewerId, ownerId);
  if (rel?.friend === "accepted") return "friend";
  if (rel?.following) return "follower";
  return "stranger";
}

/** The items of `ownerId` that someone with `relation` may see, hidden parts removed. */
export async function visibleItems(ownerId: string, relation: Relation, limit = 500): Promise<Record<string, unknown>[]> {
  const { resources } = await items.items
    .query<ItemDoc>({
      query: "SELECT * FROM c WHERE c.userId = @u AND (NOT IS_DEFINED(c.record.deletedAt) OR IS_NULL(c.record.deletedAt)) ORDER BY c.record.updatedAt DESC OFFSET 0 LIMIT @n",
      parameters: [{ name: "@u", value: ownerId }, { name: "@n", value: limit }],
    }, { partitionKey: ownerId })
    .fetchAll();
  return resources
    .filter((doc) => canSee(relation, doc.visibility))
    .map((doc) => relation === "owner" ? { ...doc.record, visibility: doc.visibility } : shareable(doc.record, doc.share));
}

/** What another person sees of a profile. */
export function publicProfile(p: Profile) {
  return { username: p.username, displayName: p.displayName, bio: p.bio ?? "", avatarURL: p.avatarURL ?? null };
}
