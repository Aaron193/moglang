"use strict";

const MAX_AUTOMATIC_RESTARTS = 3;
const RESTART_WINDOW_MS = 60_000;

class RestartBudget {
  constructor(maximum = MAX_AUTOMATIC_RESTARTS, windowMs = RESTART_WINDOW_MS) {
    this.maximum = maximum;
    this.windowMs = windowMs;
    this.times = [];
  }

  record(now = Date.now()) {
    this.times = this.times.filter((time) => now - time < this.windowMs);
    if (this.times.length >= this.maximum) {
      return { canRestart: false, attempt: this.times.length + 1, delay: null };
    }
    this.times.push(now);
    return {
      canRestart: true,
      attempt: this.times.length,
      delay: 250 * 2 ** (this.times.length - 1)
    };
  }

  reset() {
    this.times = [];
  }
}

module.exports = { MAX_AUTOMATIC_RESTARTS, RESTART_WINDOW_MS, RestartBudget };
