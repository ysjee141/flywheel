# 11. Phase 1 구현 명세

**결론: 22개 PR로 나눈다. 08은 무인 실행 때로 미뤘다. 각 PR은 혼자 병합할 수 있고, 시험 이름이 수용 기준을 가리킨다.**

## 1. 소켓과 인증

| 소켓 | 사용자 | 샌드박스 마운트 | 인증 |
|---|---|---|---|
| `control.sock` | 창업자 CLI, 웹 콘솔 프로세스 | 아니오 | `SO_PEERCRED`의 UID와 파일 권한 0600 |
| `agent.sock` | Hook, 메모리 MCP | 예, 작업별 별도 파일 | 작업별 소켓 + 작업 토큰 |
| `proxy.sock` | 모델·레지스트리 통신 | 예, 작업별 별도 파일 | 작업별 소켓 + 도메인 목록 |

Node 표준 API는 `SO_PEERCRED`를 주지 않는다. 그래서 P1은 0700 디렉터리와 0600 파일 권한을 쓴다. 네이티브 확장은 선택이다.
작업 토큰은 256비트 난수다. DB에는 해시만 둔다. 작업 종료 때 폐기한다. 토큰은 에이전트가 읽을 수 있으므로 그 작업의 권한만 가진다.
Hook도 샌드박스 안에서 실행된다. 그래서 같은 토큰을 가진 에이전트가 Hook 이벤트를 위조할 수 있다. Hook 이벤트는 우발적 실패 탐지용이며 증거로 쓰지 않는다.

메시지는 길이 앞붙임(4바이트, 최대 1MiB) JSON이다.

| 메서드 | 입력 | 오류 |
|---|---|---|
| `hook.event` | event, tool_use_id, decision, rule | `AX-E-AUTH` |
| `memory.search` | query, limit ≤ 10 | `AX-E-INPUT` |
| `memory.propose` | title, kind, body, refs | `AX-E-POLICY`, `AX-E-CONFLICT` |
| `checkpoint.put` | done, remaining, failed_attempts | `AX-E-INPUT` |
| `artifact.put` | kind, size ≤ 50MiB, sha256, 출력 폴더의 상대 경로 | `AX-E-POLICY` |
| `approval.propose` | action, target, params | `AX-E-POLICY` |

아티팩트 본문은 소켓으로 보내지 않는다. 코어가 세션 종료 뒤 출력 폴더에서 일반 파일만 `O_NOFOLLOW`로 읽고 해시를 다시 계산한다.
`hook.event`는 초당 200회, 나머지는 메서드당 초당 10회, 작업당 제안 20건으로 제한한다. Hook 제한에 걸리면 도구가 거부되어 안전하게 실패한다. `agent.sock`에는 승인 결정, 상태 전이, 위험도 변경 메서드가 없다.

`agent.sock`의 응답도 비신뢰 세션으로 들어간다. 오류 메시지에 다른 작업, 경로, 정책 원문을 넣지 않는다.
연결은 작업당 8개, 유휴 30초로 제한한다. 초과 연결은 새것을 거부한다.

## 2. 패키지 의존

```text
cli -> core -> {policy, memory, db}
core -> adapters -> sandbox
executor -> approval-verify        (core에 의존하지 않음)
hook-entry -> policy               (단일 파일로 묶음)
```

순환 의존은 CI에서 거부한다. `executor`는 DB를 쓰지 않고 서명된 요청만 검증한다.

## 3. 핵심 인터페이스

```ts
type Result<T> = {ok: true; value: T} | {ok: false; code: string; retryable: boolean; message: string};

interface TaskStore {
  get(id: string): Task | undefined;
  transition(a: {id: string; from: State; to: State; version: number; key: string; payload: unknown; outbox?: OutboxItem[]}): Result<Task>;
}
interface Sandbox {
  run(s: {argv: string[]; clone: string; memoryMax: number; tasksMax: number; wallMs: number;
          sockets: {agent: string; proxy?: string}; settingsJson: string}): Promise<RunHandle>;
}
interface Policy { decide(i: {tool: string; input: unknown; cwd: string; tainted: boolean}): {allow: boolean; rule: string; reason: string}; }
interface ApprovalVerifier { verify(payload: Uint8Array, assertion: Assertion, now: number): Result<{approvalId: string}>; }
```

같은 멱등 키와 같은 내용의 `transition`은 처음 결과를 돌려준다. 같은 키와 다른 내용은 `AX-E-CONFLICT`다.

## 4. PR 순서

