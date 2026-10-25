-- National template drafts (owner-approved load; NOT reviewed, NOT published).
-- Section headings for a site surveillance plan, drawn from the obligation sets in design-v2.md §5
-- (IHR point of entry v1 and UKHSA England invasive Aedes v1). Loaded "in review": only the content
-- team sees it until a reviewer approves and a different content admin publishes. Safe to run twice.

do $load$
declare t uuid; v uuid;
begin
  if not exists (select 1 from public.vv_templates where key = 'surveillance_plan_v1') then
    insert into public.vv_templates (key, kind, name, sort_order)
    values ('surveillance_plan_v1', 'surveillance_plan', 'Site surveillance plan', 10) returning id into t;
    insert into public.vv_template_versions (template_id, version, summary, sections, sources, status)
    values (t, 1, 'The sections a site''s vector surveillance plan covers, for points of entry and council sites. Draft for specialist review.',
      '[{"key":"scope","title":"Scope, site and operational areas","required":true,
         "guidance":"What the plan covers: the site, its operational areas (terminals, cargo, external areas, service providers) and the zone around them."},
        {"key":"responsibilities","title":"Roles and responsibilities","required":true,
         "guidance":"Who leads, who does the field work, who is told about findings, and contractors used."},
        {"key":"surveillance","title":"Surveillance programme","required":true,
         "guidance":"Trap types, where they are placed, seasons and how often they are checked."},
        {"key":"identification","title":"Identification and testing","required":true,
         "guidance":"How samples are identified, who provides official identification, and when pathogen testing is arranged."},
        {"key":"response","title":"Incursion and response","required":true,
         "guidance":"What happens after a suspected or confirmed invasive find: notifications, response area, enhanced surveillance and control."},
        {"key":"control","title":"Control and source reduction","required":false,
         "guidance":"Routine control, removing breeding sites, and supervising treatments."},
        {"key":"training","title":"Training and competence","required":false,
         "guidance":"Training needed for each role and how it is kept up to date."},
        {"key":"reporting","title":"Reporting and records","required":true,
         "guidance":"What is reported, to whom and when (including negative results), and how records are kept."},
        {"key":"review","title":"Review and exercises","required":true,
         "guidance":"When the plan is reviewed, how it is exercised, and how lessons are acted on."}]',
      '[{"title":"WHO: Vector surveillance and control at ports, airports and ground crossings","url":"https://www.who.int/publications/i/item/9789241549592"},
        {"title":"UKHSA: National contingency plan for invasive Aedes mosquitoes in England","url":"https://www.gov.uk/guidance/national-contingency-plan-for-invasive-aedes-mosquitoes-in-england"}]',
      'draft') returning id into v;
    update public.vv_template_versions set status = 'in_review' where id = v;
  end if;
end $load$;
