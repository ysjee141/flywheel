# 05. 에이전트, Skill, MCP

**결론: 에이전트는 상주 프로세스가 아니라 역할 명세다. 작업이 있을 때 권한이 고정된 세션으로 실행한다.**

## 1. 역할 16종

초안 본문을 기준으로 한다(F-12). `P`는 활성화 시점이다. 1~3은 로드맵 단계, `S`는 서비스 시작 때, `A`·`C`·`D`는 해당 팩의 활성화 때다.
활성화 전에도 역할의 입출력 계약은 유지한다. 그래서 생애주기가 역할 추가로 바뀌지 않는다.

| ID | 역할 | P | 입력 → 출력 | 프로파일 | 금지 |
|---|---|---|---|---|---|
| A01 | PM | 1 | 아이디어 → `prd.md`, `task.yaml` | planning | 코드, 위험도 하향 |
| A02 | CS/VOC | 3 | 마스킹된 문의 → 답변 초안, 버그 | support | 발송, 환불 |
| A03 | 제품·시장 검증 | S | 질문 → 출처 있는 비교표 | planning | 무출처 수치 |
| A04 | 수익화 | 3 | 비용·가설 → 가격안, 손익표 | planning | 가격 적용 |
| A05 | 브랜딩·마케팅 | 2 | PRD → 브랜드 묶음, 문구 초안 | planning | 게시, 광고 |
| A06 | 데이터 | 3 | 집계 → 퍼널 분석 | analytics | 개인 단위 조회 |
| A07 | 법무 | 2 | 데이터 목록 → 초안, 쟁점 | planning | 적법 단정 |
| A08 | UI/UX | 2 | PRD → 토큰, 화면, 접근성 결과 | web-dev | 백엔드 |
| A09 | DBA | 2 | 모델 → ERD, 마이그레이션, RLS 시험 | db-dev | 프로덕션 접속 |
| A10 | 웹 FE/BE | 1 | 작업 → 패치, 시험 | web-dev | CI·정책 변경 |
| A11 | 모바일 | C | 작업 → 패치, 빌드 | mobile-dev | 스토어 제출 |
| A12 | 인프라·DevOps | 2 | 환경 명세 → IaC 계획 | infra-plan | apply |
| A13 | QA | 1 | 수용 기준 → 시험, 증거 | qa | 제품 코드 수정 |
| A14 | 서비스 보안 | 1 | 패치 → 리뷰 판정 | audit | 코드 수정 |
| A15 | 개인정보 | 2 | 데이터 흐름 → 점검표 | audit | 실데이터 조회 |
| A16 | AgentShield 감사 | 1 | 설정 → 리뷰 판정 | audit | 설정 수정 |

기업 기능 모듈 12개의 담당과 검토는 [14](14-business-modules.md) §3에 있다. 모듈을 늘려도 역할 수는 16이다.
Phase 1의 교차 리뷰는 별도 역할이 아니라 실행기의 리뷰 단계다.

## 2. 역할 명세 형식

```yaml
id: A10
version: 1
phase: 1
model_tier: standard
profile: web-dev
max_risk: R2
limits: { turns: 60, wall_minutes: 45 }  # API 모드에서만 budget_micro_usd 추가
inputs: [task, acceptance, repo_snapshot, memory_refs]
outputs: { patch: required, evidence: required, memory_proposals: optional }
tools: [read, search, edit, sandboxed_shell]
write_paths: ["apps/**", "packages/**", "tests/**"]
handoff: [A13, A14]
done_when:
  - 모든 수용 기준에 증거 참조가 있다
  - 작업 트리 해시와 시험 결과가 일치한다
escalate_when: [요구 충돌, 새 유료 의존성, 범위 밖 파일, 같은 실패 2회]
```

출력 공통 봉투는 `task_id`, `role_id`, `role_version`, `status`, `artifacts[]`, `evidence[]`, `open_questions[]`, `tainted`다. 코어는 `tainted`의 하향을 무시한다.

## 3. Skill 명세

