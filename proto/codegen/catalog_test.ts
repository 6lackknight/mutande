/**
 * Golden/drift tests for the RPC catalog (stage 1 of the RPC chain collapse).
 *
 * The wire is frozen: proto/rpc-catalog.json must exactly describe the daemon
 * dispatch in core/src/daemon/rpc.rs, cover every method the Flutter
 * DaemonClient calls, and generated artifacts must be fresh.
 */

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  generateAll,
  loadCatalog,
  repoRootFromScript,
  validateCatalog,
} from "./generate.ts";

const root = repoRootFromScript();
const catalog = loadCatalog(root);

function catalogNames(): Set<string> {
  const names = new Set<string>();
  for (const m of catalog.methods) {
    names.add(m.name);
    for (const a of m.aliases ?? []) names.add(a);
  }
  return names;
}

Deno.test("catalog passes structural validation", () => {
  validateCatalog(catalog);
});

Deno.test("catalog matches core rpc.rs dispatch exactly", () => {
  const src = Deno.readTextFileSync(`${root}/core/src/daemon/rpc.rs`);
  const start = src.indexOf("match method {");
  const end = src.indexOf("unknown method:");
  assert(start > 0 && end > start, "could not locate dispatch match in rpc.rs");
  const dispatch = src.slice(start, end);

  const dispatchKeys = new Set<string>();
  for (const arm of dispatch.matchAll(/^\s*("([a-z_]+)"(?:\s*\|\s*"[a-z_]+")*)\s*=>/gm)) {
    for (const key of arm[1].matchAll(/"([a-z_]+)"/g)) {
      dispatchKeys.add(key[1]);
    }
  }
  assert(dispatchKeys.size > 0, "no dispatch keys parsed from rpc.rs");

  const names = catalogNames();
  const missingFromCatalog = [...dispatchKeys].filter((k) => !names.has(k)).sort();
  const missingFromDispatch = [...names].filter((k) => !dispatchKeys.has(k)).sort();
  assertEquals(missingFromCatalog, [], "rpc.rs methods missing from catalog");
  assertEquals(missingFromDispatch, [], "catalog methods missing from rpc.rs dispatch");
});

Deno.test("every DaemonClient RPC call is in the catalog", () => {
  const src = Deno.readTextFileSync(
    `${root}/app/lib/services/daemon_client.dart`,
  );
  const called = new Set<string>();
  for (const m of src.matchAll(/_call(?:WithTimeout)?\(\s*'([a-z_]+)'/g)) {
    called.add(m[1]);
  }
  assert(called.size > 0, "no _call sites parsed from daemon_client.dart");

  const names = catalogNames();
  const unknown = [...called].filter((k) => !names.has(k)).sort();
  assertEquals(
    unknown,
    [],
    "DaemonClient calls RPC methods the daemon does not dispatch",
  );
});

Deno.test("generated artifacts are fresh (run: deno task generate)", () => {
  const outputs = generateAll(catalog);
  for (const [rel, expected] of Object.entries(outputs)) {
    const actual = Deno.readTextFileSync(`${root}/${rel}`);
    assertEquals(actual, expected, `${rel} is stale — regenerate from the catalog`);
  }
});

Deno.test("passthrough kinds match the deepening decision record", () => {
  // Q6A: passthroughs are mechanical hub forwards only. Guard against
  // accidentally reclassifying methods that carry daemon-side logic.
  const coreOnly = [
    "approve_thread_downgrade", // local inbox notification
    "set_transport_default", // validates transport values
    "submit_feedback", // injects device platform
    "list_agents", // branches on handle param
    "close_thread",
    "delete_thread",
    "toggle_message_upvote",
  ];
  for (const name of coreOnly) {
    const m = catalog.methods.find((x) => x.name === name);
    assert(m, `${name} missing from catalog`);
    assertEquals(m!.kind, "core", `${name} must stay core-owned (see notes)`);
  }
});
