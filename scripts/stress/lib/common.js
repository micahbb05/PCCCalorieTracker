#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

function nowIsoCompact() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, value) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2));
}

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function mean(values) {
  if (!values.length) return 0;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function mape(rows) {
  if (!rows.length) return 0;
  const absPct = rows.map((row) => {
    const ref = row.reference;
    const val = row.actual;
    if (ref === 0) return val === 0 ? 0 : 100;
    return Math.abs(((val - ref) / ref) * 100);
  });
  return mean(absPct);
}

async function runCommand(command, args, opts = {}) {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const child = spawn(command, args, {
      cwd: opts.cwd || process.cwd(),
      env: { ...process.env, ...(opts.env || {}) },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      const txt = String(chunk);
      stdout += txt;
      if (opts.stream) process.stdout.write(txt);
    });

    child.stderr.on('data', (chunk) => {
      const txt = String(chunk);
      stderr += txt;
      if (opts.stream) process.stderr.write(txt);
    });

    child.on('close', (code, signal) => {
      resolve({
        ok: code === 0,
        code,
        signal,
        stdout,
        stderr,
        durationMs: Date.now() - startedAt,
      });
    });
  });
}

async function timedFetch(url, init, opts = {}) {
  const timeoutMs = Number.isFinite(opts.timeoutMs) ? opts.timeoutMs : 20000;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const startedAt = Date.now();
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    const durationMs = Date.now() - startedAt;
    const text = await response.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch {
      json = null;
    }
    return { response, durationMs, text, json };
  } finally {
    clearTimeout(timeout);
  }
}

function safeNumber(value, fallback = 0) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function pickTier() {
  const tier = (process.env.STRESS_TIER || 'pr').toLowerCase();
  if (['pr', 'nightly', 'pre-release'].includes(tier)) return tier;
  return 'pr';
}

module.exports = {
  ensureDir,
  mean,
  mape,
  nowIsoCompact,
  percentile,
  pickTier,
  readJson,
  runCommand,
  safeNumber,
  timedFetch,
  writeJson,
};
