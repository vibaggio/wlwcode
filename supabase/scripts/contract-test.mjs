// scripts/contract-test.mjs
// Compara chamadas db.rpc("app_*") do bundle com funções no banco.
// Falha se houver divergência.

import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const bundle = readFileSync('supabase/app.min.js', 'utf8');

// Extrai nomes de RPC chamadas
const rpcNames = new Set();
for (const m of bundle.matchAll(/rpc\(\s*["'`]?(app_[a-z0-9_]+)["'`]?/gi)) {
  rpcNames.add(m[1]);
}

if (rpcNames.size === 0) {
  console.error('Nenhuma chamada app_* encontrada no bundle. Verificar regex.');
  process.exit(1);
}

console.log(`Encontradas ${rpcNames.size} chamadas app_* no bundle.`);

// Consulta o banco via supabase CLI
const list = [...rpcNames].map(n => `'${n}'`).join(',');
const sql = `
  select p.proname,
         has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname in (${list});
`;
const out = execSync(`supabase db execute --sql "${sql.replace(/"/g, '\\"')}"`,
                    { encoding: 'utf8' });

const found = new Set();
const problems = [];
for (const line of out.split('\n')) {
  const parts = line.split('|').map(s => s.trim());
  const [name, anonExec, authExec] = parts;
  if (!name || !name.startsWith('app_')) continue;
  found.add(name);
  if (anonExec === 't') problems.push(`  ✗ ${name} tem EXECUTE para anon`);
  if (authExec !== 't') problems.push(`  ✗ ${name} não tem EXECUTE para authenticated`);
}

for (const n of rpcNames) {
  if (!found.has(n)) problems.push(`  ✗ ${n} não existe no banco`);
}

if (problems.length > 0) {
  console.error('Contrato quebrado:\n' + problems.join('\n'));
  process.exit(1);
}

console.log('Contrato OK.');