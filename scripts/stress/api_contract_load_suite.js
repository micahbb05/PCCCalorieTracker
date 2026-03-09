#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const {
  ensureDir,
  mean,
  percentile,
  pickTier,
  readJson,
  timedFetch,
  writeJson,
} = require('./lib/common');

const ROOT = path.resolve(__dirname, '..', '..');
const BASE_URL = (process.env.BACKEND_BASE_URL || 'https://us-central1-calorie-tracker-364e3.cloudfunctions.net').replace(/\/$/, '');

function buildUrl(endpoint, query) {
  const url = new URL(`${BASE_URL}/${endpoint}`);
  if (query && typeof query === 'object') {
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
    }
  }
  return String(url);
}

function classifyPhaseConfig(profile, tier) {
  const phases = profile.phases;
  if (tier === 'nightly' || tier === 'pre-release') return phases;
  if (profile.ai) {
    return {
      steady: { requests: 1, concurrency: 1 },
      burst: { requests: 0, concurrency: 1 },
      soak: { durationSeconds: 0, concurrency: 1 },
    };
  }
  const soakDuration = Math.min(3, phases.soak.durationSeconds);
  return {
    steady: { requests: Math.min(2, phases.steady.requests), concurrency: 1 },
    burst: { requests: Math.min(3, phases.burst.requests), concurrency: 1 },
    soak: { durationSeconds: soakDuration, concurrency: 1 },
  };
}

function validateContract(endpoint, status, json) {
  if (status >= 400) return true;
  if (!json || typeof json !== 'object') return false;

  const obj = json;
  if (endpoint === 'searchUSDAFoods') {
    return Array.isArray(obj.foods) && obj.foods.every((x) => typeof x.name === 'string' && typeof x.calories === 'number');
  }
  if (endpoint === 'estimatePlatePortions') {
    return obj.ozByFoodName && typeof obj.ozByFoodName === 'object' && obj.countByFoodName && typeof obj.countByFoodName === 'object';
  }
  if (endpoint === 'analyzeFoodPhoto') {
    return Array.isArray(obj.items) && obj.items.every((x) => typeof x.name === 'string' && typeof x.calories === 'number');
  }
  if (endpoint === 'analyzeFoodText') {
    return Array.isArray(obj.items) && obj.items.every((x) => typeof x.name === 'string' && typeof x.calories === 'number');
  }
  if (endpoint === 'proxyNutrislice') {
    return typeof obj === 'object';
  }
  return true;
}

async function materializeBody(profile) {
  if (profile.method !== 'POST') return null;
  const body = { ...(profile.body || {}) };
  if (body.imagePath) {
    const abs = path.resolve(ROOT, body.imagePath);
    if (!fs.existsSync(abs)) throw new Error(`Missing fixture image: ${body.imagePath}`);
    body.imageBase64 = fs.readFileSync(abs).toString('base64');
    delete body.imagePath;
  }
  return body;
}

async function oneRequest(profile) {
  const url = buildUrl(profile.endpoint, profile.query);
  const body = await materializeBody(profile);
  const init = {
    method: profile.method,
    headers: { 'content-type': 'application/json' },
  };
  if (profile.method === 'POST') init.body = JSON.stringify(body || {});

  try {
    const timeoutMs = profile.ai ? 25000 : 8000;
    const res = await timedFetch(url, init, { timeoutMs });
    const expectedStatuses = new Set(profile.expectedStatuses || [200]);
    const okStatus = expectedStatuses.has(res.response.status);
    const contractValid = validateContract(profile.endpoint, res.response.status, res.json);
    return {
      ok: okStatus && contractValid,
      status: res.response.status,
      durationMs: res.durationMs,
      contractValid,
      textSample: res.text.slice(0, 200),
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      durationMs: 0,
      contractValid: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

async function runLoad(profile, phaseName, phaseConfig) {
  const results = [];

  const runWorker = async (count) => {
    for (let i = 0; i < count; i += 1) {
      results.push(await oneRequest(profile));
    }
  };

  if (phaseName === 'soak') {
    if (phaseConfig.durationSeconds <= 0) return results;
    const endAt = Date.now() + (phaseConfig.durationSeconds * 1000);
    const workers = Array.from({ length: phaseConfig.concurrency }, async () => {
      while (Date.now() < endAt) {
        results.push(await oneRequest(profile));
      }
    });
    await Promise.all(workers);
    return results;
  }

  const requests = phaseConfig.requests;
  if (requests <= 0) return results;
  const perWorker = Math.ceil(requests / phaseConfig.concurrency);
  const workers = Array.from({ length: phaseConfig.concurrency }, () => runWorker(perWorker));
  await Promise.all(workers);
  return results.slice(0, requests);
}

async function runFailureInjection(outDir) {
  const cases = [
    {
      name: 'searchUSDAFoods-empty-query',
      url: buildUrl('searchUSDAFoods', { query: '' }),
      init: { method: 'GET' },
      expected: [400],
    },
    {
      name: 'analyzeFoodText-empty-body',
      url: buildUrl('analyzeFoodText'),
      init: { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ mealText: '' }) },
      expected: [400],
    },
    {
      name: 'estimatePlatePortions-invalid-body',
      url: buildUrl('estimatePlatePortions'),
      init: { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({}) },
      expected: [400],
    },
    {
      name: 'proxyNutrislice-invalid-url',
      url: buildUrl('proxyNutrislice'),
      init: { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ targetUrl: 'https://example.com/' }) },
      expected: [405],
    },
  ];

  const results = [];
  for (const c of cases) {
    const res = await timedFetch(c.url, c.init, { timeoutMs: 15000 });
    const ok = c.expected.includes(res.response.status);
    results.push({ name: c.name, status: res.response.status, ok, bodySample: res.text.slice(0, 200) });
  }

  writeJson(path.join(outDir, 'api_failure_injection.json'), results);
  return results;
}

