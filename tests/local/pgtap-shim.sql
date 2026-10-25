-- Small pgTAP-compatible subset for local runs where the pgtap extension isn't
-- installed: no_plan, ok, is, matches, lives_ok, throws_ok, hasnt_column, finish.
-- Output follows TAP ("ok N - ..." / "not ok N - ..."). Throwaway databases only.
create schema if not exists tap;
grant usage on schema tap to public;

create or replace function tap.no_plan() returns setof text language plpgsql as $$
begin
  create temp table if not exists _tap (n serial primary key, passed boolean not null, descr text);
  grant all on _tap to public;
  grant all on sequence _tap_n_seq to public;
  return;
end $$;

create or replace function tap._rec(_passed boolean, _descr text, _diag text default null) returns text
language plpgsql as $$
declare n int;
begin
  insert into _tap (passed, descr) values (coalesce(_passed, false), _descr) returning _tap.n into n;
  return case when coalesce(_passed, false) then 'ok ' else 'not ok ' end || n || ' - ' || coalesce(_descr, '')
         || case when not coalesce(_passed, false) and _diag is not null then E'\n#   ' || _diag else '' end;
end $$;

create or replace function tap.ok(boolean, text) returns text language sql as $$ select tap._rec($1, $2) $$;

create or replace function tap.is(anyelement, anyelement, text) returns text language sql as $$
  select tap._rec($1 is not distinct from $2, $3, 'got: ' || coalesce($1::text, 'NULL') || '  want: ' || coalesce($2::text, 'NULL'))
$$;

create or replace function tap.matches(text, text, text) returns text language sql as $$
  select tap._rec($1 ~ $2, $3, 'got: ' || coalesce($1, 'NULL') || '  pattern: ' || $2)
$$;

create or replace function tap.lives_ok(_sql text, _descr text) returns text language plpgsql as $$
begin
  execute _sql;
  return tap._rec(true, _descr);
exception when others then
  return tap._rec(false, _descr, 'died: ' || sqlstate || ' ' || sqlerrm);
end $$;

create or replace function tap.throws_ok(_sql text, _errcode text, _errmsg text, _descr text) returns text
language plpgsql as $$
begin
  execute _sql;
  return tap._rec(false, _descr, 'no exception raised (wanted ' || _errcode || ')');
exception when others then
  return tap._rec(sqlstate = _errcode and (_errmsg is null or sqlerrm = _errmsg), _descr,
                  'got: ' || sqlstate || ' ' || sqlerrm || '  want: ' || _errcode);
end $$;

create or replace function tap.hasnt_column(_schema name, _table name, _column name, _descr text) returns text
language sql as $$
  select tap._rec(not exists (select 1 from information_schema.columns
                              where table_schema = _schema and table_name = _table and column_name = _column), _descr)
$$;

create or replace function tap.finish() returns setof text language plpgsql as $$
declare total int; failed int;
begin
  select count(*), count(*) filter (where not passed) into total, failed from _tap;
  return next '1..' || total;
  if failed > 0 then return next '# FAILED ' || failed || ' of ' || total; else return next '# All ' || total || ' tests passed'; end if;
end $$;

grant execute on all functions in schema tap to public;
