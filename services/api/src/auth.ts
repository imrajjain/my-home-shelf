import { createRemoteJWKSet, jwtVerify } from "jose";
import type { HttpRequest } from "@azure/functions";

/**
 * Verifies the access token Shelf for Mac gets from Microsoft Entra External
 * ID. The signature, issuer, audience and expiry are all checked; the user's
 * stable id is the token's `oid`.
 */
const tenant = process.env.AUTH_TENANT_ID ?? "";
const domain = process.env.AUTH_DOMAIN ?? "";
const audience = process.env.AUTH_AUDIENCE ?? "";

const jwks = createRemoteJWKSet(new URL(`https://${domain}.ciamlogin.com/${tenant}/discovery/v2.0/keys`));
const issuer = `https://${tenant}.ciamlogin.com/${tenant}/v2.0`;

export interface Caller {
  id: string;
  name?: string;
  email?: string;
}

export class Unauthorized extends Error {}

/** The signed-in caller, or throws `Unauthorized`. */
export async function caller(request: HttpRequest): Promise<Caller> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) throw new Unauthorized("Sign in first.");
  try {
    const { payload } = await jwtVerify(token, jwks, { issuer, audience });
    const id = String(payload.oid ?? payload.sub ?? "");
    if (!id) throw new Unauthorized("Token has no user id.");
    return { id, name: payload.name as string | undefined, email: (payload.email ?? payload.preferred_username) as string | undefined };
  } catch (error) {
    if (error instanceof Unauthorized) throw error;
    throw new Unauthorized("Your sign-in has expired.");
  }
}

/** The caller when a token is present and valid; otherwise null (for pages anyone may read). */
export async function optionalCaller(request: HttpRequest): Promise<Caller | null> {
  if (!request.headers.get("authorization")) return null;
  try { return await caller(request); } catch { return null; }
}
