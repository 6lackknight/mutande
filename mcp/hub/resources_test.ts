import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  HOST_PATH_REFUSAL,
  prepareBundleResources,
  resourceHasInlineContent,
  resourceHostOnlyPath,
} from "./resources.ts";

Deno.test("resourceHasInlineContent detects content and base64", () => {
  assertEquals(resourceHasInlineContent({ content: "hello" }), true);
  assertEquals(resourceHasInlineContent({ content_base64: "aGVsbG8=" }), true);
  assertEquals(resourceHasInlineContent({ path: "/mnt/data/x.md" }), false);
});

Deno.test("resourceHostOnlyPath detects ChatGPT sandbox paths", () => {
  assertEquals(
    resourceHostOnlyPath({ path: "/mnt/data/mutande-organisations-prd.md" }),
    "/mnt/data/mutande-organisations-prd.md",
  );
  assertEquals(
    resourceHostOnlyPath({
      path: "/mnt/data/x.md",
      content: "inline ok",
    }),
    null,
  );
});

Deno.test("prepareBundleResources rejects /mnt/data without content", () => {
  const err = assertThrows(
    () =>
      prepareBundleResources({
        notes: "handoff",
        resources: [{
          name: "prd.md",
          path: "/mnt/data/mutande-organisations-prd.md",
        }],
      }),
    Error,
  );
  assertEquals(err.message.includes(HOST_PATH_REFUSAL.slice(0, 40)), true);
  assertEquals(err.message.includes("/mnt/data/"), true);
});

Deno.test("prepareBundleResources accepts inline content with path label", () => {
  const out = prepareBundleResources({
    notes: "handoff",
    resources: [{
      name: "prd.md",
      path: "/mnt/data/prd.md",
      content: "# PRD\n\nHello",
    }],
  });
  const resources = out.resources as Array<Record<string, unknown>>;
  assertEquals(resources[0].content, "# PRD\n\nHello");
});

Deno.test("prepareBundleResources decodes content_base64 text", () => {
  const out = prepareBundleResources({
    resources: [{
      name: "note.txt",
      content_base64: btoa("hello from base64"),
    }],
  });
  const resources = out.resources as Array<Record<string, unknown>>;
  assertEquals(resources[0].content, "hello from base64");
});
