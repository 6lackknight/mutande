import { test } from "node:test";
import assert from "node:assert/strict";
// @ts-expect-error -- node --test needs the explicit .ts extension; bundler resolution forbids it.
import { isPitchPath, needsAuth } from "./proxy-rules.ts";

test("isPitchPath matches the deck and everything under it", () => {
  for (const p of [
    "/pitch",
    "/pitch/",
    "/pitch/1",
    "/pitch/assets/index-X.js",
    "/pitch/../admin",
    "/pitch/presenter/",
  ]) {
    assert.equal(isPitchPath(p), true, `expected isPitchPath(${p}) === true`);
  }
});

test("isPitchPath rejects lookalikes and other routes", () => {
  for (const p of ["/pitch-deck", "/pitchfoo", "/PITCH", "/Pitch", "/", "/dashboard"]) {
    assert.equal(isPitchPath(p), false, `expected isPitchPath(${p}) === false`);
  }
});

test("needsAuth matches protected prefixes exactly or with a slash", () => {
  for (const p of ["/signup", "/onboarding/create", "/dashboard", "/admin/ops", "/join", "/join/abc"]) {
    assert.equal(needsAuth(p), true, `expected needsAuth(${p}) === true`);
  }
});

test("needsAuth rejects public, auth, pitch, and prefix-without-slash paths", () => {
  for (const p of ["/", "/login", "/pitch", "/pitch/1", "/auth/login", "/dashboards"]) {
    assert.equal(needsAuth(p), false, `expected needsAuth(${p}) === false`);
  }
});
