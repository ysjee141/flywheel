-- AX 회사 기록 DDL. state.db와 다른 company.db에 둔다. 시각은 epoch 밀리초(UTC).
PRAGMA foreign_keys = ON;
CREATE TABLE company_record (
  id TEXT PRIMARY KEY, module TEXT NOT NULL, kind TEXT NOT NULL,
  scope TEXT NOT NULL CHECK (scope IN ('company','service')), service_id TEXT,
  version INTEGER NOT NULL CHECK (version >= 1), supersedes TEXT UNIQUE REFERENCES company_record(id),
  sensitivity TEXT NOT NULL DEFAULT 'confidential' CHECK (sensitivity IN ('internal','confidential')),
  basis TEXT NOT NULL CHECK (basis IN ('actual','forecast','simulated')),
  payload_json TEXT NOT NULL CHECK (json_valid(payload_json)),
  source_sha256 TEXT CHECK (source_sha256 IS NULL OR length(source_sha256)=64),
  actor TEXT NOT NULL, created_at INTEGER NOT NULL,
  CHECK ((scope='service') = (service_id IS NOT NULL)),
  CHECK ((version=1) = (supersedes IS NULL))
) STRICT;
CREATE TRIGGER company_record_chain BEFORE INSERT ON company_record WHEN NEW.supersedes IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM company_record p WHERE p.id=NEW.supersedes AND p.module=NEW.module AND p.kind=NEW.kind
    AND p.scope=NEW.scope AND p.service_id IS NEW.service_id AND p.version=NEW.version-1)
  BEGIN SELECT RAISE(ABORT,'bad record chain'); END;
CREATE TRIGGER company_record_no_replace BEFORE INSERT ON company_record
  WHEN EXISTS (SELECT 1 FROM company_record WHERE id=NEW.id OR (NEW.supersedes IS NOT NULL AND supersedes=NEW.supersedes))
  BEGIN SELECT RAISE(ABORT,'company_record is append-only'); END;
CREATE TRIGGER company_record_no_update BEFORE UPDATE ON company_record BEGIN SELECT RAISE(ABORT,'company_record is append-only'); END;
CREATE TRIGGER company_record_no_delete BEFORE DELETE ON company_record BEGIN SELECT RAISE(ABORT,'company_record is append-only'); END;

CREATE TABLE decision (
  id TEXT PRIMARY KEY, module TEXT NOT NULL, service_id TEXT, question TEXT NOT NULL,
  options_json TEXT NOT NULL CHECK (json_array_length(options_json) >= 2),
  choice TEXT NOT NULL, reason TEXT NOT NULL CHECK (length(reason) > 0),
  snapshot_json TEXT NOT NULL CHECK (json_valid(snapshot_json)), review_at INTEGER,
  actor TEXT NOT NULL CHECK (actor='founder'), decided_at INTEGER NOT NULL
) STRICT;
CREATE TRIGGER decision_no_replace BEFORE INSERT ON decision WHEN EXISTS (SELECT 1 FROM decision WHERE id=NEW.id)
  BEGIN SELECT RAISE(ABORT,'decision is append-only'); END;
CREATE TRIGGER decision_no_update BEFORE UPDATE ON decision BEGIN SELECT RAISE(ABORT,'decision is append-only'); END;
CREATE TRIGGER decision_no_delete BEFORE DELETE ON decision BEGIN SELECT RAISE(ABORT,'decision is append-only'); END;

CREATE TABLE founder_time (
  id TEXT PRIMARY KEY, task_id TEXT, category TEXT NOT NULL CHECK (category IN ('business','platform','development')),
  week_start TEXT NOT NULL CHECK (date(week_start) IS week_start AND strftime('%w',week_start)='1'),
  expected_minutes INTEGER CHECK (expected_minutes >= 0),
  draft_minutes INTEGER CHECK (draft_minutes >= 0), confirmed_minutes INTEGER CHECK (confirmed_minutes >= 0),
  confirmed_at INTEGER, CHECK ((confirmed_minutes IS NULL) = (confirmed_at IS NULL))
) STRICT;
CREATE VIEW founder_week AS SELECT week_start, category, sum(confirmed_minutes) AS minutes
  FROM founder_time WHERE confirmed_minutes IS NOT NULL GROUP BY week_start, category;
