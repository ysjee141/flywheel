-- AX 제어 평면 DDL. SQLite 3.45+. 모든 시각은 epoch 밀리초(UTC).
PRAGMA foreign_keys = ON;
CREATE TABLE schema_version (version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL);
INSERT INTO schema_version VALUES (1, unixepoch()*1000);

CREATE TABLE project (
  id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, repo_url TEXT NOT NULL,
  created_at INTEGER NOT NULL
) STRICT;

CREATE TABLE task (
  id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES project(id),
  parent_id TEXT REFERENCES task(id),
  state TEXT NOT NULL CHECK (state IN ('draft','ready','running','verifying','reviewing',
    'awaiting_approval','merging','done','blocked','failed','cancelled')),
  resume_state TEXT CHECK (resume_state IN ('ready','verifying','reviewing','awaiting_approval')),
  risk TEXT NOT NULL CHECK (risk IN ('R0','R1','R2','R3')),
  tainted INTEGER NOT NULL DEFAULT 0 CHECK (tainted IN (0,1)),
  goal TEXT NOT NULL, acceptance_json TEXT NOT NULL CHECK (json_valid(acceptance_json)),
  base_sha TEXT, head_sha TEXT, vault_version TEXT,
  attempt INTEGER NOT NULL DEFAULT 0, review_round INTEGER NOT NULL DEFAULT 0 CHECK (review_round <= 3),
  budget_micro_usd INTEGER NOT NULL DEFAULT 0 CHECK (budget_micro_usd >= 0), -- 0: 구독 모드, API 예약 불가
  version INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  CHECK ((state='blocked') = (resume_state IS NOT NULL))
) STRICT;
CREATE INDEX task_by_state ON task(state, updated_at);

CREATE TRIGGER task_taint_sticky BEFORE UPDATE OF tainted ON task
  WHEN OLD.tainted=1 AND NEW.tainted=0
  BEGIN SELECT RAISE(ABORT,'taint is sticky; create a sanitized task'); END;

CREATE TABLE event (
  seq INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT REFERENCES task(id),
  type TEXT NOT NULL, actor TEXT NOT NULL, idempotency_key TEXT NOT NULL UNIQUE,
  payload_json TEXT NOT NULL CHECK (json_valid(payload_json)),
  prev_hash TEXT NOT NULL, hash TEXT NOT NULL UNIQUE, at INTEGER NOT NULL
) STRICT;
CREATE TRIGGER event_no_update BEFORE UPDATE ON event BEGIN SELECT RAISE(ABORT,'event is append-only'); END;
CREATE TRIGGER event_no_delete BEFORE DELETE ON event BEGIN SELECT RAISE(ABORT,'event is append-only'); END;

CREATE TABLE lease (
  resource TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES task(id),
  fence INTEGER NOT NULL, expires_at INTEGER NOT NULL
) STRICT;
CREATE TABLE fence_counter (resource TEXT PRIMARY KEY, value INTEGER NOT NULL) STRICT;

CREATE TABLE budget_entry (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES task(id), call_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('reserve','settle','release')),
  amount_micro_usd INTEGER NOT NULL CHECK (amount_micro_usd >= 0),
  model TEXT, at INTEGER NOT NULL, UNIQUE (call_id, kind)
) STRICT;

CREATE TABLE approval (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES task(id),
  action TEXT NOT NULL, payload_hash TEXT NOT NULL CHECK (length(payload_hash)=64),
  nonce TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK (status IN ('pending','approved','denied','expired','consumed','revoked')),
  requested_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
  decided_at INTEGER, decided_by TEXT, credential_id TEXT, signature BLOB, consumed_at INTEGER,
  outcome TEXT CHECK (outcome IN ('succeeded','failed','unknown')),
  CHECK (expires_at > requested_at),
  CHECK (status NOT IN ('approved','consumed') OR (decided_at IS NOT NULL AND signature IS NOT NULL)),
  CHECK ((status='consumed') = (consumed_at IS NOT NULL)),
  CHECK (outcome IS NULL OR status='consumed')
) STRICT;
CREATE TRIGGER approval_immutable BEFORE UPDATE OF task_id, action, payload_hash, nonce, expires_at ON approval
  BEGIN SELECT RAISE(ABORT,'approval binding is immutable'); END;
