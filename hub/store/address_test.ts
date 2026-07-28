import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  formatDisplayAddress,
  formatWirePath,
  parseDisplayAddress,
  parseWirePath,
  stripAgentSuffix,
} from "./address.ts";
import { HubError } from "./errors.ts";

Deno.test("parse bare and agent-scoped display addresses", () => {
  assertEquals(parseDisplayAddress("alice@acme"), { local: "alice", orgSlug: "acme", agentSlug: undefined });
  assertEquals(parseDisplayAddress("alice@acme/claude"), {
    local: "alice",
    orgSlug: "acme",
    agentSlug: "claude",
  });
  assertEquals(parseDisplayAddress("@all@acme"), { local: "@all", orgSlug: "acme", agentSlug: undefined });
});

Deno.test("format display and wire path", () => {
  assertEquals(formatDisplayAddress("alice", "acme", "cursor"), "alice@acme/cursor");
  assertEquals(formatWirePath("acme", "alice", "cursor"), "acme/alice/cursor");
  assertEquals(parseWirePath("acme/alice/cursor"), {
    orgSlug: "acme",
    local: "alice",
    agentSlug: "cursor",
  });
});

Deno.test("strip agent suffix", () => {
  assertEquals(stripAgentSuffix("bob@acme/research"), "bob@acme");
  assertEquals(stripAgentSuffix("bob@acme"), "bob@acme");
});

Deno.test("reject reserved agent slugs", () => {
  assertThrows(() => parseDisplayAddress("alice@acme/default"), HubError);
  assertThrows(() => parseDisplayAddress("alice@acme/all"), HubError);
});
