-- =====================================================================
-- VECTOVIA — v2-001: foundation (organisations, members, invitations, audit,
-- products and access, teams, content review roles) plus the first-build
-- Vectovia schema (sites, programmes, traps, field work, results, risk,
-- actions, attachments, library, incursions, exports, external references).
-- STATUS: APPROVED BY THE OWNER AND APPLIED 2026-10-26 to vectovia-mvp (widvaahmcqanxezfhjqd), in 5 parts.
-- Built by pruning First Line's tested schema (revs 6–28, all with pgTAP tests)
-- to the foundation and Vectovia objects only: no Investigations, no legal
-- sources, no AI, no case links. Re-stated at the end: ensure_personal_workspace
-- and provision_organisation (no Investigations entitlements row), the team
-- functions and set_product_access (organisation-admin check, no confidential-
-- case flag). New organisations get Vectovia by default. Adds the shared
-- species and trap-type seed. Tests: supabase/tests (run tests/local/run-db-tests.ps1).
-- Design v2 changes (site-first, obligations, zones, national view) follow
-- in later revisions.
-- =====================================================================

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE TYPE public.content_role AS ENUM (
    'author',
    'reviewer',
    'content_admin'
);

CREATE TYPE public.kp_status AS ENUM (
    'draft',
    'in_review',
    'reviewed',
    'published',
    'superseded',
    'rejected',
    'withdrawn'
);

CREATE TYPE public.workspace_kind AS ENUM (
    'personal',
    'organisation'
);

CREATE TYPE public.workspace_role AS ENUM (
    'owner',
    'admin',
    'member'
);

