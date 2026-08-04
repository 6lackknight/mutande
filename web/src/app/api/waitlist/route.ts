import { hubBaseUrl } from "@/lib/hub";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON body required" }, { status: 400 });
  }

  let res: Response;
  try {
    res = await fetch(`${hubBaseUrl()}/v1/waitlist`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      cache: "no-store",
    });
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Network error talking to hub";
    return NextResponse.json(
      { error: `Hub unreachable: ${message}` },
      { status: 503 },
    );
  }

  const text = await res.text();
  let payload: unknown = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = { error: text };
    }
  }

  if (!res.ok) {
    const obj =
      typeof payload === "object" && payload !== null
        ? (payload as { message?: unknown; error?: unknown })
        : null;
    const error =
      typeof obj?.message === "string"
        ? obj.message
        : typeof obj?.error === "string"
          ? obj.error
          : res.statusText || "Request failed";
    return NextResponse.json({ error }, { status: res.status });
  }

  return NextResponse.json(payload ?? { ok: true }, { status: 201 });
}
