-- pgTAP tests for docs/database/rev23b-vectovia-storage.sql (private bucket, upload rule).
-- Runs against the local Storage stand-in. Synthetic data only; everything rolls back.
begin;
select no_plan();

insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000024f1','r23bp1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000024a1','r23ba1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000024b1','r23bb1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000024f1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R23b Council A','00000000-0000-0000-0000-0000000024a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R23b Council B','00000000-0000-0000-0000-0000000024b1'));
create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;

select is((select public from storage.buckets where id='vectovia-files'), false, 'the Vectovia file store is private');
select is((select file_size_limit from storage.buckets where id='vectovia-files'), 26214400::bigint, '25 MB per file');

select pg_temp.as_user('00000000-0000-0000-0000-0000000024f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',true);
select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',true);
select pg_temp.as_user('00000000-0000-0000-0000-0000000024a1');
select public.vv_save_site('82000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC site',null,null,null,null,null,51.9,1.3,null,null,null,null);
create temp table paths (p text); grant all on paths to authenticated;
insert into paths select public.vv_register_attachment('87000000-0000-0000-0000-000000000001','site','82000000-0000-0000-0000-000000000001',
  'photo.jpg','image/jpeg',10,repeat('a',64),null,null,'unknown');

select throws_ok($$insert into storage.objects (bucket_id, name) values ('vectovia-files', 'somewhere/else.jpg')$$,
  '42501', null, 'a file cannot be stored anywhere except its registered path');
select throws_ok($$insert into storage.objects (bucket_id, name) select 'evidence', p from paths$$,
  '42501', null, 'nor in the case evidence store');
select lives_ok($$insert into storage.objects (bucket_id, name) select 'vectovia-files', p from paths$$, 'the uploader stores the file at its registered path');
select throws_ok($$insert into storage.objects (bucket_id, name) select 'vectovia-files', p from paths$$,
  '23505', null, 'the original cannot be uploaded a second time');
select is((select count(*) from storage.objects)::int, 0, 'signed-in users cannot read stored files directly');
update storage.objects set name = 'tampered.jpg' where bucket_id = 'vectovia-files';
delete from storage.objects where bucket_id = 'vectovia-files';
reset role;
select is((select count(*) from storage.objects where name = (select p from paths))::int, 1, 'the original can be neither renamed nor deleted from the browser');

set local role service_role;
select public.vv_confirm_attachment('87000000-0000-0000-0000-000000000001', repeat('a',64), 10);
reset role;
delete from storage.objects where bucket_id = 'vectovia-files';
select pg_temp.as_user('00000000-0000-0000-0000-0000000024a1');
select throws_ok($$insert into storage.objects (bucket_id, name) select 'vectovia-files', p from paths$$,
  '42501', null, 'after the fingerprint check, nothing can be stored at that path again');
select pg_temp.as_user('00000000-0000-0000-0000-0000000024b1');
select throws_ok($$insert into storage.objects (bucket_id, name) select 'vectovia-files', p from paths$$,
  '42501', null, 'another council cannot store anything at this council''s paths');

select * from finish();
rollback;
