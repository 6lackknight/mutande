import { assertEquals } from "jsr:@std/assert@1";
import {
  SessionStore,
  encodeSseComment,
  encodeSseMessage,
} from "./sessions.ts";

Deno.test("SessionStore create get delete and ownership", () => {
  const store = new SessionStore();
  const a = store.create("auth0|a", "chatgpt");
  assertEquals(store.get(a.id)?.auth0Sub, "auth0|a");
  assertEquals(store.getForUser(a.id, "auth0|b"), undefined);
  assertEquals(store.getForUser(a.id, "auth0|a")?.id, a.id);
  assertEquals(store.delete(a.id), true);
  assertEquals(store.get(a.id), undefined);
});

Deno.test("SessionStore allows only one SSE attachment", () => {
  const store = new SessionStore();
  const s = store.create("auth0|a", "chatgpt");
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

Deno.test("SSE encode helpers", () => {
  const msg = new TextDecoder().decode(encodeSseMessage({ ok: true }, "1"));
  assertEquals(msg.includes("event: message\n"), true);
  assertEquals(msg.includes("id: 1\n"), true);
  assertEquals(msg.includes('data: {"ok":true}\n\n'), true);
  const c = new TextDecoder().decode(encodeSseComment("keepalive"));
  assertEquals(c, ": keepalive\n\n");
});
