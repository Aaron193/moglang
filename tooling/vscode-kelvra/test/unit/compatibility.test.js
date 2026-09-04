"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { checkCompatibility, protocolMetadata } = require("../../src/compatibility");

test("reads advertised Kelvra protocol metadata", () => {
  const metadata = protocolMetadata({
    serverInfo: { name: "kelvra-lsp", version: "0.1.6" },
    kelvra: { toolingProtocolVersion: "1.2", features: ["install"] }
  });
  assert.deepEqual(metadata, {
    serverVersion: "0.1.6",
    protocolVersion: 1,
    features: ["install"]
  });
});

test("accepts protocol 1 and rejects incompatible major versions", () => {
  assert.equal(checkCompatibility({ toolingProtocolVersion: 1 }).compatible, true);
  const incompatible = checkCompatibility({ toolingProtocolVersion: 2 });
  assert.equal(incompatible.compatible, false);
  assert.match(incompatible.reason, /outside the supported range 1-1/);
});

test("rejects stale legacy servers that cannot negotiate a protocol", () => {
  const result = checkCompatibility({ serverInfo: { version: "old" } });
  assert.equal(result.compatible, false);
  assert.equal(result.legacy, true);
  assert.equal(result.protocolVersion, null);
  assert.match(result.reason, /too old/);
});