CREATE TRIGGER approval_transition BEFORE UPDATE OF status ON approval
  WHEN NOT ((OLD.status='pending' AND NEW.status IN ('approved','denied','expired','revoked'))
         OR (OLD.status='approved' AND NEW.status IN ('consumed','expired','revoked')))
  BEGIN SELECT RAISE(ABORT,'invalid approval transition'); END;

CREATE TABLE memory (
  -- FTS 외부 콘텐츠의 키. VACUUM에도 바뀌지 않도록 명시한다.
  rid INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE, project_id TEXT REFERENCES project(id),
  scope TEXT NOT NULL CHECK (scope IN ('project','global')),
  kind TEXT NOT NULL CHECK (kind IN ('decision','lesson','runbook','instinct','checkpoint')),
  status TEXT NOT NULL CHECK (status IN ('quarantined','candidate','active','superseded','retired')),
  trust TEXT NOT NULL CHECK (trust IN ('founder','verified','agent','external')),
  sensitivity TEXT NOT NULL CHECK (sensitivity IN ('public','internal','confidential')),
  title TEXT NOT NULL, body TEXT NOT NULL CHECK (length(body) <= 8000),
  content_hash TEXT NOT NULL, supersedes TEXT REFERENCES memory(id),
  source_task TEXT REFERENCES task(id), source_json TEXT NOT NULL CHECK (json_valid(source_json)),
  valid_until INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  CHECK ((scope='project') = (project_id IS NOT NULL)),
  CHECK (NOT (trust='external' AND status IN ('candidate','active'))),
  CHECK (NOT (scope='global' AND trust NOT IN ('founder','verified') AND status='active'))
) STRICT;
CREATE UNIQUE INDEX memory_dedupe ON memory(ifnull(project_id,''), kind, content_hash) WHERE status IN ('candidate','active');

CREATE TABLE memory_evidence (
  id TEXT PRIMARY KEY, memory_id TEXT NOT NULL REFERENCES memory(id),
  task_id TEXT NOT NULL REFERENCES task(id), project_id TEXT NOT NULL REFERENCES project(id),
  commit_sha TEXT NOT NULL, outcome TEXT NOT NULL CHECK (outcome IN ('success','failure')),
  weight REAL NOT NULL CHECK (weight IN (0.5, 1.0)),
  verifier TEXT NOT NULL CHECK (verifier IN ('ci','founder','local_test')),
  ref TEXT NOT NULL, at INTEGER NOT NULL,
  CHECK ((verifier='local_test') = (weight=0.5)),
  UNIQUE (memory_id, task_id), UNIQUE (memory_id, commit_sha)
) STRICT;
CREATE TRIGGER evidence_no_taint BEFORE INSERT ON memory_evidence
  WHEN (SELECT tainted FROM task WHERE id=NEW.task_id) = 1
  BEGIN SELECT RAISE(ABORT,'tainted task cannot provide evidence'); END;

CREATE VIRTUAL TABLE memory_fts USING fts5(title, body, content='memory', content_rowid='rid', tokenize='trigram');
CREATE TRIGGER memory_ai AFTER INSERT ON memory BEGIN
  INSERT INTO memory_fts(rowid,title,body) VALUES (NEW.rid,NEW.title,NEW.body); END;
CREATE TRIGGER memory_ad AFTER DELETE ON memory BEGIN
  INSERT INTO memory_fts(memory_fts,rowid,title,body) VALUES ('delete',OLD.rid,OLD.title,OLD.body); END;
CREATE TRIGGER memory_au AFTER UPDATE OF title, body ON memory BEGIN
  INSERT INTO memory_fts(memory_fts,rowid,title,body) VALUES ('delete',OLD.rid,OLD.title,OLD.body);
  INSERT INTO memory_fts(rowid,title,body) VALUES (NEW.rid,NEW.title,NEW.body); END;

CREATE TABLE vault_version (
  id TEXT PRIMARY KEY, parent_id TEXT REFERENCES vault_version(id),
  status TEXT NOT NULL CHECK (status IN ('building','validated','current','archived','rejected')),
  manifest_hash TEXT, report_json TEXT CHECK (report_json IS NULL OR json_valid(report_json)), created_at INTEGER NOT NULL
) STRICT;
CREATE UNIQUE INDEX one_current_vault ON vault_version(status) WHERE status='current';