| Skill | P | 위험 | 입력 | 완료 조건 |
|---|---|---|---|---|
| idea-to-prd | 1 | R0 | 아이디어, 고객 | 문제, 비범위, 수용 기준, 지표가 있음 |
| scaffold-service | 2 | R1 | 유형, 이름, 지역 | 새 clone에서 설치·시험·빌드 통과 |
| learn-and-evolve | 3 | R0 | 작업 증거 | 후보와 출처. 자동 활성화 없음 |
| memory-dreaming | 3 | R0 | 볼트 스냅샷 | 검증 보고서 |
| safe-db-migration | 2 | R2 | 스키마 차이 | 확장-이전-축소 계획, 복구 시험 |
| payment-webhook | A | R2 | 공급자, 상품 | 서명, 중복, 역순, 대사 시험 |
| pre-deploy-security | 1 | R1 | 커밋, 산출물 | SARIF와 판정 |
| store-release-prep | C | R2 | 빌드, 메타데이터 | 점검표. 제출은 R3 |
| launch-kit | S | R0 | PRD | 초안. 게시는 R3 |
| legal-doc-pack | S | R2 | 데이터 목록, 국가 | 초안 표시, 쟁점, 검토자 기록 |
| marketplace-packager | D | R2 | 패키지 | 서명, SBOM, 권한 목록 |
| brand-system | 2 | R1 | PRD, 회사 기준 | 브랜드 묶음, 유사 이름 조사, 리뷰 |
| obligation-check | 2 | R1 | 활동, 국가 | 의무, 기한, 근거, 전문가 질문 |
| pricing-model | 3 | R1 | 비용, 가설 | 세 시나리오와 출처. 적용은 R3 |
| month-close | 3 | R1 | 가져온 파일 | 대사, 차이, 원본 해시 |
| portfolio-review | 3 | R0 | 서비스 지표 | 선택지, 반대 근거, 다시 볼 날 |
| customer-validation | S | R1 | 질문, 동의 | 근거, 실험, 판정 조건 |

마지막 6종은 초안에 없던 추가분이다.

`SKILL.md`에는 발동 조건, 비발동 조건, 입력, 절차, 실패 처리, 산출물 검사를 둔다. 실행 파일은 매니페스트의 해시와 일치해야 한다.
DB 되돌리기 SQL은 삭제된 데이터를 살리지 못한다. 그래서 파괴 변경은 확장-이전-축소와 백업 복원으로 처리한다.

## 4. MCP 프로파일

| 프로파일 | 서버 | 쓰기 | 네트워크 |
|---|---|---|---|
| planning | 웹 검색, ax-memory | 제안만 | 검색 공급자 |
| web-dev | ax-memory, Playwright(로컬) | 작업별 clone | 패키지 레지스트리 |
| db-dev | 로컬 Postgres, ax-memory | 임시 DB | 없음 |
| qa | Playwright, ax-memory | 시험 파일 | localhost |
| mobile-dev | ax-memory, 빌드 도구 | 작업별 clone | 레지스트리 |
| infra-plan | IaC 검사 | 없음 | 공급자 읽기 전용 |
| audit | 스캐너, ax-memory | 없음 | 취약점 DB |
| analytics | 집계 뷰 | 없음 | 분석 API |
| company | 회사 기록 게이트웨이 | 초안만 | 없음 |
| support | 마스킹된 티켓 | 초안 | 티켓 API |

외부 API 자격증명이 필요한 MCP(검색, 분석, 티켓, 클라우드 읽기)는 호스트의 게이트웨이에서 실행한다. 샌드박스에는 작업별 소켓만 준다.
게이트웨이는 도구별 허용 매개변수와 응답 크기를 검사한다. 응답을 준 작업은 `tainted`가 된다.
초안의 `web-dev`에는 GitHub, Supabase, Vercel이 있다. 이 설계는 원격 쓰기를 코어와 실행기로 옮겨 제거했다.

상한은 서버 9개, 도구 80개, 도구 설명 12,000토큰이다. 하나라도 넘으면 세션을 시작하지 않는다. 토큰 값은 **제안**이다.
프로파일 적용 절차는 다음과 같다.

1. 코어가 프로파일과 서버 잠금 파일에서 작업별 `mcp.json`을 만든다.
2. 서버 패키지는 버전과 무결성 값으로 고정한다.
3. 시작 뒤 실제 `tools/list`를 잠금 파일과 비교한다. 이름, 설명, 스키마가 다르면 중단한다. 설명 변경도 인젝션 경로다.
4. 세션 중 프로파일을 바꾸지 않는다. 바꾸려면 체크포인트 뒤 새 세션을 연다.
