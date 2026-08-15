const MAX_JSON_BYTES = 2048;
const MAX_RESULTS = 100;
const ALLOWED_STATUSES = new Set(["new", "reviewed", "resolved"]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/api/")) {
      if (!(await isAuthorized(request, env.ADMIN_TOKEN))) {
        return json({ error: "unauthorized" }, 401, {
          "www-authenticate": "Bearer",
        });
      }

      try {
        return await handleApi(request, env, url);
      } catch (error) {
        if (error instanceof RequestValidationError) {
          return json({ error: error.code }, error.status);
        }
        console.error("feedback_admin_request_failed", error);
        return json({ error: "internal_error" }, 500);
      }
    }

    return env.ASSETS.fetch(request);
  },
};

async function handleApi(request, env, url) {
  if (request.method === "GET" && url.pathname === "/api/feedback") {
    return listFeedback(env, url.searchParams.get("status") ?? "all");
  }

  const feedbackId = getFeedbackId(url.pathname);
  if (feedbackId === null) {
    return json({ error: "not_found" }, 404);
  }

  if (request.method === "PATCH") {
    return updateFeedbackStatus(request, env, feedbackId);
  }

  if (request.method === "DELETE") {
    return deleteFeedback(env, feedbackId);
  }

  return json({ error: "method_not_allowed" }, 405, {
    allow: "GET, PATCH, DELETE",
  });
}

async function listFeedback(env, requestedStatus) {
  if (requestedStatus !== "all" && !ALLOWED_STATUSES.has(requestedStatus)) {
    return json({ error: "invalid_status" }, 400);
  }

  const query = requestedStatus === "all"
    ? env.FEEDBACK_DB.prepare(`
        SELECT id, type, message, email, app_version, platform, locale,
               status, created_at
        FROM feedback
        ORDER BY id DESC
        LIMIT ?
      `).bind(MAX_RESULTS)
    : env.FEEDBACK_DB.prepare(`
        SELECT id, type, message, email, app_version, platform, locale,
               status, created_at
        FROM feedback
        WHERE status = ?
        ORDER BY id DESC
        LIMIT ?
      `).bind(requestedStatus, MAX_RESULTS);

  const [feedback, groupedCounts] = await Promise.all([
    query.all(),
    env.FEEDBACK_DB.prepare(`
      SELECT status, COUNT(*) AS count
      FROM feedback
      GROUP BY status
    `).all(),
  ]);

  const counts = {
    all: 0,
    new: 0,
    reviewed: 0,
    resolved: 0,
  };

  for (const row of groupedCounts.results ?? []) {
    const status = String(row.status);
    const count = Number(row.count);
    if (status in counts) {
      counts[status] = count;
      counts.all += count;
    }
  }

  return json({
    items: feedback.results ?? [],
    counts,
  });
}

async function updateFeedbackStatus(request, env, feedbackId) {
  const payload = await readLimitedJson(request);
  const status = payload?.status;

  if (!isRecord(payload) || !ALLOWED_STATUSES.has(status)) {
    return json({ error: "invalid_status" }, 400);
  }

  const result = await env.FEEDBACK_DB.prepare(`
    UPDATE feedback
    SET status = ?
    WHERE id = ?
  `).bind(status, feedbackId).run();

  if (result.meta?.changes !== 1) {
    return json({ error: "feedback_not_found" }, 404);
  }

  return json({ ok: true, id: feedbackId, status });
}

async function deleteFeedback(env, feedbackId) {
  const result = await env.FEEDBACK_DB.prepare(`
    DELETE FROM feedback
    WHERE id = ?
  `).bind(feedbackId).run();

  if (result.meta?.changes !== 1) {
    return json({ error: "feedback_not_found" }, 404);
  }

  return new Response(null, { status: 204 });
}

function getFeedbackId(pathname) {
  const match = pathname.match(/^\/api\/feedback\/(\d+)$/);
  if (!match) return null;

  const id = Number(match[1]);
  return Number.isSafeInteger(id) && id > 0 ? id : null;
}

async function readLimitedJson(request) {
  const contentType = request.headers.get("content-type") ?? "";
  const mediaType = contentType.split(";", 1)[0].trim().toLowerCase();
  if (mediaType !== "application/json") {
    throw new RequestValidationError("content_type_must_be_json", 415);
  }

  const contentLength = request.headers.get("content-length");
  if (contentLength !== null && Number(contentLength) > MAX_JSON_BYTES) {
    throw new RequestValidationError("payload_too_large", 413);
  }

  const reader = request.body?.getReader();
  if (!reader) {
    throw new RequestValidationError("invalid_json", 400);
  }

  const chunks = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      totalBytes += value.byteLength;
      if (totalBytes > MAX_JSON_BYTES) {
        await reader.cancel();
        throw new RequestValidationError("payload_too_large", 413);
      }

      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    return JSON.parse(new TextDecoder().decode(body));
  } catch {
    throw new RequestValidationError("invalid_json", 400);
  }
}

async function isAuthorized(request, expectedToken) {
  if (typeof expectedToken !== "string" || expectedToken.length === 0) {
    return false;
  }

  const authorization = request.headers.get("authorization") ?? "";
  const prefix = "Bearer ";
  if (!authorization.startsWith(prefix)) return false;

  const providedToken = authorization.slice(prefix.length);
  const [providedDigest, expectedDigest] = await Promise.all([
    digest(providedToken),
    digest(expectedToken),
  ]);

  let difference = 0;
  for (let index = 0; index < expectedDigest.length; index += 1) {
    difference |= providedDigest[index] ^ expectedDigest[index];
  }
  return difference === 0;
}

async function digest(value) {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...extraHeaders,
    },
  });
}

class RequestValidationError extends Error {
  constructor(code, status) {
    super(code);
    this.code = code;
    this.status = status;
  }
}
