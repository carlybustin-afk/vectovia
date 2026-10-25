-- pgTAP tests for docs/database/rev25-vectovia-library.sql.
-- Requires revs 6–25. Synthetic people and content only; everything rolls back.
begin;
select no_plan();

-- AU author, RV reviewer, CA content admin, X ordinary user (council A field officer), B1 council B owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000026f1','r25p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026c1','r25au@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026c2','r25rv@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026c3','r25ca@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026a1','r25a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026b1','r25b1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000026f1');
insert into public.content_roles (user_id, role) values
 ('00000000-0000-0000-0000-0000000026c1','author'), ('00000000-0000-0000-0000-0000000026c2','reviewer'), ('00000000-0000-0000-0000-0000000026c3','content_admin');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R25 Council A','00000000-0000-0000-0000-0000000026a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R25 Council B','00000000-0000-0000-0000-0000000026b1')),
 ('albo', (select id from public.vv_taxa where key='aedes_albopictus')),
 ('bg', (select id from public.vv_trap_types where key='bg_sentinel'));

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000026f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',true);
select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',true);

-- ---------- Drafting and two-stage review ----------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a1');
select throws_ok($$select public.vv_lib_save_draft('species',pg_temp.ws('albo'),'{"summary":"SYNTHETIC summary text"}','[]')$$, '42501', null,
  'only content authors draft library pages');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026c1');
select throws_ok($$select public.vv_lib_save_draft('species',pg_temp.ws('albo'),'{"summary":"short"}','[]')$$, '23514', null, 'a page needs a summary');
insert into ids values ('v1', public.vv_lib_save_draft('species',pg_temp.ws('albo'),
  '{"summary":"SYNTHETIC invasive container-breeding mosquito","breeding_habitats":["SYNTHETIC tyres"],"best_traps":["bg_sentinel","ovitrap"]}',
  '[{"title":"SYNTHETIC source","url":"https://example.org/source"}]'));
select is((select version from public.vv_library_versions where id = pg_temp.ws('v1')), 1, 'first draft');
select matches(public.vv_lib_add_image('a1000000-0000-0000-0000-000000000001', pg_temp.ws('v1'), 'Aedes albopictus.jpg', 'SYNTHETIC female',
  'SYNTHETIC Photographer','CC BY 4.0','https://commons.example/x', 1), '^species/[0-9a-f-]{36}/a1000000-0000-0000-0000-000000000001/Aedes_albopictus.jpg$',
  'a credited photo is added to the draft');
select throws_ok($$select public.vv_lib_add_image('a1000000-0000-0000-0000-000000000002', pg_temp.ws('v1'), 'x.jpg', null, 'SYNTHETIC', 'CC BY 4.0', 'http://insecure.example', 1)$$,
  '23514', null, 'the source link must be https');
select throws_ok($$select public.vv_lib_add_image('a1000000-0000-0000-0000-000000000002', pg_temp.ws('v1'), 'x.jpg', null, '', 'CC BY 4.0', 'https://x.example', 1)$$,
  '23514', null, 'every photo is credited');

select pg_temp.as_user('00000000-0000-0000-0000-0000000026a1');
select is((select count(*) from public.vv_library_versions)::int, 0, 'councils cannot see drafts');

select pg_temp.as_user('00000000-0000-0000-0000-0000000026c1');
select lives_ok($$select public.vv_lib_submit(pg_temp.ws('v1'))$$, 'author submits');
select throws_ok($$select public.vv_lib_add_image('a1000000-0000-0000-0000-000000000003', pg_temp.ws('v1'), 'x.jpg', null, 'SYNTHETIC', 'CC BY 4.0', 'https://x.example', 1)$$,
  '42501', null, 'photos cannot be added once submitted');
select throws_ok($$select public.vv_lib_review(pg_temp.ws('v1'), true, 'SYNTHETIC looks fine')$$, '42501', null, 'the author cannot review it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026c3');
select throws_ok($$select public.vv_lib_publish(pg_temp.ws('v1'))$$, '42501', null, 'cannot publish before the professional review');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026c2');
select lives_ok($$select public.vv_lib_review(pg_temp.ws('v1'), true, 'SYNTHETIC checked against the keys')$$, 'entomologist reviews');
select throws_ok($$select public.vv_lib_publish(pg_temp.ws('v1'))$$, '42501', null, 'the reviewer cannot also give final approval');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026c3');
select lives_ok($$select public.vv_lib_publish(pg_temp.ws('v1'))$$, 'final approval publishes');

select pg_temp.as_user('00000000-0000-0000-0000-0000000026a1');
select is((select content->>'summary' from public.vv_library_versions), 'SYNTHETIC invasive container-breeding mosquito', 'councils read the published page');
select is((select credit || ' / ' || licence from public.vv_library_images), 'SYNTHETIC Photographer / CC BY 4.0', 'with each photo''s credit and licence');
select throws_ok($$update public.vv_library_versions set content = '{"summary":"SYNTHETIC rewritten text"}'$$, '42501', null, 'no direct edits');

-- A new version supersedes; the old one stays readable.
select pg_temp.as_user('00000000-0000-0000-0000-0000000026c1');
insert into ids values ('v2', public.vv_lib_save_draft('species',pg_temp.ws('albo'),'{"summary":"SYNTHETIC updated summary text"}','[]'));
select public.vv_lib_submit(pg_temp.ws('v2'));
select pg_temp.as_user('00000000-0000-0000-0000-0000000026c2');
select public.vv_lib_review(pg_temp.ws('v2'), true, 'SYNTHETIC checked again');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026c3');
select public.vv_lib_publish(pg_temp.ws('v2'));
select is((select string_agg(status::text, ',' order by version) from public.vv_library_versions), 'superseded,published', 'v1 superseded, v2 published');

-- ---------- Council notes ----------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a1');
select lives_ok($$select public.vv_save_library_note('a2000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'trap',pg_temp.ws('bg'),'SYNTHETIC our BG traps live in store 3')$$,
  'a council adds a private note to a trap page');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026b1');
select is((select count(*) from public.vv_library_notes)::int, 0, 'another council cannot see it');
select throws_ok($$select public.vv_save_library_note('a2000000-0000-0000-0000-000000000001',pg_temp.ws('wsB'),'trap',pg_temp.ws('bg'),'SYNTHETIC hijack')$$,
  '42501', null, 'nor change it');
select is((select count(*) from information_schema.columns where table_schema='public' and table_name in ('vv_library_versions','vv_library_images')
  and column_name='workspace_id')::int, 0, 'library pages hold no council data');
reset role;
select throws_ok($$delete from public.vv_library_versions$$, '42501', null, 'library versions are never deleted');

select * from finish();
rollback;
