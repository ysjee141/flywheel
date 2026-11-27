# 로컬 검증 기록 (2026-11-24)

환경: WSL2 6.18, bubblewrap 0.11.1, Node 26.10.0(SQLite 3.53.4), sqlite3 CLI 3.50.6, git 2.53.0.
범위: 설계 예제의 확인이다. P0 전체 시험의 통과 증거가 아니다.

| 확인 | 결과 |
|---|---|
| DDL 적재 (Node, Python) | 성공 |
| DDL 적재 (sqlite3 CLI) | 실패. 이 CLI에는 FTS5가 없다. 운영 점검은 `ax db` 명령을 쓴다 |
| DDL 제약 | 거부 사례와 허용 사례가 기대와 일치 |
| VACUUM 뒤 FTS 조인 | 성공. 명시적 `rid` 사용 |
| JSON Schema 4종 | 유효·무효 예제 모두 기대와 일치(ajv 8) |
| bwrap `--clearenv` 단독 | **실패.** `/proc/1/environ`에서 호스트 환경 변수가 보였다 |
| `--as-pid-1` | 카나리 없음 |
| `env -i bwrap` | 카나리 없음 |
| 네트워크 | `Network is unreachable` |
| `/home`, `/mnt`, `/init`, `/run` | 없음 |
| WSL 실행 형식 | `MZ` 파일 실행 실패(rc 127). 실제 PE 파일은 미시험 |
| `MemoryMax=256M` | 초과 할당 프로세스 종료(rc 143) |
| `TasksMax=64` | fork가 61회에서 실패 |
| 호스트 `core.fsmonitor` | 설정된 명령이 **실행됨**. 끄면 실행되지 않음 |
| 샌드박스 → loopback → Unix 소켓 → 프록시 | 허용 도메인 200, 그 외 403 |
| tmpfs 20MiB 초과 쓰기 | `No space left on device` |
| Mermaid 4개 구문 | mermaid 11 `parse` 통과. 렌더링은 미시험 |

시험하지 않은 것: 모델 API 중계, 추상 소켓, 패스키, GitHub 규칙.

## 동시성 시험

`python3 evidence/check_concurrency.py` 결과다.

| 시험 | 결과 |
|---|---|
| 예산 예약 100건 동시, 상한 10건 | 10건 성공 |
| 임대 50건 동시 | 1건 성공, 만료 후 펜싱 증가 |
| 승인 소비 100건 동시 | 1건 성공 |
| 볼트 교체 중 강제 종료 100회 | 73회 커밋(재실행에서는 79회), 모두 복구, `integrity_check` 정상 |

프로세스 강제 종료 시험이다. 전원 차단은 시험하지 않았다. 종료 시점 분포는 무작위라 모든 단계를 빠짐없이 덮는다고 보장하지 않는다.