CREATE VIEW eligible_evidence AS SELECT e.* FROM memory_evidence e JOIN task t ON t.id=e.task_id WHERE t.tainted=0;

CREATE TABLE task_transition (from_state TEXT NOT NULL, to_state TEXT NOT NULL, PRIMARY KEY (from_state,to_state)) STRICT;
INSERT INTO task_transition VALUES
  ('draft','ready'),
  ('draft','cancelled'),
  ('ready','running'),
  ('ready','cancelled'),
  ('ready','failed'),
  ('running','verifying'),
  ('running','ready'),
  ('running','blocked'),
  ('running','cancelled'),
  ('verifying','reviewing'),
  ('verifying','ready'),
  ('verifying','blocked'),
  ('verifying','cancelled'),
  ('reviewing','ready'),
  ('reviewing','awaiting_approval'),
  ('reviewing','merging'),
  ('reviewing','blocked'),
  ('reviewing','cancelled'),
  ('awaiting_approval','merging'),
  ('awaiting_approval','cancelled'),
  ('awaiting_approval','blocked'),
  ('merging','done'),
  ('merging','verifying'),
  ('merging','failed'),
  ('merging','blocked'),
  ('blocked','ready'),
  ('blocked','verifying'),
  ('blocked','reviewing'),
  ('blocked','awaiting_approval'),
  ('blocked','cancelled');
CREATE TRIGGER task_state_guard BEFORE UPDATE OF state ON task
  WHEN OLD.state<>NEW.state AND NOT EXISTS
    (SELECT 1 FROM task_transition WHERE from_state=OLD.state AND to_state=NEW.state)
  BEGIN SELECT RAISE(ABORT,'invalid task transition'); END;
CREATE TRIGGER task_resume_guard BEFORE UPDATE OF state ON task
  WHEN OLD.state='blocked' AND NEW.state NOT IN ('cancelled', OLD.resume_state)
  BEGIN SELECT RAISE(ABORT,'must resume to resume_state'); END;
CREATE TRIGGER task_risk_floor BEFORE UPDATE OF risk ON task WHEN NEW.risk < OLD.risk
  BEGIN SELECT RAISE(ABORT,'risk cannot be lowered'); END;
CREATE TRIGGER task_starts_draft BEFORE INSERT ON task WHEN NEW.state<>'draft'
  BEGIN SELECT RAISE(ABORT,'task must start as draft'); END;

CREATE TABLE task_dependency (task_id TEXT NOT NULL REFERENCES task(id), depends_on TEXT NOT NULL REFERENCES task(id),
  PRIMARY KEY (task_id, depends_on), CHECK (task_id <> depends_on)) STRICT;

CREATE TABLE outbox (
  id TEXT PRIMARY KEY, event_seq INTEGER NOT NULL REFERENCES event(seq), kind TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE, payload_json TEXT NOT NULL CHECK (json_valid(payload_json)),
  status TEXT NOT NULL CHECK (status IN ('pending','sending','sent','dead')),
  attempts INTEGER NOT NULL DEFAULT 0, next_at INTEGER NOT NULL, remote_ref TEXT, last_error TEXT
) STRICT;
CREATE INDEX outbox_due ON outbox(next_at) WHERE status IN ('pending','sending');

-- 화면 표시용 사본. 실행기는 자기 소유 파일의 공개 키만 믿는다.
CREATE TABLE credential (
  id TEXT PRIMARY KEY, label TEXT NOT NULL, public_key BLOB NOT NULL, sign_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, revoked_at INTEGER
) STRICT;

CREATE TABLE review (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES task(id), round INTEGER NOT NULL CHECK (round BETWEEN 1 AND 3),
  head_sha TEXT NOT NULL CHECK (length(head_sha)=40), vendor TEXT NOT NULL, model TEXT NOT NULL,
  verdict TEXT NOT NULL CHECK (verdict IN ('pass','fail','inconclusive')),
  report_json TEXT NOT NULL CHECK (json_valid(report_json)), at INTEGER NOT NULL,
  UNIQUE (task_id, round, vendor)
) STRICT;

CREATE TRIGGER task_taint_inherit_insert BEFORE INSERT ON task
  WHEN NEW.tainted=0 AND (SELECT tainted FROM task WHERE id=NEW.parent_id)=1
  BEGIN SELECT RAISE(ABORT,'child of tainted task must be tainted'); END;