async function main() {
  const runId = process.env.STRESS_RUN_ID || 'adhoc';
  const tier = pickTier();
  const outDir = path.join(ROOT, 'output', 'stress', runId);
  ensureDir(outDir);

  const profiles = readJson(path.join(ROOT, 'scripts', 'stress', 'fixtures', 'api_load_profiles.v1.json'));
  const endpointSummaries = [];

  for (const rawProfile of profiles) {
    const profile = JSON.parse(JSON.stringify(rawProfile));
    const phases = classifyPhaseConfig(profile, tier);

    const steadyResults = await runLoad(profile, 'steady', phases.steady);
    const burstResults = await runLoad(profile, 'burst', phases.burst);
    const soakResults = await runLoad(profile, 'soak', phases.soak);

    const all = [...steadyResults, ...burstResults, ...soakResults];
    const successRate = all.length ? all.filter((x) => x.ok).length / all.length : 0;
    const contractRate = all.length ? all.filter((x) => x.contractValid).length / all.length : 0;
    const latencies = all.map((x) => x.durationMs).filter((x) => x > 0);

    endpointSummaries.push({
      id: profile.id,
      endpoint: profile.endpoint,
      ai: !!profile.ai,
      samples: all.length,
      successRate,
      contractRate,
      p95LatencyMs: percentile(latencies, 95),
      avgLatencyMs: mean(latencies),
      errors: all.filter((x) => !x.ok).slice(0, 10),
    });
  }

  const failureInjection = await runFailureInjection(outDir);

  const nonAi = endpointSummaries.filter((x) => !x.ai);
  const ai = endpointSummaries.filter((x) => x.ai);

  const aggregate = {
    suite: 'api_contract_load',
    tier,
    passed: tier === 'pr'
      ? endpointSummaries.every((x) => x.samples > 0) && failureInjection.every((x) => x.ok)
      : endpointSummaries.every((x) => x.successRate >= 0.995 && x.contractRate === 1)
        && nonAi.every((x) => x.p95LatencyMs <= 1200)
        && ai.every((x) => x.p95LatencyMs <= 4500)
        && failureInjection.every((x) => x.ok),
    metrics: {
      apiSuccessRate: endpointSummaries.length
        ? endpointSummaries.reduce((acc, x) => acc + x.successRate, 0) / endpointSummaries.length
        : 0,
      contractValidity: endpointSummaries.length
        ? endpointSummaries.reduce((acc, x) => acc + x.contractRate, 0) / endpointSummaries.length
        : 0,
      apiNonAiP95LatencyMs: nonAi.length ? Math.max(...nonAi.map((x) => x.p95LatencyMs)) : 0,
      apiAiP95LatencyMs: ai.length ? Math.max(...ai.map((x) => x.p95LatencyMs)) : 0,
    },
    endpoints: endpointSummaries,
    failureInjection,
  };

  writeJson(path.join(outDir, 'api_contract_load.json'), aggregate);
  console.log(JSON.stringify(aggregate, null, 2));
  if (!aggregate.passed) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
