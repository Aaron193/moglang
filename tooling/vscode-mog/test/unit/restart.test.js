"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { RestartBudget } = require("../../src/restart");

test("bounds automatic restarts and uses exponential delay", () => {
  const budget = new RestartBudget(3, 60_000);
  assert.deepEqual(budget.record(0), { canRestart: true, attempt: 1, delay: 250 });
  assert.deepEqual(budget.record(1), { canRestart: true, attempt: 2, delay: 500 });
  assert.deepEqual(budget.record(2), { canRestart: true, attempt: 3, delay: 1000 });
  assert.deepEqual(budget.record(3), { canRestart: false, attempt: 4, delay: null });
});

test("restart budget expires and can be manually reset", () => {
  const budget = new RestartBudget(1, 100);
  budget.record(0);
  assert.equal(budget.record(50).canRestart, false);
  assert.equal(budget.record(101).canRestart, true);
  budget.reset();
  assert.equal(budget.record(102).attempt, 1);
});
