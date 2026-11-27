// 참조 예제. 설계 검증용이며 제품 코드가 아니다. PreToolUse 전용: 실패는 모두 exit 2.
import path from 'node:path'; import fs from 'node:fs'; import net from 'node:net';
const deny = (rule, why) => { fs.writeSync(2, `AX-${rule}: ${why}\n`); process.exit(2); };
process.on('uncaughtException', () => deny('INTERNAL', '내부 오류. 다시 시도하지 말고 보고하세요'));
process.on('unhandledRejection', () => deny('INTERNAL', '내부 오류. 다시 시도하지 말고 보고하세요'));
setTimeout(() => deny('TIMEOUT', 'Hook 시간 초과'), 1500);
const MAX = 1 << 20, WORK = process.env.AX_WORK, SOCK = process.env.AX_SOCK;
if (!WORK || !SOCK) deny('CONFIG', 'AX 환경이 없습니다');
let n = 0; const chunks = [];
for await (const c of process.stdin) { n += c.length; if (n > MAX) deny('SIZE', '입력이 너무 큽니다'); chunks.push(c); }
const e = JSON.parse(Buffer.concat(chunks).toString('utf8'));
if (e.hook_event_name !== 'PreToolUse' || typeof e.tool_name !== 'string') deny('INPUT', '입력 형식 오류');
const resolveReal = p => { // 없는 파일은 존재하는 가장 가까운 상위를 해석
  let cur = path.resolve(e.cwd ?? WORK, p), tail = [];
  for (;;) { try { return path.join(fs.realpathSync(cur), ...tail); }
    catch (err) { if (err.code !== 'ENOENT') throw err;
      if (fs.lstatSync(cur, { throwIfNoEntry: false })?.isSymbolicLink()) deny('PATH', '끊어진 상징 링크');
      tail.unshift(path.basename(cur)); const up = path.dirname(cur); if (up === cur) throw err; cur = up; } } };
const root = fs.realpathSync(WORK), BLOCK = /(^|\/)(\.git|\.claude|\.codex|\.github\/workflows)(\/|$)|(^|\/)(\.mcp\.json|\.env[^/]*)$/i;
if (['Write', 'Edit', 'NotebookEdit', 'Read'].includes(e.tool_name)) {
  const p = e.tool_input?.file_path ?? e.tool_input?.notebook_path;
  if (typeof p !== 'string') deny('INPUT', '경로 없음');
  const r = resolveReal(p), rel = path.relative(root, r);
  if (rel.startsWith('..') || path.isAbsolute(rel)) deny('PATH', '작업 폴더 밖입니다');
  if (BLOCK.test(rel) && (e.tool_name !== 'Read' || /\.env/i.test(rel))) deny('PROTECTED', '보호된 경로입니다');
} else if (!['Bash', 'Grep', 'Glob'].includes(e.tool_name)) deny('TOOL', '허용되지 않은 도구입니다');
await new Promise((ok, bad) => { const s = net.connect(SOCK); s.on('error', bad);
  s.on('data', d => d.toString().startsWith('ack') ? ok() : bad(new Error('nack')));
  s.write(JSON.stringify({ id: e.tool_use_id, tool: e.tool_name, decision: 'allow' }) + '\n'); });
process.exit(0);
