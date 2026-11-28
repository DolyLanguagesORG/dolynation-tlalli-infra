#!/usr/bin/env node
/**
 * Semantic parity checker between PostgreSQL live schema (from database/postgres/01-init.sql)
 * and Drizzle ORM schema.ts (#25). Ignores naming-convention-only index differences
 * (e.g. users_email_key vs users_email_unique) and compares tables, columns, SQL types,
 * varchar lengths, and NOT NULL constraints.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import process from 'node:process';

const DRIZZLE_TO_PG_TYPE = {
  serial: 'integer',
  integer: 'integer',
  smallint: 'smallint',
  bigint: 'bigint',
  varchar: 'character varying',
  text: 'text',
  boolean: 'boolean',
  date: 'date',
  jsonb: 'jsonb',
  numeric: 'numeric',
  uuid: 'uuid',
};

function findStringEnd(src, startIdx, quote) {
  let i = startIdx + 1;
  while (i < src.length) {
    const ch = src[i];
    if (ch === '\\') {
      i += 2;
      continue;
    }
    if (ch === quote) {
      return i + 1;
    }
    i += 1;
  }
  return src.length;
}

function skipWhitespaceAndComments(src, idx) {
  let i = idx;
  while (i < src.length) {
    const ch = src[i];
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      i += 1;
      continue;
    }
    if (ch === '/' && src[i + 1] === '/') {
      const nl = src.indexOf('\n', i + 2);
      i = nl === -1 ? src.length : nl + 1;
      continue;
    }
    if (ch === '/' && src[i + 1] === '*') {
      const end = src.indexOf('*/', i + 2);
      i = end === -1 ? src.length : end + 2;
      continue;
    }
    break;
  }
  return i;
}

function readBalanced(src, openIdx, openChar, closeChar) {
  let depth = 0;
  let i = openIdx;
  while (i < src.length) {
    const ch = src[i];
    if (ch === '\'' || ch === '"' || ch === '`') {
      i = findStringEnd(src, i, ch);
      continue;
    }
    if (ch === '/' && src[i + 1] === '/') {
      const nl = src.indexOf('\n', i + 2);
      i = nl === -1 ? src.length : nl + 1;
      continue;
    }
    if (ch === '/' && src[i + 1] === '*') {
      const end = src.indexOf('*/', i + 2);
      i = end === -1 ? src.length : end + 2;
      continue;
    }
    if (ch === openChar) depth += 1;
    if (ch === closeChar) {
      depth -= 1;
      if (depth === 0) {
        return { text: src.slice(openIdx + 1, i), endIdx: i + 1 };
      }
    }
    i += 1;
  }
  throw new Error(`Unbalanced ${openChar}${closeChar} starting at index ${openIdx}`);
}

function stripCommentsOutsideStrings(src) {
  let out = '';
  let i = 0;
  while (i < src.length) {
    const ch = src[i];
    if (ch === '\'' || ch === '"' || ch === '`') {
      const end = findStringEnd(src, i, ch);
      out += src.slice(i, end);
      i = end;
      continue;
    }
    if (ch === '/' && src[i + 1] === '/') {
      const nl = src.indexOf('\n', i + 2);
      i = nl === -1 ? src.length : nl;
      continue;
    }
    if (ch === '/' && src[i + 1] === '*') {
      const end = src.indexOf('*/', i + 2);
      i = end === -1 ? src.length : end + 2;
      continue;
    }
    out += ch;
    i += 1;
  }
  return out;
}

function splitTopLevelProperties(body) {
  const entries = [];
  let brace = 0;
  let paren = 0;
  let bracket = 0;
  let start = 0;
  let i = 0;

  while (i < body.length) {
    const ch = body[i];
    if (ch === '\'' || ch === '"' || ch === '`') {
      i = findStringEnd(body, i, ch);
      continue;
    }
    if (ch === '/' && body[i + 1] === '/') {
      const nl = body.indexOf('\n', i + 2);
      i = nl === -1 ? body.length : nl + 1;
      continue;
    }
    if (ch === '/' && body[i + 1] === '*') {
      const end = body.indexOf('*/', i + 2);
      i = end === -1 ? body.length : end + 2;
      continue;
    }
    if (ch === '.' && /^\.\$type\s*</.test(body.slice(i))) {
      const ltIdx = body.indexOf('<', i);
      i = readBalanced(body, ltIdx, '<', '>').endIdx;
      continue;
    }
    if (ch === '{') brace += 1;
    else if (ch === '}') brace -= 1;
    else if (ch === '(') paren += 1;
    else if (ch === ')') paren -= 1;
    else if (ch === '[') bracket += 1;
    else if (ch === ']') bracket -= 1;
    else if (ch === ',' && brace === 0 && paren === 0 && bracket === 0) {
      const chunk = body.slice(start, i).trim();
      if (chunk.length > 0) entries.push(chunk);
      start = i + 1;
    }
    i += 1;
  }
  const tail = body.slice(start).trim();
  if (tail.length > 0) entries.push(tail);
  return entries;
}

