-- Checks v2-008 and the knowledge library draft load. Synthetic people only; rolls back.
begin;
select no_plan();
\ir ../../docs/vectovia/knowledge-draft-load.sql
\ir ../../docs/vectovia/knowledge-draft-load.sql

select is((select string_agg(kind || '=' || n, ',' order by kind) from (select kind, count(*) n from public.vv_library_documents group by kind) x),
  'form=2,power=9,procedure=4', 'nine powers, four procedures and two forms load, and loading twice adds nothing');
select is((select count(*) from public.vv_library_versions where document_id is not null and status = 'in_review' and author_id is null)::int, 15,
  'every page waits for review, with no named author');
select is((select count(*) from public.vv_library_versions where document_id is not null and jsonb_array_length(sources) = 0)::int, 0, 'every page has sources');
select is((select count(*) from public.vv_library_versions where document_id is not null and not (content ? 'review_points'))::int, 0,
  'every page lists what the reviewer must check');

-- RV reviewer, CA content admin, AU author, A1 organisation owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000208c1','v28au@test.invalid',now()), ('00000000-0000-0000-0000-0000000208c2','v28rv@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000208c3','v28ca@test.invalid',now()), ('00000000-0000-0000-0000-0000000208a1','v28a1@test.invalid',now());
insert into public.content_roles (user_id, role) values
 ('00000000-0000-0000-0000-0000000208c1','author'), ('00000000-0000-0000-0000-0000000208c2','reviewer'), ('00000000-0000-0000-0000-0000000208c3','content_admin');
select public.provision_organisation('SYNTHETIC V28 Council','00000000-0000-0000-0000-0000000208a1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids select 'epa', v.id from public.vv_library_versions v join public.vv_library_documents d on d.id = v.document_id where d.key = 'epa_s79_insects';
create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000208a1');
select is((select count(*) from public.vv_library_versions where document_id is not null)::int, 0, 'organisations see none of the drafts');
select pg_temp.as_user('00000000-0000-0000-0000-0000000208c1');
select throws_ok($$select public.vv_lib_submit((select v from ids where k='epa'))$$, '42501', null, 'nobody can resubmit a loaded draft as their own');
select pg_temp.as_user('00000000-0000-0000-0000-0000000208c3');
select throws_ok($$select public.vv_lib_publish((select v from ids where k='epa'))$$, '42501', null, 'nothing is published before review');
select pg_temp.as_user('00000000-0000-0000-0000-0000000208c2');
select lives_ok($$select public.vv_lib_review((select v from ids where k='epa'), true, 'SYNTHETIC checked against legislation.gov.uk')$$, 'a reviewer reviews a loaded draft');
select throws_ok($$select public.vv_lib_publish((select v from ids where k='epa'))$$, '42501', null, 'the reviewer cannot publish it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000208c3');
select lives_ok($$select public.vv_lib_publish((select v from ids where k='epa'))$$, 'a content admin who did not review it publishes');
select pg_temp.as_user('00000000-0000-0000-0000-0000000208a1');
select is((select count(*) from public.vv_library_versions where document_id is not null)::int, 1, 'organisations now see that one page only');

-- Drafts written in the app keep their author rules.
select pg_temp.as_user('00000000-0000-0000-0000-0000000208c1');
insert into ids values ('own', public.vv_lib_save_draft('form', (select id from public.vv_library_documents where key = 'form_sanitary_survey'),
  '{"summary":"SYNTHETIC revised checklist for the survey.","sections":[]}', '[]'));
select public.vv_lib_submit((select v from ids where k='own'));
select throws_ok($$select public.vv_lib_review((select v from ids where k='own'), true, 'SYNTHETIC reviewing my own page')$$, '42501', null,
  'an author still cannot review their own page');

select * from finish();
rollback;
