-- Type A 기준 DDL. PostgreSQL 15+. 앱은 app_rw 역할로 접속하고 표 소유자가 아니다.
CREATE ROLE app_rw NOLOGIN NOBYPASSRLS;
CREATE SCHEMA app; CREATE SCHEMA private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
CREATE TABLE app.app_user (id uuid PRIMARY KEY, email text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE app.organization (id uuid PRIMARY KEY, name text NOT NULL);
CREATE TABLE app.membership (
  organization_id uuid NOT NULL REFERENCES app.organization(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app.app_user(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('owner','admin','member','viewer')), PRIMARY KEY (organization_id, user_id));
CREATE TABLE app.project (
  id uuid NOT NULL, organization_id uuid NOT NULL REFERENCES app.organization(id) ON DELETE CASCADE,
  name text NOT NULL, PRIMARY KEY (id), UNIQUE (organization_id, id));
CREATE TABLE app.document (
  id uuid PRIMARY KEY, organization_id uuid NOT NULL, project_id uuid NOT NULL, body text NOT NULL,
  FOREIGN KEY (organization_id, project_id) REFERENCES app.project(organization_id, id) ON DELETE CASCADE);
CREATE TABLE app.subscription (
  id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES app.organization(id),
  status text NOT NULL CHECK (status IN ('trialing','active','past_due','canceled')),
  amount bigint NOT NULL CHECK (amount >= 0), currency char(3) NOT NULL, version int NOT NULL DEFAULT 1,
  UNIQUE (organization_id, id));
CREATE TABLE app.billing_attempt (
  id uuid PRIMARY KEY, subscription_id uuid NOT NULL REFERENCES app.subscription(id),
  period_start date NOT NULL, attempt_no int NOT NULL CHECK (attempt_no BETWEEN 1 AND 3),
  status text NOT NULL CHECK (status IN ('started','unknown','succeeded','failed')),
  amount bigint NOT NULL, currency char(3) NOT NULL, provider_ref text UNIQUE,
  UNIQUE (subscription_id, period_start, attempt_no));
CREATE UNIQUE INDEX one_paid_period ON app.billing_attempt(subscription_id, period_start) WHERE status = 'succeeded';
CREATE UNIQUE INDEX one_open_attempt ON app.billing_attempt(subscription_id, period_start) WHERE status IN ('started','unknown');
CREATE TABLE app.payment_event (
  provider text NOT NULL, event_id text NOT NULL, received_at timestamptz NOT NULL DEFAULT now(),
  payload jsonb NOT NULL, processed_at timestamptz, PRIMARY KEY (provider, event_id));

CREATE FUNCTION private.uid() RETURNS uuid LANGUAGE sql STABLE SET search_path = '' AS
  $$ SELECT NULLIF(current_setting('app.user_id', true), '')::uuid $$;
-- membership 정책의 재귀를 피하려고 SECURITY DEFINER를 쓴다. 소유자는 로그인할 수 없는 역할로 둔다.
CREATE FUNCTION private.has_role(org uuid, roles text[]) RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
  $$ SELECT EXISTS (SELECT 1 FROM app.membership m WHERE m.organization_id = org AND m.user_id = private.uid() AND m.role = ANY(roles)) $$;
REVOKE ALL ON FUNCTION private.has_role(uuid, text[]) FROM PUBLIC;
GRANT USAGE ON SCHEMA app, private TO app_rw;
GRANT EXECUTE ON FUNCTION private.uid(), private.has_role(uuid, text[]) TO app_rw;

ALTER TABLE app.app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.organization ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.project ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.document ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.subscription ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.billing_attempt ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.payment_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY u_self ON app.app_user FOR SELECT TO app_rw USING (id = private.uid());
CREATE POLICY o_read ON app.organization FOR SELECT TO app_rw USING (private.has_role(id, '{owner,admin,member,viewer}'));
CREATE POLICY m_read ON app.membership FOR SELECT TO app_rw USING (private.has_role(organization_id, '{owner,admin,member,viewer}'));
CREATE POLICY p_read ON app.project FOR SELECT TO app_rw USING (private.has_role(organization_id, '{owner,admin,member,viewer}'));
CREATE POLICY p_ins ON app.project FOR INSERT TO app_rw WITH CHECK (private.has_role(organization_id, '{owner,admin}'));
CREATE POLICY d_read ON app.document FOR SELECT TO app_rw USING (private.has_role(organization_id, '{owner,admin,member,viewer}'));
CREATE POLICY d_ins ON app.document FOR INSERT TO app_rw WITH CHECK (private.has_role(organization_id, '{owner,admin,member}'));
CREATE POLICY d_upd ON app.document FOR UPDATE TO app_rw USING (private.has_role(organization_id, '{owner,admin,member}'))
  WITH CHECK (private.has_role(organization_id, '{owner,admin,member}'));
CREATE POLICY d_del ON app.document FOR DELETE TO app_rw USING (private.has_role(organization_id, '{owner,admin}'));
CREATE POLICY s_read ON app.subscription FOR SELECT TO app_rw USING (private.has_role(organization_id, '{owner,admin}'));
GRANT SELECT ON app.app_user, app.organization, app.membership, app.project, app.document, app.subscription TO app_rw;
GRANT INSERT ON app.project, app.document TO app_rw;
GRANT DELETE ON app.document TO app_rw;
GRANT UPDATE (body) ON app.document TO app_rw;
-- 역할 변경, 청구, 결제 이벤트는 서버 전용 함수나 역할로만 다룬다. app_rw에는 권한이 없다.