function parseDrizzleSchema(filePath) {
  const src = readFileSync(filePath, 'utf8');
  const tables = new Map();
  const pgTableRegex = /\bpgTable\s*\(/g;

  let match;
  while ((match = pgTableRegex.exec(src)) !== null) {
    let cursor = skipWhitespaceAndComments(src, match.index + match[0].length);
    const quote = src[cursor];
    if (quote !== '\'' && quote !== '"') {
      throw new Error(`Expected quoted table name near index ${cursor}`);
    }
    const nameEnd = findStringEnd(src, cursor, quote);
    const tableName = src.slice(cursor + 1, nameEnd - 1);

    cursor = skipWhitespaceAndComments(src, nameEnd);
    if (src[cursor] !== ',') {
      throw new Error(`Expected comma after table name "${tableName}"`);
    }
    cursor = skipWhitespaceAndComments(src, cursor + 1);
    if (src[cursor] !== '{') {
      throw new Error(`Expected column definition object for table "${tableName}"`);
    }

    const columnsBlock = readBalanced(src, cursor, '{', '}');
    const propChunks = splitTopLevelProperties(stripCommentsOutsideStrings(columnsBlock.text));
    const columns = new Map();

    for (const chunk of propChunks) {
      const colonIdx = chunk.indexOf(':');
      if (colonIdx === -1) continue;
      const expr = chunk.slice(colonIdx + 1).trim();
      const colMatch =
        /^(serial|integer|smallint|bigint|varchar|text|boolean|timestamp|date|jsonb|numeric|uuid)\(\s*['"]([a-zA-Z0-9_]+)['"]/.exec(
          expr,
        );
      if (!colMatch) {
        throw new Error(`Unsupported Drizzle column expression in "${tableName}": ${chunk}`);
      }
      const [, drizzleType, colName] = colMatch;
      let dataType;
      if (drizzleType === 'timestamp') {
        dataType = /withTimezone\s*:\s*true/.test(expr)
          ? 'timestamp with time zone'
          : 'timestamp without time zone';
      } else {
        dataType = DRIZZLE_TO_PG_TYPE[drizzleType];
      }

      let maxLength = null;
      if (drizzleType === 'varchar') {
        const lenMatch = /length\s*:\s*(\d+)/.exec(expr);
        if (lenMatch?.[1]) maxLength = Number(lenMatch[1]);
      }

      const nullable = !(/\.notNull\s*\(/.test(expr) || /\.primaryKey\s*\(/.test(expr));
      columns.set(colName, { dataType, nullable, maxLength });
    }

    tables.set(tableName, columns);
  }

  return tables;
}

function queryPostgresSchema() {
  const sqlQuery =
    "SELECT table_name, column_name, data_type, is_nullable, COALESCE(character_maximum_length::text, '') FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position;";

  const pgHost = process.env.PGHOST ?? '127.0.0.1';
  const pgPort = process.env.PGPORT ?? '5432';
  const pgUser = process.env.PGUSER ?? 'postgres';
  const pgPassword = process.env.PGPASSWORD ?? 'postgres';
  const pgDatabase = process.env.PGDATABASE ?? 'dolynglish';
  const dockerContainer = process.env.DOCKER_PG_CONTAINER?.trim();

  let stdout;
  if (dockerContainer) {
    stdout = execFileSync(
      'docker',
      [
        'exec',
        '-e',
        `PGPASSWORD=${pgPassword}`,
        dockerContainer,
        'psql',
        '-h',
        '127.0.0.1',
        '-U',
        pgUser,
        '-d',
        pgDatabase,
        '-qtA',
        '-F',
        '\t',
        '-c',
        sqlQuery,
      ],
      { encoding: 'utf8' },
    );
  } else {
    stdout = execFileSync(
      'psql',
      ['-h', pgHost, '-p', pgPort, '-U', pgUser, '-d', pgDatabase, '-qtA', '-F', '\t', '-c', sqlQuery],
      {
        encoding: 'utf8',
        env: { ...process.env, PGPASSWORD: pgPassword },
      },
    );
  }

  const tables = new Map();
  for (const rawLine of stdout.split('\n')) {
    const line = rawLine.trim();
    if (!line) continue;
    const [tableName, columnName, dataType, isNullable, maxLenRaw] = line.split('\t');
    let cols = tables.get(tableName);
    if (!cols) {
      cols = new Map();
      tables.set(tableName, cols);
    }
    cols.set(columnName, {
      dataType,
      nullable: isNullable === 'YES',
      maxLength: maxLenRaw ? Number(maxLenRaw) : null,
    });
  }
  return tables;
}

function compareSchemas(drizzleTables, pgTables) {
  const diffs = [];

  for (const tableName of drizzleTables.keys()) {
    if (!pgTables.has(tableName)) {
      diffs.push(`MISSING_IN_SQL: table "${tableName}" exists in Drizzle schema.ts but not in PostgreSQL`);
    }
  }
  for (const tableName of pgTables.keys()) {
    if (!drizzleTables.has(tableName)) {
      diffs.push(`MISSING_IN_DRIZZLE: table "${tableName}" exists in PostgreSQL but not in Drizzle schema.ts`);
    }
  }

  let checkedColumns = 0;
  for (const [tableName, dCols] of drizzleTables.entries()) {
    const pCols = pgTables.get(tableName);
    if (!pCols) continue;

    for (const colName of dCols.keys()) {
      if (!pCols.has(colName)) {
        diffs.push(`MISSING_IN_SQL: column "${tableName}.${colName}" exists in Drizzle schema.ts but not in PostgreSQL`);
      }
    }
    for (const colName of pCols.keys()) {
      if (!dCols.has(colName)) {
        diffs.push(`MISSING_IN_DRIZZLE: column "${tableName}.${colName}" exists in PostgreSQL but not in Drizzle schema.ts`);
      }
    }

    for (const [colName, dCol] of dCols.entries()) {
      const pCol = pCols.get(colName);
      if (!pCol) continue;
      checkedColumns += 1;

      if (dCol.dataType !== pCol.dataType) {
        diffs.push(
          `TYPE_MISMATCH: "${tableName}.${colName}" -> Drizzle=${dCol.dataType}, PostgreSQL=${pCol.dataType}`,
        );
      }
      if (dCol.nullable !== pCol.nullable) {
        diffs.push(
          `NULLABILITY_MISMATCH: "${tableName}.${colName}" -> Drizzle=${dCol.nullable ? 'NULL' : 'NOT NULL'}, PostgreSQL=${pCol.nullable ? 'NULL' : 'NOT NULL'}`,
        );
      }
      if (dCol.maxLength !== null && pCol.maxLength !== null && dCol.maxLength !== pCol.maxLength) {
        diffs.push(
          `LENGTH_MISMATCH: "${tableName}.${colName}" -> Drizzle=varchar(${dCol.maxLength}), PostgreSQL=varchar(${pCol.maxLength})`,
        );
      }
    }
  }

  return { diffs, checkedColumns };
}

function main() {
  const schemaPath = resolve(
    process.argv[2] ??
      process.env.DRIZZLE_SCHEMA_PATH ??
      '../dolynation-atl-back/src/database/drizzle/schema.ts',
  );
  const drizzleTables = parseDrizzleSchema(schemaPath);
  const pgTables = queryPostgresSchema();
  const { diffs, checkedColumns } = compareSchemas(drizzleTables, pgTables);

  if (diffs.length > 0) {
    console.error(`Schema parity check FAILED (${diffs.length} difference(s)):`);
    for (const d of diffs) {
      console.error(`  - ${d}`);
    }
    process.exit(1);
  }

  console.log(
    `OK: Drizzle (${schemaPath}) and PostgreSQL schema match (${drizzleTables.size} tables, ${checkedColumns} columns verified).`,
  );
}

main();
