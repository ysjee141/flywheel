#!/bin/sh
# 임시 Postgres 컨테이너(네트워크 없음)에서 RLS와 청구 제약을 시험한다.
D=$(cd "$(dirname "$0")/.." && pwd); C=ax-typea-$$
docker run -d --rm --network none --name $C -e POSTGRES_PASSWORD=x postgres:17-alpine >/dev/null || exit 1
trap 'docker stop -t 1 $C >/dev/null' EXIT
# 초기화용 임시 서버는 TCP를 열지 않는다. TCP로 확인해야 최종 서버를 기다린다.
for i in $(seq 60); do docker exec $C pg_isready -q -h 127.0.0.1 -U postgres && break; sleep 0.5; done
P="docker exec -i $C psql -q -U postgres -v ON_ERROR_STOP=1 -At"
$P < "$D/schemas/type-a.sql" || exit 1
$P <<'S' || exit 1
insert into app.app_user select ('00000000-0000-0000-0000-00000000000'||i)::uuid,'e'||i from generate_series(1,5) i;
insert into app.organization values('a0000000-0000-0000-0000-000000000000','A'),('b0000000-0000-0000-0000-000000000000','B');
insert into app.membership select 'a0000000-0000-0000-0000-000000000000',('00000000-0000-0000-0000-00000000000'||i)::uuid,(array['owner','admin','member','viewer'])[i] from generate_series(1,4) i;
insert into app.membership values('b0000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000005','owner');
insert into app.project values('a1000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000000','pa'),('b1000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000000','pb');
insert into app.document values('a2000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000000','a1000000-0000-0000-0000-000000000000','x'),('b2000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000000','y');
insert into app.subscription values('a3000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000000','active',9900,'KRW');
S
as() { # 사용자, SQL, 기대값, 이름
  R=$({ echo "begin; set local role app_rw; set local app.user_id='$1';"; echo "$2"; echo "rollback;"; } | $P 2>&1 | tail -1)
  case "$R" in $3) echo "ok   $4";; *) echo "FAIL $4: $R";; esac; }
U=00000000-0000-0000-0000-00000000000; A=a0000000-0000-0000-0000-000000000000; B=b0000000-0000-0000-0000-000000000000
as ${U}1 "select count(*) from app.document;" 1 "A 소유자는 A 문서만"
as ${U}5 "select count(*) from app.document where organization_id='$A';" 0 "B 소유자는 A를 못 봄"
as "" "select count(*) from app.document;" 0 "로그인 없음"
as ${U}4 "select count(*) from app.document;" 1 "viewer 읽기"
as ${U}4 "insert into app.document values(gen_random_uuid(),'$A','a1000000-0000-0000-0000-000000000000','z');" "*row-level security*" "viewer 쓰기 거부"
as ${U}3 "with x as (insert into app.document values(gen_random_uuid(),'$A','a1000000-0000-0000-0000-000000000000','z') returning 1) select count(*) from x;" 1 "member 쓰기"
as ${U}3 "insert into app.document values(gen_random_uuid(),'$B','b1000000-0000-0000-0000-000000000000','z');" "*row-level security*" "타 테넌트 쓰기 거부"
as ${U}3 "insert into app.document values(gen_random_uuid(),'$A','b1000000-0000-0000-0000-000000000000','z');" "*Key is not present in table*project*" "테넌트 교차 외래 키 거부"
as ${U}3 "update app.document set organization_id='$B';" "*permission denied*" "테넌트 이동 거부"
as ${U}3 "with x as (delete from app.document returning 1) select count(*) from x;" 0 "member 삭제 0행"
as ${U}2 "with x as (delete from app.document returning 1) select count(*) from x;" 1 "admin 삭제"
as ${U}3 "update app.membership set role='owner';" "*permission denied*" "권한 상승 거부"
as ${U}3 "select count(*) from app.subscription;" 0 "member 구독 조회 없음"
as ${U}1 "select count(*) from app.payment_event;" "*permission denied*" "결제 이벤트 거부"
echo "RLS 없는 app 표: $(echo "select count(*) from pg_class c join pg_namespace n on n.oid=relnamespace where nspname='app' and relkind='r' and not relrowsecurity" | $P)"
for i in $(seq 10); do (echo "insert into app.billing_attempt values(gen_random_uuid(),'a3000000-0000-0000-0000-000000000000','2027-01-01',1+$i%3,'started',9900,'KRW');" | $P >/dev/null 2>&1) & done; wait
echo "동시 청구 시작 10건 중 성공(기대 1): $(echo 'select count(*) from app.billing_attempt' | $P)"
echo "update app.billing_attempt set status='unknown'; insert into app.billing_attempt select gen_random_uuid(),'a3000000-0000-0000-0000-000000000000','2027-01-01',1+(max(attempt_no)%3),'started',9900,'KRW' from app.billing_attempt;" | $P 2>&1 | grep -q one_open_attempt && echo "ok   unknown 중 재청구 거부" || echo "FAIL unknown 중 재청구"
