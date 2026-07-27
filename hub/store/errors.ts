export class HubError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly status = 400,
  ) {
    super(message);
    this.name = "HubError";
  }
}

export function envelopeTooLarge(size: number): HubError {
  return new HubError(
    `Envelope exceeds ${60}KB limit (${size} bytes serialized). Use blob storage for larger handoffs.`,
    "envelope_too_large",
    413,
  );
}

export function notFound(resource: string): HubError {
  return new HubError(`${resource} not found`, "not_found", 404);
}

export function forbidden(message = "Forbidden"): HubError {
  return new HubError(message, "forbidden", 403);
}

export function unauthorized(message = "Unauthorized"): HubError {
  return new HubError(message, "unauthorized", 401);
}

export function conflict(message: string): HubError {
  return new HubError(message, "conflict", 409);
}

export function quotaExceeded(): HubError {
  return new HubError(
    "Org blob quota exceeded (500MB free tier)",
    "quota_exceeded",
    413,
  );
}
