-- pgTAP tests for docs/database/rev28-invitation-emails.sql.
-- Requires revs 6–28. Synthetic people and data only; everything rolls back.
begin;
select no_plan();

-- Council A: A1 owner, A2 admin, A3 member. Council B: B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000028a1','r28a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000028a2','r28a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000028a3','r28a3@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000028b1','r28b1@test.invalid',now());
create temp table ids (k text primary key, v uuid);
create temp table toks (k text primary key, v text);
grant all on ids, toks to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R28 Council A','00000000-0000-0000-0000-0000000028a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R28 Council B','00000000-0000-0000-0000-0000000028b1'));
insert into public.workspace_members (workspace_id, user_id, role) values
 ((select v from ids where k='wsA'), '00000000-0000-0000-0000-0000000028a2', 'admin'),
 ((select v from ids where k='wsA'), '00000000-0000-0000-0000-0000000028a3', 'member');

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.tok(k text) returns text language sql as $$ select v from toks where toks.k = $1 $$;
create function pg_temp.inv(k text) returns uuid language sql as $$
  select id from public.workspace_invitations where token_hash = encode(extensions.digest((select v from toks where toks.k = $1), 'sha256'), 'hex') $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000028a1');
insert into toks values ('admin', public.create_invitation(pg_temp.ws('wsA'),'new.admin@test.invalid','admin'));
select pg_temp.as_user('00000000-0000-0000-0000-0000000028a2');
insert into toks values ('member', public.create_invitation(pg_temp.ws('wsA'),'New.Member@test.invalid','member'));

-- ---------- What goes in the email ----------------------------------------------------------
select is((select email from public.invitation_for_email(pg_temp.tok('member'))), 'new.member@test.invalid', 'the inviter gets the invitation for their link');
select is((select workspace_name from public.invitation_for_email(pg_temp.tok('member'))), 'SYNTHETIC R28 Council A', 'with the council name');
select is((select inviter_email from public.invitation_for_email(pg_temp.tok('member'))), 'r28a2@test.invalid', 'and who is inviting');
select throws_ok($$select * from public.invitation_for_email(pg_temp.tok('admin'))$$, '42501', null, 'an admin cannot email an admin invitation (owners only)');
select throws_ok($$select * from public.invitation_for_email('not-a-token')$$, '42501', null, 'a malformed link is refused');
select throws_ok($$select * from public.invitation_for_email(repeat('a',64))$$, '42501', null, 'an unknown link is refused');
select pg_temp.as_user('00000000-0000-0000-0000-0000000028a3');
select throws_ok($$select * from public.invitation_for_email(pg_temp.tok('member'))$$, '42501', null, 'a plain member cannot send invitations');
select pg_temp.as_user('00000000-0000-0000-0000-0000000028b1');
select throws_ok($$select * from public.invitation_for_email(pg_temp.tok('member'))$$, '42501', null, 'another council cannot use the link');
select pg_temp.as_user('00000000-0000-0000-0000-0000000028a1');
select is((select role::text from public.invitation_for_email(pg_temp.tok('admin'))), 'admin', 'the owner can email the admin invitation');

-- ---------- Recording: service role only -------------------------------------------------------
select throws_ok($$select public.record_invitation_email(pg_temp.inv('member'),'00000000-0000-0000-0000-0000000028a1','sent','x',null)$$, '42501', null,
  'browsers cannot write the email log');
reset role;
select lives_ok($$select public.record_invitation_email(pg_temp.inv('member'),'00000000-0000-0000-0000-0000000028a2','sent','re_123',null)$$, 'the email function records a send');
select is((select to_email from public.invitation_emails), 'new.member@test.invalid', 'the log keeps the recipient');
select is((select count(*) from public.audit_events where action = 'invitation.emailed')::int, 1, 'and the audit trail notes it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000028a2');
select is((select count(*) from public.invitation_emails)::int, 1, 'the council''s admins see the log');
select throws_ok($$update public.invitation_emails set status = 'failed'$$, '42501', null, 'the log cannot be changed');
select pg_temp.as_user('00000000-0000-0000-0000-0000000028a3');
select is((select count(*) from public.invitation_emails)::int, 0, 'plain members do not');
select pg_temp.as_user('00000000-0000-0000-0000-0000000028b1');
select is((select count(*) from public.invitation_emails)::int, 0, 'nor does another council');

-- ---------- Limits ---------------------------------------------------------------------------------
reset role;
select public.record_invitation_email(pg_temp.inv('member'),'00000000-0000-0000-0000-0000000028a2','sent','re_x',null) from generate_series(1, 4);
select pg_temp.as_user('00000000-0000-0000-0000-0000000028a2');
select throws_ok($$select * from public.invitation_for_email(pg_temp.tok('member'))$$, '54000', null, 'no more than 5 emails a day for one invitation');

-- ---------- A fresh link ------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000028a3');
select throws_ok($$select public.reissue_invitation(pg_temp.inv('member'))$$, '42501', null, 'a plain member cannot reissue');
select pg_temp.as_user('00000000-0000-0000-0000-0000000028a1');
insert into toks select 'admin_old', v from toks where k = 'admin';
update toks set v = public.reissue_invitation(pg_temp.inv('admin_old')) where k = 'admin';
select ok(pg_temp.tok('admin') <> pg_temp.tok('admin_old') and pg_temp.tok('admin') ~ '^[0-9a-f]{64}$', 'reissuing gives a new link');
select throws_ok($$select * from public.invitation_for_email(pg_temp.tok('admin_old'))$$, '42501', null, 'the old link stops working');
select is((select email from public.invitation_for_email(pg_temp.tok('admin'))), 'new.admin@test.invalid', 'the new one works');
select public.revoke_invitation(pg_temp.inv('admin'));
select throws_ok($$select * from public.invitation_for_email(pg_temp.tok('admin'))$$, '42501', null, 'a cancelled invitation cannot be emailed');
select throws_ok($$select public.reissue_invitation(pg_temp.inv('admin_old'))$$, '42501', null, 'or reissued');

-- ---------- Grants ---------------------------------------------------------------------------------
reset role;
select ok(not has_function_privilege('anon', 'public.invitation_for_email(text)', 'execute'), 'signed-out visitors cannot call it');
select ok(not has_function_privilege('authenticated', 'public.record_invitation_email(uuid, uuid, text, text, text)', 'execute'), 'only the server records sends');
select ok(not has_table_privilege('authenticated', 'public.invitation_emails', 'insert'), 'browsers cannot write the log directly');

select * from finish();
rollback;