| PR | 내용 | 선행 | 핵심 시험 | 시간 |
|---|---|---|---|---:|
| 01 | workspace, 린트, 타입, CI | - | 새 clone 빌드 | 4 |
| 02 | 스키마 생성 타입, ajv 검사 | 01 | 예제 8개 | 2 |
| 03 | DB 이행, 단일 쓰기 잠금 | 02 | 중복 실행 거부 | 4 |
| 04 | 상태 전이, 이벤트 사슬 | 03 | O-01, O-02, O-07, NFR-02 | 6 |
| 05 | outbox, 시작 복구 | 04 | O-03, NFR-03 | 4 |
| 06 | 임대, 예산 | 04 | O-04, O-05, NFR-06 | 5 |
| 07 | bwrap, cgroup 실행기 | 01 | 검증용 격리(SB-01~10), V-01~04 | 8 |
| 09 | Claude 어댑터 | 07 | 가짜 CLI 이벤트 12종 | 6 |
| 10 | 정책 엔진 | 02 | P-02, P-06 | 5 |
| 11 | Hook 진입점, 생존 대조 | 09, 10 | P-01, P-08, P-09, NFR-04 | 5 |
| 12 | 메모리 저장·검색 | 03 | M-01~03, M-06, S-02, NFR-05 | 6 |
| 13 | 인계, MCP | 12 | M-07 | 4 |
| 14 | 패치 수입, 깨끗한 검증 | 07 | S-05, S-08 | 7 |
| 15 | Codex 리뷰어, 판정 집계 | 09, 14 | S-07, O-06, V-05 | 6 |
| 16 | 승인 검증기, 페이지 | 03 | AP-01~06, AP-09, AP-10 | 10 |
| 17 | 실행기, 소비 기록 | 16 | AP-07, AP-08, P-03~05, P-07 | 6 |
| 18 | 백업·복원, `ax freeze` | 05, 12, 17 | 빈 환경 복원, 멈춤 중 실행·소비·outbox 0건 | 5 |
| 20 | 병합 게이트, 원장, 감사 | 15, 17, 18 | GH-02, GH-03, GH-06, GH-07 | 6 |
| 21 | 표준 이벤트, 비밀 가림, SSE | 09 | C-01, C-04 | 6 |
| 22 | 콘솔 인증, 작업·결과 화면 | 17, 21 | C-02, C-03, C-05, C-07, C-11 | 8 |
| 23 | 시작·중지, 승인 연결 | 20, 22 | C-05, C-06 | 4 |
| 19 | 역할 5종, 전체 관통 | 05~18, 20~23 | P1 게이트, S-01, NFR-07 | 8 |
| 합계 | | | | 125 |

**미룸(무인 실행):** PR 08 모델 중계기와 패키지 GET 캐시, 8시간. 시험은 S-04, S-06, SB-11, SB-12다.
감독 모드에서는 의존성 설치를 창업자가 승인하고 샌드박스 밖의 별도 단계에서 설치 스크립트 없이 실행한다.

## 5. 패치 수입

1. 샌드박스 프로세스 그룹이 모두 끝났는지 확인한다.
2. 샌드박스 clone에서 호스트 `git`을 실행하지 않는다. 로컬 시험에서 `core.fsmonitor`가 호스트 명령을 실행했다.
3. 네트워크 없는 두 번째 샌드박스에서 패치를 만든다.
4. 크기 10MiB, 파일 500개를 넘으면 거부한다. 상징 링크, 서브모듈, 실행 비트 변경, `.gitattributes` 변경은 R2로 올린다.
5. 깨끗한 Worktree에서 `git -c core.hooksPath=/dev/null -c core.fsmonitor=false apply --index`로 적용한다. 대상 저장소 설정도 제어 평면이 만든 것만 쓴다.
6. 의존성은 잠금 파일로, 설치 스크립트 없이 받는다. 시험은 세 번째 샌드박스에서 한다.
7. 트리 해시, 명령, 종료 코드, 로그 해시를 증거로 저장한다.

## 6. 시험 예

```text
Given  작업 t1이 reviewing이고 head=A의 판정 2건이 pass
When   기준 브랜치가 바뀌어 head=B가 됨
Then   판정은 무효이고 t1은 verifying부터 다시 진행
       merging 요청은 AX-E-STALE-BASE
```

```text
Given  승인 a가 approved, payload_hash=H
When   실행기가 max_spend만 다른 요청을 받음
Then   거부하고 소비 기록을 쓰지 않으며 경보를 낸다
```

## 7. 완료 정의

- 새 사용자 계정에서 설치 안내만으로 실행된다.
- 모든 오류에 `AX-E-*` 코드와 다음 행동이 있다.
- 시험 이름에 수용 기준 ID가 있고 CI가 누락 ID를 보고한다.
- 로그와 DB에 합성 비밀이 없다.
