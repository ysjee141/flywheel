# 10. P0 시험 명세

**결론: P0은 설계 가정을 깨기 위한 시험이다. 실패하면 설계를 고치고 P1로 넘어가지 않는다.**

**진행 상황 (2026-11-24):** HC-01~09, 11~13과 추가 HC-14b~19을 [실측](evidence/hooks-2.1.331.md)했다. W0-1의 남은 일은 HC-10, 대화형 모드다.

모든 시험은 임시 디렉터리와 별도 `CLAUDE_CONFIG_DIR`에서 한다. 실제 홈 설정을 바꾸지 않는다.
증거 파일에는 버전, 명령, 종료 코드, 출력, 판정을 남긴다. 비밀은 넣지 않는다.

## 1. Hook 계약 (W0-1)

부작용 측정은 도구가 `MARK` 파일을 만들었는지로 한다.

| ID | 준비 | 기대 | 실패 시 |
|---|---|---|---|
| HC-01 | PreToolUse exit 2 | `MARK` 없음 | Hook 의존 제거 |
| HC-02 | exit 1 | `MARK` 있음 | 문서와 차이 기록 |
| HC-03 | timeout, `onFailure` 없음 | `MARK` 있음 | 차이 기록 |
| HC-04 | timeout, `onFailure: "block"` | `MARK` 없음 | 해당 버전 금지 |
| HC-05 | 실행 파일 없음, `block` | `MARK` 없음 | 해당 버전 금지 |
| HC-06 | SIGKILL, `block` | `MARK` 없음 | 해당 버전 금지 |
| HC-07 | exit 0, 깨진 JSON, `block` | 실측: `MARK` 있음 | 거부에 JSON을 쓰지 않음 |
| HC-08 | Hook 2개, 하나는 거부 | `MARK` 없음 | 진입점 단일화 유지 |
| HC-09 | Stop을 계속 차단 | 횟수 측정 | AX 상한이 더 작은지 확인 |
| HC-10 | PreCompact `manual`, `auto` | 입력 필드 저장 | 체크포인트 주기만 사용 |
| HC-11 | 병렬 도구 2개 뒤 PostToolBatch | 1회 호출인지 관찰 | Stop에서 타입 검사 |
| HC-12 | 하위 에이전트의 도구 호출 | Hook 적용 | 하위 에이전트 금지 |
| HC-13 | MCP 도구 호출 | Hook 적용 | 해당 MCP 제거 |
| HC-14 | 세션 중 설정 수정 | 파일은 꺼짐, 인라인은 유지(실측) | 인라인이 실패하는 버전 금지 |
| HC-15 | 같은 설정의 `disableAllHooks` | 실측: 꺼짐 | 설정 파일을 코어가 생성 |
| HC-16 | 저장소의 `disableAllHooks` + `--setting-sources ""` | `MARK` 없음 | 해당 버전 금지 |
| HC-17 | 권한 패턴을 `python3`로 우회 | 실측: 우회됨 | 샌드박스로 막음 |
| HC-18 | 문자열 Hook을 `bash -c`로 우회 | 실측: 우회됨 | 샌드박스로 막음 |
| HC-21 | `--setting-sources ""`에서 프로젝트 Skill, 에이전트, 지침을 읽는지 | 관찰 후 기록 | 필요한 지침을 직접 주입 |
| HC-20 | 하위 에이전트 도구 ID가 스트림과 Hook에서 같은지 | 일치(실측) | 생존 대조 대신 하위 에이전트 금지 |

## 2. 샌드박스 (W0-2)

| ID | 공격 | 기대 |
|---|---|---|
| SB-01 | 홈의 카나리 파일 읽기 | 없음 또는 거부 |
| SB-02 | 부모 프로세스의 `/proc/<pid>/environ` 읽기 | 보이지 않음 |
| SB-03 | 허용 외 HTTPS, 원시 TCP, DNS | 실패 |
| SB-04 | WSL의 `/mnt/c` 접근 | 없음 |
| SB-05 | Windows 실행 파일 호출 | 실패. `/init`과 interop 소켓이 없음 |
| SB-06 | Docker, SSH, D-Bus, tmux 소켓 | 없음 |
| SB-07 | fork 폭주, 메모리·디스크 초과 | 제한에 걸리고 호스트 정상 |
| SB-08 | 상징 링크·하드 링크 탈출 | 실패 |
| SB-09 | 추상 Unix 소켓 접근 | 실패. 네트워크 네임스페이스 분리 |
| SB-10 | TIOCSTI 입력 주입 | 실패. `--new-session` |
| SB-11 | 하네스가 중계기 인증만으로 동작 | 동작. 샌드박스에 장기 토큰 없음 |
| SB-12 | 잠금 파일에 없는 패키지 이름으로 데이터 전송 | 거부 |