CREATE TRIGGER task_taint_propagate AFTER UPDATE OF tainted ON task WHEN NEW.tainted=1 AND OLD.tainted=0
  -- recursive_triggers 설정에 의존하지 않는다.
  BEGIN UPDATE task SET tainted=1 WHERE tainted=0 AND id IN (
    WITH RECURSIVE d(id) AS (SELECT id FROM task WHERE parent_id=NEW.id
      UNION SELECT t.id FROM task t JOIN d ON t.parent_id=d.id) SELECT id FROM d); END;
CREATE TRIGGER task_parent_immutable BEFORE UPDATE OF parent_id ON task
  BEGIN SELECT RAISE(ABORT,'parent is immutable'); END;

-- INSERT OR REPLACE는 기본 설정에서 DELETE 트리거를 부르지 않는다. 그래서 INSERT 전에 중복을 거부한다.
CREATE TRIGGER event_no_replace BEFORE INSERT ON event
  WHEN EXISTS (SELECT 1 FROM event WHERE seq=NEW.seq OR idempotency_key=NEW.idempotency_key OR hash=NEW.hash)
  BEGIN SELECT RAISE(ABORT,'event duplicate'); END;
CREATE TRIGGER approval_insert_guard BEFORE INSERT ON approval
  WHEN NEW.status<>'pending' OR EXISTS (SELECT 1 FROM approval WHERE id=NEW.id OR nonce=NEW.nonce)
  BEGIN SELECT RAISE(ABORT,'approval must be new and pending'); END;
CREATE TRIGGER approval_no_delete BEFORE DELETE ON approval BEGIN SELECT RAISE(ABORT,'approval is append-only'); END;
CREATE TRIGGER task_no_replace BEFORE INSERT ON task WHEN EXISTS (SELECT 1 FROM task WHERE id=NEW.id)
  BEGIN SELECT RAISE(ABORT,'task exists'); END;
CREATE TRIGGER evidence_no_replace BEFORE INSERT ON memory_evidence
  WHEN EXISTS (SELECT 1 FROM memory_evidence WHERE id=NEW.id OR (memory_id=NEW.memory_id AND (task_id=NEW.task_id OR commit_sha=NEW.commit_sha)))
  BEGIN SELECT RAISE(ABORT,'evidence duplicate'); END;

CREATE TRIGGER budget_no_update BEFORE UPDATE ON budget_entry BEGIN SELECT RAISE(ABORT,'budget is append-only'); END;
CREATE TRIGGER budget_no_delete BEFORE DELETE ON budget_entry BEGIN SELECT RAISE(ABORT,'budget is append-only'); END;
CREATE TRIGGER budget_insert_guard BEFORE INSERT ON budget_entry
  WHEN EXISTS (SELECT 1 FROM budget_entry WHERE id=NEW.id OR (call_id=NEW.call_id AND kind=NEW.kind))
    OR (NEW.kind<>'reserve' AND NOT EXISTS (SELECT 1 FROM budget_entry WHERE call_id=NEW.call_id AND kind='reserve' AND task_id=NEW.task_id))
    OR (NEW.kind<>'reserve' AND EXISTS (SELECT 1 FROM budget_entry WHERE call_id=NEW.call_id AND kind IN ('settle','release')))
  BEGIN SELECT RAISE(ABORT,'invalid budget entry'); END;
CREATE TRIGGER memory_insert_guard BEFORE INSERT ON memory
  WHEN EXISTS (SELECT 1 FROM memory WHERE id=NEW.id OR rid=NEW.rid) OR (NEW.status='active' AND NEW.trust<>'founder')
  BEGIN SELECT RAISE(ABORT,'memory must be new; only founder may insert active'); END;
-- 점수의 감쇠는 서비스가 계산한다. DB는 최소 증거 수만 강제한다.
CREATE TRIGGER memory_promote_guard BEFORE UPDATE OF status ON memory
  WHEN NEW.status='active' AND OLD.status<>'active' AND NEW.trust<>'founder' AND (OLD.status<>'candidate' OR
    (SELECT count(*) FROM eligible_evidence WHERE memory_id=NEW.id AND outcome='success') < 3 OR
    (SELECT count(*) FROM eligible_evidence WHERE memory_id=NEW.id AND outcome='success' AND verifier='ci') < 2 OR
    (SELECT count(DISTINCT at/86400000) FROM eligible_evidence WHERE memory_id=NEW.id AND outcome='success') < 2)
  BEGIN SELECT RAISE(ABORT,'insufficient evidence'); END;
