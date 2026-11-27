// 참조 예제. WebAuthn assertion 검증의 AX 고유 부분. 정규화 범위는 문자열·안전 정수·불리언·null·배열·객체다.
import crypto from 'node:crypto';
export const canon = v => {
  if (v === null || typeof v === 'boolean' || typeof v === 'string') {
    if (typeof v === 'string' && !v.isWellFormed()) throw new Error('surrogate'); return JSON.stringify(v); }
  if (typeof v === 'number') { if (!Number.isSafeInteger(v)) throw new Error('integer only'); return JSON.stringify(v); }
  if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
  if (typeof v === 'object') return '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
  throw new Error('type'); };
const sha = b => crypto.createHash('sha256').update(b).digest();
export const payloadHash = p => sha(canon(p));
export const challenge = p => sha(Buffer.concat([Buffer.from('ax-approval-v1\0'), payloadHash(p), Buffer.from(p.nonce)]));
export function verify(p, a, cred, cfg, now) {
  if (cred.revoked) return 'revoked';
  if (now >= p.expires_at) return 'expired';
  const c = JSON.parse(a.clientDataJSON.toString());
  if (c.type !== 'webauthn.get') return 'type';
  if (c.origin !== cfg.origin || c.crossOrigin === true) return 'origin';
  const got = Buffer.from(c.challenge, 'base64url'), want = challenge(p);
  if (got.length !== 32 || !crypto.timingSafeEqual(got, want)) return 'challenge';
  const d = a.authenticatorData; if (d.length < 37) return 'authdata';
  if (!d.subarray(0, 32).equals(sha(cfg.rpId))) return 'rpid';
  if ((d[32] & 5) !== 5) return 'user-verification';
  if (!crypto.verify('sha256', Buffer.concat([d, sha(a.clientDataJSON)]), cred.publicKey, a.signature)) return 'signature';
  return 'ok'; }