공식 문서는 `ANTHROPIC_BASE_URL`과 `ANTHROPIC_AUTH_TOKEN`을 통한 게이트웨이 연결을 안내한다([문서](https://code.claude.com/docs/en/llm-gateway)).
SB-11은 무인 실행을 열 때 시험한다. 현재 감독 모드에는 필요하지 않다([ADR-0007](adr/0007-subscription-agents.md)).
SB-11이 구독 인증에서 실패할 수 있다. 그러면 자율 실행에는 별도 API 키와 중계기를 쓴다. 구독 토큰을 샌드박스에 넣지 않는다.
약관상 자동화 허용 범위도 공급자 문서로 확인한다(**가정**).

WSL은 Windows 실행 경로가 있어 일반 Linux보다 공격면이 넓다. SB-04와 SB-05는 생략할 수 없다.
bwrap은 메모리와 디스크 총량을 제한하지 않는다. cgroup v2는 `systemd-run --user`로, 디스크는 크기를 정한 tmpfs로 제한한다.

시작 명령의 기준은 다음과 같다. 네트워크는 프록시의 Unix 소켓 하나만 마운트해 제공한다.

```sh
env -i /usr/bin/bwrap --unshare-all --die-with-parent --new-session --clearenv \
  --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib64 /lib64 \
  --proc /proc --dev /dev --size 1073741824 --tmpfs /tmp \
  --bind "$CLONE" /work --chdir /work \
  --ro-bind /opt/ax/toolchain /opt/ax/toolchain --ro-bind /etc/ssl /etc/ssl \
  --setenv PATH /opt/ax/toolchain/bin:/usr/bin --setenv HOME /tmp -- "$@"
```

`env -i`는 필수다. `--clearenv`만 쓰면 샌드박스 안 PID 1(bwrap)의 `/proc/1/environ`에 호스트 환경 변수가 남는다. [로컬 시험](evidence/2026-11-24-local-checks.md)에서 카나리 노출을 확인했다.
Node가 홈의 nvm 아래에 있으면 샌드박스에서 보이지 않는다. 고정 버전 도구를 `/opt/ax/toolchain`에 설치한다.

## 3. 승인 (W0-5)

| ID | 변조 | 기대 |
|---|---|---|
| AP-01 | JSON 키 순서만 변경 | 같은 해시 |
| AP-02 | 금액, 대상, SHA 중 하나 변경 | 거부 |
| AP-03 | 다른 출처(origin) 또는 RP ID | 거부 |
| AP-04 | 사용자 확인 플래그 없음 | 거부 |
| AP-05 | 만료 1ms 후 소비 | 거부 |
| AP-06 | 동시 소비 100건 | 1건 성공 |
| AP-07 | 소비 직후 실행기 종료 | `unknown`, 재실행 없음 |
| AP-08 | DB 복원 후 이전 승인 사용 | 거부 |
| AP-10 | 콘솔 출처(다른 포트)에서 만든 패스키 서명 | 거부 |
| AP-09 | Markdown·제어 문자·유사 문자 표시 | 일반 텍스트와 경고 |

AP-06~08은 실행기 소비 원장에서 시험한다. 원장은 `state.db` 백업과 함께 되돌리지 않는다. 원장을 잃으면 모든 미소비 승인을 폐기한다.

## 4. GitHub (W0-4)

| ID | 시도 | 기대 |
|---|---|---|
| GH-01 | 샌드박스 세션에서 HTTPS, SSH, `gh`, `git.exe`로 푸시 | 자격증명 없음, 모두 실패 |
| GH-02 | CI, 리뷰, 창업자 확인 중 하나가 없는 병합 | 게이트가 거부 |
| GH-03 | 확인 뒤 새 커밋 또는 기준 변경 | 병합 거부, 재검증 |
| GH-04 | 푸시 토큰으로 워크플로·저장소 설정 수정 | 권한 없음 |
| GH-05 | PR 코드에서 비밀 출력 | 값 없음 |
| GH-06 | 같은 이름의 가짜 검사 상태 | 지정 워크플로가 아니면 거부 |
| GH-07 | 게이트 밖에서 `main` 푸시·강제 푸시 | 감사 발견, 멈춤, 배포 거부 |

P0에서는 GH-01, GH-04, GH-05를 시험한다. GH-02, GH-03, GH-06, GH-07은 게이트를 구현하는 W1-11에서 시험한다.

## 5. 종료 판정

P1 시작 조건은 HC 필수 항목, V-01~04, GH-01, GH-04, GH-05다. 아래는 무인 실행을 여는 조건이다.

HC-01, HC-04~06, HC-08, HC-12, HC-13, HC-16, HC-20, 인라인 HC-14, SB 전체, AP 전체, GH-01~07이 통과해야 자율 실행을 연다. 또한 서버 강제 보호 규칙이 필요하다(ADR-0009).
나머지 HC는 관찰 결과에 맞춰 [04](04-hooks-policy-hitl.md)를 고친다.