CREATE TRIGGER memory_trust_guard BEFORE UPDATE OF trust ON memory
  WHEN NEW.trust='founder' AND OLD.trust<>'founder' OR OLD.trust='external' AND NEW.trust<>'external'
  BEGIN SELECT RAISE(ABORT,'trust cannot be raised this way'); END;

-- 서비스 생애주기. 코어는 유형 이름을 열거하지 않는다. 유형은 pack_id 문자열이다.
CREATE TABLE service (
  id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, project_id TEXT UNIQUE REFERENCES project(id),
  state TEXT NOT NULL CHECK (state IN ('discover','define','build','release','operate','retire','archived')),
  kind TEXT NOT NULL DEFAULT 'product' CHECK (kind IN ('product','reference')),
  pack_id TEXT, pack_version TEXT, manifest_hash TEXT, version INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  CHECK ((pack_id IS NULL) = (pack_version IS NULL)),
  CHECK (state NOT IN ('build','release','operate','retire') OR (project_id IS NOT NULL AND pack_id IS NOT NULL AND manifest_hash IS NOT NULL))
) STRICT;
CREATE TABLE service_transition (from_state TEXT NOT NULL, to_state TEXT NOT NULL, PRIMARY KEY (from_state,to_state)) STRICT;
INSERT INTO service_transition VALUES
  ('discover','define'),
  ('discover','archived'),
  ('define','build'),
  ('define','archived'),
  ('build','release'),
  ('build','archived'),
  ('release','operate'),
  ('release','build'),
  ('operate','build'),
  ('operate','retire'),
  ('retire','archived');
-- 전이는 같은 트랜잭션에서 먼저 넣은 게이트 기록을 요구한다.
CREATE TABLE service_gate (
  service_id TEXT NOT NULL REFERENCES service(id), service_version INTEGER NOT NULL,
  from_state TEXT NOT NULL, to_state TEXT NOT NULL, evidence_json TEXT NOT NULL CHECK (json_valid(evidence_json) AND json_array_length(evidence_json) > 0),
  approved_by TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (service_id, service_version),
  FOREIGN KEY (from_state,to_state) REFERENCES service_transition(from_state,to_state)
) STRICT;
CREATE TRIGGER service_starts_discover BEFORE INSERT ON service
  WHEN NEW.state<>'discover' OR EXISTS (SELECT 1 FROM service WHERE id=NEW.id OR name=NEW.name OR project_id=NEW.project_id)
  BEGIN SELECT RAISE(ABORT,'service must be new and start at discover'); END;
CREATE TRIGGER service_state_guard BEFORE UPDATE OF state ON service
  WHEN OLD.state<>NEW.state AND (NEW.version<>OLD.version+1 OR NOT EXISTS
    (SELECT 1 FROM service_gate g WHERE g.service_id=OLD.id AND g.service_version=OLD.version AND g.from_state=OLD.state AND g.to_state=NEW.state))
  BEGIN SELECT RAISE(ABORT,'service transition needs gate'); END;
CREATE TRIGGER service_version_guard BEFORE UPDATE OF version ON service WHEN NEW.version<>OLD.version AND NEW.version<>OLD.version+1
  BEGIN SELECT RAISE(ABORT,'version must advance by one'); END;
CREATE TRIGGER service_id_guard BEFORE UPDATE OF id ON service BEGIN SELECT RAISE(ABORT,'service id is immutable'); END;
CREATE TRIGGER service_no_delete BEFORE DELETE ON service BEGIN SELECT RAISE(ABORT,'archive instead'); END;
CREATE TRIGGER service_gate_no_update BEFORE UPDATE ON service_gate BEGIN SELECT RAISE(ABORT,'gate is append-only'); END;
CREATE TRIGGER service_gate_no_delete BEFORE DELETE ON service_gate BEGIN SELECT RAISE(ABORT,'gate is append-only'); END;
CREATE TRIGGER service_gate_no_replace BEFORE INSERT ON service_gate
  WHEN EXISTS (SELECT 1 FROM service_gate WHERE service_id=NEW.service_id AND service_version=NEW.service_version)
  BEGIN SELECT RAISE(ABORT,'gate duplicate'); END;
