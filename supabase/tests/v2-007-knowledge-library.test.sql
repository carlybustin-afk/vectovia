-- pgTAP tests for docs/database/v2-007-knowledge-library.sql. Synthetic people and content only; rolls back.
begin;
select no_plan();

-- AU author, RV reviewer, CA content admin; A1 owner and A2 field officer of organisation A; B1 owner of organisation B.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000207c1','v27au@test.invalid',now()), ('00000000-0000-0000-0000-0000000207c2','v27rv@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000207c3','v27ca@test.invalid',now()), ('00000000-0000-0000-0000-0000000207a1','v27a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000207a2','v27a2@test.invalid',now()), ('00000000-0000-0000-0000-0000000207b1','v27b1@test.invalid',now());
insert into public.content_roles (user_id, role) values
 ('00000000-0000-0000-0000-0000000207c1','author'), ('00000000-0000-0000-0000-0000000207c2','reviewer'), ('00000000-0000-0000-0000-0000000207c3','content_admin');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC V27 Port Health','00000000-0000-0000-0000-0000000207a1')),
 ('wsB', public.provision_organisation('SYNTHETIC V27 Council','00000000-0000-0000-0000-0000000207b1'));
insert into public.workspace_members (workspace_id, user_id, role) values ((select v from ids where k='wsA'), '00000000-0000-0000-0000-0000000207a2', 'member');

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000207a1');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000207a2','vectovia','field');

-- ---------- Library entries ---------------------------------------------------------------------
select throws_ok($$select public.vv_lib_save_document('c7000000-0000-0000-0000-000000000001','power','synthetic_epa_s79','SYNTHETIC statutory nuisance',null,1)$$,
  '42501', null, 'an organisation owner cannot add library entries');
select pg_temp.as_user('00000000-0000-0000-0000-0000000207c1');
select throws_ok($$select public.vv_lib_save_document('c7000000-0000-0000-0000-000000000001','power','Bad Key','SYNTHETIC statutory nuisance',null,1)$$,
  '23514', null, 'keys are lower case');
select lives_ok($$select public.vv_lib_save_document('c7000000-0000-0000-0000-000000000001','power','synthetic_epa_s79','SYNTHETIC statutory nuisance','UK legislation',1)$$,
  'an author adds a powers entry');
select lives_ok($$select public.vv_lib_save_document('c7000000-0000-0000-0000-000000000001','power','synthetic_epa_s79','SYNTHETIC statutory nuisance','UK legislation',1)$$,
  'adding again is harmless');
select lives_ok($$select public.vv_lib_save_document('c7000000-0000-0000-0000-000000000002','procedure','synthetic_ovitrap_check','SYNTHETIC checking an ovitrap','Field procedures',1)$$,
  'and a procedure');
select lives_ok($$select public.vv_lib_save_document('c7000000-0000-0000-0000-000000000003','form','synthetic_sanitary_form','SYNTHETIC sanitary survey checklist','Survey forms',1)$$,
  'and a form');
select throws_ok($$select public.vv_lib_save_document('c7000000-0000-0000-0000-000000000002','power','synthetic_ovitrap_check','SYNTHETIC checking an ovitrap',null,1)$$,
  '22023', null, 'an entry''s kind cannot change');
select lives_ok($$select public.vv_lib_save_document('c7000000-0000-0000-0000-000000000002','procedure','synthetic_ovitrap_check','SYNTHETIC checking an ovitrap (egg papers)','Field procedures',1)$$,
  'an entry can be renamed');
reset role;
select is((select count(*) from public.audit_events where action like 'vv_library.document_%' and target_id::text like 'c7000000-%')::int, 4, 'adding and renaming are audited, retries are not');

-- ---------- Drafts, review and publication -----------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000207c1');
select throws_ok($$select public.vv_lib_save_draft('procedure','c7000000-0000-0000-0000-000000000001','{"summary":"SYNTHETIC summary text"}','[]')$$, '22023', null,
  'a page must match its entry''s kind');
select throws_ok($$select public.vv_lib_save_draft('power','c7000000-0000-0000-0000-000000000001','{"summary":"SYNTHETIC summary text"}','[{"title":"SYNTHETIC","url":"http://example.org"}]')$$,
  '22023', null, 'sources must be https links');
insert into ids values ('p1', public.vv_lib_save_draft('power','c7000000-0000-0000-0000-000000000001',
  '{"summary":"SYNTHETIC what the power allows and when it applies.","instrument":"SYNTHETIC Act","provision":"s79"}','[]'));
select throws_ok($$select public.vv_lib_submit(pg_temp.ws('p1'))$$, '22023', 'add at least one source before sending for review', 'a power needs a source before review');
insert into ids values ('p2', public.vv_lib_save_draft('power','c7000000-0000-0000-0000-000000000001',
  '{"summary":"SYNTHETIC what the power allows and when it applies.","instrument":"SYNTHETIC Act","provision":"s79"}',
  '[{"title":"SYNTHETIC legislation page","url":"https://www.legislation.gov.uk/"}]'));
