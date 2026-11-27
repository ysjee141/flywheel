# Flywheel 상세 설계

Flywheel은 1인 창업자를 위한 AX Orchestration Platform이다. 문서의 "AX"와 명령어 `ax`는 Flywheel을 가리킨다.

**결론: AX는 앞으로 만들 Type A~D 서비스를 체계적이고 안정적으로, AI Native 방식으로 계속 개발하고 운영하기 위한 플랫폼이다. 이 문서 묶음은 [초안](../draft.md)을 구현 가능한 계약으로 바꾼 설계다. 설계 v1은 2026-11-25에 확정됐다. 제품 구현 코드는 아직 없다. 계약과 참조 예제만 [검증](evidence/README.md)했다. 첫 작업은 [W0-1](09-roadmap.md)의 남은 시험이다.**

## 읽는 순서

| 문서 | 답하는 질문 |
|---|---|
| [설계 v1 설명서](DESIGN-V1-GUIDE.md) | 확정 전에 무엇을 어떤 순서로 볼까 |
| [00 리뷰](00-review.md) | 초안의 무엇을 왜 바꿨나 |
| [01 아키텍처](01-architecture.md) | 구성 요소와 신뢰 경계는 무엇인가 |
| [02 오케스트레이션](02-orchestration.md) | 작업은 어떻게 실행되고 복구되나 |
| [03 메모리](03-memory-learning.md) | 무엇을 기억하고 어떻게 승격하나 |
| [04 Hook·승인](04-hooks-policy-hitl.md) | 무엇을 어디서 막나 |
| [05 역할](05-agents-skills-mcp.md) | 누가 무엇을 할 수 있나 |
| [06 품질·보안](06-quality-security.md) | 무엇을 통과해야 하나 |
| [13 서비스 생애주기](13-service-lifecycle.md) | 여러 서비스를 어떻게 같은 방식으로 만들고 운영하나 |
| [07 유형별 요구](07-service-blueprints.md) | Type A~D 팩은 무엇을 갖춰야 하나 |
| [14 기업 기능 모듈](14-business-modules.md) | 브랜드, 돈, 법무 같은 회사 기능을 어떻게 함께 쓰나 |
| [15 콘솔·대시보드](15-founder-console.md) | 창업자는 어디서 보고 판단하나 |
| [16 구축 하네스](16-build-harness.md) | AX를 어떤 절차로 만드나 |
| [17 피드백 루프](17-feedback-loop.md) | 배운 것과 지적을 어떻게 모으고 닫나 |
| [08 운영](08-operations.md) | 어떻게 운영하고 복구하나 |
| [09 로드맵](09-roadmap.md) | 무엇부터 만드나 |
| [10 P0 시험 명세](10-p0-test-spec.md) | 첫 주에 무엇을 어떻게 시험하나 |
| [11 Phase 1 구현](11-phase1-implementation.md) | P1을 어떤 PR로 만드나 |
| [실측: Hook](evidence/hooks-2.1.331.md), [실측: 로컬](evidence/2026-11-24-local-checks.md) | 무엇을 실제로 확인했나 |
| [12 감독 모드](12-supervised-mode.md) | 지금 구독 에이전트를 어떻게 실행하나 |
| [리뷰 기록](REVIEW-LOG.md) | 어떤 결함을 고쳤나 |

결정: [0001](adr/0001-local-control-plane.md), [0002](adr/0002-hooks-not-boundary.md), [0003](adr/0003-human-promoted-learning.md), [0004](adr/0004-selective-ecc.md), [0005](adr/0005-type-b-first.md), [0006](adr/0006-webauthn-approval.md), [0007](adr/0007-subscription-agents.md), [0008](adr/0008-platform-first.md), [0009](adr/0009-private-free-merge-gate.md), [0010](adr/0010-business-modules.md), [0011](adr/0011-founder-console.md), [0012](adr/0012-build-harness.md), [0013](adr/0013-feedback-loop.md)

계약: [DB](schemas/memory.sql), [작업](schemas/task.schema.json), [메모리](schemas/memory-record.schema.json), [승인](schemas/approval.schema.json), [서비스](schemas/service.schema.json), [리뷰](schemas/review.schema.json), [Type A](schemas/type-a.sql), [기업 기능 모듈](schemas/business-module.schema.json), [회사 기록](schemas/company.sql)

## 용어

