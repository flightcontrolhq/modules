import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { selectLocalDevSourceRef } from "../src/local-dev-source-ref.js";

describe("local dev source ref", () => {
  it("uses the explicit override before the current branch", () => {
    assert.equal(selectLocalDevSourceRef({ override: "override-ref", branch: "feature/rds" }), "override-ref");
  });

  it("uses the current branch without requiring an origin branch", () => {
    assert.equal(selectLocalDevSourceRef({ branch: "feature/rds" }), "feature/rds");
  });

  it("falls back to main when no override or branch is available", () => {
    assert.equal(selectLocalDevSourceRef({}), "main");
  });
});
