import type { HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { Unauthorized } from "./auth";

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export function json(body: unknown, status = 200): HttpResponseInit {
  return { status, jsonBody: body, headers: { "Cache-Control": "no-store" } };
}

/** Wraps a handler: errors become clean JSON answers, never stack traces. */
export function handler(fn: (request: HttpRequest, context: InvocationContext) => Promise<HttpResponseInit>) {
  return async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    try {
      return await fn(request, context);
    } catch (error) {
      if (error instanceof Unauthorized) return json({ error: error.message }, 401);
      if (error instanceof HttpError) return json({ error: error.message }, error.status);
      context.error(error);
      return json({ error: "Something went wrong on Shelf's side." }, 500);
    }
  };
}

export async function body<T>(request: HttpRequest): Promise<T> {
  try { return (await request.json()) as T; } catch { throw new HttpError(400, "Expected a JSON body."); }
}
