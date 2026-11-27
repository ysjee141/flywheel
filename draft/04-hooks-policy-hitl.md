# 04. Hook, 정책, 승인

**결론: Hook은 빠르게 알려 주는 계층이다. 막아야 하는 일은 샌드박스, 자격증명 분리, 병합 게이트, 권한 실행기가 막는다.**

## 1. 방어 계층

| 순서 | 계층 | 우회되면 |
|---|---|---|
| 1 | 자격증명 부재, 샌드박스, 네트워크 허용 목록 | 사고로 처리 |
| 2 | 하네스 권한 `deny` 규칙 | 1이 막는다 |
| 3 | PreToolUse Hook | 1과 2가 막는다 |
| 4 | PostToolUse, Stop | CI가 잡는다 |
| 5 | CI 결과를 확인하는 병합 게이트 | 감사가 찾고 배포를 막는다([ADR-0009](adr/0009-private-free-merge-gate.md)) |

**확인됨** ([공식 문서](https://code.claude.com/docs/en/hooks), [2.1.331 실측](evidence/hooks-2.1.331.md)):
- 프로젝트 설정의 `disableAllHooks`가 AX Hook까지 껐다. `--setting-sources ""`로 막았다. 그래서 이 플래그는 필수다.
- `--settings` 파일은 세션 중 다시 읽힌다. 파일을 바꾸자 Hook이 꺼졌다. 인라인 JSON으로 넘기자 세션 중 저장소 설정을 바꿔도 유지됐다. 그래서 인라인 JSON을 쓴다. 설정에 비밀을 넣지 않는다.
- exit 0과 깨진 JSON은 `onFailure: "block"`이어도 통과한다. 그래서 거부는 JSON이 아니라 exit 2로만 표현한다.
- 헤드리스에서 `ask`는 거부와 같다.
- Stop 차단은 8회까지 이어지고 9번째에 풀린다.
- `bash -c`와 `python3`는 문자열 규칙을 우회한다.
- exit 2는 PreToolUse를 막는다. exit 1은 막지 않는다.
- timeout과 crash는 기본적으로 작업을 통과시킨다. `onFailure: "block"`은 v2.1.295부터 있다. 로컬은 2.1.331이다.
- 같은 이벤트의 Hook은 병렬로 실행된다. 그래서 이벤트마다 AX 진입점 하나만 등록하고 그 안에서 순서를 정한다.
- `if` 필터는 best-effort다. 강한 거부는 권한 체계로 한다.
- `allowManagedHooksOnly`는 관리 설정에서 Hook 출처를 제한한다.

## 2. 공통 계약

- 입력은 stdin JSON 하나다. 1MiB를 넘거나 해석할 수 없으면 PreToolUse는 exit 2다.
- Hook 프로그램은 빌드된 단일 파일이다. 설치 때 해시를 기록하고 시작 때 대조한다.
- 작업이 쓰는 파일에서 정책을 읽지 않는다. 정책은 읽기 전용 마운트에서 읽는다.
- Hook은 에이전트와 같은 샌드박스에서 실행된다. 그래서 이벤트는 위조될 수 있고 증거가 아니다.
- 모든 Hook은 `ax-core` 소켓에 이벤트를 보낸다. 소켓 실패 시 PreToolUse는 거부하고 나머지는 로컬 큐에 쓴다.
- 로그에는 명령 원문 대신 도구, 규칙 ID, 결정, HMAC을 남긴다.

| 종료 | 뜻 |
|---|---|
| 0 | 통과. PreToolUse는 stdout을 비운다 |
| 2 | 차단. stderr는 `AX-<규칙>: 이유. 다음 행동` |
| 그 외 | 사용 금지. 래퍼가 PreToolUse에서는 2로 바꾼다 |

## 3. 이벤트별 정책

| ID | 이벤트 | 동작 | timeout | 실패 시 |
|---|---|---|---|---|
| H-01 | SessionStart | 작업 토큰, 볼트 버전, 정책 해시 확인 후 컨텍스트 주입 | 5s | SessionStart는 막지 못한다. H-02가 첫 도구를 거부 |
| H-02 | PreToolUse 전체 | 세션 초기화 확인, 경로·도구·도메인 정책 | 2s | 차단 (`onFailure: "block"`) |
| H-03 | PreToolUse Bash | 위험 명령 감지, 장기 명령 안내 | 2s | 차단 |
| H-04 | PostToolUse 편집 | 변경 파일 포맷, 비밀 검사 | 10s | 경고 + `dirty_check` 기록 |
| H-05 | PostToolBatch | 증분 타입 검사 | 60s | 경고 |
| H-06 | PreCompact | 체크포인트 확인 | 5s | 압축 허용, 이벤트 기록 |
| H-07 | Stop | 완료 조건 검사 | 120s | 완료 불인정, `blocked` |
| H-08 | SubagentStop | 산출물 스키마 검사 | 10s | 완료 불인정 |
| H-09 | ConfigChange | 작업 중 설정 변경 차단 | 2s | 세션 종료 |

`PostToolBatch`는 병렬 도구 2개에 1회 호출되고 `tool_calls` 배열을 준다(실측). H-06과 H-09는 아직 시험하지 않았다.

**Hook 생존 대조.** 코어는 하네스 스트림의 도구 호출 ID와 H-02가 소켓으로 보낸 ID를 대조한다.
2초 안에 짝이 없는 도구 호출이 있으면 세션을 강제 종료하고 산출물을 격리한다. `ax_hook_fail_open_total`을 올린다.
이는 사후 탐지다. 이미 실행된 명령의 피해는 샌드박스가 제한한다.

**H-04:** `tsc`를 파일마다 실행하면 느리다. 그래서 H-05로 옮겼다. `console.log`는 무조건 경고하지 않고 린트 규칙과 CLI 패키지 예외를 쓴다.
**H-06:** 80% 트리거에 의존하지 않는다. 체크포인트는 테스트 결과, 커밋, 결정, 10분 경과 때마다 쓴다.
**H-07:** 다음을 모두 확인한다. 변경이 없는 조사 작업은 테스트 대신 근거 목록을 확인한다.
1. 마지막 편집 뒤에 필수 테스트가 통과했다. 테스트 결과는 트리 해시에 묶인다.
2. 수용 기준마다 증거 참조가 있다.
3. 비밀 검사에서 발견이 없다.

같은 이유로 3회 반려하면 작업을 `blocked`로 바꾸고 세션 종료를 허용한다. `stop_hook_active`만으로 횟수를 추정하지 않고 AX가 센다.

## 4. 권한 정책

```yaml
# policies/base.yaml
version: 1
default: deny
filesystem:
  write: ["$WORKTREE/**", "$TASK_TMP/**"]
  deny_write: ["**/.git/**", "**/.claude/**", "**/.codex/**", "**/.mcp.json", "**/.github/workflows/**", "policies/**"]
  deny_read: ["**/.env*", "$HOME/.ssh/**", "$HOME/.config/gh/**"]
network: { default: deny, allow_from_profile: true }
commands:
  deny: [git-push, package-publish, docker-socket, privilege-escalation]
  approval_action: { prod-migration: db.migrate, prod-deploy: deploy.production }
limits: { wall_minutes: 60, output_mib: 50, processes: 256, memory_mib: 4096 }
```

`deny_write` 경로를 바꿔야 하는 작업은 R2로 시작하고 전용 프로파일을 쓴다.
경로는 `realpath`로 해석한 뒤 검사한다. 상징 링크와 `..` 시험을 포함한다.
명령 분류기는 셸 파서를 쓴다. 해석할 수 없는 구문은 허용하지 않고 구조화된 도구를 안내한다.

## 5. 승인 브로커

**흐름.** 에이전트는 실행을 요청하지 않고 제안을 만든다.

1. 에이전트가 `ax approval propose`로 작업 유형과 매개변수를 낸다.
2. 브로커가 스키마, 허용 목록, 위험도를 검사한다. 브로커가 산출물 해시와 커밋을 직접 계산한다.
3. 정규화한 JSON(RFC 8785)의 SHA-256을 `payload_hash`로 저장한다.
4. 메신저에는 승인 ID와 링크만 보낸다. 메신저 버튼은 승인 수단이 아니다.
5. 승인 페이지는 브로커가 만든 대상, 차이, 비용, 되돌리기 방법을 보여 준다. 에이전트 설명은 별도 칸에 일반 텍스트로 보인다.
6. 창업자가 패스키(WebAuthn)로 승인한다. 도전값은 `payload_hash`와 `nonce`의 해시다. 사용자 확인을 필수로 한다.
7. 실행기가 서명, 만료, 해시를 다시 검증한다. 공개 키는 실행기 소유 파일에서 읽는다. `state.db`의 키는 화면 표시용이다.
8. 실행기가 자기 소비 원장에 `nonce`를 고유 키로 먼저 확정한다. 중복이면 거부한다.
9. 실행 결과를 자기 원장에 쓴다. 코어는 이를 읽어 `approval`을 `consumed`로 맞춘다.

소비의 정본은 실행기 원장이다. 실행기는 `state.db`를 쓰지 않는다. `state.db`만 조작해서는 키를 추가하거나 승인을 다시 쓸 수 없다.

`consumed` 뒤 실행이 중단되면 `outcome`을 `unknown`으로 기록하고 자동 재시도하지 않는다. 대상 시스템의 멱등 키로 조회한 뒤 창업자가 결정한다.

| 작업 | 만료 | 추가 확인 |
|---|---|---|
| `merge.confirm` (R0·R1) | 24시간 | 헤드 SHA 일치, CI와 필요한 리뷰 통과 |
| `merge.r2` | 24시간 | 헤드 SHA 일치, CI 통과 |
| `deploy.production` | 2시간 | 되돌릴 이전 버전 |
| `db.migrate` | 1시간 | 백업 복원 시험, 스테이징 결과 |
| `message.send` | 4시간 | 수신자 수와 목록 해시, 본문 해시 |
| `ads.spend` | 1시간 | 금액 상한, 종료일 |
| `store.submit`, `marketplace.publish` | 24시간 | 산출물 해시 |
| `price.change` | 4시간 | 가격표 버전, 기존 고객 처리, 약관 일치 |
| `legal.publish` | 24시간 | 문서 해시, 전문가 확인 기록 |
| `brand.publish` | 24시간 | 브랜드 묶음 해시, 유사 이름 조사 |
| `trademark.file` | 24시간 | 전문가 확인, 비용 상한. 출원은 창업자가 직접 함 |
| `refund.issue` | 4시간 | 원결제, 금액, 중복 환불 없음 |
| `policy.change` | 24시간 | 로컬 승인 페이지 |

응답이 없으면 거부다. 작업은 자원을 놓고 `blocked`로 가고 `resume_state`는 `awaiting_approval`이다.
하루 승인 요청 상한은 10건이다. `merge.confirm`은 이 상한에 넣지 않는다. 마케팅 게시는 수신자와 내용이 고정된 묶음으로 승인할 수 있다. 넘으면 낮은 우선순위를 다음 날로 묶는다. 한 작업은 하루 2건까지 요청한다. 작업 하나가 창업자의 승인 몫을 소진하지 못하게 한다. 승인 피로도는 보안 위험이다.
R0와 R1 병합도 승인 페이지에서 패스키 한 번으로 확인한다. 페이지를 만들기 전에는 `ax-publish` 사용자의 터미널에서 SHA를 보고 확인한다([ADR-0011](adr/0011-founder-console.md)).
기기 분실 시 로컬 관리 명령으로 자격증명을 폐기한다. 대기와 승인 상태의 요청을 모두 `revoked`로 바꾼다.

웹 콘솔은 승인할 수 없다([15](15-founder-console.md) §7). 승인 페이지는 쿠키 세션을 쓰지 않고 건마다 패스키를 요구한다.
승인 페이지는 호스트 `localhost`에만 연다(창업자 확정, 2026-11-25). 샌드박스는 네트워크가 분리되어 접근하지 못한다. 원격 접속은 P2 뒤 사설 VPN으로만 연다. 그때 RP ID가 달라지므로 패스키를 다시 등록한다. 페이지와 실행기는 에이전트와 다른 OS 사용자로 실행한다.
같은 사용자로 실행하면 에이전트 탈출 시 DB를 바꿀 수 있다. 실행기는 DB의 상태가 아니라 서명을 최종 근거로 쓴다.

Hook과 승인 검증의 [참조 예제](evidence/reference/approval.mjs)를 44개 사례로 시험했다. 참조 예제는 제품 코드가 아니다.
도전값은 `SHA256("ax-approval-v1\0" || payload_hash || nonce)`이다. 매개변수의 수는 안전한 정수만 허용한다. 소수와 짝 없는 서로게이트는 거부한다.

## 6. 수용 기준

- P-01: Hook을 강제 종료, 지연, 잘못된 JSON으로 만들면 위험 도구가 실행되지 않는다.
- P-02: `bash -c`, `python -c`, base64, 별칭, 스크립트 파일로 우회해도 프로덕션 변경이 불가능하다.
- P-03: 승인 뒤 매개변수 1바이트를 바꾸면 실행기가 거부한다.
- P-04: 같은 승인을 100개 동시 요청으로 소비하면 1건만 성공한다.
- P-05: 만료, 폐기, 다른 작업의 승인이 거부된다.
- P-06: 상징 링크로 샌드박스 밖을 쓰거나 읽을 수 없다.
- P-07: DB의 `status`를 직접 바꿔도 유효한 서명이 없으면 실행되지 않는다.
- P-08: 저장소에 `disableAllHooks`를 넣어도 H-02가 동작한다.
- P-09: 세션 중 설정 파일을 바꿀 수 없고, 짝 없는 도구 호출이 있으면 세션이 2초 안에 끝난다.
