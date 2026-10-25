-- pgTAP tests for docs/database/rev25b-vectovia-library-storage.sql.
begin;
select no_plan();

insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000027c1','r25bau@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000027a1','r25bx@test.invalid',now());
insert into public.content_roles (user_id, role) values ('00000000-0000-0000-0000-0000000027c1','author');
create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create temp table paths (p text); grant all on paths to authenticated;

select is((select public from storage.buckets where id='vectovia-library'), true, 'library images are public (open-licence, no council data)');
select is((select file_size_limit from storage.buckets where id='vectovia-library'), 5242880::bigint, '5 MB per image');

select pg_temp.as_user('00000000-0000-0000-0000-0000000027c1');
create temp table v (id uuid); grant all on v to authenticated;
insert into v select public.vv_lib_save_draft('trap',(select id from public.vv_trap_types where key='ovitrap'),'{"summary":"SYNTHETIC ovitrap page text"}','[]');
insert into paths select public.vv_lib_add_image('a3000000-0000-0000-0000-000000000001',(select id from v),'ovitrap.jpg',null,'SYNTHETIC','CC0','https://x.example',1);
select throws_ok($$insert into storage.objects (bucket_id, name) values ('vectovia-library','elsewhere.jpg')$$, '42501', null, 'only at the registered path');
select lives_ok($$insert into storage.objects (bucket_id, name) select 'vectovia-library', p from paths$$, 'the author uploads the image');
select throws_ok($$insert into storage.objects (bucket_id, name) select 'vectovia-library', p from paths$$, '23505', null, 'and only once');
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a1');
select throws_ok($$insert into storage.objects (bucket_id, name) select 'vectovia-library', p || '2' from paths$$, '42501', null, 'others cannot upload');
delete from storage.objects where bucket_id = 'vectovia-library';
reset role;
select is((select count(*) from storage.objects where bucket_id = 'vectovia-library')::int, 1, 'and nobody can delete images from the browser');

select * from finish();
rollback;