| 용어 | 뜻 |
|---|---|
| 제어 평면 | 상태, 권한, 승인을 결정하는 코드 |
| 하네스 | Claude Code, Codex 같은 에이전트 실행 도구 |
| 능력 모듈 | 서비스 안에서 실행되는 공통 코드 |
| 기업 기능 모듈 | AX 안에서 회사와 서비스의 업무를 돕는 역할, 절차, 기록 |
| 볼트 | 메모리의 Markdown 파생본 |
| Instinct | 조건과 행동을 가진 원자적 학습 후보 |
| 펜싱 토큰 | 오래된 작업의 쓰기를 거부하는 증가 번호 |
| outbox | DB 변경과 함께 기록한 외부 작업 목록 |
| tainted | 비신뢰 입력을 읽었다는 표시 |

## 요구사항 추적

| 초안 | 반영 | 상태 |
|---|---|---|
| 1-1 보일러플레이트 | 07 §1 | 유지, 추출 시점 변경 |
| 1-2 Hook 강제 | 04 §1~3 | 변경 |
| 1-3 컨텍스트·MCP | 05 §4 | 유지, 토큰 상한 추가 |
| 1-4 Instinct·Dreaming | 03 §4~6 | 변경, Dreaming 연기 |
| 1-5 루프·교차 검증 | 02 §1, 06 §3 | 변경(검증을 리뷰 앞에) |
| 2 아키텍처 | 01 | 유지, 경계 추가 |
| 3 Type A~D | 13, 07 | 변경(현재 개발 대상이 아닌 팩 요구) |
| 4.1 메모리 4계층 | 03 §1~6 | 변경 |
| 4.3 `ax memory` | 03 §8 | 변경, prune 분리 |
| 5.1 Hook 표 | 04 §3 | 변경 |
| 5.2 프로파일 | 05 §4 | 변경 |
| 5.3 Santa Loop | 06 §3 | 변경 |
| 6 Agent 16종 | 05 §1, 14 §3 | 유지, 기업 기능 연결 |
| 7 Skill 11종 | 05 §3 | 유지, 6종 추가 |
| 8 로드맵 | 09 | 변경(플랫폼 능력 단계) |
| 9 HITL·오염·STE-KO·KPI | 04 §5, 03 §6, README, 08 §3 | 변경 |

## 문서 규칙

한 문장에 하나의 뜻을 담는다. 25어절을 넘기지 않는다. 결론과 행위자를 먼저 쓴다.

## 창업자 결정 필요

| ID | 질문 | 기본값 | 시한 |
|---|---|---|---|
| Q-01 | 주당 가용 시간 | **확정:** 20시간 (2026-11-25) | 완료 |
| Q-02 | 월 LLM 비용 | **확정:** Claude Code 구독 20달러, API 0 | 완료 |
| Q-03 | 리뷰 도구 | **확정:** R1은 Claude 새 세션, R2는 여기에 무료 Codex 추가 | 완료 |
| Q-04 | 기준 서비스 2개로 플랫폼을 검증하는 방식 | **확정:** 채택 (2026-11-25) | 완료 |
| Q-05 | 결제 공급자 | 사업자 소재지와 첫 판매 국가는 한국(**확정**). 공급자는 미정 | 결제가 있는 서비스의 `define` |
| Q-06 | GitHub 요금제와 저장소 공개 여부 | **확정:** 비공개 + Free (2026-11-25), [ADR-0009](adr/0009-private-free-merge-gate.md) | 완료 |
| Q-07 | 승인 페이지 위치 | **확정:** 내 PC의 `localhost` (2026-11-25). 휴대폰은 P2 뒤 선택 | 완료 |
| Q-08 | OpenAI로 비공개 코드 전송 허용 | 데이터 설정 완료(창업자 진술, 2026-11-25). V-05 통과 뒤 허용 | 첫 R2 전 |
| Q-09 | 기업 기능 모듈 12개와 시간 상한 | **확정:** 출시 전 주 1시간, 출시 후 주 3시간, 임시값 (2026-11-25) | 완료 |
| Q-10 | 웹 콘솔, 실시간 진행, 요약, 대시보드 | **확정:** 포함 (2026-11-25), [ADR-0011](adr/0011-founder-console.md) | 완료 |
| Q-11 | 설계 v1 확정 | **확정:** 확인표 1~14번 동의 (2026-11-25) | 완료 |
| Q-12 | AX를 만드는 하네스 | **확정:** 얇은 하네스, 최소판부터 (2026-11-25), [ADR-0012](adr/0012-build-harness.md) | 완료 |
| Q-13 | 플랫폼과 회사 이름 | **확정:** 플랫폼 Flywheel, 회사 happlanet (2026-11-26). 명령어는 `ax`. 상표와 중복은 미확인 | 완료. 외부 공개 전 재확인 |
| Q-14 | 피드백 루프 | **확정:** 하나의 대장과 효과 확인 (2026-11-26), [ADR-0013](adr/0013-feedback-loop.md). +8시간, +1주 | 완료. 공식은 4주 뒤 재조정 |
