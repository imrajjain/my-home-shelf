/**
 * Who may see what. This is the one place that decides whether a shelf item
 * leaves the server, so everything that returns another person's items goes
 * through `canSee`.
 *
 *   private  only the owner
 *   friends  the owner and accepted friends
 *   public   anyone, including followers and the public profile page
 */
export type Visibility = "private" | "friends" | "public";

/** How the person asking relates to the owner of the items. */
export type Relation = "owner" | "friend" | "follower" | "stranger" | "anonymous";

export function canSee(relation: Relation, visibility: Visibility | undefined): boolean {
  // Anything without an explicit setting is private: sharing is opt-in.
  const v = visibility ?? "private";
  switch (relation) {
    case "owner":
      return true;
    case "friend":
      return v === "friends" || v === "public";
    case "follower":
    case "stranger":
    case "anonymous":
      return v === "public";
  }
}

/** Fields of an item that never leave the owner's account, whatever its visibility. */
const OWNER_ONLY = ["extra"] as const;

/** Per-item switches for the parts people may want to keep to themselves. */
export interface ShareSwitches {
  notes?: boolean;
  rating?: boolean;
  progress?: boolean;
}

/** The copy of an item another person receives: hidden parts removed. */
export function shareable(record: Record<string, unknown>, share: ShareSwitches | undefined): Record<string, unknown> {
  const copy: Record<string, unknown> = { ...record };
  // Emptied rather than removed, so the app's record format still decodes.
  for (const key of OWNER_ONLY) copy[key] = {};
  if (!share?.notes) copy.notes = "";
  if (!share?.rating) copy.rating = 0;
  if (!share?.progress) copy.progress = 0;
  return copy;
}

const USERNAME = /^[a-z0-9_]{3,20}$/;
const RESERVED = new Set([
  "admin", "administrator", "support", "help", "shelf", "api", "app", "www", "root", "system",
  "me", "settings", "login", "logout", "signin", "signup", "about", "public", "user", "users",
]);

/** Lower-cases a requested username and checks it; returns null if it can't be used. */
export function normalizeUsername(raw: string): string | null {
  const name = raw.trim().replace(/^@/, "").toLowerCase();
  return USERNAME.test(name) && !RESERVED.has(name) ? name : null;
}