select is((select version from public.vv_library_versions where id = pg_temp.ws('p2')), 2, 'each save is a new version');
select lives_ok($$select public.vv_lib_submit(pg_temp.ws('p2'))$$, 'with a source it goes to review');
insert into ids values ('f1', public.vv_lib_save_draft('form','c7000000-0000-0000-0000-000000000003','{"summary":"SYNTHETIC checklist for the yearly survey.","sections":[]}','[]'));
select lives_ok($$select public.vv_lib_submit(pg_temp.ws('f1'))$$, 'a form can go to review without a source');

select pg_temp.as_user('00000000-0000-0000-0000-0000000207a2');
select is((select count(*) from public.vv_library_versions where document_id is not null)::int, 0, 'organisations do not see unpublished pages');
select is((select count(*) from public.vv_library_documents)::int, 3, 'but can see the list of entries');

select pg_temp.as_user('00000000-0000-0000-0000-0000000207c1');
select throws_ok($$select public.vv_lib_review(pg_temp.ws('p2'), true, 'SYNTHETIC checked against the Act')$$, '42501', null, 'the author cannot review');
select pg_temp.as_user('00000000-0000-0000-0000-0000000207c2');
select lives_ok($$select public.vv_lib_review(pg_temp.ws('p2'), true, 'SYNTHETIC checked against the Act')$$, 'the reviewer approves');
select throws_ok($$select public.vv_lib_publish(pg_temp.ws('p2'))$$, '42501', null, 'the reviewer cannot publish');
select pg_temp.as_user('00000000-0000-0000-0000-0000000207c3');
select lives_ok($$select public.vv_lib_publish(pg_temp.ws('p2'))$$, 'a different content admin publishes');
reset role;
select throws_ok($$update public.vv_library_versions set content = '{"summary":"SYNTHETIC rewritten after publishing."}' where id = (select v from ids where k='p2')$$,
  '42501', null, 'a published page cannot be rewritten');

-- A second version supersedes the first.
select pg_temp.as_user('00000000-0000-0000-0000-0000000207c1');
insert into ids values ('p3', public.vv_lib_save_draft('power','c7000000-0000-0000-0000-000000000001',
  '{"summary":"SYNTHETIC updated summary of the power."}','[{"title":"SYNTHETIC legislation page","url":"https://www.legislation.gov.uk/"}]'));
select public.vv_lib_submit(pg_temp.ws('p3'));
select pg_temp.as_user('00000000-0000-0000-0000-0000000207c2');
select public.vv_lib_review(pg_temp.ws('p3'), true, 'SYNTHETIC checked the update');
select pg_temp.as_user('00000000-0000-0000-0000-0000000207c3');
select public.vv_lib_publish(pg_temp.ws('p3'));
select is((select string_agg(version || ':' || status, ',' order by version) from public.vv_library_versions where document_id = 'c7000000-0000-0000-0000-000000000001'),
  '1:draft,2:superseded,3:published', 'only the newest is published; the earlier one is kept as superseded');

select pg_temp.as_user('00000000-0000-0000-0000-0000000207a2');
select is((select count(*) from public.vv_library_versions where document_id is not null)::int, 2, 'organisations see the published page and its history');
select throws_ok($$select public.vv_lib_add_image(gen_random_uuid(), pg_temp.ws('p1'), 'x.jpg', null, 'SYNTHETIC', 'CC BY', 'https://example.org/x.jpg', 0)$$,
  '42501', null, 'photos are for species and trap pages only');

-- ---------- Local arrangements --------------------------------------------------------------------
select lives_ok($$select public.vv_save_library_note('c7100000-0000-0000-0000-000000000001', pg_temp.ws('wsA'), 'power', 'c7000000-0000-0000-0000-000000000001',
  'SYNTHETIC our legal team signs off any notice under this power')$$, 'a field officer adds a local arrangement');
select throws_ok($$select public.vv_save_library_note(gen_random_uuid(), pg_temp.ws('wsA'), 'procedure', 'c7000000-0000-0000-0000-000000000001', 'SYNTHETIC wrong kind')$$,
  '22023', null, 'a note must match its entry''s kind');
select pg_temp.as_user('00000000-0000-0000-0000-0000000207b1');
select is((select count(*) from public.vv_library_notes)::int, 0, 'another organisation never sees it');
select throws_ok($$select public.vv_save_library_note('c7100000-0000-0000-0000-000000000001', pg_temp.ws('wsB'), 'power', 'c7000000-0000-0000-0000-000000000001', 'SYNTHETIC takeover')$$,
  '42501', null, 'nor changes it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000207c3');
select is((select count(*) from public.vv_library_notes)::int, 0, 'nor does the content team: local arrangements never reach the shared library');

-- ---------- Signed-out visitors ------------------------------------------------------------------
reset role;
set local role anon;
select throws_ok($$select count(*) from public.vv_library_documents$$, '42501', null, 'signed-out visitors cannot read the library');
select throws_ok($$select public.vv_lib_save_document(gen_random_uuid(),'power','synthetic_x','SYNTHETIC x',null,0)$$, '42501', null, 'nor add to it');
reset role;

select * from finish();
rollback;
