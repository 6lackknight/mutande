import { assertEquals } from "jsr:@std/assert@1";
import {
  SessionStore,
  encodeSseComment,
  encodeSseMessage,
} from "./sessions.ts";

Deno.test("SessionStore create get delete and ownership", async () => {
  const store = new SessionStore();
  const a = await store.create("auth0|a", "chatgpt");
  assertEquals((await store.get(a.id))?.auth0Sub, "auth0|a");
  assertEquals(await store.getForUser(a.id, "auth0|b"), undefined);
  assertEquals((await store.getForUser(a.id, "auth0|a"))?.id, a.id);
  assertEquals(await store.delete(a.id), true);
  assertEquals(await store.get(a.id), undefined);
});

Deno.test("SessionStore allows only one SSE attachment", async () => {
  const store = new SessionStore();
  const s = await store.create("auth0|a", "chatgpt");
  const cancel = () => {};
  const controller = {
    enqueue: () => {},
    close: () => {},
    error: () => {},
  } as unknown as ReadableStreamDefaultController<Uint8Array>;
  assertEquals(store.attachSse(s.id, controller, cancel), true);
  assertEquals(store.attachSse(s.id, controller, cancel), false);
  store.detachSse(s.id);
  assertEquals(store.attachSse(s.id, controller, cancel), true);
});

Deno.test("SessionStore resumes from Deno KV on a fresh isolate map", async () => {
  const kv = await Deno.openKv(":memory:");
  try {
    const a = new SessionStore(kv);
    const created = await a.create("auth0|a", "grok");
    // Simulate another Deploy isolate: new local map, same KV.
    const b = new SessionStore(kv);
    const resumed = await b.getForUser(created.id, "auth0|a");
    assertEquals(resumed?.id, created.id);
    assertEquals(resumed?.agentSlug, "grok");
    assertEquals(await b.getForUser(created.id, "auth0|other"), undefined);

    await b.delete(created.id);
    assertEquals(await a.get(created.id), undefined);
  } finally {
    kv.close();
  }
});

Deno.test("SSE encode helpers", () => {
  const msg = new TextDecoder().decode(encodeSseMessage({ ok: true }, "1"));
  assertEquals(msg.includes("event: message\n"), true);
  assertEquals(msg.includes("id: 1\n"), true);
  assertEquals(msg.includes('data: {"ok":true}\n\n'), true);
  const c = new TextDecoder().decode(encodeSseComment("keepalive"));
  assertEquals(c, ": keepalive\n\n");
});
