import { CosmosClient, type Container } from "@azure/cosmos";
import { DefaultAzureCredential } from "@azure/identity";
import type { Visibility, ShareSwitches } from "./visibility";

/**
 * Cosmos DB (free tier). The function app signs in with its managed
 * identity, so there are no database keys in its settings.
 *
 *   profiles       /id       one per user
 *   usernames      /id       the lower-cased handle → user id; keeps handles unique
 *   items          /userId   one per shelf item (an ItemRecord plus sharing)
 *   relationships  /fromId   follows and friendships, one doc per direction
 */
const client = new CosmosClient({
  endpoint: process.env.COSMOS_ENDPOINT ?? "",
  aadCredentials: new DefaultAzureCredential(),
});
const database = client.database(process.env.COSMOS_DATABASE ?? "shelf");

export const profiles: Container = database.container("profiles");
export const usernames: Container = database.container("usernames");
export const items: Container = database.container("items");
export const relationships: Container = database.container("relationships");

export interface Profile {
  id: string;
  username: string;
  displayName: string;
  bio?: string;
  avatarURL?: string;
  createdAt: string;
}

export interface ItemDoc {
  id: string;
  userId: string;
  /** The ItemRecord exactly as the app sends it. */
  record: Record<string, unknown> & { updatedAt: string; deletedAt?: string | null };
  visibility?: Visibility;
  share?: ShareSwitches;
  /** Server time of the last write, the sync cursor. */
  serverTime: number;
}

export interface RelationshipDoc {
  id: string;        // `${fromId}:${toId}`
  fromId: string;
  toId: string;
  following: boolean;
  /** none, requested (from → to), or accepted (mirrored on both docs). */
  friend: "none" | "requested" | "accepted";
  updatedAt: string;
}

export function isNotFound(error: unknown): boolean {
  return (error as { code?: number })?.code === 404;
}

export function isConflict(error: unknown): boolean {
  return (error as { code?: number })?.code === 409;
}
