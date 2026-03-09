#!/usr/bin/env node

const path = require('path');
const { readJson, writeJson } = require('./lib/common');

const ROOT = path.resolve(__dirname);
const schemas = readJson(path.join(ROOT, 'fixtures', 'schemas.json')).definitions;

function isType(value, type) {
  if (type === 'array') return Array.isArray(value);
  if (type === 'null') return value === null;
  if (type === 'integer') return Number.isInteger(value);
  return typeof value === type;
}

function validateObject(value, schema, ptr = '') {
  const errors = [];

  if (schema.type) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => isType(value, t))) {
      errors.push(`${ptr || '/'} expected type ${types.join('|')}`);
      return errors;
    }
  }

  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${ptr || '/'} expected enum ${schema.enum.join(', ')}`);
  }

  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) errors.push(`${ptr || '/'} below minimum ${schema.minimum}`);
    if (schema.exclusiveMinimum !== undefined && value <= schema.exclusiveMinimum) {
      errors.push(`${ptr || '/'} must be > ${schema.exclusiveMinimum}`);
    }
  }

  if (typeof value === 'string') {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${ptr || '/'} minLength ${schema.minLength}`);
    }
  }

  if (Array.isArray(value)) {
    if (schema.items) {
      value.forEach((item, index) => {
        errors.push(...validateObject(item, schema.items, `${ptr}/${index}`));
      });
    }
    return errors;
  }

  if (value && typeof value === 'object') {
    const required = schema.required || [];
    required.forEach((key) => {
      if (!(key in value)) errors.push(`${ptr || '/'} missing required key ${key}`);
    });

    const properties = schema.properties || {};
    for (const [key, child] of Object.entries(properties)) {
      if (key in value) {
        errors.push(...validateObject(value[key], child, `${ptr}/${key}`));
      }
    }

    if (schema.additionalProperties && typeof schema.additionalProperties === 'object') {
      for (const [key, childVal] of Object.entries(value)) {
        if (!properties[key]) {
          errors.push(...validateObject(childVal, schema.additionalProperties, `${ptr}/${key}`));
        }
      }
    }
  }

  return errors;
}

function main() {
  const files = [
    { key: 'food_fixture', file: 'food_fixtures.v1.json' },
    { key: 'exercise_fixture', file: 'exercise_golden.v1.json' },
    { key: 'ai_eval_case', file: 'ai_eval_cases.v1.json' },
    { key: 'api_load_profile', file: 'api_load_profiles.v1.json' },
  ];

  const failures = [];
  for (const def of files) {
    const data = readJson(path.join(ROOT, 'fixtures', def.file));
    if (!Array.isArray(data)) {
      failures.push(`${def.file} must be an array`);
      continue;
    }
    data.forEach((entry, index) => {
      const errs = validateObject(entry, schemas[def.key], `/${def.file}/${index}`);
      failures.push(...errs);
    });
  }

  const report = {
    suite: 'fixture_schema_validation',
    passed: failures.length === 0,
    totalErrors: failures.length,
    failures,
  };

  const out = path.join(ROOT, '..', '..', 'output', 'stress', process.env.STRESS_RUN_ID || 'adhoc', 'fixture_validation.json');
  writeJson(out, report);

  if (failures.length) {
    console.error('Fixture schema validation failed');
    failures.forEach((f) => console.error(`- ${f}`));
    process.exit(1);
  }

  console.log('Fixture schema validation passed');
}

main();