CREATE FUNCTION public.accept_invitation(_token text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare inv public.workspace_invitations; addr text;
begin
  select lower(email) into addr from auth.users where id = auth.uid() and email_confirmed_at is not null;
  select * into inv from public.workspace_invitations
   where token_hash = encode(extensions.digest(_token, 'sha256'), 'hex')
     and accepted_at is null and revoked_at is null and expires_at > now()
   for update;
  if addr is null or inv.id is null or inv.email <> addr then
    raise exception 'invitation not valid' using errcode = '42501';
  end if;
  insert into public.workspace_members (workspace_id, user_id, role) values (inv.workspace_id, auth.uid(), inv.role)
  on conflict do nothing;
  update public.workspace_invitations set accepted_at = now() where id = inv.id;
  perform public.write_audit(inv.workspace_id, 'invitation.accepted', inv.id);
  return inv.workspace_id;
end $$;

CREATE FUNCTION public.create_invitation(_ws uuid, _email text, _role public.workspace_role) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare tok text; inv uuid;
begin
  if not exists (select 1 from public.workspaces where id = _ws and kind = 'organisation') then
    raise exception 'invitations are for organisation workspaces' using errcode = '42501';
  end if;
  if _role = 'owner'
     or (_role = 'admin'  and not public.has_ws_role(_ws, array['owner']::public.workspace_role[]))
     or (_role = 'member' and not public.has_ws_role(_ws, array['owner','admin']::public.workspace_role[])) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.workspace_invitations (workspace_id, email, role, invited_by, token_hash, expires_at)
  values (_ws, lower(trim(_email)), _role, auth.uid(), encode(extensions.digest(tok, 'sha256'), 'hex'), now() + interval '7 days')
  returning id into inv;
  perform public.write_audit(_ws, 'invitation.created', inv, jsonb_build_object('role', _role));
  return tok;
end $$;

CREATE FUNCTION public.default_workspace_products() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.workspace_products (workspace_id, product, enabled) values (new.id, 'vectovia', true) on conflict do nothing;
  return new;
end $$;

CREATE FUNCTION public.forbid_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin raise exception '% is append-only', tg_table_name using errcode = '42501'; end $$;

CREATE FUNCTION public.grant_content_role(_user uuid, _role public.content_role) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if _user = auth.uid() or not public.has_content_role(array['content_admin']::public.content_role[]) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.content_roles (user_id, role, granted_by) values (_user, _role, auth.uid()) on conflict do nothing;
  perform public.write_audit(null, 'content_role.granted', _user, jsonb_build_object('role', _role));
end $$;

CREATE FUNCTION public.guard_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare col text;
begin
  foreach col in array tg_argv loop
    if to_jsonb(new) -> col is distinct from to_jsonb(old) -> col then
      raise exception '%.% is immutable', tg_table_name, col using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

CREATE FUNCTION public.guard_membership() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ws public.workspaces;
begin
  -- Row lock serialises concurrent owner removals/demotions in one workspace:
  -- the second transaction waits, then re-checks against committed state.
  select * into ws from public.workspaces where id = coalesce(new.workspace_id, old.workspace_id) for update;
  if not found then return coalesce(new, old); end if; -- workspace being deleted
  if tg_op in ('INSERT', 'UPDATE') and ws.kind = 'personal'
     and (new.user_id <> ws.personal_owner_id or new.role <> 'owner') then
    raise exception 'personal workspaces have one owner only' using errcode = '42501';
  end if;
  -- Rev 4 (R4-1): a personal workspace's owner membership cannot be removed
  -- (it disappears only when the workspace itself is deleted).
  if tg_op = 'DELETE' and ws.kind = 'personal' then
    raise exception 'personal workspace owner cannot be removed' using errcode = '42501';
  end if;
  if tg_op in ('UPDATE', 'DELETE') and old.role = 'owner' and ws.kind = 'organisation'
     and (tg_op = 'DELETE' or new.role <> 'owner')
     and not exists (select 1 from public.workspace_members
                     where workspace_id = old.workspace_id and role = 'owner' and user_id <> old.user_id) then
    raise exception 'a workspace must keep at least one owner' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;

CREATE FUNCTION public.has_content_role(_roles public.content_role[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.content_roles
                 where user_id = auth.uid() and role = any(_roles))
$$;

CREATE FUNCTION public.has_product(_ws uuid, _product text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select enabled from public.workspace_products where workspace_id = _ws and product = _product), false)
$$;

CREATE FUNCTION public.has_product_access(_ws uuid, _product text, _levels text[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(public.product_level(_ws, _product) = any(_levels), false)
$$;

CREATE FUNCTION public.has_ws_role(_ws uuid, _roles public.workspace_role[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.workspace_members
                 where workspace_id = _ws and user_id = auth.uid() and role = any(_roles))
$$;

CREATE FUNCTION public.invitation_for_email(_token text) RETURNS TABLE(invitation_id uuid, workspace_id uuid, workspace_name text, email text, role public.workspace_role, expires_at timestamp with time zone, inviter_email text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare i public.workspace_invitations;
begin
  if _token !~ '^[0-9a-f]{64}$' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into i from public.workspace_invitations w where w.token_hash = encode(extensions.digest(_token, 'sha256'), 'hex');
  if i.id is null or i.accepted_at is not null or i.revoked_at is not null or i.expires_at <= now()
     or not public.may_invite(i.workspace_id, i.role) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if (select count(*) from public.invitation_emails e where e.invitation_id = i.id and e.created_at > now() - interval '1 day') >= 5
     or (select count(*) from public.invitation_emails e where e.workspace_id = i.workspace_id and e.created_at > now() - interval '1 hour') >= 50 then
    raise exception 'too many invitation emails; try again later' using errcode = '54000';
  end if;
  return query select i.id, i.workspace_id, w.name, i.email, i.role, i.expires_at, (select u.email::text from auth.users u where u.id = auth.uid())
    from public.workspaces w where w.id = i.workspace_id;
end $_$;

CREATE FUNCTION public.is_member(_ws uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.workspace_members
                 where workspace_id = _ws and user_id = auth.uid())
$$;

CREATE FUNCTION public.is_platform_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.platform_admins where user_id = auth.uid())
$$;

CREATE FUNCTION public.kp_guard_version() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if old.status <> 'draft' and (to_jsonb(new) - array['status', 'reviewer_id', 'reviewed_at', 'review_note', 'publisher_id', 'published_at', 'last_checked_at'])
                           is distinct from (to_jsonb(old) - array['status', 'reviewer_id', 'reviewed_at', 'review_note', 'publisher_id', 'published_at', 'last_checked_at']) then
    raise exception 'only drafts can be edited' using errcode = '42501';
  end if;
  if old.reviewer_id is not null and new.reviewer_id is distinct from old.reviewer_id then
    raise exception 'the review decision is final' using errcode = '42501';
  end if;
  if old.publisher_id is not null and new.publisher_id is distinct from old.publisher_id then
    raise exception 'the publication decision is final' using errcode = '42501';
  end if;
  return new;
end $$;

CREATE FUNCTION public.kp_is_editor() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.has_content_role(array['author', 'reviewer', 'content_admin']::public.content_role[])
$$;

CREATE FUNCTION public.may_invite(_ws uuid, _role public.workspace_role) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select _role <> 'owner'
     and ((_role = 'admin' and public.has_ws_role(_ws, array['owner']::public.workspace_role[]))
          or (_role = 'member' and public.has_ws_role(_ws, array['owner', 'admin']::public.workspace_role[])))
$$;

CREATE FUNCTION public.my_products() RETURNS TABLE(workspace_id uuid, product text, level text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select m.workspace_id, p.product, public.product_level(m.workspace_id, p.product)
    from public.workspace_members m
    join public.workspace_products p on p.workspace_id = m.workspace_id and p.enabled
   where m.user_id = auth.uid()
$$;

CREATE FUNCTION public.platform_workspaces() RETURNS TABLE(id uuid, kind public.workspace_kind, name text, investigations boolean, vectovia boolean, members bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return query
    select w.id, w.kind, w.name, public.has_product(w.id, 'investigations'), public.has_product(w.id, 'vectovia'),
           (select count(*) from public.workspace_members m where m.workspace_id = w.id)
      from public.workspaces w where w.kind = 'organisation' order by w.name;
end $$;

CREATE FUNCTION public.product_level(_ws uuid, _product text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select case
    when not public.has_product(_ws, _product) then null
    when m.role in ('owner', 'admin') then 'manage'
    else coalesce(a.level, case when _product = 'investigations' then 'field' else 'none' end)
  end
  from public.workspace_members m
  left join public.product_access a on a.workspace_id = m.workspace_id and a.user_id = m.user_id and a.product = _product
  where m.workspace_id = _ws and m.user_id = auth.uid()
$$;

CREATE FUNCTION public.record_invitation_email(_invitation uuid, _sent_by uuid, _status text, _provider_message_id text, _error text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.workspace_invitations;
begin
  select * into i from public.workspace_invitations where id = _invitation;
  if i.id is null then raise exception 'unknown invitation' using errcode = '22023'; end if;
  insert into public.invitation_emails (invitation_id, workspace_id, sent_by, to_email, status, provider_message_id, error)
  values (i.id, i.workspace_id, _sent_by, i.email, _status, nullif(left(_provider_message_id, 200), ''), nullif(left(_error, 500), ''));
  perform public.write_audit(i.workspace_id, case when _status = 'sent' then 'invitation.emailed' else 'invitation.email_failed' end, i.id, '{}'::jsonb);
end $$;

CREATE FUNCTION public.reissue_invitation(_invitation uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.workspace_invitations; tok text;
begin
  select * into i from public.workspace_invitations where id = _invitation for update;
  if i.id is null or i.accepted_at is not null or i.revoked_at is not null or not public.may_invite(i.workspace_id, i.role) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  update public.workspace_invitations set token_hash = encode(extensions.digest(tok, 'sha256'), 'hex'), expires_at = now() + interval '7 days'
   where id = _invitation;
  perform public.write_audit(i.workspace_id, 'invitation.reissued', i.id, '{}'::jsonb);
  return tok;
end $$;

CREATE FUNCTION public.remove_member(_ws uuid, _user uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare target_role public.workspace_role;
begin
  perform 1 from public.workspaces where id = _ws for update;
  select role into target_role from public.workspace_members where workspace_id = _ws and user_id = _user;
  if target_role is null
     or not (_user = auth.uid()
             or public.has_ws_role(_ws, array['owner']::public.workspace_role[])
             or (target_role = 'member' and public.has_ws_role(_ws, array['admin']::public.workspace_role[]))) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from public.workspace_members where workspace_id = _ws and user_id = _user;
  perform public.write_audit(_ws, 'member.removed', _user);
end $$;

CREATE FUNCTION public.revoke_content_role(_user uuid, _role public.content_role) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if _user = auth.uid() or not public.has_content_role(array['content_admin']::public.content_role[]) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from public.content_roles where user_id = _user and role = _role;
  perform public.write_audit(null, 'content_role.revoked', _user, jsonb_build_object('role', _role));
end $$;

CREATE FUNCTION public.revoke_invitation(_invitation uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ws uuid;
begin
  select workspace_id into ws from public.workspace_invitations where id = _invitation and accepted_at is null and revoked_at is null;
  if ws is null or not public.has_ws_role(ws, array['owner','admin']::public.workspace_role[]) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.workspace_invitations set revoked_at = now() where id = _invitation;
  perform public.write_audit(ws, 'invitation.revoked', _invitation);
end $$;

CREATE FUNCTION public.role_in(_ws uuid, _user uuid) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select role::text from public.workspace_members where workspace_id = _ws and user_id = _user
$$;

CREATE FUNCTION public.set_member_role(_ws uuid, _user uuid, _role public.workspace_role) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  -- Rev 4 (R4-2): lock first so the caller's owner status is re-read after
  -- any concurrent membership change commits.
  perform 1 from public.workspaces where id = _ws for update;
  if _role = 'owner' or not public.has_ws_role(_ws, array['owner']::public.workspace_role[]) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.workspace_members set role = _role where workspace_id = _ws and user_id = _user;
  if not found then raise exception 'not a member' using errcode = '42501'; end if;
  perform public.write_audit(_ws, 'member.role_changed', _user, jsonb_build_object('role', _role));
end $$;

CREATE FUNCTION public.set_workspace_product(_ws uuid, _product text, _enabled boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if _product <> 'vectovia' then raise exception 'unknown product' using errcode = '22023'; end if;
  insert into public.workspace_products (workspace_id, product, enabled, updated_at, updated_by)
  values (_ws, _product, _enabled, now(), auth.uid())
  on conflict (workspace_id, product) do update set enabled = excluded.enabled, updated_at = now(), updated_by = auth.uid();
  insert into public.workspace_product_events (workspace_id, product, enabled, actor_id) values (_ws, _product, _enabled, auth.uid());
  perform public.write_audit(_ws, 'product.' || case when _enabled then 'enabled' else 'disabled' end, null, jsonb_build_object('product', _product));
end $$;

CREATE FUNCTION public.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin new.updated_at := now(); return new; end $$;

CREATE FUNCTION public.transfer_ownership(_ws uuid, _to uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform 1 from public.workspaces where id = _ws for update;
  if _to = auth.uid() or not public.has_ws_role(_ws, array['owner']::public.workspace_role[])
     or not exists (select 1 from public.workspaces where id = _ws and kind = 'organisation') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.workspace_members set role = 'owner' where workspace_id = _ws and user_id = _to;
  if not found then raise exception 'target is not a current member' using errcode = '42501'; end if;
  update public.workspace_members set role = 'admin' where workspace_id = _ws and user_id = auth.uid();
  perform public.write_audit(_ws, 'ownership.transferred', _to);
end $$;

CREATE FUNCTION public.vv_can_read_attachment(_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.vv_attachments a where a.id = _id and public.vv_can_see_site(a.site_id))
$$;

CREATE FUNCTION public.vv_can_run_incursion(_incursion uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.vv_incursions i
     where i.id = _incursion and public.vv_can_see_site(i.site_id)
       and (public.vv_has(i.workspace_id, array['manage'])
            or (i.lead_officer_id = auth.uid() and public.vv_has(i.workspace_id, array['field', 'manage'])))
  )
$$;

CREATE FUNCTION public.vv_can_see_incursion(_incursion uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.vv_incursions i where i.id = _incursion and public.vv_can_see_site(i.site_id))
$$;

CREATE FUNCTION public.vv_can_see_programme(_programme uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.vv_programmes p
     where p.id = _programme
       and public.vv_has(p.workspace_id, array['view', 'field', 'manage'])
       and (public.vv_has(p.workspace_id, array['manage'])
            or exists (select 1 from public.vv_programme_teams pt join public.team_members tm on tm.team_id = pt.team_id
                        where pt.programme_id = p.id and tm.user_id = auth.uid()))
  )
$$;

CREATE FUNCTION public.vv_can_see_record(_type text, _id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select case _type
    when 'site' then public.vv_can_see_site(_id)
    when 'incursion' then public.vv_can_see_incursion(_id)
    when 'sample' then exists (select 1 from public.vv_samples s where s.id = _id and public.vv_can_see_site(s.site_id))
    else false end
$$;

CREATE FUNCTION public.vv_can_see_site(_site uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.vv_sites s
     where s.id = _site
       and public.vv_has(s.workspace_id, array['view', 'field', 'manage'])
       and (public.vv_has(s.workspace_id, array['manage'])
            or not exists (select 1 from public.vv_site_programmes sp where sp.site_id = s.id)
            or exists (select 1 from public.vv_site_programmes sp where sp.site_id = s.id and public.vv_can_see_programme(sp.programme_id)))
  )
$$;

CREATE FUNCTION public.vv_check_time(_t timestamp with time zone, _what text) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
begin
  if _t is not null and _t > now() + interval '10 minutes' then raise exception '% cannot be in the future', _what using errcode = '22023'; end if;
end $$;

CREATE FUNCTION public.vv_confirm_attachment(_id uuid, _sha256 text, _size_bytes bigint) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare a public.vv_attachments; st text;
begin
  select * into a from public.vv_attachments where id = _id for update;
  if a.id is null then raise exception 'unknown attachment' using errcode = '22023'; end if;
  if a.status <> 'pending' then return a.status; end if;
  st := case when lower(_sha256) = a.sha256_reported and _size_bytes = a.size_bytes then 'verified' else 'mismatch' end;
  update public.vv_attachments set status = st, sha256_stored = lower(_sha256), verified_at = now() where id = _id;
  insert into public.vv_attachment_events (attachment_id, workspace_id, action, actor_id, actor_role, detail)
  values (_id, a.workspace_id, st, null, 'system', jsonb_build_object('sha256_stored', lower(_sha256), 'size_bytes', _size_bytes));
  return st;
end $$;

CREATE FUNCTION public.vv_correct_attachment(_id uuid, _caption text, _captured_at timestamp with time zone, _capture_source text, _why text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare a public.vv_attachments;
begin
  select * into a from public.vv_attachments where id = _id for update;
  if a.id is null or not public.vv_has(a.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(a.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(_why, ''))) < 5 then raise exception 'say why' using errcode = '22023'; end if;
  if _captured_at > now() + interval '5 minutes' then raise exception 'capture time cannot be in the future' using errcode = '22023'; end if;
  update public.vv_attachments set caption = nullif(trim(_caption), ''),
    captured_at = case when coalesce(_capture_source, 'unknown') = 'unknown' then null else _captured_at end,
    capture_source = coalesce(_capture_source, 'unknown') where id = _id;
  insert into public.vv_attachment_events (attachment_id, workspace_id, action, actor_id, actor_role, detail)
  values (_id, a.workspace_id, 'caption_corrected', auth.uid(), coalesce(public.ws_role_of(a.workspace_id), 'unknown'),
          jsonb_build_object('from', jsonb_build_object('caption', a.caption, 'captured_at', a.captured_at, 'capture_source', a.capture_source),
                             'reason', trim(_why)));
end $$;

CREATE FUNCTION public.vv_correct_visit(_visit uuid, _occurred_at timestamp with time zone, _officer uuid, _condition text, _observations text, _exposure_start timestamp with time zone, _exposure_end timestamp with time zone, _not_completed_reason text, _why text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v public.vv_visits; after jsonb;
begin
  select * into v from public.vv_visits where id = _visit for update;
  if v.id is null or not public.vv_has(v.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(v.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(_why, ''))) < 5 then raise exception 'say why you are correcting it' using errcode = '22023'; end if;
  perform public.vv_check_time(_occurred_at, 'the visit time');
  update public.vv_visits set occurred_at = coalesce(_occurred_at, occurred_at), officer_id = coalesce(_officer, officer_id),
    trap_condition = coalesce(_condition, trap_condition), observations = nullif(trim(_observations), ''),
    exposure_started_at = _exposure_start, exposure_ended_at = _exposure_end,
    not_completed_reason = case when outcome = 'not_completed' then coalesce(nullif(trim(_not_completed_reason), ''), not_completed_reason) else null end,
    updated_by = auth.uid(), updated_at = now()
   where id = _visit;
  select to_jsonb(x) into after from public.vv_visits x where x.id = _visit;
  perform public.vv_event(v.workspace_id, 'visit', _visit, 'corrected', public.vv_diff(to_jsonb(v), after) || jsonb_build_object('reason', trim(_why)));
end $$;

CREATE FUNCTION public.vv_deploy_trap(_id uuid, _ws uuid, _trap uuid, _site uuid, _latitude double precision, _longitude double precision, _placement text, _started_at timestamp with time zone, _officer uuid, _interval integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare t public.vv_traps; s public.vv_sites;
begin
  if _id is null or not public.vv_has(_ws, array['field', 'manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if exists (select 1 from public.vv_deployments where id = _id) then
    if exists (select 1 from public.vv_deployments where id = _id and trap_id = _trap and site_id = _site) then return; end if;
    raise exception 'deployment id already used' using errcode = '23505';
  end if;
  select * into s from public.vv_sites where id = _site and workspace_id = _ws;
  if s.id is null or not public.vv_can_see_site(_site) then raise exception 'unknown site' using errcode = '22023'; end if;
  if s.status <> 'active' then raise exception 'the site is inactive' using errcode = '22023'; end if;
  select * into t from public.vv_traps where id = _trap and workspace_id = _ws for update;
  if t.id is null then raise exception 'unknown trap' using errcode = '22023'; end if;
  if t.status <> 'available' then raise exception 'the trap is %', t.status using errcode = '22023'; end if;
  if _officer is not null and not exists (select 1 from public.workspace_members where workspace_id = _ws and user_id = _officer) then
    raise exception 'unknown officer' using errcode = '22023';
  end if;
  perform public.vv_check_time(_started_at, 'the start');
  insert into public.vv_deployments (id, workspace_id, trap_id, site_id, latitude, longitude, placement, started_at, responsible_officer, visit_interval_days, created_by)
  values (_id, _ws, _trap, _site, coalesce(_latitude, s.latitude), coalesce(_longitude, s.longitude), nullif(trim(_placement), ''),
          coalesce(_started_at, now()), coalesce(_officer, auth.uid()), coalesce(_interval, 7), auth.uid());
  update public.vv_traps set status = 'deployed', updated_by = auth.uid(), updated_at = now() where id = _trap;
  perform public.vv_event(_ws, 'deployment', _id, 'started', jsonb_build_object('trap_id', _trap, 'site_id', _site, 'started_at', coalesce(_started_at, now())));
  perform public.vv_event(_ws, 'trap', _trap, 'deployed', jsonb_build_object('deployment_id', _id, 'site_id', _site));
end $$;

CREATE FUNCTION public.vv_diff(_before jsonb, _after jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_object_agg(k, jsonb_build_object('from', _before -> k, 'to', _after -> k)), '{}'::jsonb)
    from jsonb_object_keys(_after) k
   where k not in ('updated_at', 'updated_by') and (_before -> k) is distinct from (_after -> k)
$$;

CREATE FUNCTION public.vv_end_deployment(_deployment uuid, _ended_at timestamp with time zone, _reason text, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d public.vv_deployments; next_status text;
begin
  select * into d from public.vv_deployments where id = _deployment for update;
  if d.id is null or not public.vv_has(d.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(d.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if d.ended_at is not null then
    if d.end_reason = _reason then return; end if;   -- retry
    raise exception 'the deployment has already ended' using errcode = '22023';
  end if;
  if _reason not in ('moved', 'removed', 'damaged', 'lost', 'programme_ended') then raise exception 'unknown reason' using errcode = '22023'; end if;
  perform public.vv_check_time(_ended_at, 'the end');
  if coalesce(_ended_at, now()) < d.started_at then raise exception 'the end is before the start' using errcode = '22023'; end if;
  update public.vv_deployments set ended_at = coalesce(_ended_at, now()), end_reason = _reason, end_note = nullif(trim(_note), ''), ended_by = auth.uid()
   where id = _deployment;
  next_status := case _reason when 'damaged' then 'damaged' when 'lost' then 'retired' else 'available' end;
  update public.vv_traps set status = next_status, updated_by = auth.uid(), updated_at = now() where id = d.trap_id;
  perform public.vv_event(d.workspace_id, 'deployment', _deployment, 'ended', jsonb_build_object('reason', _reason, 'ended_at', coalesce(_ended_at, now())));
  perform public.vv_event(d.workspace_id, 'trap', d.trap_id, 'deployment_ended', jsonb_build_object('deployment_id', _deployment, 'status', next_status));
end $$;

CREATE FUNCTION public.vv_event(_ws uuid, _type text, _id uuid, _kind text, _detail jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.vv_events (workspace_id, record_type, record_id, kind, detail, actor_id, actor_role)
  values (_ws, _type, _id, _kind, coalesce(_detail, '{}'::jsonb), auth.uid(),
          coalesce(public.product_level(_ws, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(_ws), 'unknown') || ')');
end $$;

CREATE FUNCTION public.vv_findings_awaiting_review(_ws uuid) RETURNS TABLE(result_id uuid, sample_id uuid, site_id uuid, status text, taxon_id uuid, council_taxon_id uuid, quantity numeric, unit text, result_date date)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select r.id, r.sample_id, r.site_id, v.status, v.taxon_id, v.council_taxon_id, v.quantity, v.unit, v.result_date
    from public.vv_results r
    join public.vv_result_versions v on v.result_id = r.id and v.version = r.current_version
   where r.workspace_id = _ws and v.status in ('provisional', 'confirmed')
     and not exists (select 1 from public.vv_assessment_results ar where ar.result_id = r.id)
   order by v.result_date nulls last, r.created_at
$$;

CREATE FUNCTION public.vv_has(_ws uuid, _levels text[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.has_product_access(_ws, 'vectovia', _levels)
$$;

CREATE FUNCTION public.vv_lib_add_image(_id uuid, _version uuid, _file_name text, _caption text, _credit text, _licence text, _source_url text, _sort integer) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v public.vv_library_versions; path text;
begin
  select * into v from public.vv_library_versions where id = _version;
  if v.id is null or v.status <> 'draft' or v.author_id is distinct from auth.uid()
     or not public.has_content_role(array['author']::public.content_role[]) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_library_images where id = _id) then
    select storage_path into path from public.vv_library_images where id = _id and version_id = _version;
    if path is not null then return path; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  path := v.kind || '/' || coalesce(v.taxon_id, v.trap_type_id)::text || '/' || _id::text || '/' ||
          left(regexp_replace(coalesce(_file_name, 'image'), '[^A-Za-z0-9._-]+', '_', 'g'), 100);
  insert into public.vv_library_images (id, version_id, storage_path, caption, credit, licence, source_url, sort_order, added_by)
  values (_id, _version, path, nullif(trim(_caption), ''), trim(_credit), trim(_licence), trim(_source_url), coalesce(_sort, 0), auth.uid());
  return path;
end $$;

CREATE FUNCTION public.vv_lib_publish(_version uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v public.vv_library_versions;
begin
  if not public.has_content_role(array['content_admin']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from public.vv_library_versions where id = _version for update;
  if v.status is distinct from 'reviewed' or auth.uid() = v.author_id or auth.uid() = v.reviewer_id then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.vv_library_versions set status = 'superseded'
   where status = 'published' and ((v.kind = 'species' and taxon_id = v.taxon_id) or (v.kind = 'trap' and trap_type_id = v.trap_type_id));
  update public.vv_library_versions set status = 'published', publisher_id = auth.uid(), published_at = now() where id = _version;
  perform public.write_audit(null, 'vv_library.published', _version, '{}'::jsonb);
end $$;

CREATE FUNCTION public.vv_lib_review(_version uuid, _approve boolean, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare author uuid;
begin
  if not public.has_content_role(array['reviewer']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(trim(coalesce(_note, ''))) < 10 then raise exception 'a review note is required' using errcode = '22023'; end if;
  select author_id into author from public.vv_library_versions where id = _version and status = 'in_review' for update;
  if author is null or author = auth.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.vv_library_versions set status = case when _approve then 'reviewed' else 'rejected' end::public.kp_status,
    reviewer_id = auth.uid(), reviewed_at = now(), review_note = trim(_note) where id = _version;
  perform public.write_audit(null, case when _approve then 'vv_library.reviewed' else 'vv_library.rejected' end, _version, '{}'::jsonb);
end $$;

CREATE FUNCTION public.vv_lib_save_draft(_kind text, _subject uuid, _content jsonb, _sources jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v int; vid uuid;
begin
  if not public.has_content_role(array['author']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  if _kind = 'species' and not exists (select 1 from public.vv_taxa where id = _subject)
     or _kind = 'trap' and not exists (select 1 from public.vv_trap_types where id = _subject)
     or _kind not in ('species', 'trap') then
    raise exception 'unknown subject' using errcode = '22023';
  end if;
  select coalesce(max(version), 0) + 1 into v from public.vv_library_versions
   where (_kind = 'species' and taxon_id = _subject) or (_kind = 'trap' and trap_type_id = _subject);
  insert into public.vv_library_versions (kind, taxon_id, trap_type_id, version, content, sources, author_id)
  values (_kind, case when _kind = 'species' then _subject end, case when _kind = 'trap' then _subject end, v, _content, coalesce(_sources, '[]'), auth.uid())
  returning id into vid;
  perform public.write_audit(null, 'vv_library.drafted', vid, jsonb_build_object('kind', _kind, 'version', v));
  return vid;
end $$;

CREATE FUNCTION public.vv_lib_submit(_version uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.vv_library_versions set status = 'in_review' where id = _version and status = 'draft' and author_id = auth.uid();
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform public.write_audit(null, 'vv_library.submitted', _version, '{}'::jsonb);
end $$;

CREATE FUNCTION public.vv_link_incursion(_id uuid, _results uuid[], _sites uuid[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.vv_incursions;
begin
  select * into i from public.vv_incursions where id = _id;
  if i.id is null or not public.vv_can_run_incursion(_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  if exists (select 1 from unnest(coalesce(_results, '{}')) x(id) where not exists (
       select 1 from public.vv_results r where r.id = x.id and r.workspace_id = i.workspace_id and public.vv_can_see_site(r.site_id)))
  or exists (select 1 from unnest(coalesce(_sites, '{}')) x(id) where not exists (
       select 1 from public.vv_sites s where s.id = x.id and s.workspace_id = i.workspace_id and public.vv_can_see_site(s.id))) then
    raise exception 'unknown finding or site' using errcode = '22023';
  end if;
  insert into public.vv_incursion_findings (incursion_id, result_id, workspace_id, added_by)
    select distinct _id, x.id, i.workspace_id, auth.uid() from unnest(coalesce(_results, '{}')) x(id) on conflict do nothing;
  insert into public.vv_incursion_sites (incursion_id, site_id, workspace_id, added_by)
    select distinct _id, x.id, i.workspace_id, auth.uid() from unnest(coalesce(_sites, '{}')) x(id) on conflict do nothing;
  insert into public.vv_incursion_sites (incursion_id, site_id, workspace_id, added_by)
    select distinct _id, r.site_id, i.workspace_id, auth.uid() from public.vv_results r where r.id = any(coalesce(_results, '{}')) on conflict do nothing;
  perform public.vv_event(i.workspace_id, 'incursion', _id, 'linked', jsonb_build_object('findings', to_jsonb(_results), 'sites', to_jsonb(_sites)));
end $$;

CREATE FUNCTION public.vv_log_attachment_access(_id uuid, _action text, _actor uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare a public.vv_attachments;
begin
  if _action not in ('viewed', 'downloaded') then raise exception 'invalid action' using errcode = '22023'; end if;
  select * into a from public.vv_attachments where id = _id;
  if a.id is null then raise exception 'unknown attachment' using errcode = '22023'; end if;
  insert into public.vv_attachment_events (attachment_id, workspace_id, action, actor_id, actor_role)
  values (_id, a.workspace_id, _action, _actor,
          coalesce((select role::text from public.workspace_members where workspace_id = a.workspace_id and user_id = _actor), 'unknown'));
end $$;

CREATE FUNCTION public.vv_log_export(_id uuid, _ws uuid, _kind text, _scope jsonb, _counts jsonb, _file_name text, _size bigint, _sha256 text, _format_version text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.vv_has(_ws, array['view', 'field', 'manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if exists (select 1 from public.vv_exports where id = _id) then
    if exists (select 1 from public.vv_exports where id = _id and workspace_id = _ws and created_by = auth.uid() and sha256 = lower(_sha256)) then return; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if (_scope ? 'incursion_id') and not public.vv_can_see_incursion((_scope ->> 'incursion_id')::uuid) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.vv_exports (id, workspace_id, kind, scope, counts, file_name, size_bytes, sha256, format_version, created_by, created_role)
  values (_id, _ws, _kind, coalesce(_scope, '{}'), coalesce(_counts, '{}'), trim(_file_name), _size, lower(_sha256), _format_version, auth.uid(),
    coalesce(public.product_level(_ws, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(_ws), 'unknown') || ')');
end $$;

CREATE FUNCTION public.vv_matrix_level(_likelihood integer, _consequence integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case when _likelihood * _consequence <= 4 then 'low' when _likelihood * _consequence <= 9 then 'medium'
              when _likelihood * _consequence <= 16 then 'high' else 'very_high' end
$$;

CREATE FUNCTION public.vv_move_trap(_deployment uuid, _new_id uuid, _site uuid, _latitude double precision, _longitude double precision, _placement text, _moved_at timestamp with time zone, _officer uuid, _interval integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d public.vv_deployments;
begin
  if exists (select 1 from public.vv_deployments where id = _new_id) then return; end if;   -- retry
  select * into d from public.vv_deployments where id = _deployment;
  if d.id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  perform public.vv_end_deployment(_deployment, _moved_at, 'moved', null);
  perform public.vv_deploy_trap(_new_id, d.workspace_id, d.trap_id, _site, _latitude, _longitude, _placement, coalesce(_moved_at, now()), _officer, _interval);
end $$;

CREATE FUNCTION public.vv_open_incursion(_id uuid, _site uuid, _results uuid[], _title text, _taxon uuid, _council_taxon uuid, _lead uuid, _status text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s public.vv_sites; st public.vv_workspace_settings; ref text; existing public.vv_incursions;
begin
  select * into s from public.vv_sites where id = _site;
  if s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into existing from public.vv_incursions where id = _id;
  if existing.id is not null then
    if existing.workspace_id <> s.workspace_id or existing.site_id <> _site then raise exception 'not allowed' using errcode = '42501'; end if;
    return existing.reference;
  end if;
  if coalesce(_status, 'suspected') not in ('suspected', 'confirmed') then raise exception 'an incursion opens as suspected or confirmed' using errcode = '22023'; end if;
  if cardinality(coalesce(_results, '{}')) = 0 then raise exception 'choose the findings this incursion is about' using errcode = '22023'; end if;
  if exists (select 1 from unnest(_results) x(id) where not exists (
       select 1 from public.vv_results r where r.id = x.id and r.workspace_id = s.workspace_id and public.vv_can_see_site(r.site_id))) then
    raise exception 'unknown finding' using errcode = '22023';
  end if;
  if _lead is not null and not exists (
       select 1 from public.workspace_members m where m.workspace_id = s.workspace_id and m.user_id = _lead
          and (m.role in ('owner', 'admin') or exists (select 1 from public.product_access pa where pa.workspace_id = s.workspace_id
               and pa.user_id = _lead and pa.product = 'vectovia' and pa.level in ('field', 'manage')))) then
    raise exception 'the lead officer needs field or manager access to Vectovia' using errcode = '22023';
  end if;
  insert into public.vv_workspace_settings (workspace_id) values (s.workspace_id) on conflict do nothing;
  select * into st from public.vv_workspace_settings where workspace_id = s.workspace_id for update;
  ref := st.site_prefix || '-I' || lpad(st.next_incursion_no::text, 4, '0');
  update public.vv_workspace_settings set next_incursion_no = next_incursion_no + 1 where workspace_id = s.workspace_id;
  insert into public.vv_incursions (id, workspace_id, reference, site_id, title, taxon_id, council_taxon_id, status, lead_officer_id, created_by)
  values (_id, s.workspace_id, ref, _site, trim(_title), _taxon, _council_taxon, coalesce(_status, 'suspected'), _lead, auth.uid());
  insert into public.vv_incursion_findings (incursion_id, result_id, workspace_id, added_by)
    select distinct _id, x.id, s.workspace_id, auth.uid() from unnest(_results) x(id);
  insert into public.vv_incursion_sites (incursion_id, site_id, workspace_id, added_by)
    select distinct _id, r.site_id, s.workspace_id, auth.uid() from public.vv_results r where r.id = any(_results)
    union select _id, _site, s.workspace_id, auth.uid();
  insert into public.vv_incursion_steps (incursion_id, workspace_id, step_key, sort_order)
    select _id, s.workspace_id, k, o from unnest(array['notify', 'confirm_id', 'response_area', 'enhanced_trapping', 'control',
      'communications', 'review', 'stand_down']) with ordinality x(k, o);
  perform public.vv_event(s.workspace_id, 'incursion', _id, 'opened',
    jsonb_build_object('reference', ref, 'status', coalesce(_status, 'suspected'), 'lead_officer_id', _lead, 'findings', to_jsonb(_results)));
  return ref;
end $$;

CREATE FUNCTION public.vv_record_notification(_id uuid, _incursion uuid, _kind text, _contact uuid, _recipient text, _method text, _notified_at timestamp with time zone, _reference text, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.vv_incursions; c public.vv_notify_contacts;
begin
  select * into i from public.vv_incursions where id = _incursion;
  if i.id is null or not public.vv_can_run_incursion(_incursion) then raise exception 'not allowed' using errcode = '42501'; end if;
  if exists (select 1 from public.vv_notifications where id = _id) then
    if exists (select 1 from public.vv_notifications where id = _id and incursion_id = _incursion) then return; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _contact is not null then
    select * into c from public.vv_notify_contacts where id = _contact and workspace_id = i.workspace_id;
    if c.id is null then raise exception 'unknown contact' using errcode = '22023'; end if;
  end if;
  if _notified_at is null or _notified_at > now() + interval '5 minutes' then
    raise exception 'when they were notified is required and cannot be in the future' using errcode = '22023';
  end if;
  insert into public.vv_notifications (id, workspace_id, incursion_id, kind, contact_id, recipient, method, notified_at, reference, note,
    recorded_by, recorded_role)
  values (_id, i.workspace_id, _incursion, coalesce(c.kind, _kind), _contact,
    coalesce(nullif(trim(_recipient), ''), c.name || coalesce(' (' || c.organisation || ')', '')), _method, _notified_at,
    nullif(trim(_reference), ''), nullif(trim(_note), ''), auth.uid(),
    coalesce(public.product_level(i.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(i.workspace_id), 'unknown') || ')');
  perform public.vv_event(i.workspace_id, 'incursion', _incursion, 'notified', jsonb_build_object('notification_id', _id, 'kind', coalesce(c.kind, _kind)));
end $$;

CREATE FUNCTION public.vv_record_visit(_id uuid, _deployment uuid, _occurred_at timestamp with time zone, _officer uuid, _outcome text, _reason text, _condition text, _observations text, _exposure_start timestamp with time zone, _exposure_end timestamp with time zone, _samples jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d public.vv_deployments; x jsonb; ref text; st public.vv_workspace_settings; n int;
begin
  select * into d from public.vv_deployments where id = _deployment;
  if d.id is null or not public.vv_has(d.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(d.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_visits where id = _id) then
    if exists (select 1 from public.vv_visits where id = _id and deployment_id = _deployment) then return; end if;
    raise exception 'visit id already used' using errcode = '23505';
  end if;
  if _occurred_at is null then raise exception 'when did the visit happen?' using errcode = '22023'; end if;
  perform public.vv_check_time(_occurred_at, 'the visit time');
  perform public.vv_check_time(_exposure_end, 'the end of exposure');
  if _occurred_at < d.started_at - interval '1 minute' then raise exception 'the visit is before the trap was deployed' using errcode = '22023'; end if;
  if d.ended_at is not null and _occurred_at > d.ended_at + interval '1 day' then
    raise exception 'the visit is after the deployment ended' using errcode = '22023';
  end if;
  if _officer is not null and not exists (select 1 from public.workspace_members where workspace_id = d.workspace_id and user_id = _officer) then
    raise exception 'unknown officer' using errcode = '22023';
  end if;
  n := jsonb_array_length(coalesce(_samples, '[]'));
  if _outcome = 'collected' and n = 0 then raise exception 'add at least one sample, or record no catch' using errcode = '22023'; end if;
  if _outcome in ('no_catch', 'not_completed') and n > 0 then raise exception 'samples can only be added when they were collected' using errcode = '22023'; end if;
  insert into public.vv_visits (id, workspace_id, deployment_id, site_id, occurred_at, officer_id, outcome, not_completed_reason, trap_condition,
    observations, exposure_started_at, exposure_ended_at, created_by)
  values (_id, d.workspace_id, _deployment, d.site_id, _occurred_at, coalesce(_officer, auth.uid()), _outcome, nullif(trim(_reason), ''),
    coalesce(_condition, 'working'), nullif(trim(_observations), ''), _exposure_start, _exposure_end, auth.uid());
  for x in select * from jsonb_array_elements(coalesce(_samples, '[]')) loop
    ref := nullif(trim(x->>'reference'), '');
    if ref is null then
      insert into public.vv_workspace_settings (workspace_id) values (d.workspace_id) on conflict do nothing;
      select * into st from public.vv_workspace_settings where workspace_id = d.workspace_id for update;
      ref := st.site_prefix || '-S' || lpad(st.next_sample_no::text, 5, '0');
      update public.vv_workspace_settings set next_sample_no = next_sample_no + 1 where workspace_id = d.workspace_id;
    end if;
    insert into public.vv_samples (id, workspace_id, visit_id, site_id, reference, method, notes, created_by)
    values ((x->>'id')::uuid, d.workspace_id, _id, d.site_id, ref, coalesce(x->>'method', 'adult_trap_catch'), nullif(trim(x->>'notes'), ''), auth.uid());
    perform public.vv_event(d.workspace_id, 'sample', (x->>'id')::uuid, 'collected', jsonb_build_object('reference', ref, 'visit_id', _id));
  end loop;
  perform public.vv_event(d.workspace_id, 'visit', _id, 'recorded', jsonb_build_object('outcome', _outcome, 'occurred_at', _occurred_at, 'samples', n));
  if _condition in ('damaged', 'missing') then
    perform public.vv_event(d.workspace_id, 'trap', d.trap_id, 'condition_reported', jsonb_build_object('condition', _condition, 'visit_id', _id));
  end if;
end $$;

CREATE FUNCTION public.vv_record_workspace(_type text, _id uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select case _type
    when 'site' then (select workspace_id from public.vv_sites where id = _id)
    when 'incursion' then (select workspace_id from public.vv_incursions where id = _id)
    when 'sample' then (select workspace_id from public.vv_samples where id = _id)
    end
$$;

CREATE FUNCTION public.vv_refresh_sample_status(_sample uuid) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  update public.vv_samples s set status = case
    when exists (select 1 from public.vv_results r where r.sample_id = s.id)
     and not exists (select 1 from public.vv_results r join public.vv_result_versions v on v.result_id = r.id and v.version = r.current_version
                      where r.sample_id = s.id and v.status = 'pending')
    then 'resulted' else 'awaiting_result' end
  where s.id = _sample
$$;

CREATE FUNCTION public.vv_register_attachment(_id uuid, _record_type text, _record_id uuid, _file_name text, _mime_type text, _size_bytes bigint, _sha256 text, _caption text, _captured_at timestamp with time zone, _capture_source text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ws uuid; site uuid; r text; k text; path text; safe text;
begin
  if _id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if exists (select 1 from public.vv_attachments where id = _id) then   -- retry
    select storage_path into path from public.vv_attachments where id = _id and record_id = _record_id and uploaded_by = auth.uid();
    if path is not null then return path; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _record_type = 'site' then select workspace_id, id into ws, site from public.vv_sites where id = _record_id;
  elsif _record_type = 'visit' then select workspace_id, site_id into ws, site from public.vv_visits where id = _record_id;
  elsif _record_type = 'sample' then select workspace_id, site_id into ws, site from public.vv_samples where id = _record_id;
  else raise exception 'unknown record' using errcode = '22023';
  end if;
  if site is null or not public.vv_has(ws, array['field', 'manage']) or not public.vv_can_see_site(site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _captured_at > now() + interval '5 minutes' then raise exception 'capture time cannot be in the future' using errcode = '22023'; end if;
  k := case when _mime_type like 'image/%' then 'photo'
            when _mime_type in ('application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'text/csv') then 'spreadsheet'
            else 'document' end;
  r := coalesce(public.product_level(ws, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(ws), 'unknown') || ')';
  -- Path: council / record type / record / item / safe file name. Never trusted from the browser.
  safe := left(regexp_replace(coalesce(_file_name, 'file'), '[^A-Za-z0-9._-]+', '_', 'g'), 120);
  path := ws::text || '/' || _record_type || '/' || _record_id::text || '/' || _id::text || '/' || safe;
  insert into public.vv_attachments (id, workspace_id, record_type, record_id, site_id, kind, file_name, mime_type, size_bytes,
    sha256_reported, storage_path, caption, captured_at, capture_source, uploaded_by, uploaded_role)
  values (_id, ws, _record_type, _record_id, site, k, _file_name, _mime_type, _size_bytes, lower(_sha256), path,
    nullif(trim(_caption), ''), case when coalesce(_capture_source, 'unknown') = 'unknown' then null else _captured_at end,
    coalesce(_capture_source, 'unknown'), auth.uid(), r);
  insert into public.vv_attachment_events (attachment_id, workspace_id, action, actor_id, actor_role, detail)
  values (_id, ws, 'registered', auth.uid(), r, jsonb_build_object('size_bytes', _size_bytes, 'sha256_reported', lower(_sha256), 'mime_type', _mime_type));
  return path;
end $$;

CREATE FUNCTION public.vv_remove_external_ref(_id uuid, _reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r public.vv_external_refs;
begin
  select * into r from public.vv_external_refs where id = _id for update;
  if r.id is null or not public.vv_has(r.workspace_id, array['manage']) or not public.vv_can_see_record(r.record_type, r.record_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if r.removed_at is not null then return; end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  update public.vv_external_refs set removed_by = auth.uid(), removed_at = now(), removed_reason = trim(_reason) where id = _id;
  perform public.vv_event(r.workspace_id, r.record_type, r.record_id, 'external_ref_removed',
    jsonb_build_object('ref_id', _id, 'reason', trim(_reason)));
end $$;

CREATE FUNCTION public.vv_reopen_incursion(_id uuid, _incursion uuid, _status text, _reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.vv_incursions; role text;
begin
  select * into i from public.vv_incursions where id = _incursion for update;
  if i.id is null or not public.vv_has(i.workspace_id, array['manage']) or not public.vv_can_see_site(i.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_stand_downs where id = _id) then
    if exists (select 1 from public.vv_stand_downs where id = _id and incursion_id = _incursion and kind = 'reopen') then return; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if i.status <> 'stood_down' then raise exception 'only a stood-down incursion can be reopened' using errcode = '22023'; end if;
  if _status not in ('suspected', 'confirmed', 'responding', 'monitoring') then raise exception 'unknown status' using errcode = '22023'; end if;
  role := coalesce(public.product_level(i.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(i.workspace_id), 'unknown') || ')';
  insert into public.vv_stand_downs (id, workspace_id, incursion_id, kind, decided_at, rationale, decided_by, decided_role)
  values (_id, i.workspace_id, _incursion, 'reopen', now(), trim(_reason), auth.uid(), role);
  update public.vv_incursion_steps set status = 'to_do', note = null, decided_by = null, decided_at = null
   where incursion_id = _incursion and step_key = 'stand_down';
  update public.vv_incursions set status = _status, updated_by = auth.uid(), updated_at = now() where id = _incursion;
  perform public.vv_event(i.workspace_id, 'incursion', _incursion, 'reopened', jsonb_build_object('stand_down_id', _id, 'to', _status));
end $$;

CREATE FUNCTION public.vv_save_action(_id uuid, _site uuid, _assessment uuid, _title text, _detail text, _owner uuid, _due date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s public.vv_sites; old public.vv_actions; after jsonb;
begin
  select * into s from public.vv_sites where id = _site;
  if s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _assessment is not null and not exists (select 1 from public.vv_assessments where id = _assessment and site_id = _site) then
    raise exception 'unknown assessment' using errcode = '22023';
  end if;
  if _owner is not null and not exists (select 1 from public.workspace_members where workspace_id = s.workspace_id and user_id = _owner) then
    raise exception 'unknown owner' using errcode = '22023';
  end if;
  select * into old from public.vv_actions where id = _id for update;
  if old.id is not null and (old.site_id <> _site or old.status <> 'open') then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.id is null then
    insert into public.vv_actions (id, workspace_id, site_id, assessment_id, title, detail, owner_id, due_on, created_by)
    values (_id, s.workspace_id, _site, _assessment, trim(_title), nullif(trim(_detail), ''), _owner, _due, auth.uid());
    perform public.vv_event(s.workspace_id, 'action', _id, 'created', jsonb_build_object('owner_id', _owner, 'due_on', _due));
  else
    update public.vv_actions set title = trim(_title), detail = nullif(trim(_detail), ''), owner_id = _owner, due_on = _due where id = _id;
    select to_jsonb(x) into after from public.vv_actions x where x.id = _id;
    perform public.vv_event(s.workspace_id, 'action', _id, 'changed', public.vv_diff(to_jsonb(old), after));
  end if;
end $$;

CREATE FUNCTION public.vv_save_assessment(_id uuid, _site uuid, _results uuid[], _likelihood integer, _consequence integer, _final_level text, _override_reason text, _factors jsonb, _rationale text, _reason text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s public.vv_sites; a public.vv_assessments; v int; lvl text; role text;
begin
  select * into s from public.vv_sites where id = _site;
  if s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  lvl := public.vv_matrix_level(_likelihood, _consequence);
  role := coalesce(public.product_level(s.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(s.workspace_id), 'unknown') || ')';
  select * into a from public.vv_assessments where id = _id for update;
  if a.id is not null and a.site_id <> _site then raise exception 'not allowed' using errcode = '42501'; end if;
  if a.id is null then
    if cardinality(coalesce(_results, '{}')) = 0 then raise exception 'choose the findings this assessment covers' using errcode = '22023'; end if;
    if exists (select 1 from unnest(_results) x(id) where not exists (select 1 from public.vv_results r where r.id = x.id and r.site_id = _site)) then
      raise exception 'findings must be from this site' using errcode = '22023';
    end if;
    insert into public.vv_assessments (id, workspace_id, site_id, created_by) values (_id, s.workspace_id, _site, auth.uid());
    insert into public.vv_assessment_results (assessment_id, result_id, workspace_id) select distinct _id, x.id, s.workspace_id from unnest(_results) x(id);
    v := 1;
  else
    v := a.current_version + 1;
    update public.vv_assessments set current_version = v where id = _id;
  end if;
  insert into public.vv_assessment_versions (assessment_id, workspace_id, version, likelihood, consequence, matrix_version, matrix_level,
    final_level, override_reason, factors, rationale, reason, author_id, author_role)
  values (_id, s.workspace_id, v, _likelihood, _consequence, 'default-5x5-v1', lvl, coalesce(_final_level, lvl),
    case when coalesce(_final_level, lvl) = lvl then null else trim(_override_reason) end, coalesce(_factors, '[]'), trim(_rationale),
    case when v = 1 then null else trim(_reason) end, auth.uid(), role);
  perform public.vv_event(s.workspace_id, 'assessment', _id, case when v = 1 then 'recorded' else 'revised' end,
    jsonb_build_object('version', v, 'matrix_level', lvl, 'final_level', coalesce(_final_level, lvl)));
  return v;
end $$;

CREATE FUNCTION public.vv_save_council_taxon(_id uuid, _ws uuid, _scientific text, _common text, _active boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_council_taxa;
begin
  if _id is null or not public.vv_has(_ws, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into old from public.vv_council_taxa where id = _id for update;
  if old.id is not null and old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.id is null then
    insert into public.vv_council_taxa (id, workspace_id, scientific_name, common_name, active, created_by)
    values (_id, _ws, trim(_scientific), nullif(trim(_common), ''), coalesce(_active, true), auth.uid());
  else
    update public.vv_council_taxa set scientific_name = trim(_scientific), common_name = nullif(trim(_common), ''), active = coalesce(_active, active) where id = _id;
  end if;
  perform public.vv_event(_ws, 'council_taxon', _id, case when old.id is null then 'created' else 'changed' end, jsonb_build_object('name', trim(_scientific)));
end $$;

CREATE FUNCTION public.vv_save_council_trap_type(_id uuid, _ws uuid, _name text, _description text, _active boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_council_trap_types;
begin
  if _id is null or not public.vv_has(_ws, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into old from public.vv_council_trap_types where id = _id for update;
  if old.id is not null and old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.id is null then
    insert into public.vv_council_trap_types (id, workspace_id, name, description, active, created_by)
    values (_id, _ws, trim(_name), nullif(trim(_description), ''), coalesce(_active, true), auth.uid());
  else
    update public.vv_council_trap_types set name = trim(_name), description = nullif(trim(_description), ''), active = coalesce(_active, active) where id = _id;
  end if;
  perform public.vv_event(_ws, 'council_trap_type', _id, case when old.id is null then 'created' else 'changed' end, jsonb_build_object('name', trim(_name)));
end $$;

CREATE FUNCTION public.vv_save_external_ref(_id uuid, _record_type text, _record_id uuid, _system text, _external_id text, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ws uuid;
begin
  ws := public.vv_record_workspace(_record_type, _record_id);
  if ws is null or not public.vv_has(ws, array['manage']) or not public.vv_can_see_record(_record_type, _record_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_external_refs where id = _id) then
    if exists (select 1 from public.vv_external_refs where id = _id and record_id = _record_id and external_id = trim(_external_id)) then return; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.vv_external_refs (id, workspace_id, record_type, record_id, system, external_id, note, created_by)
  values (_id, ws, _record_type, _record_id, trim(_system), trim(_external_id), nullif(trim(_note), ''), auth.uid());
  perform public.vv_event(ws, _record_type, _record_id, 'external_ref_added',
    jsonb_build_object('ref_id', _id, 'system', trim(_system), 'external_id', trim(_external_id)));
end $$;

CREATE FUNCTION public.vv_save_incursion_task(_id uuid, _incursion uuid, _step text, _title text, _detail text, _owner uuid, _due date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.vv_incursions; old public.vv_actions; after jsonb;
begin
  select * into i from public.vv_incursions where id = _incursion;
  if i.id is null or not public.vv_can_run_incursion(_incursion) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from public.vv_incursion_steps where incursion_id = _incursion and step_key = _step) then
    raise exception 'unknown step' using errcode = '22023';
  end if;
  if _owner is not null and not exists (select 1 from public.workspace_members where workspace_id = i.workspace_id and user_id = _owner) then
    raise exception 'unknown owner' using errcode = '22023';
  end if;
  select * into old from public.vv_actions where id = _id for update;
  if old.id is not null and (old.incursion_id is distinct from _incursion or old.step_key <> _step or old.status <> 'open') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if old.id is null then
    insert into public.vv_actions (id, workspace_id, site_id, incursion_id, step_key, title, detail, owner_id, due_on, created_by)
    values (_id, i.workspace_id, i.site_id, _incursion, _step, trim(_title), nullif(trim(_detail), ''), _owner, _due, auth.uid());
    perform public.vv_event(i.workspace_id, 'action', _id, 'created',
      jsonb_build_object('owner_id', _owner, 'due_on', _due, 'incursion_id', _incursion, 'step', _step));
  else
    update public.vv_actions set title = trim(_title), detail = nullif(trim(_detail), ''), owner_id = _owner, due_on = _due where id = _id;
    select to_jsonb(x) into after from public.vv_actions x where x.id = _id;
    perform public.vv_event(i.workspace_id, 'action', _id, 'changed', public.vv_diff(to_jsonb(old), after));
  end if;
end $$;

CREATE FUNCTION public.vv_save_library_note(_id uuid, _ws uuid, _kind text, _subject uuid, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_library_notes;
begin
  if _id is null or not public.vv_has(_ws, array['field', 'manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into old from public.vv_library_notes where id = _id for update;
  if old.id is not null then
    if old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
    update public.vv_library_notes set note = trim(_note), updated_at = now() where id = _id;
  else
    insert into public.vv_library_notes (id, workspace_id, kind, taxon_id, trap_type_id, note, created_by)
    values (_id, _ws, _kind, case when _kind = 'species' then _subject end, case when _kind = 'trap' then _subject end, trim(_note), auth.uid());
  end if;
end $$;

CREATE FUNCTION public.vv_save_notify_contact(_id uuid, _ws uuid, _name text, _organisation text, _kind text, _detail text, _active boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_notify_contacts; after jsonb;
begin
  if not public.vv_has(_ws, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into old from public.vv_notify_contacts where id = _id for update;
  if old.id is not null and old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.id is null then
    insert into public.vv_notify_contacts (id, workspace_id, name, organisation, kind, detail, active, created_by)
    values (_id, _ws, trim(_name), nullif(trim(_organisation), ''), _kind, nullif(trim(_detail), ''), coalesce(_active, true), auth.uid());
    perform public.vv_event(_ws, 'notify_contact', _id, 'created', jsonb_build_object('name', trim(_name), 'kind', _kind));
  else
    update public.vv_notify_contacts set name = trim(_name), organisation = nullif(trim(_organisation), ''), kind = _kind,
      detail = nullif(trim(_detail), ''), active = coalesce(_active, true) where id = _id;
    select to_jsonb(x) into after from public.vv_notify_contacts x where x.id = _id;
    perform public.vv_event(_ws, 'notify_contact', _id, 'changed', public.vv_diff(to_jsonb(old), after));
  end if;
end $$;

CREATE FUNCTION public.vv_save_programme(_id uuid, _ws uuid, _name text, _description text, _status text, _starts date, _ends date, _teams uuid[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare before jsonb; after jsonb; old public.vv_programmes;
begin
  if _id is null or not public.vv_has(_ws, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if exists (select 1 from unnest(coalesce(_teams, '{}')) t(id) where not exists (select 1 from public.teams where id = t.id and workspace_id = _ws)) then
    raise exception 'unknown team' using errcode = '22023';
  end if;
  select * into old from public.vv_programmes where id = _id for update;
  if old.id is not null and old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.id is null then
    insert into public.vv_programmes (id, workspace_id, name, description, status, starts_on, ends_on, created_by)
    values (_id, _ws, trim(_name), nullif(trim(_description), ''), coalesce(_status, 'active'), _starts, _ends, auth.uid());
  else
    before := to_jsonb(old) || jsonb_build_object('teams', (select coalesce(jsonb_agg(team_id order by team_id), '[]') from public.vv_programme_teams where programme_id = _id));
    update public.vv_programmes set name = trim(_name), description = nullif(trim(_description), ''), status = coalesce(_status, status),
      starts_on = _starts, ends_on = _ends, updated_at = now() where id = _id;
    delete from public.vv_programme_teams where programme_id = _id;
  end if;
  insert into public.vv_programme_teams (programme_id, workspace_id, team_id) select distinct _id, _ws, t.id from unnest(coalesce(_teams, '{}')) t(id);
  select to_jsonb(p) || jsonb_build_object('teams', (select coalesce(jsonb_agg(team_id order by team_id), '[]') from public.vv_programme_teams where programme_id = _id))
    into after from public.vv_programmes p where p.id = _id;
  perform public.vv_event(_ws, 'programme', _id, case when before is null then 'created' else 'changed' end,
    case when before is null then '{}'::jsonb else public.vv_diff(before, after) end);
end $$;

CREATE FUNCTION public.vv_save_result(_id uuid, _sample uuid, _status text, _taxon uuid, _council_taxon uuid, _quantity numeric, _unit text, _method text, _identified_by text, _laboratory text, _lab_reference text, _result_date date, _uncertainty text, _reason text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s public.vv_samples; r public.vv_results; v int; role text;
begin
  select * into s from public.vv_samples where id = _sample;
  if s.id is null or not public.vv_has(s.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(s.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _council_taxon is not null and not exists (select 1 from public.vv_council_taxa where id = _council_taxon and workspace_id = s.workspace_id) then
    raise exception 'unknown species' using errcode = '22023';
  end if;
  if _result_date > (now() at time zone 'Europe/London')::date + 1 then raise exception 'the result date cannot be in the future' using errcode = '22023'; end if;
  role := coalesce(public.product_level(s.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(s.workspace_id), 'unknown') || ')';
  select * into r from public.vv_results where id = _id for update;
  if r.id is not null and r.sample_id <> _sample then raise exception 'not allowed' using errcode = '42501'; end if;
  if r.id is null then
    insert into public.vv_results (id, workspace_id, sample_id, site_id, created_by) values (_id, s.workspace_id, _sample, s.site_id, auth.uid());
    v := 1;
  else
    v := r.current_version + 1;
  end if;
  insert into public.vv_result_versions (result_id, workspace_id, version, status, taxon_id, council_taxon_id, quantity, unit, method,
    identified_by, laboratory, lab_reference, result_date, uncertainty, reason, author_id, author_role)
  values (_id, s.workspace_id, v, _status, _taxon, _council_taxon, _quantity, _unit, _method, nullif(trim(_identified_by), ''),
    nullif(trim(_laboratory), ''), nullif(trim(_lab_reference), ''), _result_date, nullif(trim(_uncertainty), ''),
    case when v = 1 then null else trim(_reason) end, auth.uid(), role);
  if v > 1 then update public.vv_results set current_version = v where id = _id; end if;
  perform public.vv_refresh_sample_status(_sample);
  perform public.vv_event(s.workspace_id, 'result', _id, case when v = 1 then 'recorded' else 'corrected' end,
    jsonb_build_object('version', v, 'status', _status, 'sample_id', _sample) || case when v > 1 then jsonb_build_object('reason', trim(_reason)) else '{}'::jsonb end);
  return v;
end $$;

CREATE FUNCTION public.vv_save_site(_id uuid, _ws uuid, _name text, _line_1 text, _line_2 text, _town text, _postcode text, _uprn text, _latitude double precision, _longitude double precision, _description text, _access text, _status text, _programmes uuid[]) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_sites; ref text; s public.vv_workspace_settings; before jsonb; after jsonb; mgr boolean;
begin
  if _id is null or not public.vv_has(_ws, array['field', 'manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  mgr := public.vv_has(_ws, array['manage']);
  if exists (select 1 from unnest(coalesce(_programmes, '{}')) p(id)
              where not exists (select 1 from public.vv_programmes x where x.id = p.id and x.workspace_id = _ws)
                 or not public.vv_can_see_programme(p.id)) then
    raise exception 'unknown programme' using errcode = '22023';
  end if;
  if not mgr and cardinality(coalesce(_programmes, '{}')) = 0 then
    raise exception 'choose at least one of your programmes' using errcode = '22023';
  end if;
  select * into old from public.vv_sites where id = _id for update;
  if old.id is not null and (old.workspace_id <> _ws or not public.vv_can_see_site(_id)) then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.id is null then
    insert into public.vv_workspace_settings (workspace_id) values (_ws) on conflict do nothing;
    select * into s from public.vv_workspace_settings where workspace_id = _ws for update;
    ref := s.site_prefix || '-' || lpad(s.next_site_no::text, 4, '0');
    update public.vv_workspace_settings set next_site_no = next_site_no + 1 where workspace_id = _ws;
    insert into public.vv_sites (id, workspace_id, reference, name, line_1, line_2, town, postcode, uprn, latitude, longitude,
      location_description, access_instructions, status, created_by)
    values (_id, _ws, ref, trim(_name), nullif(trim(_line_1), ''), nullif(trim(_line_2), ''), nullif(trim(_town), ''),
      nullif(upper(trim(_postcode)), ''), nullif(trim(_uprn), ''), _latitude, _longitude, nullif(trim(_description), ''),
      nullif(trim(_access), ''), coalesce(_status, 'active'), auth.uid());
  else
    ref := old.reference;
    before := to_jsonb(old) || jsonb_build_object('programmes', (select coalesce(jsonb_agg(programme_id order by programme_id), '[]') from public.vv_site_programmes where site_id = _id));
    update public.vv_sites set name = trim(_name), line_1 = nullif(trim(_line_1), ''), line_2 = nullif(trim(_line_2), ''),
      town = nullif(trim(_town), ''), postcode = nullif(upper(trim(_postcode)), ''), uprn = nullif(trim(_uprn), ''),
      latitude = _latitude, longitude = _longitude, location_description = nullif(trim(_description), ''),
      access_instructions = nullif(trim(_access), ''), status = coalesce(_status, status), updated_by = auth.uid(), updated_at = now()
     where id = _id;
    -- A field officer can only change links to programmes they can see; other links are kept.
    delete from public.vv_site_programmes where site_id = _id and (mgr or public.vv_can_see_programme(programme_id));
  end if;
  insert into public.vv_site_programmes (site_id, programme_id, workspace_id)
  select distinct _id, p.id, _ws from unnest(coalesce(_programmes, '{}')) p(id) on conflict do nothing;
  select to_jsonb(x) || jsonb_build_object('programmes', (select coalesce(jsonb_agg(programme_id order by programme_id), '[]') from public.vv_site_programmes where site_id = _id))
    into after from public.vv_sites x where x.id = _id;
  perform public.vv_event(_ws, 'site', _id, case when before is null then 'created' else 'changed' end,
    case when before is null then jsonb_build_object('reference', ref) else public.vv_diff(before, after) end);
  return ref;
end $$;

CREATE FUNCTION public.vv_save_trap(_id uuid, _ws uuid, _identifier text, _trap_type uuid, _council_trap_type uuid, _status text, _notes text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_traps; after jsonb;
begin
  if _id is null or not public.vv_has(_ws, array['field', 'manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if _council_trap_type is not null and not exists (select 1 from public.vv_council_trap_types where id = _council_trap_type and workspace_id = _ws) then
    raise exception 'unknown trap type' using errcode = '22023';
  end if;
  select * into old from public.vv_traps where id = _id for update;
  if old.id is not null and old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(_status, 'available') = 'deployed' and coalesce(old.status, '') <> 'deployed' then
    raise exception 'a trap becomes deployed when it is deployed at a site' using errcode = '22023';
  end if;
  if old.status = 'deployed' and coalesce(_status, 'deployed') <> 'deployed' then
    raise exception 'end its deployment first' using errcode = '22023';
  end if;
  if old.id is null then
    insert into public.vv_traps (id, workspace_id, identifier, trap_type_id, council_trap_type_id, status, notes, created_by)
    values (_id, _ws, trim(_identifier), _trap_type, _council_trap_type, coalesce(_status, 'available'), nullif(trim(_notes), ''), auth.uid());
  else
    update public.vv_traps set identifier = trim(_identifier), trap_type_id = _trap_type, council_trap_type_id = _council_trap_type,
      status = coalesce(_status, status), notes = nullif(trim(_notes), ''), updated_by = auth.uid(), updated_at = now() where id = _id;
  end if;
  select to_jsonb(t) into after from public.vv_traps t where t.id = _id;
  perform public.vv_event(_ws, 'trap', _id, case when old.id is null then 'created' else 'changed' end,
    case when old.id is null then jsonb_build_object('identifier', trim(_identifier)) else public.vv_diff(to_jsonb(old), after) end);
end $$;

CREATE FUNCTION public.vv_set_action_status(_id uuid, _status text, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare a public.vv_actions;
begin
  select * into a from public.vv_actions where id = _id for update;
  if a.id is null or not public.vv_can_see_site(a.site_id)
     or not (public.vv_has(a.workspace_id, array['manage']) or (a.owner_id = auth.uid() and public.vv_has(a.workspace_id, array['field', 'manage']))) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _status not in ('open', 'done', 'cancelled') then raise exception 'unknown status' using errcode = '22023'; end if;
  if a.status = _status then return; end if;
  update public.vv_actions set status = _status, completion_note = nullif(trim(_note), ''),
    completed_by = case when _status = 'open' then null else auth.uid() end,
    completed_at = case when _status = 'open' then null else now() end
   where id = _id;
  perform public.vv_event(a.workspace_id, 'action', _id, _status, jsonb_build_object('note', nullif(trim(_note), '')));
end $$;

CREATE FUNCTION public.vv_set_incursion_step(_id uuid, _step text, _status text, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.vv_incursions; old public.vv_incursion_steps;
begin
  select * into i from public.vv_incursions where id = _id;
  if i.id is null or not public.vv_can_run_incursion(_id) or i.status = 'stood_down' then raise exception 'not allowed' using errcode = '42501'; end if;
  if _step = 'stand_down' then raise exception 'use stand-down for this step' using errcode = '22023'; end if;
  if _status not in ('to_do', 'done', 'skipped') then raise exception 'unknown status' using errcode = '22023'; end if;
  select * into old from public.vv_incursion_steps where incursion_id = _id and step_key = _step for update;
  if old.incursion_id is null then raise exception 'unknown step' using errcode = '22023'; end if;
  if old.status = _status then return; end if;
  if (_status in ('skipped', 'to_do')) and char_length(trim(coalesce(_note, ''))) < 5 then
    raise exception 'give a reason' using errcode = '22023';
  end if;
  update public.vv_incursion_steps set status = _status, note = nullif(trim(_note), ''),
    decided_by = case when _status = 'to_do' then null else auth.uid() end,
    decided_at = case when _status = 'to_do' then null else now() end
   where incursion_id = _id and step_key = _step;
  perform public.vv_event(i.workspace_id, 'incursion', _id, 'step',
    jsonb_build_object('step', _step, 'from', old.status, 'to', _status, 'note', nullif(trim(_note), '')));
end $$;

CREATE FUNCTION public.vv_set_response_area(_id uuid, _lat numeric, _lon numeric, _radius_m numeric, _reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_incursions; area jsonb;
begin
  select * into old from public.vv_incursions where id = _id for update;
  if old.id is null or not public.vv_can_run_incursion(_id) or old.status = 'stood_down' then raise exception 'not allowed' using errcode = '42501'; end if;
  area := case when _lat is null then null else jsonb_build_object('type', 'circle', 'lat', _lat, 'lon', _lon, 'radius_m', round(_radius_m)) end;
  if old.response_area is not distinct from area then return; end if;
  if old.response_area is not null and char_length(trim(coalesce(_reason, ''))) < 5 then
    raise exception 'give a reason for changing the response area' using errcode = '22023';
  end if;
  update public.vv_incursions set response_area = area, updated_by = auth.uid(), updated_at = now() where id = _id;
  perform public.vv_event(old.workspace_id, 'incursion', _id, 'response_area',
    jsonb_build_object('from', old.response_area, 'to', area, 'reason', nullif(trim(_reason), '')));
end $$;

CREATE FUNCTION public.vv_stand_down(_id uuid, _incursion uuid, _decided_at timestamp with time zone, _rationale text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.vv_incursions; role text;
begin
  select * into i from public.vv_incursions where id = _incursion for update;
  if i.id is null or not public.vv_has(i.workspace_id, array['manage']) or not public.vv_can_see_site(i.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_stand_downs where id = _id) then
    if exists (select 1 from public.vv_stand_downs where id = _id and incursion_id = _incursion and kind = 'stand_down') then return; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if i.status = 'stood_down' then raise exception 'already stood down' using errcode = '22023'; end if;
  if exists (select 1 from public.vv_incursion_steps where incursion_id = _incursion and step_key <> 'stand_down' and status = 'to_do') then
    raise exception 'complete or skip every other step first' using errcode = '22023';
  end if;
  if _decided_at is null or _decided_at > now() + interval '5 minutes' then raise exception 'when it was decided is required' using errcode = '22023'; end if;
  role := coalesce(public.product_level(i.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(i.workspace_id), 'unknown') || ')';
  insert into public.vv_stand_downs (id, workspace_id, incursion_id, kind, decided_at, rationale, decided_by, decided_role)
  values (_id, i.workspace_id, _incursion, 'stand_down', _decided_at, trim(_rationale), auth.uid(), role);
  update public.vv_incursion_steps set status = 'done', note = left(trim(_rationale), 2000), decided_by = auth.uid(), decided_at = now()
   where incursion_id = _incursion and step_key = 'stand_down';
  update public.vv_incursions set status = 'stood_down', updated_by = auth.uid(), updated_at = now() where id = _incursion;
  perform public.vv_event(i.workspace_id, 'incursion', _incursion, 'stood_down', jsonb_build_object('stand_down_id', _id, 'from', i.status));
end $$;

CREATE FUNCTION public.vv_update_incursion(_id uuid, _title text, _taxon uuid, _council_taxon uuid, _lead uuid, _status text, _reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_incursions; after jsonb;
begin
  select * into old from public.vv_incursions where id = _id for update;
  if old.id is null or not public.vv_has(old.workspace_id, array['manage']) or not public.vv_can_see_site(old.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if old.status = 'stood_down' then raise exception 'reopen the incursion first' using errcode = '42501'; end if;
  if _status not in ('suspected', 'confirmed', 'responding', 'monitoring') then raise exception 'unknown status' using errcode = '22023'; end if;
  if _status <> old.status and char_length(trim(coalesce(_reason, ''))) < 5 then
    raise exception 'give a reason for the status change' using errcode = '22023';
  end if;
  if _lead is not null and _lead is distinct from old.lead_officer_id and not exists (
       select 1 from public.workspace_members m where m.workspace_id = old.workspace_id and m.user_id = _lead
          and (m.role in ('owner', 'admin') or exists (select 1 from public.product_access pa where pa.workspace_id = old.workspace_id
               and pa.user_id = _lead and pa.product = 'vectovia' and pa.level in ('field', 'manage')))) then
    raise exception 'the lead officer needs field or manager access to Vectovia' using errcode = '22023';
  end if;
  update public.vv_incursions set title = trim(_title), taxon_id = _taxon, council_taxon_id = _council_taxon, lead_officer_id = _lead,
    status = _status, updated_by = auth.uid(), updated_at = now() where id = _id;
  select to_jsonb(x) into after from public.vv_incursions x where x.id = _id;
  perform public.vv_event(old.workspace_id, 'incursion', _id, 'changed',
    public.vv_diff(to_jsonb(old), after) || case when _status <> old.status then jsonb_build_object('reason', trim(_reason)) else '{}'::jsonb end);
end $$;

CREATE FUNCTION public.vv_visit_schedule(_ws uuid) RETURNS TABLE(deployment_id uuid, trap_id uuid, site_id uuid, started_at timestamp with time zone, responsible_officer uuid, visit_interval_days integer, last_visit_at timestamp with time zone, next_due_on date, state text)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  with base as (
    select d.id, d.trap_id, d.site_id, d.started_at, d.responsible_officer, d.visit_interval_days,
           (select max(v.occurred_at) from public.vv_visits v where v.deployment_id = d.id) as last_visit_at
      from public.vv_deployments d
     where d.workspace_id = _ws and d.ended_at is null
  )
  select b.id, b.trap_id, b.site_id, b.started_at, b.responsible_officer, b.visit_interval_days, b.last_visit_at,
         ((coalesce(b.last_visit_at, b.started_at) at time zone 'Europe/London')::date + b.visit_interval_days) as next_due_on,
         case
           when ((coalesce(b.last_visit_at, b.started_at) at time zone 'Europe/London')::date + b.visit_interval_days) < (now() at time zone 'Europe/London')::date then 'overdue'
           when ((coalesce(b.last_visit_at, b.started_at) at time zone 'Europe/London')::date + b.visit_interval_days) <= (now() at time zone 'Europe/London')::date + 2 then 'due'
           else 'scheduled'
         end
    from base b
   order by 8, 1
$$;

CREATE FUNCTION public.write_audit(_ws uuid, _action text, _target uuid, _detail jsonb DEFAULT '{}'::jsonb) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into public.audit_events (workspace_id, actor_id, action, target_id, detail)
  values (_ws, auth.uid(), _action, _target, coalesce(_detail, '{}'::jsonb))
$$;

CREATE FUNCTION public.ws_role_of(_ws uuid) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select role::text from public.workspace_members where workspace_id = _ws and user_id = auth.uid()
$$;

SET default_tablespace = '';

SET default_table_access_method = heap;

CREATE TABLE public.audit_events (
    id bigint NOT NULL,
    workspace_id uuid,
    actor_id uuid,
    action text NOT NULL,
    target_id uuid,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.audit_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public.content_roles (
    user_id uuid NOT NULL,
    role public.content_role NOT NULL,
    granted_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.invitation_emails (
    id bigint NOT NULL,
    invitation_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    sent_by uuid NOT NULL,
    to_email text NOT NULL,
    status text NOT NULL,
    provider text DEFAULT 'resend'::text NOT NULL,
    provider_message_id text,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invitation_emails_error_check CHECK ((char_length(error) <= 500)),
    CONSTRAINT invitation_emails_provider_check CHECK ((provider = 'resend'::text)),
    CONSTRAINT invitation_emails_provider_message_id_check CHECK ((char_length(provider_message_id) <= 200)),
    CONSTRAINT invitation_emails_status_check CHECK ((status = ANY (ARRAY['sent'::text, 'failed'::text]))),
    CONSTRAINT invitation_emails_to_email_check CHECK (((to_email = lower(to_email)) AND ((char_length(to_email) >= 3) AND (char_length(to_email) <= 320))))
);

ALTER TABLE public.invitation_emails ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.invitation_emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public.platform_admins (
    user_id uuid NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.product_access (
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    product text NOT NULL,
    level text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT product_access_level_check CHECK ((level = ANY (ARRAY['none'::text, 'view'::text, 'field'::text, 'manage'::text]))),
    CONSTRAINT product_access_product_check CHECK ((product = ANY (ARRAY['investigations'::text, 'vectovia'::text])))
);

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    display_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT profiles_display_name_check CHECK ((char_length(display_name) <= 120))
);

CREATE TABLE public.team_members (
    team_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    added_by uuid,
    added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.teams (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    can_view_confidential boolean DEFAULT false NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT teams_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 80)))
);

CREATE TABLE public.vv_actions (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    site_id uuid NOT NULL,
    assessment_id uuid,
    title text NOT NULL,
    detail text,
    owner_id uuid,
    due_on date,
    status text DEFAULT 'open'::text NOT NULL,
    completion_note text,
    completed_by uuid,
    completed_at timestamp with time zone,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    incursion_id uuid,
    step_key text,
    CONSTRAINT vv_actions_check CHECK (((status = 'open'::text) = (completed_at IS NULL))),
    CONSTRAINT vv_actions_check1 CHECK (((status <> 'cancelled'::text) OR (char_length(TRIM(BOTH FROM COALESCE(completion_note, ''::text))) >= 5))),
    CONSTRAINT vv_actions_completion_note_check CHECK ((char_length(completion_note) <= 2000)),
    CONSTRAINT vv_actions_detail_check CHECK ((char_length(detail) <= 2000)),
    CONSTRAINT vv_actions_status_check CHECK ((status = ANY (ARRAY['open'::text, 'done'::text, 'cancelled'::text]))),
    CONSTRAINT vv_actions_step_check CHECK (((incursion_id IS NULL) = (step_key IS NULL))),
    CONSTRAINT vv_actions_title_check CHECK (((char_length(title) >= 3) AND (char_length(title) <= 200)))
);

CREATE TABLE public.vv_assessment_results (
    assessment_id uuid NOT NULL,
    result_id uuid NOT NULL,
    workspace_id uuid NOT NULL
);

CREATE TABLE public.vv_assessment_versions (
    assessment_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    version integer NOT NULL,
    likelihood integer NOT NULL,
    consequence integer NOT NULL,
    matrix_version text NOT NULL,
    matrix_level text NOT NULL,
    final_level text NOT NULL,
    override_reason text,
    factors jsonb DEFAULT '[]'::jsonb NOT NULL,
    rationale text NOT NULL,
    reason text,
    author_id uuid NOT NULL,
    author_role text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_assessment_versions_check CHECK (((final_level = matrix_level) OR (char_length(TRIM(BOTH FROM COALESCE(override_reason, ''::text))) >= 5))),
    CONSTRAINT vv_assessment_versions_check1 CHECK (((version = 1) OR (char_length(TRIM(BOTH FROM COALESCE(reason, ''::text))) >= 5))),
    CONSTRAINT vv_assessment_versions_consequence_check CHECK (((consequence >= 1) AND (consequence <= 5))),
    CONSTRAINT vv_assessment_versions_factors_check CHECK ((jsonb_typeof(factors) = 'array'::text)),
    CONSTRAINT vv_assessment_versions_final_level_check CHECK ((final_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'very_high'::text]))),
    CONSTRAINT vv_assessment_versions_likelihood_check CHECK (((likelihood >= 1) AND (likelihood <= 5))),
    CONSTRAINT vv_assessment_versions_matrix_level_check CHECK ((matrix_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'very_high'::text]))),
    CONSTRAINT vv_assessment_versions_override_reason_check CHECK ((char_length(override_reason) <= 1000)),
    CONSTRAINT vv_assessment_versions_rationale_check CHECK (((char_length(rationale) >= 10) AND (char_length(rationale) <= 4000))),
    CONSTRAINT vv_assessment_versions_reason_check CHECK ((char_length(reason) <= 500)),
    CONSTRAINT vv_assessment_versions_version_check CHECK ((version > 0))
);

CREATE TABLE public.vv_assessments (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    site_id uuid NOT NULL,
    current_version integer DEFAULT 1 NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.vv_attachment_events (
    id bigint NOT NULL,
    attachment_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    action text NOT NULL,
    actor_id uuid,
    actor_role text,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_attachment_events_action_check CHECK ((action = ANY (ARRAY['registered'::text, 'verified'::text, 'mismatch'::text, 'viewed'::text, 'downloaded'::text, 'caption_corrected'::text])))
);

ALTER TABLE public.vv_attachment_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.vv_attachment_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public.vv_attachments (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    record_type text NOT NULL,
    record_id uuid NOT NULL,
    site_id uuid NOT NULL,
    kind text NOT NULL,
    file_name text NOT NULL,
    mime_type text NOT NULL,
    size_bytes bigint NOT NULL,
    sha256_reported text NOT NULL,
    sha256_stored text,
    status text DEFAULT 'pending'::text NOT NULL,
    storage_path text NOT NULL,
    derived_from uuid,
    caption text,
    captured_at timestamp with time zone,
    capture_source text NOT NULL,
    uploaded_by uuid NOT NULL,
    uploaded_role text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    verified_at timestamp with time zone,
    CONSTRAINT vv_attachments_caption_check CHECK ((char_length(caption) <= 500)),
    CONSTRAINT vv_attachments_capture_source_check CHECK ((capture_source = ANY (ARRAY['device_metadata'::text, 'officer'::text, 'unknown'::text]))),
    CONSTRAINT vv_attachments_check CHECK (((status = 'pending'::text) = (verified_at IS NULL))),
    CONSTRAINT vv_attachments_check1 CHECK (((capture_source <> 'unknown'::text) OR (captured_at IS NULL))),
    CONSTRAINT vv_attachments_file_name_check CHECK (((char_length(file_name) >= 1) AND (char_length(file_name) <= 255))),
    CONSTRAINT vv_attachments_kind_check CHECK ((kind = ANY (ARRAY['photo'::text, 'document'::text, 'spreadsheet'::text]))),
    CONSTRAINT vv_attachments_mime_type_check CHECK ((mime_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/heic'::text, 'image/heif'::text, 'application/pdf'::text, 'application/msword'::text, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text, 'application/vnd.ms-excel'::text, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'::text, 'text/csv'::text]))),
    CONSTRAINT vv_attachments_record_type_check CHECK ((record_type = ANY (ARRAY['site'::text, 'visit'::text, 'sample'::text]))),
    CONSTRAINT vv_attachments_sha256_reported_check CHECK ((sha256_reported ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT vv_attachments_sha256_stored_check CHECK ((sha256_stored ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT vv_attachments_size_bytes_check CHECK (((size_bytes >= 1) AND (size_bytes <= 26214400))),
    CONSTRAINT vv_attachments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'verified'::text, 'mismatch'::text])))
);

CREATE TABLE public.vv_council_taxa (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    scientific_name text NOT NULL,
    common_name text,
    active boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_council_taxa_common_name_check CHECK ((char_length(common_name) <= 120)),
    CONSTRAINT vv_council_taxa_scientific_name_check CHECK (((char_length(scientific_name) >= 3) AND (char_length(scientific_name) <= 120)))
);

CREATE TABLE public.vv_council_trap_types (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    active boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_council_trap_types_description_check CHECK ((char_length(description) <= 500)),
    CONSTRAINT vv_council_trap_types_name_check CHECK (((char_length(name) >= 3) AND (char_length(name) <= 120)))
);

CREATE TABLE public.vv_deployments (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    trap_id uuid NOT NULL,
    site_id uuid NOT NULL,
    latitude double precision,
    longitude double precision,
    placement text,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    end_reason text,
    end_note text,
    responsible_officer uuid,
    visit_interval_days integer DEFAULT 7 NOT NULL,
    created_by uuid NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_by uuid,
    CONSTRAINT vv_deployments_check CHECK (((latitude IS NULL) = (longitude IS NULL))),
    CONSTRAINT vv_deployments_check1 CHECK (((ended_at IS NULL) = (end_reason IS NULL))),
    CONSTRAINT vv_deployments_check2 CHECK (((ended_at IS NULL) OR (ended_at >= started_at))),
    CONSTRAINT vv_deployments_end_note_check CHECK ((char_length(end_note) <= 1000)),
    CONSTRAINT vv_deployments_end_reason_check CHECK ((end_reason = ANY (ARRAY['moved'::text, 'removed'::text, 'damaged'::text, 'lost'::text, 'programme_ended'::text]))),
    CONSTRAINT vv_deployments_latitude_check CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
    CONSTRAINT vv_deployments_longitude_check CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))),
    CONSTRAINT vv_deployments_placement_check CHECK ((char_length(placement) <= 1000)),
    CONSTRAINT vv_deployments_visit_interval_days_check CHECK (((visit_interval_days >= 1) AND (visit_interval_days <= 60)))
);

CREATE TABLE public.vv_events (
    id bigint NOT NULL,
    workspace_id uuid NOT NULL,
    record_type text NOT NULL,
    record_id uuid NOT NULL,
    kind text NOT NULL,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    actor_id uuid,
    actor_role text,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_events_record_type_check CHECK ((record_type = ANY (ARRAY['programme'::text, 'site'::text, 'trap'::text, 'council_taxon'::text, 'council_trap_type'::text, 'deployment'::text, 'visit'::text, 'sample'::text, 'result'::text, 'assessment'::text, 'action'::text, 'incursion'::text, 'notify_contact'::text])))
);

ALTER TABLE public.vv_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.vv_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public.vv_exports (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    kind text NOT NULL,
    scope jsonb DEFAULT '{}'::jsonb NOT NULL,
    counts jsonb DEFAULT '{}'::jsonb NOT NULL,
    file_name text NOT NULL,
    size_bytes bigint NOT NULL,
    sha256 text NOT NULL,
    format_version text NOT NULL,
    created_by uuid NOT NULL,
    created_role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_exports_counts_check CHECK ((jsonb_typeof(counts) = 'object'::text)),
    CONSTRAINT vv_exports_file_name_check CHECK (((char_length(file_name) >= 3) AND (char_length(file_name) <= 200))),
    CONSTRAINT vv_exports_format_version_check CHECK (((char_length(format_version) >= 1) AND (char_length(format_version) <= 40))),
    CONSTRAINT vv_exports_kind_check CHECK ((kind = ANY (ARRAY['report_pdf'::text, 'report_docx'::text, 'incursion_pdf'::text, 'incursion_docx'::text, 'csv'::text]))),
    CONSTRAINT vv_exports_scope_check CHECK ((jsonb_typeof(scope) = 'object'::text)),
    CONSTRAINT vv_exports_sha256_check CHECK ((sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT vv_exports_size_bytes_check CHECK ((size_bytes > 0))
);

CREATE TABLE public.vv_external_refs (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    record_type text NOT NULL,
    record_id uuid NOT NULL,
    system text NOT NULL,
    external_id text NOT NULL,
    note text,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    removed_by uuid,
    removed_at timestamp with time zone,
    removed_reason text,
    CONSTRAINT vv_external_refs_check CHECK ((((removed_at IS NULL) = (removed_by IS NULL)) AND ((removed_at IS NULL) = (removed_reason IS NULL)))),
    CONSTRAINT vv_external_refs_external_id_check CHECK (((char_length(external_id) >= 1) AND (char_length(external_id) <= 120))),
    CONSTRAINT vv_external_refs_note_check CHECK ((char_length(note) <= 500)),
    CONSTRAINT vv_external_refs_record_type_check CHECK ((record_type = ANY (ARRAY['site'::text, 'incursion'::text, 'sample'::text]))),
    CONSTRAINT vv_external_refs_removed_reason_check CHECK ((char_length(removed_reason) <= 500)),
    CONSTRAINT vv_external_refs_system_check CHECK (((char_length(system) >= 2) AND (char_length(system) <= 60)))
);

CREATE TABLE public.vv_incursion_findings (
    incursion_id uuid NOT NULL,
    result_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    added_by uuid NOT NULL,
    added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.vv_incursion_sites (
    incursion_id uuid NOT NULL,
    site_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    added_by uuid NOT NULL,
    added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.vv_incursion_steps (
    incursion_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    step_key text NOT NULL,
    sort_order integer NOT NULL,
    status text DEFAULT 'to_do'::text NOT NULL,
    note text,
    decided_by uuid,
    decided_at timestamp with time zone,
    CONSTRAINT vv_incursion_steps_check CHECK (((status = 'to_do'::text) = (decided_at IS NULL))),
    CONSTRAINT vv_incursion_steps_check1 CHECK (((status <> 'skipped'::text) OR (char_length(TRIM(BOTH FROM COALESCE(note, ''::text))) >= 5))),
    CONSTRAINT vv_incursion_steps_note_check CHECK ((char_length(note) <= 2000)),
    CONSTRAINT vv_incursion_steps_status_check CHECK ((status = ANY (ARRAY['to_do'::text, 'done'::text, 'skipped'::text]))),
    CONSTRAINT vv_incursion_steps_step_key_check CHECK ((step_key = ANY (ARRAY['notify'::text, 'confirm_id'::text, 'response_area'::text, 'enhanced_trapping'::text, 'control'::text, 'communications'::text, 'review'::text, 'stand_down'::text])))
);

CREATE TABLE public.vv_incursions (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    reference text NOT NULL,
    site_id uuid NOT NULL,
    title text NOT NULL,
    taxon_id uuid,
    council_taxon_id uuid,
    status text DEFAULT 'suspected'::text NOT NULL,
    lead_officer_id uuid,
    response_area jsonb,
    opened_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_incursions_check CHECK ((num_nonnulls(taxon_id, council_taxon_id) <= 1)),
    CONSTRAINT vv_incursions_response_area_check CHECK (((response_area IS NULL) OR (((response_area ->> 'type'::text) = 'circle'::text) AND (jsonb_typeof((response_area -> 'lat'::text)) = 'number'::text) AND ((((response_area ->> 'lat'::text))::numeric >= ('-90'::integer)::numeric) AND (((response_area ->> 'lat'::text))::numeric <= (90)::numeric)) AND (jsonb_typeof((response_area -> 'lon'::text)) = 'number'::text) AND ((((response_area ->> 'lon'::text))::numeric >= ('-180'::integer)::numeric) AND (((response_area ->> 'lon'::text))::numeric <= (180)::numeric)) AND (jsonb_typeof((response_area -> 'radius_m'::text)) = 'number'::text) AND ((((response_area ->> 'radius_m'::text))::numeric >= (10)::numeric) AND (((response_area ->> 'radius_m'::text))::numeric <= (50000)::numeric))))),
    CONSTRAINT vv_incursions_status_check CHECK ((status = ANY (ARRAY['suspected'::text, 'confirmed'::text, 'responding'::text, 'monitoring'::text, 'stood_down'::text]))),
    CONSTRAINT vv_incursions_title_check CHECK (((char_length(title) >= 3) AND (char_length(title) <= 200)))
);

CREATE TABLE public.vv_library_images (
    id uuid NOT NULL,
    version_id uuid NOT NULL,
    storage_path text NOT NULL,
    caption text,
    credit text NOT NULL,
    licence text NOT NULL,
    source_url text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    added_by uuid NOT NULL,
    added_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_library_images_caption_check CHECK ((char_length(caption) <= 300)),
    CONSTRAINT vv_library_images_credit_check CHECK (((char_length(credit) >= 2) AND (char_length(credit) <= 200))),
    CONSTRAINT vv_library_images_licence_check CHECK (((char_length(licence) >= 2) AND (char_length(licence) <= 100))),
    CONSTRAINT vv_library_images_source_url_check CHECK ((source_url ~ '^https://'::text))
);

CREATE TABLE public.vv_library_notes (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    kind text NOT NULL,
    taxon_id uuid,
    trap_type_id uuid,
    note text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_library_notes_check CHECK ((((kind = 'species'::text) = (taxon_id IS NOT NULL)) AND ((kind = 'trap'::text) = (trap_type_id IS NOT NULL)))),
    CONSTRAINT vv_library_notes_kind_check CHECK ((kind = ANY (ARRAY['species'::text, 'trap'::text]))),
    CONSTRAINT vv_library_notes_note_check CHECK (((char_length(note) >= 2) AND (char_length(note) <= 4000)))
);

CREATE TABLE public.vv_library_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind text NOT NULL,
    taxon_id uuid,
    trap_type_id uuid,
    version integer NOT NULL,
    content jsonb NOT NULL,
    sources jsonb DEFAULT '[]'::jsonb NOT NULL,
    status public.kp_status DEFAULT 'draft'::public.kp_status NOT NULL,
    author_id uuid,
    reviewer_id uuid,
    reviewed_at timestamp with time zone,
    review_note text,
    publisher_id uuid,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_library_versions_check CHECK ((((kind = 'species'::text) = (taxon_id IS NOT NULL)) AND ((kind = 'trap'::text) = (trap_type_id IS NOT NULL)))),
    CONSTRAINT vv_library_versions_content_check CHECK (((jsonb_typeof(content) = 'object'::text) AND ((char_length(COALESCE((content ->> 'summary'::text), ''::text)) >= 10) AND (char_length(COALESCE((content ->> 'summary'::text), ''::text)) <= 2000)))),
    CONSTRAINT vv_library_versions_kind_check CHECK ((kind = ANY (ARRAY['species'::text, 'trap'::text]))),
    CONSTRAINT vv_library_versions_review_note_check CHECK ((char_length(review_note) <= 2000)),
    CONSTRAINT vv_library_versions_sources_check CHECK ((jsonb_typeof(sources) = 'array'::text)),
    CONSTRAINT vv_library_versions_version_check CHECK ((version > 0))
);

CREATE TABLE public.vv_notifications (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    incursion_id uuid NOT NULL,
    kind text NOT NULL,
    contact_id uuid,
    recipient text NOT NULL,
    method text NOT NULL,
    notified_at timestamp with time zone NOT NULL,
    reference text,
    note text,
    recorded_by uuid NOT NULL,
    recorded_role text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_notifications_kind_check CHECK ((kind = ANY (ARRAY['ukhsa'::text, 'port_health'::text, 'apha'::text, 'internal'::text, 'other'::text]))),
    CONSTRAINT vv_notifications_method_check CHECK ((method = ANY (ARRAY['phone'::text, 'email'::text, 'letter'::text, 'meeting'::text, 'other'::text]))),
    CONSTRAINT vv_notifications_note_check CHECK ((char_length(note) <= 2000)),
    CONSTRAINT vv_notifications_recipient_check CHECK (((char_length(recipient) >= 2) AND (char_length(recipient) <= 200))),
    CONSTRAINT vv_notifications_reference_check CHECK ((char_length(reference) <= 120))
);

CREATE TABLE public.vv_notify_contacts (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    organisation text,
    kind text NOT NULL,
    detail text,
    active boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_notify_contacts_detail_check CHECK ((char_length(detail) <= 500)),
    CONSTRAINT vv_notify_contacts_kind_check CHECK ((kind = ANY (ARRAY['ukhsa'::text, 'port_health'::text, 'apha'::text, 'internal'::text, 'other'::text]))),
    CONSTRAINT vv_notify_contacts_name_check CHECK (((char_length(name) >= 2) AND (char_length(name) <= 200))),
    CONSTRAINT vv_notify_contacts_organisation_check CHECK ((char_length(organisation) <= 200))
);

CREATE TABLE public.vv_programme_teams (
    programme_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    team_id uuid NOT NULL
);

CREATE TABLE public.vv_programmes (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    vector_group text DEFAULT 'mosquito'::text NOT NULL,
    description text,
    status text DEFAULT 'active'::text NOT NULL,
    starts_on date,
    ends_on date,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_programmes_check CHECK (((ends_on IS NULL) OR (starts_on IS NULL) OR (ends_on >= starts_on))),
    CONSTRAINT vv_programmes_description_check CHECK ((char_length(description) <= 2000)),
    CONSTRAINT vv_programmes_name_check CHECK (((char_length(name) >= 3) AND (char_length(name) <= 120))),
    CONSTRAINT vv_programmes_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'closed'::text]))),
    CONSTRAINT vv_programmes_vector_group_check CHECK ((vector_group = 'mosquito'::text))
);

CREATE TABLE public.vv_result_versions (
    result_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    version integer NOT NULL,
    status text NOT NULL,
    taxon_id uuid,
    council_taxon_id uuid,
    quantity numeric,
    unit text,
    method text,
    identified_by text,
    laboratory text,
    lab_reference text,
    result_date date,
    uncertainty text,
    reason text,
    author_id uuid NOT NULL,
    author_role text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_result_versions_check CHECK (((taxon_id IS NULL) OR (council_taxon_id IS NULL))),
    CONSTRAINT vv_result_versions_check1 CHECK (((status <> ALL (ARRAY['provisional'::text, 'confirmed'::text])) OR (taxon_id IS NOT NULL) OR (council_taxon_id IS NOT NULL))),
    CONSTRAINT vv_result_versions_check2 CHECK (((version = 1) OR (char_length(TRIM(BOTH FROM COALESCE(reason, ''::text))) >= 5))),
    CONSTRAINT vv_result_versions_identified_by_check CHECK ((char_length(identified_by) <= 200)),
    CONSTRAINT vv_result_versions_lab_reference_check CHECK ((char_length(lab_reference) <= 100)),
    CONSTRAINT vv_result_versions_laboratory_check CHECK ((char_length(laboratory) <= 200)),
    CONSTRAINT vv_result_versions_method_check CHECK ((method = ANY (ARRAY['morphology'::text, 'molecular'::text, 'other'::text]))),
    CONSTRAINT vv_result_versions_quantity_check CHECK (((quantity IS NULL) OR (quantity >= (0)::numeric))),
    CONSTRAINT vv_result_versions_reason_check CHECK ((char_length(reason) <= 500)),
    CONSTRAINT vv_result_versions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'provisional'::text, 'confirmed'::text, 'inconclusive'::text]))),
    CONSTRAINT vv_result_versions_uncertainty_check CHECK ((char_length(uncertainty) <= 1000)),
    CONSTRAINT vv_result_versions_unit_check CHECK ((unit = ANY (ARRAY['individuals'::text, 'females'::text, 'males'::text, 'eggs'::text, 'larvae'::text, 'pupae'::text, 'presence'::text]))),
    CONSTRAINT vv_result_versions_version_check CHECK ((version > 0))
);

CREATE TABLE public.vv_results (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    sample_id uuid NOT NULL,
    site_id uuid NOT NULL,
    current_version integer DEFAULT 1 NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.vv_samples (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    visit_id uuid NOT NULL,
    site_id uuid NOT NULL,
    reference text NOT NULL,
    method text NOT NULL,
    notes text,
    status text DEFAULT 'awaiting_result'::text NOT NULL,
    created_by uuid NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_samples_method_check CHECK ((method = ANY (ARRAY['adult_trap_catch'::text, 'egg_paper'::text, 'larvae'::text, 'pupae'::text, 'other'::text]))),
    CONSTRAINT vv_samples_notes_check CHECK ((char_length(notes) <= 1000)),
    CONSTRAINT vv_samples_reference_check CHECK (((char_length(reference) >= 1) AND (char_length(reference) <= 60))),
    CONSTRAINT vv_samples_status_check CHECK ((status = ANY (ARRAY['awaiting_result'::text, 'resulted'::text])))
);

CREATE TABLE public.vv_site_programmes (
    site_id uuid NOT NULL,
    programme_id uuid NOT NULL,
    workspace_id uuid NOT NULL
);

CREATE TABLE public.vv_sites (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    reference text NOT NULL,
    name text NOT NULL,
    line_1 text,
    line_2 text,
    town text,
    postcode text,
    uprn text,
    latitude double precision,
    longitude double precision,
    location_description text,
    access_instructions text,
    status text DEFAULT 'active'::text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_sites_access_instructions_check CHECK ((char_length(access_instructions) <= 2000)),
    CONSTRAINT vv_sites_check CHECK (((latitude IS NULL) = (longitude IS NULL))),
    CONSTRAINT vv_sites_check1 CHECK (((latitude IS NOT NULL) OR (line_1 IS NOT NULL) OR (location_description IS NOT NULL))),
    CONSTRAINT vv_sites_latitude_check CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
    CONSTRAINT vv_sites_line_1_check CHECK ((char_length(line_1) <= 200)),
    CONSTRAINT vv_sites_line_2_check CHECK ((char_length(line_2) <= 200)),
    CONSTRAINT vv_sites_location_description_check CHECK ((char_length(location_description) <= 2000)),
    CONSTRAINT vv_sites_longitude_check CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))),
    CONSTRAINT vv_sites_name_check CHECK (((char_length(name) >= 2) AND (char_length(name) <= 120))),
    CONSTRAINT vv_sites_postcode_check CHECK ((char_length(postcode) <= 10)),
    CONSTRAINT vv_sites_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text]))),
    CONSTRAINT vv_sites_town_check CHECK ((char_length(town) <= 100)),
    CONSTRAINT vv_sites_uprn_check CHECK ((uprn ~ '^[0-9]{1,12}$'::text))
);

CREATE TABLE public.vv_stand_downs (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    incursion_id uuid NOT NULL,
    kind text NOT NULL,
    decided_at timestamp with time zone NOT NULL,
    rationale text NOT NULL,
    decided_by uuid NOT NULL,
    decided_role text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_stand_downs_kind_check CHECK ((kind = ANY (ARRAY['stand_down'::text, 'reopen'::text]))),
    CONSTRAINT vv_stand_downs_rationale_check CHECK (((char_length(rationale) >= 10) AND (char_length(rationale) <= 4000)))
);

CREATE TABLE public.vv_taxa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    scientific_name text NOT NULL,
    common_name text,
    vector_group text DEFAULT 'mosquito'::text NOT NULL,
    invasive boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    CONSTRAINT vv_taxa_common_name_check CHECK ((char_length(common_name) <= 120)),
    CONSTRAINT vv_taxa_key_check CHECK ((key ~ '^[a-z0-9_]{3,60}$'::text)),
    CONSTRAINT vv_taxa_scientific_name_check CHECK (((char_length(scientific_name) >= 3) AND (char_length(scientific_name) <= 120))),
    CONSTRAINT vv_taxa_vector_group_check CHECK ((vector_group = 'mosquito'::text))
);

CREATE TABLE public.vv_trap_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    name text NOT NULL,
    description text,
    vector_group text DEFAULT 'mosquito'::text NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    CONSTRAINT vv_trap_types_description_check CHECK ((char_length(description) <= 500)),
    CONSTRAINT vv_trap_types_key_check CHECK ((key ~ '^[a-z0-9_]{3,60}$'::text)),
    CONSTRAINT vv_trap_types_name_check CHECK (((char_length(name) >= 3) AND (char_length(name) <= 120))),
    CONSTRAINT vv_trap_types_vector_group_check CHECK ((vector_group = 'mosquito'::text))
);

CREATE TABLE public.vv_traps (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    identifier text NOT NULL,
    trap_type_id uuid,
    council_trap_type_id uuid,
    status text DEFAULT 'available'::text NOT NULL,
    notes text,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vv_traps_check CHECK (((trap_type_id IS NULL) <> (council_trap_type_id IS NULL))),
    CONSTRAINT vv_traps_identifier_check CHECK (((char_length(identifier) >= 1) AND (char_length(identifier) <= 60))),
    CONSTRAINT vv_traps_notes_check CHECK ((char_length(notes) <= 2000)),
    CONSTRAINT vv_traps_status_check CHECK ((status = ANY (ARRAY['available'::text, 'deployed'::text, 'damaged'::text, 'retired'::text])))
);

CREATE TABLE public.vv_visits (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    deployment_id uuid NOT NULL,
    site_id uuid NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    officer_id uuid NOT NULL,
    outcome text NOT NULL,
    not_completed_reason text,
    trap_condition text NOT NULL,
    observations text,
    exposure_started_at timestamp with time zone,
    exposure_ended_at timestamp with time zone,
    created_by uuid NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone,
    CONSTRAINT vv_visits_check CHECK (((outcome <> 'not_completed'::text) OR (char_length(TRIM(BOTH FROM COALESCE(not_completed_reason, ''::text))) >= 3))),
    CONSTRAINT vv_visits_check1 CHECK (((exposure_ended_at IS NULL) OR (exposure_started_at IS NULL) OR (exposure_ended_at >= exposure_started_at))),
    CONSTRAINT vv_visits_not_completed_reason_check CHECK ((char_length(not_completed_reason) <= 1000)),
    CONSTRAINT vv_visits_observations_check CHECK ((char_length(observations) <= 4000)),
    CONSTRAINT vv_visits_outcome_check CHECK ((outcome = ANY (ARRAY['collected'::text, 'no_catch'::text, 'not_completed'::text]))),
    CONSTRAINT vv_visits_trap_condition_check CHECK ((trap_condition = ANY (ARRAY['working'::text, 'not_working'::text, 'damaged'::text, 'missing'::text])))
);

CREATE TABLE public.vv_workspace_settings (
    workspace_id uuid NOT NULL,
    site_prefix text DEFAULT 'VS'::text NOT NULL,
    next_site_no integer DEFAULT 1 NOT NULL,
    next_sample_no integer DEFAULT 1 NOT NULL,
    next_incursion_no integer DEFAULT 1 NOT NULL,
    CONSTRAINT vv_workspace_settings_next_incursion_no_check CHECK ((next_incursion_no > 0)),
    CONSTRAINT vv_workspace_settings_next_sample_no_check CHECK ((next_sample_no > 0)),
    CONSTRAINT vv_workspace_settings_next_site_no_check CHECK ((next_site_no > 0)),
    CONSTRAINT vv_workspace_settings_site_prefix_check CHECK ((site_prefix ~ '^[A-Z0-9]{1,8}$'::text))
);

CREATE TABLE public.workspace_invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    email text NOT NULL,
    role public.workspace_role NOT NULL,
    invited_by uuid,
    token_hash text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    accepted_at timestamp with time zone,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT workspace_invitations_email_check CHECK ((email = lower(email))),
    CONSTRAINT workspace_invitations_role_check CHECK ((role <> 'owner'::public.workspace_role))
);

CREATE TABLE public.workspace_members (
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role public.workspace_role NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.workspace_product_events (
    id bigint NOT NULL,
    workspace_id uuid NOT NULL,
    product text NOT NULL,
    enabled boolean NOT NULL,
    actor_id uuid,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.workspace_product_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.workspace_product_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public.workspace_products (
    workspace_id uuid NOT NULL,
    product text NOT NULL,
    enabled boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT workspace_products_product_check CHECK ((product = ANY (ARRAY['investigations'::text, 'vectovia'::text])))
);

CREATE TABLE public.workspaces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind public.workspace_kind NOT NULL,
    name text NOT NULL,
    personal_owner_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT workspaces_check CHECK (((kind = 'personal'::public.workspace_kind) = (personal_owner_id IS NOT NULL))),
    CONSTRAINT workspaces_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 120)))
);

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.content_roles
    ADD CONSTRAINT content_roles_pkey PRIMARY KEY (user_id, role);

ALTER TABLE ONLY public.invitation_emails
    ADD CONSTRAINT invitation_emails_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_admins
    ADD CONSTRAINT platform_admins_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY public.product_access
    ADD CONSTRAINT product_access_pkey PRIMARY KEY (workspace_id, user_id, product);

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (team_id, user_id);

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_workspace_id_name_key UNIQUE (workspace_id, name);

ALTER TABLE ONLY public.vv_actions
    ADD CONSTRAINT vv_actions_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_actions
    ADD CONSTRAINT vv_actions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_assessment_results
    ADD CONSTRAINT vv_assessment_results_pkey PRIMARY KEY (assessment_id, result_id);

ALTER TABLE ONLY public.vv_assessment_versions
    ADD CONSTRAINT vv_assessment_versions_pkey PRIMARY KEY (assessment_id, version);

ALTER TABLE ONLY public.vv_assessments
    ADD CONSTRAINT vv_assessments_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_assessments
    ADD CONSTRAINT vv_assessments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_attachment_events
    ADD CONSTRAINT vv_attachment_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_attachments
    ADD CONSTRAINT vv_attachments_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_attachments
    ADD CONSTRAINT vv_attachments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_attachments
    ADD CONSTRAINT vv_attachments_storage_path_key UNIQUE (storage_path);

ALTER TABLE ONLY public.vv_council_taxa
    ADD CONSTRAINT vv_council_taxa_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_council_taxa
    ADD CONSTRAINT vv_council_taxa_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_council_trap_types
    ADD CONSTRAINT vv_council_trap_types_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_council_trap_types
    ADD CONSTRAINT vv_council_trap_types_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_deployments
    ADD CONSTRAINT vv_deployments_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_deployments
    ADD CONSTRAINT vv_deployments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_events
    ADD CONSTRAINT vv_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_exports
    ADD CONSTRAINT vv_exports_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_external_refs
    ADD CONSTRAINT vv_external_refs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_incursion_findings
    ADD CONSTRAINT vv_incursion_findings_pkey PRIMARY KEY (incursion_id, result_id);

ALTER TABLE ONLY public.vv_incursion_sites
    ADD CONSTRAINT vv_incursion_sites_pkey PRIMARY KEY (incursion_id, site_id);

ALTER TABLE ONLY public.vv_incursion_steps
    ADD CONSTRAINT vv_incursion_steps_pkey PRIMARY KEY (incursion_id, step_key);

ALTER TABLE ONLY public.vv_incursions
    ADD CONSTRAINT vv_incursions_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_incursions
    ADD CONSTRAINT vv_incursions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_incursions
    ADD CONSTRAINT vv_incursions_workspace_id_reference_key UNIQUE (workspace_id, reference);

ALTER TABLE ONLY public.vv_library_images
    ADD CONSTRAINT vv_library_images_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_library_images
    ADD CONSTRAINT vv_library_images_storage_path_key UNIQUE (storage_path);

ALTER TABLE ONLY public.vv_library_notes
    ADD CONSTRAINT vv_library_notes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_library_versions
    ADD CONSTRAINT vv_library_versions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_library_versions
    ADD CONSTRAINT vv_library_versions_taxon_id_version_key UNIQUE (taxon_id, version);

ALTER TABLE ONLY public.vv_library_versions
    ADD CONSTRAINT vv_library_versions_trap_type_id_version_key UNIQUE (trap_type_id, version);

ALTER TABLE ONLY public.vv_notifications
    ADD CONSTRAINT vv_notifications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_notify_contacts
    ADD CONSTRAINT vv_notify_contacts_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_notify_contacts
    ADD CONSTRAINT vv_notify_contacts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_programme_teams
    ADD CONSTRAINT vv_programme_teams_pkey PRIMARY KEY (programme_id, team_id);

ALTER TABLE ONLY public.vv_programmes
    ADD CONSTRAINT vv_programmes_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_programmes
    ADD CONSTRAINT vv_programmes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_programmes
    ADD CONSTRAINT vv_programmes_workspace_id_name_key UNIQUE (workspace_id, name);

ALTER TABLE ONLY public.vv_result_versions
    ADD CONSTRAINT vv_result_versions_pkey PRIMARY KEY (result_id, version);

ALTER TABLE ONLY public.vv_results
    ADD CONSTRAINT vv_results_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_results
    ADD CONSTRAINT vv_results_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_samples
    ADD CONSTRAINT vv_samples_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_samples
    ADD CONSTRAINT vv_samples_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_samples
    ADD CONSTRAINT vv_samples_workspace_id_reference_key UNIQUE (workspace_id, reference);

ALTER TABLE ONLY public.vv_site_programmes
    ADD CONSTRAINT vv_site_programmes_pkey PRIMARY KEY (site_id, programme_id);

ALTER TABLE ONLY public.vv_sites
    ADD CONSTRAINT vv_sites_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_sites
    ADD CONSTRAINT vv_sites_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_sites
    ADD CONSTRAINT vv_sites_workspace_id_reference_key UNIQUE (workspace_id, reference);

ALTER TABLE ONLY public.vv_stand_downs
    ADD CONSTRAINT vv_stand_downs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_taxa
    ADD CONSTRAINT vv_taxa_key_key UNIQUE (key);

ALTER TABLE ONLY public.vv_taxa
    ADD CONSTRAINT vv_taxa_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_trap_types
    ADD CONSTRAINT vv_trap_types_key_key UNIQUE (key);

ALTER TABLE ONLY public.vv_trap_types
    ADD CONSTRAINT vv_trap_types_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_traps
    ADD CONSTRAINT vv_traps_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_traps
    ADD CONSTRAINT vv_traps_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_traps
    ADD CONSTRAINT vv_traps_workspace_id_identifier_key UNIQUE (workspace_id, identifier);

ALTER TABLE ONLY public.vv_visits
    ADD CONSTRAINT vv_visits_id_workspace_id_key UNIQUE (id, workspace_id);

ALTER TABLE ONLY public.vv_visits
    ADD CONSTRAINT vv_visits_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.vv_workspace_settings
    ADD CONSTRAINT vv_workspace_settings_pkey PRIMARY KEY (workspace_id);

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_token_hash_key UNIQUE (token_hash);

ALTER TABLE ONLY public.workspace_members
    ADD CONSTRAINT workspace_members_pkey PRIMARY KEY (workspace_id, user_id);

ALTER TABLE ONLY public.workspace_product_events
    ADD CONSTRAINT workspace_product_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.workspace_products
    ADD CONSTRAINT workspace_products_pkey PRIMARY KEY (workspace_id, product);

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_personal_owner_id_key UNIQUE (personal_owner_id);

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_pkey PRIMARY KEY (id);

CREATE INDEX invitation_emails_inv_idx ON public.invitation_emails USING btree (invitation_id, created_at);

CREATE INDEX invitation_emails_ws_idx ON public.invitation_emails USING btree (workspace_id, created_at);

CREATE INDEX team_members_user_idx ON public.team_members USING btree (user_id);

CREATE INDEX vv_actions_owner_idx ON public.vv_actions USING btree (workspace_id, owner_id, status);

CREATE INDEX vv_attachment_events_idx ON public.vv_attachment_events USING btree (attachment_id, recorded_at);

CREATE INDEX vv_attachments_record_idx ON public.vv_attachments USING btree (record_type, record_id);

CREATE UNIQUE INDEX vv_deployments_one_active ON public.vv_deployments USING btree (trap_id) WHERE (ended_at IS NULL);

CREATE INDEX vv_deployments_site_idx ON public.vv_deployments USING btree (site_id, started_at DESC);

CREATE INDEX vv_events_record_idx ON public.vv_events USING btree (record_type, record_id, recorded_at);

CREATE INDEX vv_exports_ws_idx ON public.vv_exports USING btree (workspace_id, created_at DESC);

CREATE UNIQUE INDEX vv_external_refs_active ON public.vv_external_refs USING btree (workspace_id, record_type, lower(system), external_id) WHERE (removed_at IS NULL);

CREATE UNIQUE INDEX vv_library_one_published_species ON public.vv_library_versions USING btree (taxon_id) WHERE (status = 'published'::public.kp_status);

CREATE UNIQUE INDEX vv_library_one_published_trap ON public.vv_library_versions USING btree (trap_type_id) WHERE (status = 'published'::public.kp_status);

CREATE INDEX vv_results_sample_idx ON public.vv_results USING btree (sample_id);

CREATE INDEX vv_samples_visit_idx ON public.vv_samples USING btree (visit_id);

CREATE INDEX vv_visits_deployment_idx ON public.vv_visits USING btree (deployment_id, occurred_at DESC);

CREATE INDEX workspace_members_user_idx ON public.workspace_members USING btree (user_id);

CREATE TRIGGER audit_append_only BEFORE DELETE OR UPDATE ON public.audit_events FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER invitation_emails_append_only BEFORE UPDATE ON public.invitation_emails FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER members_guard BEFORE INSERT OR DELETE OR UPDATE ON public.workspace_members FOR EACH ROW EXECUTE FUNCTION public.guard_membership();

CREATE TRIGGER profiles_touch BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TRIGGER vv_actions_immutable BEFORE UPDATE ON public.vv_actions FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'site_id', 'assessment_id', 'incursion_id', 'step_key', 'created_by', 'created_at');

CREATE TRIGGER vv_actions_no_delete BEFORE DELETE ON public.vv_actions FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_assessment_results_append_only BEFORE DELETE OR UPDATE ON public.vv_assessment_results FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_assessment_versions_append_only BEFORE DELETE OR UPDATE ON public.vv_assessment_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_assessments_immutable BEFORE UPDATE ON public.vv_assessments FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'site_id', 'created_by', 'created_at');

CREATE TRIGGER vv_assessments_no_delete BEFORE DELETE ON public.vv_assessments FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_attachment_events_append_only BEFORE DELETE OR UPDATE ON public.vv_attachment_events FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_attachments_immutable BEFORE UPDATE ON public.vv_attachments FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'record_type', 'record_id', 'site_id', 'kind', 'file_name', 'mime_type', 'size_bytes', 'sha256_reported', 'storage_path', 'derived_from', 'uploaded_by', 'uploaded_role', 'received_at');

CREATE TRIGGER vv_attachments_no_delete BEFORE DELETE ON public.vv_attachments FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_deployments_immutable BEFORE UPDATE ON public.vv_deployments FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'trap_id', 'site_id', 'started_at', 'created_by', 'recorded_at');

CREATE TRIGGER vv_deployments_no_delete BEFORE DELETE ON public.vv_deployments FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_events_append_only BEFORE DELETE OR UPDATE ON public.vv_events FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_exports_append_only BEFORE DELETE OR UPDATE ON public.vv_exports FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_external_refs_immutable BEFORE UPDATE ON public.vv_external_refs FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'record_type', 'record_id', 'system', 'external_id', 'note', 'created_by', 'created_at');

CREATE TRIGGER vv_external_refs_no_delete BEFORE DELETE ON public.vv_external_refs FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_incursion_findings_append_only BEFORE DELETE OR UPDATE ON public.vv_incursion_findings FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_incursion_sites_append_only BEFORE DELETE OR UPDATE ON public.vv_incursion_sites FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_incursion_steps_immutable BEFORE UPDATE ON public.vv_incursion_steps FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('incursion_id', 'workspace_id', 'step_key', 'sort_order');

CREATE TRIGGER vv_incursion_steps_no_delete BEFORE DELETE ON public.vv_incursion_steps FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_incursions_immutable BEFORE UPDATE ON public.vv_incursions FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'reference', 'site_id', 'opened_at', 'created_by', 'created_at');

CREATE TRIGGER vv_incursions_no_delete BEFORE DELETE ON public.vv_incursions FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_library_images_no_change BEFORE DELETE OR UPDATE ON public.vv_library_images FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_library_versions_guard BEFORE UPDATE ON public.vv_library_versions FOR EACH ROW EXECUTE FUNCTION public.kp_guard_version();

CREATE TRIGGER vv_library_versions_no_delete BEFORE DELETE ON public.vv_library_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_notifications_append_only BEFORE DELETE OR UPDATE ON public.vv_notifications FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_notify_contacts_immutable BEFORE UPDATE ON public.vv_notify_contacts FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'created_by', 'created_at');

CREATE TRIGGER vv_notify_contacts_no_delete BEFORE DELETE ON public.vv_notify_contacts FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_programmes_immutable BEFORE UPDATE ON public.vv_programmes FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'created_by', 'created_at');

CREATE TRIGGER vv_programmes_no_delete BEFORE DELETE ON public.vv_programmes FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_result_versions_append_only BEFORE DELETE OR UPDATE ON public.vv_result_versions FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_results_immutable BEFORE UPDATE ON public.vv_results FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'sample_id', 'site_id', 'created_by', 'created_at');

CREATE TRIGGER vv_results_no_delete BEFORE DELETE ON public.vv_results FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_samples_immutable BEFORE UPDATE ON public.vv_samples FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'visit_id', 'site_id', 'reference', 'created_by', 'recorded_at');

CREATE TRIGGER vv_samples_no_delete BEFORE DELETE ON public.vv_samples FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_sites_immutable BEFORE UPDATE ON public.vv_sites FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'reference', 'created_by', 'created_at');

CREATE TRIGGER vv_sites_no_delete BEFORE DELETE ON public.vv_sites FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_stand_downs_append_only BEFORE DELETE OR UPDATE ON public.vv_stand_downs FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_traps_immutable BEFORE UPDATE ON public.vv_traps FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'created_by', 'created_at');

CREATE TRIGGER vv_traps_no_delete BEFORE DELETE ON public.vv_traps FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER vv_visits_immutable BEFORE UPDATE ON public.vv_visits FOR EACH ROW EXECUTE FUNCTION public.guard_immutable('id', 'workspace_id', 'deployment_id', 'site_id', 'outcome', 'created_by', 'recorded_at');

CREATE TRIGGER vv_visits_no_delete BEFORE DELETE ON public.vv_visits FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER workspace_product_events_append_only BEFORE DELETE OR UPDATE ON public.workspace_product_events FOR EACH ROW EXECUTE FUNCTION public.forbid_update();

CREATE TRIGGER workspaces_default_products AFTER INSERT ON public.workspaces FOR EACH ROW EXECUTE FUNCTION public.default_workspace_products();

ALTER TABLE ONLY public.content_roles
    ADD CONSTRAINT content_roles_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.content_roles
    ADD CONSTRAINT content_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.invitation_emails
    ADD CONSTRAINT invitation_emails_invitation_id_fkey FOREIGN KEY (invitation_id) REFERENCES public.workspace_invitations(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.invitation_emails
    ADD CONSTRAINT invitation_emails_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.platform_admins
    ADD CONSTRAINT platform_admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.product_access
    ADD CONSTRAINT product_access_workspace_id_user_id_fkey FOREIGN KEY (workspace_id, user_id) REFERENCES public.workspace_members(workspace_id, user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_team_id_workspace_id_fkey FOREIGN KEY (team_id, workspace_id) REFERENCES public.teams(id, workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_workspace_id_user_id_fkey FOREIGN KEY (workspace_id, user_id) REFERENCES public.workspace_members(workspace_id, user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_actions
    ADD CONSTRAINT vv_actions_assessment_id_workspace_id_fkey FOREIGN KEY (assessment_id, workspace_id) REFERENCES public.vv_assessments(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_actions
    ADD CONSTRAINT vv_actions_incursion_fk FOREIGN KEY (incursion_id, workspace_id) REFERENCES public.vv_incursions(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_actions
    ADD CONSTRAINT vv_actions_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_actions
    ADD CONSTRAINT vv_actions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_actions
    ADD CONSTRAINT vv_actions_workspace_id_owner_id_fkey FOREIGN KEY (workspace_id, owner_id) REFERENCES public.workspace_members(workspace_id, user_id) ON DELETE SET NULL (owner_id);

ALTER TABLE ONLY public.vv_assessment_results
    ADD CONSTRAINT vv_assessment_results_assessment_id_workspace_id_fkey FOREIGN KEY (assessment_id, workspace_id) REFERENCES public.vv_assessments(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_assessment_results
    ADD CONSTRAINT vv_assessment_results_result_id_workspace_id_fkey FOREIGN KEY (result_id, workspace_id) REFERENCES public.vv_results(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_assessment_versions
    ADD CONSTRAINT vv_assessment_versions_assessment_id_workspace_id_fkey FOREIGN KEY (assessment_id, workspace_id) REFERENCES public.vv_assessments(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_assessments
    ADD CONSTRAINT vv_assessments_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_assessments
    ADD CONSTRAINT vv_assessments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_attachment_events
    ADD CONSTRAINT vv_attachment_events_attachment_id_workspace_id_fkey FOREIGN KEY (attachment_id, workspace_id) REFERENCES public.vv_attachments(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_attachments
    ADD CONSTRAINT vv_attachments_derived_from_fkey FOREIGN KEY (derived_from) REFERENCES public.vv_attachments(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_attachments
    ADD CONSTRAINT vv_attachments_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_attachments
    ADD CONSTRAINT vv_attachments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_council_taxa
    ADD CONSTRAINT vv_council_taxa_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_council_trap_types
    ADD CONSTRAINT vv_council_trap_types_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_deployments
    ADD CONSTRAINT vv_deployments_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_deployments
    ADD CONSTRAINT vv_deployments_trap_id_workspace_id_fkey FOREIGN KEY (trap_id, workspace_id) REFERENCES public.vv_traps(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_deployments
    ADD CONSTRAINT vv_deployments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_deployments
    ADD CONSTRAINT vv_deployments_workspace_id_responsible_officer_fkey FOREIGN KEY (workspace_id, responsible_officer) REFERENCES public.workspace_members(workspace_id, user_id) ON DELETE SET NULL (responsible_officer);

ALTER TABLE ONLY public.vv_events
    ADD CONSTRAINT vv_events_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_exports
    ADD CONSTRAINT vv_exports_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_external_refs
    ADD CONSTRAINT vv_external_refs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursion_findings
    ADD CONSTRAINT vv_incursion_findings_incursion_id_workspace_id_fkey FOREIGN KEY (incursion_id, workspace_id) REFERENCES public.vv_incursions(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursion_findings
    ADD CONSTRAINT vv_incursion_findings_result_id_workspace_id_fkey FOREIGN KEY (result_id, workspace_id) REFERENCES public.vv_results(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursion_sites
    ADD CONSTRAINT vv_incursion_sites_incursion_id_workspace_id_fkey FOREIGN KEY (incursion_id, workspace_id) REFERENCES public.vv_incursions(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursion_sites
    ADD CONSTRAINT vv_incursion_sites_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursion_steps
    ADD CONSTRAINT vv_incursion_steps_incursion_id_workspace_id_fkey FOREIGN KEY (incursion_id, workspace_id) REFERENCES public.vv_incursions(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursions
    ADD CONSTRAINT vv_incursions_council_taxon_id_workspace_id_fkey FOREIGN KEY (council_taxon_id, workspace_id) REFERENCES public.vv_council_taxa(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursions
    ADD CONSTRAINT vv_incursions_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursions
    ADD CONSTRAINT vv_incursions_taxon_id_fkey FOREIGN KEY (taxon_id) REFERENCES public.vv_taxa(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursions
    ADD CONSTRAINT vv_incursions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_incursions
    ADD CONSTRAINT vv_incursions_workspace_id_lead_officer_id_fkey FOREIGN KEY (workspace_id, lead_officer_id) REFERENCES public.workspace_members(workspace_id, user_id) ON DELETE SET NULL (lead_officer_id);

ALTER TABLE ONLY public.vv_library_images
    ADD CONSTRAINT vv_library_images_version_id_fkey FOREIGN KEY (version_id) REFERENCES public.vv_library_versions(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_library_notes
    ADD CONSTRAINT vv_library_notes_taxon_id_fkey FOREIGN KEY (taxon_id) REFERENCES public.vv_taxa(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_library_notes
    ADD CONSTRAINT vv_library_notes_trap_type_id_fkey FOREIGN KEY (trap_type_id) REFERENCES public.vv_trap_types(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_library_notes
    ADD CONSTRAINT vv_library_notes_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_library_versions
    ADD CONSTRAINT vv_library_versions_taxon_id_fkey FOREIGN KEY (taxon_id) REFERENCES public.vv_taxa(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_library_versions
    ADD CONSTRAINT vv_library_versions_trap_type_id_fkey FOREIGN KEY (trap_type_id) REFERENCES public.vv_trap_types(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_notifications
    ADD CONSTRAINT vv_notifications_contact_id_workspace_id_fkey FOREIGN KEY (contact_id, workspace_id) REFERENCES public.vv_notify_contacts(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_notifications
    ADD CONSTRAINT vv_notifications_incursion_id_workspace_id_fkey FOREIGN KEY (incursion_id, workspace_id) REFERENCES public.vv_incursions(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_notify_contacts
    ADD CONSTRAINT vv_notify_contacts_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_programme_teams
    ADD CONSTRAINT vv_programme_teams_programme_id_workspace_id_fkey FOREIGN KEY (programme_id, workspace_id) REFERENCES public.vv_programmes(id, workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.vv_programme_teams
    ADD CONSTRAINT vv_programme_teams_team_id_workspace_id_fkey FOREIGN KEY (team_id, workspace_id) REFERENCES public.teams(id, workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.vv_programmes
    ADD CONSTRAINT vv_programmes_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_result_versions
    ADD CONSTRAINT vv_result_versions_council_taxon_id_workspace_id_fkey FOREIGN KEY (council_taxon_id, workspace_id) REFERENCES public.vv_council_taxa(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_result_versions
    ADD CONSTRAINT vv_result_versions_result_id_workspace_id_fkey FOREIGN KEY (result_id, workspace_id) REFERENCES public.vv_results(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_result_versions
    ADD CONSTRAINT vv_result_versions_taxon_id_fkey FOREIGN KEY (taxon_id) REFERENCES public.vv_taxa(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_results
    ADD CONSTRAINT vv_results_sample_id_workspace_id_fkey FOREIGN KEY (sample_id, workspace_id) REFERENCES public.vv_samples(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_results
    ADD CONSTRAINT vv_results_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_results
    ADD CONSTRAINT vv_results_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_samples
    ADD CONSTRAINT vv_samples_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_samples
    ADD CONSTRAINT vv_samples_visit_id_workspace_id_fkey FOREIGN KEY (visit_id, workspace_id) REFERENCES public.vv_visits(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_samples
    ADD CONSTRAINT vv_samples_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_site_programmes
    ADD CONSTRAINT vv_site_programmes_programme_id_workspace_id_fkey FOREIGN KEY (programme_id, workspace_id) REFERENCES public.vv_programmes(id, workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.vv_site_programmes
    ADD CONSTRAINT vv_site_programmes_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.vv_sites
    ADD CONSTRAINT vv_sites_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_stand_downs
    ADD CONSTRAINT vv_stand_downs_incursion_id_workspace_id_fkey FOREIGN KEY (incursion_id, workspace_id) REFERENCES public.vv_incursions(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_traps
    ADD CONSTRAINT vv_traps_council_trap_type_id_workspace_id_fkey FOREIGN KEY (council_trap_type_id, workspace_id) REFERENCES public.vv_council_trap_types(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_traps
    ADD CONSTRAINT vv_traps_trap_type_id_fkey FOREIGN KEY (trap_type_id) REFERENCES public.vv_trap_types(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_traps
    ADD CONSTRAINT vv_traps_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_visits
    ADD CONSTRAINT vv_visits_deployment_id_workspace_id_fkey FOREIGN KEY (deployment_id, workspace_id) REFERENCES public.vv_deployments(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_visits
    ADD CONSTRAINT vv_visits_site_id_workspace_id_fkey FOREIGN KEY (site_id, workspace_id) REFERENCES public.vv_sites(id, workspace_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_visits
    ADD CONSTRAINT vv_visits_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.vv_workspace_settings
    ADD CONSTRAINT vv_workspace_settings_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.workspace_members
    ADD CONSTRAINT workspace_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.workspace_members
    ADD CONSTRAINT workspace_members_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.workspace_product_events
    ADD CONSTRAINT workspace_product_events_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.workspace_products
    ADD CONSTRAINT workspace_products_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_personal_owner_id_fkey FOREIGN KEY (personal_owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_read ON public.audit_events FOR SELECT TO authenticated USING (public.has_ws_role(workspace_id, ARRAY['owner'::public.workspace_role, 'admin'::public.workspace_role]));

ALTER TABLE public.content_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY content_roles_read ON public.content_roles FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.has_content_role(ARRAY['content_admin'::public.content_role])));

ALTER TABLE public.invitation_emails ENABLE ROW LEVEL SECURITY;

CREATE POLICY invitation_emails_read ON public.invitation_emails FOR SELECT TO authenticated USING (public.has_ws_role(workspace_id, ARRAY['owner'::public.workspace_role, 'admin'::public.workspace_role]));

CREATE POLICY invites_read ON public.workspace_invitations FOR SELECT TO authenticated USING (public.has_ws_role(workspace_id, ARRAY['owner'::public.workspace_role, 'admin'::public.workspace_role]));

CREATE POLICY members_read ON public.workspace_members FOR SELECT TO authenticated USING (public.is_member(workspace_id));

ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;

CREATE POLICY platform_admins_self ON public.platform_admins FOR SELECT TO authenticated USING ((user_id = auth.uid()));

ALTER TABLE public.product_access ENABLE ROW LEVEL SECURITY;

CREATE POLICY product_access_read ON public.product_access FOR SELECT TO authenticated USING (public.is_member(workspace_id));

CREATE POLICY profile_read ON public.profiles FOR SELECT TO authenticated USING ((id = auth.uid()));

CREATE POLICY profile_update ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY team_members_read ON public.team_members FOR SELECT TO authenticated USING (public.is_member(workspace_id));

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY teams_read ON public.teams FOR SELECT TO authenticated USING (public.is_member(workspace_id));

ALTER TABLE public.vv_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_actions_read ON public.vv_actions FOR SELECT TO authenticated USING (public.vv_can_see_site(site_id));

ALTER TABLE public.vv_assessment_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_assessment_results_read ON public.vv_assessment_results FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.vv_assessments a
  WHERE (a.id = vv_assessment_results.assessment_id))));

ALTER TABLE public.vv_assessment_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_assessment_versions_read ON public.vv_assessment_versions FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.vv_assessments a
  WHERE (a.id = vv_assessment_versions.assessment_id))));

ALTER TABLE public.vv_assessments ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_assessments_read ON public.vv_assessments FOR SELECT TO authenticated USING (public.vv_can_see_site(site_id));

ALTER TABLE public.vv_attachment_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_attachment_events_read ON public.vv_attachment_events FOR SELECT TO authenticated USING (public.vv_can_read_attachment(attachment_id));

ALTER TABLE public.vv_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_attachments_read ON public.vv_attachments FOR SELECT TO authenticated USING (public.vv_can_see_site(site_id));

ALTER TABLE public.vv_council_taxa ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_council_taxa_read ON public.vv_council_taxa FOR SELECT TO authenticated USING (public.vv_has(workspace_id, ARRAY['view'::text, 'field'::text, 'manage'::text]));

ALTER TABLE public.vv_council_trap_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_council_trap_types_read ON public.vv_council_trap_types FOR SELECT TO authenticated USING (public.vv_has(workspace_id, ARRAY['view'::text, 'field'::text, 'manage'::text]));

ALTER TABLE public.vv_deployments ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_deployments_read ON public.vv_deployments FOR SELECT TO authenticated USING (public.vv_can_see_site(site_id));

ALTER TABLE public.vv_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_events_read ON public.vv_events FOR SELECT TO authenticated USING (
CASE record_type
    WHEN 'site'::text THEN public.vv_can_see_site(record_id)
    WHEN 'programme'::text THEN public.vv_can_see_programme(record_id)
    WHEN 'incursion'::text THEN public.vv_can_see_incursion(record_id)
    ELSE public.vv_has(workspace_id, ARRAY['view'::text, 'field'::text, 'manage'::text])
END);

ALTER TABLE public.vv_exports ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_exports_read ON public.vv_exports FOR SELECT TO authenticated USING ((public.vv_has(workspace_id, ARRAY['manage'::text]) OR ((created_by = auth.uid()) AND public.vv_has(workspace_id, ARRAY['view'::text, 'field'::text, 'manage'::text]))));

ALTER TABLE public.vv_external_refs ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_external_refs_read ON public.vv_external_refs FOR SELECT TO authenticated USING (public.vv_can_see_record(record_type, record_id));

ALTER TABLE public.vv_incursion_findings ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_incursion_findings_read ON public.vv_incursion_findings FOR SELECT TO authenticated USING (public.vv_can_see_incursion(incursion_id));

ALTER TABLE public.vv_incursion_sites ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_incursion_sites_read ON public.vv_incursion_sites FOR SELECT TO authenticated USING (public.vv_can_see_incursion(incursion_id));

ALTER TABLE public.vv_incursion_steps ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_incursion_steps_read ON public.vv_incursion_steps FOR SELECT TO authenticated USING (public.vv_can_see_incursion(incursion_id));

ALTER TABLE public.vv_incursions ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_incursions_read ON public.vv_incursions FOR SELECT TO authenticated USING (public.vv_can_see_site(site_id));

ALTER TABLE public.vv_library_images ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_library_images_read ON public.vv_library_images FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.vv_library_versions v
  WHERE (v.id = vv_library_images.version_id))));

ALTER TABLE public.vv_library_notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_library_notes_read ON public.vv_library_notes FOR SELECT TO authenticated USING (public.vv_has(workspace_id, ARRAY['view'::text, 'field'::text, 'manage'::text]));

ALTER TABLE public.vv_library_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_library_versions_read ON public.vv_library_versions FOR SELECT TO authenticated USING (((status = ANY (ARRAY['published'::public.kp_status, 'superseded'::public.kp_status])) OR public.kp_is_editor()));

ALTER TABLE public.vv_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_notifications_read ON public.vv_notifications FOR SELECT TO authenticated USING (public.vv_can_see_incursion(incursion_id));

ALTER TABLE public.vv_notify_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_notify_contacts_read ON public.vv_notify_contacts FOR SELECT TO authenticated USING (public.vv_has(workspace_id, ARRAY['view'::text, 'field'::text, 'manage'::text]));

ALTER TABLE public.vv_programme_teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_programme_teams_read ON public.vv_programme_teams FOR SELECT TO authenticated USING (public.vv_can_see_programme(programme_id));

ALTER TABLE public.vv_programmes ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_programmes_read ON public.vv_programmes FOR SELECT TO authenticated USING (public.vv_can_see_programme(id));

ALTER TABLE public.vv_result_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_result_versions_read ON public.vv_result_versions FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.vv_results r
  WHERE (r.id = vv_result_versions.result_id))));

ALTER TABLE public.vv_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_results_read ON public.vv_results FOR SELECT TO authenticated USING (public.vv_can_see_site(site_id));

ALTER TABLE public.vv_samples ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_samples_read ON public.vv_samples FOR SELECT TO authenticated USING (public.vv_can_see_site(site_id));

CREATE POLICY vv_settings_read ON public.vv_workspace_settings FOR SELECT TO authenticated USING (public.vv_has(workspace_id, ARRAY['view'::text, 'field'::text, 'manage'::text]));

ALTER TABLE public.vv_site_programmes ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_site_programmes_read ON public.vv_site_programmes FOR SELECT TO authenticated USING ((public.vv_can_see_site(site_id) AND public.vv_can_see_programme(programme_id)));

ALTER TABLE public.vv_sites ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_sites_read ON public.vv_sites FOR SELECT TO authenticated USING (public.vv_can_see_site(id));

ALTER TABLE public.vv_stand_downs ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_stand_downs_read ON public.vv_stand_downs FOR SELECT TO authenticated USING (public.vv_can_see_incursion(incursion_id));

ALTER TABLE public.vv_taxa ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_taxa_read ON public.vv_taxa FOR SELECT TO authenticated USING (true);

ALTER TABLE public.vv_trap_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_trap_types_read ON public.vv_trap_types FOR SELECT TO authenticated USING (true);

ALTER TABLE public.vv_traps ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_traps_read ON public.vv_traps FOR SELECT TO authenticated USING (public.vv_has(workspace_id, ARRAY['view'::text, 'field'::text, 'manage'::text]));

ALTER TABLE public.vv_visits ENABLE ROW LEVEL SECURITY;

CREATE POLICY vv_visits_read ON public.vv_visits FOR SELECT TO authenticated USING (public.vv_can_see_site(site_id));

ALTER TABLE public.vv_workspace_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.workspace_invitations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.workspace_product_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.workspace_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY workspace_products_read ON public.workspace_products FOR SELECT TO authenticated USING ((public.is_member(workspace_id) OR public.is_platform_admin()));

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

CREATE POLICY ws_read ON public.workspaces FOR SELECT TO authenticated USING (public.is_member(id));

-- Lock down Supabase's default grants: every new table, sequence and function in
-- public is granted to anon and authenticated automatically. Revoke by name, then
-- the grants below give back only what each role needs.
REVOKE ALL ON TABLE public.audit_events FROM anon, authenticated;
REVOKE ALL ON TABLE public.content_roles FROM anon, authenticated;
REVOKE ALL ON TABLE public.invitation_emails FROM anon, authenticated;
REVOKE ALL ON TABLE public.platform_admins FROM anon, authenticated;
REVOKE ALL ON TABLE public.product_access FROM anon, authenticated;
REVOKE ALL ON TABLE public.profiles FROM anon, authenticated;
REVOKE ALL ON TABLE public.team_members FROM anon, authenticated;
REVOKE ALL ON TABLE public.teams FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_actions FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_assessment_results FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_assessment_versions FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_assessments FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_attachment_events FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_attachments FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_council_taxa FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_council_trap_types FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_deployments FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_events FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_exports FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_external_refs FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_incursion_findings FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_incursion_sites FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_incursion_steps FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_incursions FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_library_images FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_library_notes FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_library_versions FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_notifications FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_notify_contacts FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_programme_teams FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_programmes FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_result_versions FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_results FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_samples FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_site_programmes FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_sites FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_stand_downs FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_taxa FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_trap_types FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_traps FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_visits FROM anon, authenticated;
REVOKE ALL ON TABLE public.vv_workspace_settings FROM anon, authenticated;
REVOKE ALL ON TABLE public.workspace_invitations FROM anon, authenticated;
REVOKE ALL ON TABLE public.workspace_members FROM anon, authenticated;
REVOKE ALL ON TABLE public.workspace_product_events FROM anon, authenticated;
REVOKE ALL ON TABLE public.workspace_products FROM anon, authenticated;
REVOKE ALL ON TABLE public.workspaces FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.audit_events_id_seq FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.invitation_emails_id_seq FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.vv_attachment_events_id_seq FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.vv_events_id_seq FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.workspace_product_events_id_seq FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.accept_invitation(_token text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.accept_invitation(_token text) TO authenticated;
GRANT ALL ON FUNCTION public.accept_invitation(_token text) TO service_role;

REVOKE ALL ON FUNCTION public.create_invitation(_ws uuid, _email text, _role public.workspace_role) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.create_invitation(_ws uuid, _email text, _role public.workspace_role) TO authenticated;
GRANT ALL ON FUNCTION public.create_invitation(_ws uuid, _email text, _role public.workspace_role) TO service_role;

REVOKE ALL ON FUNCTION public.default_workspace_products() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.forbid_update() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.forbid_update() TO service_role;

REVOKE ALL ON FUNCTION public.grant_content_role(_user uuid, _role public.content_role) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.grant_content_role(_user uuid, _role public.content_role) TO authenticated;
GRANT ALL ON FUNCTION public.grant_content_role(_user uuid, _role public.content_role) TO service_role;

REVOKE ALL ON FUNCTION public.guard_immutable() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.guard_immutable() TO service_role;

REVOKE ALL ON FUNCTION public.guard_membership() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.guard_membership() TO service_role;

REVOKE ALL ON FUNCTION public.has_content_role(_roles public.content_role[]) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.has_content_role(_roles public.content_role[]) TO authenticated;
GRANT ALL ON FUNCTION public.has_content_role(_roles public.content_role[]) TO service_role;

REVOKE ALL ON FUNCTION public.has_product(_ws uuid, _product text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.has_product(_ws uuid, _product text) TO authenticated;
GRANT ALL ON FUNCTION public.has_product(_ws uuid, _product text) TO service_role;

REVOKE ALL ON FUNCTION public.has_product_access(_ws uuid, _product text, _levels text[]) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.has_product_access(_ws uuid, _product text, _levels text[]) TO authenticated;
GRANT ALL ON FUNCTION public.has_product_access(_ws uuid, _product text, _levels text[]) TO service_role;

REVOKE ALL ON FUNCTION public.has_ws_role(_ws uuid, _roles public.workspace_role[]) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.has_ws_role(_ws uuid, _roles public.workspace_role[]) TO authenticated;
GRANT ALL ON FUNCTION public.has_ws_role(_ws uuid, _roles public.workspace_role[]) TO service_role;

REVOKE ALL ON FUNCTION public.invitation_for_email(_token text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.invitation_for_email(_token text) TO authenticated;
GRANT ALL ON FUNCTION public.invitation_for_email(_token text) TO service_role;

REVOKE ALL ON FUNCTION public.is_member(_ws uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.is_member(_ws uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_member(_ws uuid) TO service_role;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.is_platform_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_platform_admin() TO service_role;

REVOKE ALL ON FUNCTION public.kp_guard_version() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.kp_is_editor() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.kp_is_editor() TO authenticated;
GRANT ALL ON FUNCTION public.kp_is_editor() TO service_role;

REVOKE ALL ON FUNCTION public.may_invite(_ws uuid, _role public.workspace_role) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.may_invite(_ws uuid, _role public.workspace_role) TO service_role;

REVOKE ALL ON FUNCTION public.my_products() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.my_products() TO authenticated;
GRANT ALL ON FUNCTION public.my_products() TO service_role;

REVOKE ALL ON FUNCTION public.platform_workspaces() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.platform_workspaces() TO authenticated;
GRANT ALL ON FUNCTION public.platform_workspaces() TO service_role;

REVOKE ALL ON FUNCTION public.product_level(_ws uuid, _product text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.product_level(_ws uuid, _product text) TO authenticated;
GRANT ALL ON FUNCTION public.product_level(_ws uuid, _product text) TO service_role;

REVOKE ALL ON FUNCTION public.record_invitation_email(_invitation uuid, _sent_by uuid, _status text, _provider_message_id text, _error text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.record_invitation_email(_invitation uuid, _sent_by uuid, _status text, _provider_message_id text, _error text) TO service_role;

REVOKE ALL ON FUNCTION public.reissue_invitation(_invitation uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.reissue_invitation(_invitation uuid) TO authenticated;
GRANT ALL ON FUNCTION public.reissue_invitation(_invitation uuid) TO service_role;

REVOKE ALL ON FUNCTION public.remove_member(_ws uuid, _user uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.remove_member(_ws uuid, _user uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_member(_ws uuid, _user uuid) TO service_role;

REVOKE ALL ON FUNCTION public.revoke_content_role(_user uuid, _role public.content_role) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.revoke_content_role(_user uuid, _role public.content_role) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_content_role(_user uuid, _role public.content_role) TO service_role;

REVOKE ALL ON FUNCTION public.revoke_invitation(_invitation uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.revoke_invitation(_invitation uuid) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_invitation(_invitation uuid) TO service_role;

REVOKE ALL ON FUNCTION public.role_in(_ws uuid, _user uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.role_in(_ws uuid, _user uuid) TO service_role;

REVOKE ALL ON FUNCTION public.set_member_role(_ws uuid, _user uuid, _role public.workspace_role) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.set_member_role(_ws uuid, _user uuid, _role public.workspace_role) TO authenticated;
GRANT ALL ON FUNCTION public.set_member_role(_ws uuid, _user uuid, _role public.workspace_role) TO service_role;

REVOKE ALL ON FUNCTION public.set_workspace_product(_ws uuid, _product text, _enabled boolean) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.set_workspace_product(_ws uuid, _product text, _enabled boolean) TO authenticated;
GRANT ALL ON FUNCTION public.set_workspace_product(_ws uuid, _product text, _enabled boolean) TO service_role;

REVOKE ALL ON FUNCTION public.touch_updated_at() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.touch_updated_at() TO service_role;

REVOKE ALL ON FUNCTION public.transfer_ownership(_ws uuid, _to uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.transfer_ownership(_ws uuid, _to uuid) TO authenticated;
GRANT ALL ON FUNCTION public.transfer_ownership(_ws uuid, _to uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_can_read_attachment(_id uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_can_read_attachment(_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_can_read_attachment(_id uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_can_run_incursion(_incursion uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_can_run_incursion(_incursion uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_can_run_incursion(_incursion uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_can_see_incursion(_incursion uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_can_see_incursion(_incursion uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_can_see_incursion(_incursion uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_can_see_programme(_programme uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_can_see_programme(_programme uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_can_see_programme(_programme uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_can_see_record(_type text, _id uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_can_see_record(_type text, _id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_can_see_record(_type text, _id uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_can_see_site(_site uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_can_see_site(_site uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_can_see_site(_site uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_check_time(_t timestamp with time zone, _what text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_check_time(_t timestamp with time zone, _what text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_confirm_attachment(_id uuid, _sha256 text, _size_bytes bigint) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_confirm_attachment(_id uuid, _sha256 text, _size_bytes bigint) TO service_role;

REVOKE ALL ON FUNCTION public.vv_correct_attachment(_id uuid, _caption text, _captured_at timestamp with time zone, _capture_source text, _why text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_correct_attachment(_id uuid, _caption text, _captured_at timestamp with time zone, _capture_source text, _why text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_correct_attachment(_id uuid, _caption text, _captured_at timestamp with time zone, _capture_source text, _why text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_correct_visit(_visit uuid, _occurred_at timestamp with time zone, _officer uuid, _condition text, _observations text, _exposure_start timestamp with time zone, _exposure_end timestamp with time zone, _not_completed_reason text, _why text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_correct_visit(_visit uuid, _occurred_at timestamp with time zone, _officer uuid, _condition text, _observations text, _exposure_start timestamp with time zone, _exposure_end timestamp with time zone, _not_completed_reason text, _why text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_correct_visit(_visit uuid, _occurred_at timestamp with time zone, _officer uuid, _condition text, _observations text, _exposure_start timestamp with time zone, _exposure_end timestamp with time zone, _not_completed_reason text, _why text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_deploy_trap(_id uuid, _ws uuid, _trap uuid, _site uuid, _latitude double precision, _longitude double precision, _placement text, _started_at timestamp with time zone, _officer uuid, _interval integer) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_deploy_trap(_id uuid, _ws uuid, _trap uuid, _site uuid, _latitude double precision, _longitude double precision, _placement text, _started_at timestamp with time zone, _officer uuid, _interval integer) TO authenticated;
GRANT ALL ON FUNCTION public.vv_deploy_trap(_id uuid, _ws uuid, _trap uuid, _site uuid, _latitude double precision, _longitude double precision, _placement text, _started_at timestamp with time zone, _officer uuid, _interval integer) TO service_role;

REVOKE ALL ON FUNCTION public.vv_diff(_before jsonb, _after jsonb) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.vv_end_deployment(_deployment uuid, _ended_at timestamp with time zone, _reason text, _note text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_end_deployment(_deployment uuid, _ended_at timestamp with time zone, _reason text, _note text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_end_deployment(_deployment uuid, _ended_at timestamp with time zone, _reason text, _note text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_event(_ws uuid, _type text, _id uuid, _kind text, _detail jsonb) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.vv_findings_awaiting_review(_ws uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_findings_awaiting_review(_ws uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_findings_awaiting_review(_ws uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_has(_ws uuid, _levels text[]) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_has(_ws uuid, _levels text[]) TO authenticated;
GRANT ALL ON FUNCTION public.vv_has(_ws uuid, _levels text[]) TO service_role;

REVOKE ALL ON FUNCTION public.vv_lib_add_image(_id uuid, _version uuid, _file_name text, _caption text, _credit text, _licence text, _source_url text, _sort integer) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_lib_add_image(_id uuid, _version uuid, _file_name text, _caption text, _credit text, _licence text, _source_url text, _sort integer) TO authenticated;
GRANT ALL ON FUNCTION public.vv_lib_add_image(_id uuid, _version uuid, _file_name text, _caption text, _credit text, _licence text, _source_url text, _sort integer) TO service_role;

REVOKE ALL ON FUNCTION public.vv_lib_publish(_version uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_lib_publish(_version uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_lib_publish(_version uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_lib_review(_version uuid, _approve boolean, _note text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_lib_review(_version uuid, _approve boolean, _note text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_lib_review(_version uuid, _approve boolean, _note text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_lib_save_draft(_kind text, _subject uuid, _content jsonb, _sources jsonb) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_lib_save_draft(_kind text, _subject uuid, _content jsonb, _sources jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.vv_lib_save_draft(_kind text, _subject uuid, _content jsonb, _sources jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.vv_lib_submit(_version uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_lib_submit(_version uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_lib_submit(_version uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_link_incursion(_id uuid, _results uuid[], _sites uuid[]) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_link_incursion(_id uuid, _results uuid[], _sites uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.vv_link_incursion(_id uuid, _results uuid[], _sites uuid[]) TO service_role;

REVOKE ALL ON FUNCTION public.vv_log_attachment_access(_id uuid, _action text, _actor uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_log_attachment_access(_id uuid, _action text, _actor uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_log_export(_id uuid, _ws uuid, _kind text, _scope jsonb, _counts jsonb, _file_name text, _size bigint, _sha256 text, _format_version text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_log_export(_id uuid, _ws uuid, _kind text, _scope jsonb, _counts jsonb, _file_name text, _size bigint, _sha256 text, _format_version text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_log_export(_id uuid, _ws uuid, _kind text, _scope jsonb, _counts jsonb, _file_name text, _size bigint, _sha256 text, _format_version text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_matrix_level(_likelihood integer, _consequence integer) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_matrix_level(_likelihood integer, _consequence integer) TO authenticated;
GRANT ALL ON FUNCTION public.vv_matrix_level(_likelihood integer, _consequence integer) TO service_role;

REVOKE ALL ON FUNCTION public.vv_move_trap(_deployment uuid, _new_id uuid, _site uuid, _latitude double precision, _longitude double precision, _placement text, _moved_at timestamp with time zone, _officer uuid, _interval integer) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_move_trap(_deployment uuid, _new_id uuid, _site uuid, _latitude double precision, _longitude double precision, _placement text, _moved_at timestamp with time zone, _officer uuid, _interval integer) TO authenticated;
GRANT ALL ON FUNCTION public.vv_move_trap(_deployment uuid, _new_id uuid, _site uuid, _latitude double precision, _longitude double precision, _placement text, _moved_at timestamp with time zone, _officer uuid, _interval integer) TO service_role;

REVOKE ALL ON FUNCTION public.vv_open_incursion(_id uuid, _site uuid, _results uuid[], _title text, _taxon uuid, _council_taxon uuid, _lead uuid, _status text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_open_incursion(_id uuid, _site uuid, _results uuid[], _title text, _taxon uuid, _council_taxon uuid, _lead uuid, _status text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_open_incursion(_id uuid, _site uuid, _results uuid[], _title text, _taxon uuid, _council_taxon uuid, _lead uuid, _status text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_record_notification(_id uuid, _incursion uuid, _kind text, _contact uuid, _recipient text, _method text, _notified_at timestamp with time zone, _reference text, _note text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_record_notification(_id uuid, _incursion uuid, _kind text, _contact uuid, _recipient text, _method text, _notified_at timestamp with time zone, _reference text, _note text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_record_notification(_id uuid, _incursion uuid, _kind text, _contact uuid, _recipient text, _method text, _notified_at timestamp with time zone, _reference text, _note text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_record_visit(_id uuid, _deployment uuid, _occurred_at timestamp with time zone, _officer uuid, _outcome text, _reason text, _condition text, _observations text, _exposure_start timestamp with time zone, _exposure_end timestamp with time zone, _samples jsonb) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_record_visit(_id uuid, _deployment uuid, _occurred_at timestamp with time zone, _officer uuid, _outcome text, _reason text, _condition text, _observations text, _exposure_start timestamp with time zone, _exposure_end timestamp with time zone, _samples jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.vv_record_visit(_id uuid, _deployment uuid, _occurred_at timestamp with time zone, _officer uuid, _outcome text, _reason text, _condition text, _observations text, _exposure_start timestamp with time zone, _exposure_end timestamp with time zone, _samples jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.vv_record_workspace(_type text, _id uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_record_workspace(_type text, _id uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_refresh_sample_status(_sample uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_refresh_sample_status(_sample uuid) TO service_role;

REVOKE ALL ON FUNCTION public.vv_register_attachment(_id uuid, _record_type text, _record_id uuid, _file_name text, _mime_type text, _size_bytes bigint, _sha256 text, _caption text, _captured_at timestamp with time zone, _capture_source text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_register_attachment(_id uuid, _record_type text, _record_id uuid, _file_name text, _mime_type text, _size_bytes bigint, _sha256 text, _caption text, _captured_at timestamp with time zone, _capture_source text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_register_attachment(_id uuid, _record_type text, _record_id uuid, _file_name text, _mime_type text, _size_bytes bigint, _sha256 text, _caption text, _captured_at timestamp with time zone, _capture_source text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_remove_external_ref(_id uuid, _reason text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_remove_external_ref(_id uuid, _reason text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_remove_external_ref(_id uuid, _reason text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_reopen_incursion(_id uuid, _incursion uuid, _status text, _reason text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_reopen_incursion(_id uuid, _incursion uuid, _status text, _reason text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_reopen_incursion(_id uuid, _incursion uuid, _status text, _reason text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_action(_id uuid, _site uuid, _assessment uuid, _title text, _detail text, _owner uuid, _due date) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_action(_id uuid, _site uuid, _assessment uuid, _title text, _detail text, _owner uuid, _due date) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_action(_id uuid, _site uuid, _assessment uuid, _title text, _detail text, _owner uuid, _due date) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_assessment(_id uuid, _site uuid, _results uuid[], _likelihood integer, _consequence integer, _final_level text, _override_reason text, _factors jsonb, _rationale text, _reason text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_assessment(_id uuid, _site uuid, _results uuid[], _likelihood integer, _consequence integer, _final_level text, _override_reason text, _factors jsonb, _rationale text, _reason text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_assessment(_id uuid, _site uuid, _results uuid[], _likelihood integer, _consequence integer, _final_level text, _override_reason text, _factors jsonb, _rationale text, _reason text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_council_taxon(_id uuid, _ws uuid, _scientific text, _common text, _active boolean) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_council_taxon(_id uuid, _ws uuid, _scientific text, _common text, _active boolean) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_council_taxon(_id uuid, _ws uuid, _scientific text, _common text, _active boolean) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_council_trap_type(_id uuid, _ws uuid, _name text, _description text, _active boolean) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_council_trap_type(_id uuid, _ws uuid, _name text, _description text, _active boolean) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_council_trap_type(_id uuid, _ws uuid, _name text, _description text, _active boolean) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_external_ref(_id uuid, _record_type text, _record_id uuid, _system text, _external_id text, _note text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_external_ref(_id uuid, _record_type text, _record_id uuid, _system text, _external_id text, _note text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_external_ref(_id uuid, _record_type text, _record_id uuid, _system text, _external_id text, _note text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_incursion_task(_id uuid, _incursion uuid, _step text, _title text, _detail text, _owner uuid, _due date) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_incursion_task(_id uuid, _incursion uuid, _step text, _title text, _detail text, _owner uuid, _due date) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_incursion_task(_id uuid, _incursion uuid, _step text, _title text, _detail text, _owner uuid, _due date) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_library_note(_id uuid, _ws uuid, _kind text, _subject uuid, _note text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_library_note(_id uuid, _ws uuid, _kind text, _subject uuid, _note text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_library_note(_id uuid, _ws uuid, _kind text, _subject uuid, _note text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_notify_contact(_id uuid, _ws uuid, _name text, _organisation text, _kind text, _detail text, _active boolean) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_notify_contact(_id uuid, _ws uuid, _name text, _organisation text, _kind text, _detail text, _active boolean) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_notify_contact(_id uuid, _ws uuid, _name text, _organisation text, _kind text, _detail text, _active boolean) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_programme(_id uuid, _ws uuid, _name text, _description text, _status text, _starts date, _ends date, _teams uuid[]) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_programme(_id uuid, _ws uuid, _name text, _description text, _status text, _starts date, _ends date, _teams uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_programme(_id uuid, _ws uuid, _name text, _description text, _status text, _starts date, _ends date, _teams uuid[]) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_result(_id uuid, _sample uuid, _status text, _taxon uuid, _council_taxon uuid, _quantity numeric, _unit text, _method text, _identified_by text, _laboratory text, _lab_reference text, _result_date date, _uncertainty text, _reason text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_result(_id uuid, _sample uuid, _status text, _taxon uuid, _council_taxon uuid, _quantity numeric, _unit text, _method text, _identified_by text, _laboratory text, _lab_reference text, _result_date date, _uncertainty text, _reason text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_result(_id uuid, _sample uuid, _status text, _taxon uuid, _council_taxon uuid, _quantity numeric, _unit text, _method text, _identified_by text, _laboratory text, _lab_reference text, _result_date date, _uncertainty text, _reason text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_site(_id uuid, _ws uuid, _name text, _line_1 text, _line_2 text, _town text, _postcode text, _uprn text, _latitude double precision, _longitude double precision, _description text, _access text, _status text, _programmes uuid[]) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_site(_id uuid, _ws uuid, _name text, _line_1 text, _line_2 text, _town text, _postcode text, _uprn text, _latitude double precision, _longitude double precision, _description text, _access text, _status text, _programmes uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_site(_id uuid, _ws uuid, _name text, _line_1 text, _line_2 text, _town text, _postcode text, _uprn text, _latitude double precision, _longitude double precision, _description text, _access text, _status text, _programmes uuid[]) TO service_role;

REVOKE ALL ON FUNCTION public.vv_save_trap(_id uuid, _ws uuid, _identifier text, _trap_type uuid, _council_trap_type uuid, _status text, _notes text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_save_trap(_id uuid, _ws uuid, _identifier text, _trap_type uuid, _council_trap_type uuid, _status text, _notes text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_save_trap(_id uuid, _ws uuid, _identifier text, _trap_type uuid, _council_trap_type uuid, _status text, _notes text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_set_action_status(_id uuid, _status text, _note text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_set_action_status(_id uuid, _status text, _note text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_set_action_status(_id uuid, _status text, _note text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_set_incursion_step(_id uuid, _step text, _status text, _note text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_set_incursion_step(_id uuid, _step text, _status text, _note text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_set_incursion_step(_id uuid, _step text, _status text, _note text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_set_response_area(_id uuid, _lat numeric, _lon numeric, _radius_m numeric, _reason text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_set_response_area(_id uuid, _lat numeric, _lon numeric, _radius_m numeric, _reason text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_set_response_area(_id uuid, _lat numeric, _lon numeric, _radius_m numeric, _reason text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_stand_down(_id uuid, _incursion uuid, _decided_at timestamp with time zone, _rationale text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_stand_down(_id uuid, _incursion uuid, _decided_at timestamp with time zone, _rationale text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_stand_down(_id uuid, _incursion uuid, _decided_at timestamp with time zone, _rationale text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_update_incursion(_id uuid, _title text, _taxon uuid, _council_taxon uuid, _lead uuid, _status text, _reason text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_update_incursion(_id uuid, _title text, _taxon uuid, _council_taxon uuid, _lead uuid, _status text, _reason text) TO authenticated;
GRANT ALL ON FUNCTION public.vv_update_incursion(_id uuid, _title text, _taxon uuid, _council_taxon uuid, _lead uuid, _status text, _reason text) TO service_role;

REVOKE ALL ON FUNCTION public.vv_visit_schedule(_ws uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.vv_visit_schedule(_ws uuid) TO authenticated;
GRANT ALL ON FUNCTION public.vv_visit_schedule(_ws uuid) TO service_role;

REVOKE ALL ON FUNCTION public.write_audit(_ws uuid, _action text, _target uuid, _detail jsonb) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.write_audit(_ws uuid, _action text, _target uuid, _detail jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.ws_role_of(_ws uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.ws_role_of(_ws uuid) TO authenticated;
GRANT ALL ON FUNCTION public.ws_role_of(_ws uuid) TO service_role;

GRANT SELECT ON TABLE public.audit_events TO authenticated;
GRANT ALL ON TABLE public.audit_events TO service_role;

GRANT SELECT,USAGE ON SEQUENCE public.audit_events_id_seq TO service_role;

GRANT SELECT ON TABLE public.content_roles TO authenticated;
GRANT ALL ON TABLE public.content_roles TO service_role;

GRANT SELECT ON TABLE public.invitation_emails TO authenticated;
GRANT ALL ON TABLE public.invitation_emails TO service_role;

GRANT SELECT ON TABLE public.platform_admins TO authenticated;
GRANT ALL ON TABLE public.platform_admins TO service_role;

GRANT SELECT ON TABLE public.product_access TO authenticated;
GRANT ALL ON TABLE public.product_access TO service_role;

GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;

GRANT UPDATE(display_name) ON TABLE public.profiles TO authenticated;

GRANT SELECT ON TABLE public.team_members TO authenticated;
GRANT ALL ON TABLE public.team_members TO service_role;

GRANT SELECT ON TABLE public.teams TO authenticated;
GRANT ALL ON TABLE public.teams TO service_role;

GRANT SELECT ON TABLE public.vv_actions TO authenticated;
GRANT ALL ON TABLE public.vv_actions TO service_role;

GRANT SELECT ON TABLE public.vv_assessment_results TO authenticated;
GRANT ALL ON TABLE public.vv_assessment_results TO service_role;

GRANT SELECT ON TABLE public.vv_assessment_versions TO authenticated;
GRANT ALL ON TABLE public.vv_assessment_versions TO service_role;

GRANT SELECT ON TABLE public.vv_assessments TO authenticated;
GRANT ALL ON TABLE public.vv_assessments TO service_role;

GRANT SELECT ON TABLE public.vv_attachment_events TO authenticated;
GRANT ALL ON TABLE public.vv_attachment_events TO service_role;

GRANT SELECT ON TABLE public.vv_attachments TO authenticated;
GRANT ALL ON TABLE public.vv_attachments TO service_role;

GRANT SELECT ON TABLE public.vv_council_taxa TO authenticated;
GRANT ALL ON TABLE public.vv_council_taxa TO service_role;

GRANT SELECT ON TABLE public.vv_council_trap_types TO authenticated;
GRANT ALL ON TABLE public.vv_council_trap_types TO service_role;

GRANT SELECT ON TABLE public.vv_deployments TO authenticated;
GRANT ALL ON TABLE public.vv_deployments TO service_role;

GRANT SELECT ON TABLE public.vv_events TO authenticated;
GRANT ALL ON TABLE public.vv_events TO service_role;

GRANT SELECT ON TABLE public.vv_exports TO authenticated;
GRANT ALL ON TABLE public.vv_exports TO service_role;

GRANT SELECT ON TABLE public.vv_external_refs TO authenticated;
GRANT ALL ON TABLE public.vv_external_refs TO service_role;

GRANT SELECT ON TABLE public.vv_incursion_findings TO authenticated;
GRANT ALL ON TABLE public.vv_incursion_findings TO service_role;

GRANT SELECT ON TABLE public.vv_incursion_sites TO authenticated;
GRANT ALL ON TABLE public.vv_incursion_sites TO service_role;

GRANT SELECT ON TABLE public.vv_incursion_steps TO authenticated;
GRANT ALL ON TABLE public.vv_incursion_steps TO service_role;

GRANT SELECT ON TABLE public.vv_incursions TO authenticated;
GRANT ALL ON TABLE public.vv_incursions TO service_role;

GRANT SELECT ON TABLE public.vv_library_images TO authenticated;
GRANT ALL ON TABLE public.vv_library_images TO service_role;

GRANT SELECT ON TABLE public.vv_library_notes TO authenticated;
GRANT ALL ON TABLE public.vv_library_notes TO service_role;

GRANT SELECT ON TABLE public.vv_library_versions TO authenticated;
GRANT ALL ON TABLE public.vv_library_versions TO service_role;

GRANT SELECT ON TABLE public.vv_notifications TO authenticated;
GRANT ALL ON TABLE public.vv_notifications TO service_role;

GRANT SELECT ON TABLE public.vv_notify_contacts TO authenticated;
GRANT ALL ON TABLE public.vv_notify_contacts TO service_role;

GRANT SELECT ON TABLE public.vv_programme_teams TO authenticated;
GRANT ALL ON TABLE public.vv_programme_teams TO service_role;

GRANT SELECT ON TABLE public.vv_programmes TO authenticated;
GRANT ALL ON TABLE public.vv_programmes TO service_role;

GRANT SELECT ON TABLE public.vv_result_versions TO authenticated;
GRANT ALL ON TABLE public.vv_result_versions TO service_role;

GRANT SELECT ON TABLE public.vv_results TO authenticated;
GRANT ALL ON TABLE public.vv_results TO service_role;

GRANT SELECT ON TABLE public.vv_samples TO authenticated;
GRANT ALL ON TABLE public.vv_samples TO service_role;

GRANT SELECT ON TABLE public.vv_site_programmes TO authenticated;
GRANT ALL ON TABLE public.vv_site_programmes TO service_role;

GRANT SELECT ON TABLE public.vv_sites TO authenticated;
GRANT ALL ON TABLE public.vv_sites TO service_role;

GRANT SELECT ON TABLE public.vv_stand_downs TO authenticated;
GRANT ALL ON TABLE public.vv_stand_downs TO service_role;

GRANT SELECT ON TABLE public.vv_taxa TO authenticated;
GRANT ALL ON TABLE public.vv_taxa TO service_role;

GRANT SELECT ON TABLE public.vv_trap_types TO authenticated;
GRANT ALL ON TABLE public.vv_trap_types TO service_role;

GRANT SELECT ON TABLE public.vv_traps TO authenticated;
GRANT ALL ON TABLE public.vv_traps TO service_role;

GRANT SELECT ON TABLE public.vv_visits TO authenticated;
GRANT ALL ON TABLE public.vv_visits TO service_role;

GRANT SELECT ON TABLE public.vv_workspace_settings TO authenticated;
GRANT ALL ON TABLE public.vv_workspace_settings TO service_role;

GRANT SELECT ON TABLE public.workspace_invitations TO authenticated;
GRANT ALL ON TABLE public.workspace_invitations TO service_role;

GRANT SELECT ON TABLE public.workspace_members TO authenticated;
GRANT ALL ON TABLE public.workspace_members TO service_role;

GRANT SELECT ON TABLE public.workspace_product_events TO authenticated;
GRANT ALL ON TABLE public.workspace_product_events TO service_role;

GRANT SELECT ON TABLE public.workspace_products TO authenticated;
GRANT ALL ON TABLE public.workspace_products TO service_role;

GRANT SELECT ON TABLE public.workspaces TO authenticated;
GRANT ALL ON TABLE public.workspaces TO service_role;

-- ---------------------------------------------------------------------
-- Re-stated without Investigations dependencies
-- ---------------------------------------------------------------------
CREATE FUNCTION public.ensure_personal_workspace() RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare uid uuid := auth.uid(); ws uuid;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  insert into public.profiles (id) values (uid) on conflict do nothing;
  select id into ws from public.workspaces where personal_owner_id = uid;
  if ws is null then
    insert into public.workspaces (kind, name, personal_owner_id) values ('personal', 'Personal workspace', uid) returning id into ws;
    insert into public.workspace_members (workspace_id, user_id, role) values (ws, uid, 'owner');
    perform public.write_audit(ws, 'workspace.personal_created', ws);
  end if;
  return ws;
end $$;
REVOKE ALL ON FUNCTION public.ensure_personal_workspace() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.ensure_personal_workspace() TO authenticated;
GRANT ALL ON FUNCTION public.ensure_personal_workspace() TO service_role;

CREATE FUNCTION public.provision_organisation(_name text, _owner uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ws uuid;
begin
  insert into public.workspaces (kind, name) values ('organisation', _name) returning id into ws;
  insert into public.workspace_members (workspace_id, user_id, role) values (ws, _owner, 'owner');
  insert into public.audit_events (workspace_id, actor_id, action, target_id) values (ws, null, 'workspace.provisioned', _owner);
  return ws;
end $$;
REVOKE ALL ON FUNCTION public.provision_organisation(_name text, _owner uuid) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.provision_organisation(_name text, _owner uuid) TO service_role;

-- ---------------------------------------------------------------------
-- Teams, re-stated for Vectovia: organisation owners and admins manage them;
-- no confidential-case flag (Vectovia holds no confidential case fields).
-- ---------------------------------------------------------------------
alter table public.teams drop column can_view_confidential;

create function public.is_org_admin(_ws uuid) returns boolean
  language sql stable security definer set search_path = '' as $$
  select public.has_ws_role(_ws, array['owner', 'admin']::public.workspace_role[])
$$;
revoke all on function public.is_org_admin(_ws uuid) from public, anon, authenticated;
grant execute on function public.is_org_admin(_ws uuid) to authenticated, service_role;

create function public.create_team(_ws uuid, _name text) returns uuid
  language plpgsql security definer set search_path = '' as $$
declare t uuid;
begin
  if not public.is_org_admin(_ws)
     or not exists (select 1 from public.workspaces where id = _ws and kind = 'organisation') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.teams (workspace_id, name, created_by) values (_ws, trim(_name), auth.uid()) returning id into t;
  perform public.write_audit(_ws, 'team.created', t);
  return t;
end $$;

create function public.update_team(_team uuid, _name text) returns void
  language plpgsql security definer set search_path = '' as $$
declare t public.teams;
begin
  select * into t from public.teams where id = _team for update;
  if t.id is null or not public.is_org_admin(t.workspace_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  if nullif(trim(_name), '') is null or trim(_name) = t.name then return; end if;
  update public.teams set name = trim(_name) where id = _team;
  perform public.write_audit(t.workspace_id, 'team.renamed', _team);
end $$;

create function public.add_team_member(_team uuid, _user uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare ws uuid;
begin
  select workspace_id into ws from public.teams where id = _team;
  if ws is null or not public.is_org_admin(ws) then raise exception 'not allowed' using errcode = '42501'; end if;
  -- FK to workspace_members rejects anyone who is not a current member of THIS organisation.
  insert into public.team_members (team_id, workspace_id, user_id, added_by) values (_team, ws, _user, auth.uid())
  on conflict do nothing;
  perform public.write_audit(ws, 'team.member_added', _team, jsonb_build_object('user_id', _user));
end $$;

create function public.remove_team_member(_team uuid, _user uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare ws uuid;
begin
  select workspace_id into ws from public.teams where id = _team;
  if ws is null or not public.is_org_admin(ws) then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from public.team_members where team_id = _team and user_id = _user;
  perform public.write_audit(ws, 'team.member_removed', _team, jsonb_build_object('user_id', _user));
end $$;

revoke all on function public.create_team(_ws uuid, _name text) from public, anon, authenticated;
revoke all on function public.update_team(_team uuid, _name text) from public, anon, authenticated;
revoke all on function public.add_team_member(_team uuid, _user uuid) from public, anon, authenticated;
revoke all on function public.remove_team_member(_team uuid, _user uuid) from public, anon, authenticated;
grant execute on function public.create_team(_ws uuid, _name text) to authenticated, service_role;
grant execute on function public.update_team(_team uuid, _name text) to authenticated, service_role;
grant execute on function public.add_team_member(_team uuid, _user uuid) to authenticated, service_role;
grant execute on function public.remove_team_member(_team uuid, _user uuid) to authenticated, service_role;

-- Product access, re-stated with the organisation-admin check.
create function public.set_product_access(_ws uuid, _user uuid, _product text, _level text) returns void
  language plpgsql security definer set search_path = '' as $$
declare r public.workspace_role;
begin
  if not public.is_org_admin(_ws) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not public.has_product(_ws, _product) then raise exception 'your organisation does not have this product' using errcode = '22023'; end if;
  select role into r from public.workspace_members where workspace_id = _ws and user_id = _user;
  if r is null then raise exception 'not a member' using errcode = '22023'; end if;
  if r in ('owner', 'admin') then raise exception 'owners and admins already have full access' using errcode = '22023'; end if;
  if _level not in ('none', 'view', 'field', 'manage') then raise exception 'unknown level' using errcode = '22023'; end if;
  insert into public.product_access (workspace_id, user_id, product, level, updated_at, updated_by)
  values (_ws, _user, _product, _level, now(), auth.uid())
  on conflict (workspace_id, user_id, product) do update set level = excluded.level, updated_at = now(), updated_by = auth.uid();
  perform public.write_audit(_ws, 'product.access_set', _user, jsonb_build_object('product', _product, 'level', _level));
end $$;
revoke all on function public.set_product_access(_ws uuid, _user uuid, _product text, _level text) from public, anon, authenticated;
grant execute on function public.set_product_access(_ws uuid, _user uuid, _product text, _level text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- File storage (private originals; public credited library images)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vectovia-files', 'vectovia-files', false, 26214400, array[
  'image/jpeg', 'image/png', 'image/heic', 'image/heif', 'application/pdf',
  'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'text/csv'])
on conflict (id) do nothing;
create policy vectovia_files_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'vectovia-files'
    and exists (select 1 from public.vv_attachments a where a.storage_path = name and a.uploaded_by = auth.uid() and a.status = 'pending'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vectovia-library', 'vectovia-library', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy vectovia_library_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'vectovia-library'
    and exists (select 1 from public.vv_library_images i join public.vv_library_versions v on v.id = i.version_id
                where i.storage_path = name and i.added_by = auth.uid() and v.status = 'draft'));

-- ---------------------------------------------------------------------
-- Reference seed: shared species and trap types (from rev21; checked = false
-- until a specialist confirms each row).
-- ---------------------------------------------------------------------
insert into public.vv_taxa (key, scientific_name, common_name, invasive, sort_order) values
  ('aedes_albopictus', 'Aedes albopictus', 'Asian tiger mosquito', true, 10),
  ('aedes_aegypti', 'Aedes aegypti', 'Yellow fever mosquito', true, 20),
  ('aedes_japonicus', 'Aedes japonicus', 'Asian bush mosquito', true, 30),
  ('aedes_detritus', 'Aedes detritus', null, false, 40),
  ('aedes_vexans', 'Aedes vexans', null, false, 50),
  ('anopheles_plumbeus', 'Anopheles plumbeus', null, false, 60),
  ('anopheles_maculipennis_sl', 'Anopheles maculipennis s.l.', null, false, 70),
  ('culex_pipiens_sl', 'Culex pipiens s.l.', 'Common house mosquito', false, 80),
  ('culex_modestus', 'Culex modestus', null, false, 90),
  ('culiseta_annulata', 'Culiseta annulata', null, false, 100),
  ('culicidae_unidentified', 'Culicidae (not identified to species)', 'Mosquito, unidentified', false, 900);
insert into public.vv_trap_types (key, name, description, sort_order) values
  ('bg_sentinel', 'BG-Sentinel', 'Adult trap using a lure and/or CO2; standard for Aedes surveillance.', 10),
  ('ovitrap', 'Ovitrap', 'Egg-laying trap for container-breeding Aedes.', 20),
  ('cdc_light', 'CDC light trap', 'Adult light trap, often with CO2.', 30),
  ('gravid', 'Gravid trap', 'Adult trap attracting egg-laying females (often Culex).', 40),
  ('mosquito_magnet', 'Mosquito Magnet', 'Adult CO2 trap.', 50),
  ('larval_dip', 'Larval dipping', 'Larval sampling of standing water.', 60);
