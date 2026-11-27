# 검증 재실행

`docs/`에서 실행한다.

| 검사 | 명령 | 필요 도구 |
|---|---|---|
| 문서 링크·ID·문장 길이 | `python3 -I evidence/lint_docs.py` | Python |
| SQLite 계약 | `node evidence/check_ddl.mjs schemas/memory.sql` | Node |
| 동시성·강제 종료 | `python3 -I evidence/check_concurrency.py` | Python |
| Hook·승인 참조 예제 | `node evidence/check_reference.mjs` | Node |
| Type A | `sh evidence/check_type_a.sh` | Docker, `postgres:17-alpine` |
| JSON Schema | ajv 8을 설치한 폴더에서 `check_schemas.cjs <schemas 경로>` | ajv |
| 서비스 계약 | ajv 8을 설치한 폴더에서 `check_services.cjs <schemas 경로>` | ajv |
| 기업 기능 모듈·회사 기록 | `python3 -I evidence/check_business.py` | Python |
| Mermaid | mermaid 11과 jsdom을 설치한 폴더에서 `check_mermaid.mjs <docs 경로>` | npm |
| Hook 실측 HC-16~18 | 빈 폴더에서 `check_hooks_hc16_18.sh` | Claude Code. 사용량 발생 |

`REJ`는 기대한 거부다. `FAIL`과 `MISMATCH`가 실패다. HC-01~15, 19, 20은 재실행 스크립트로 정리하지 않았다.
