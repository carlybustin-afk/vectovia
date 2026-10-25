-- Obligation set drafts (owner-approved load; NOT reviewed, NOT published).
-- Drafted from docs/vectovia/design-v2.md §5: the owner's analysis of IHR core capacity 5 (18 provisions)
-- and UKHSA's National contingency plan for invasive Aedes mosquitoes in England (21 May 2026).
-- Loaded as "in review": only the content team can see them until a specialist reviewer approves
-- and a different content admin publishes. Sites can adopt a set only once it is published.
-- Safe to run twice: each set is loaded only if it does not exist yet.

do $load$
declare s uuid; v uuid;
begin
  -- ---------- IHR point of entry v1 ----------
  if not exists (select 1 from public.vv_obligation_sets where key = 'ihr_point_of_entry') then
    insert into public.vv_obligation_sets (key, name, framework, jurisdiction, applies_to, sort_order)
    values ('ihr_point_of_entry', 'IHR point of entry: vector surveillance and control', 'ihr', 'International',
            '{port,airport,ground_crossing}', 10) returning id into s;
    insert into public.vv_obligation_versions (set_id, version, summary, sources, status)
    values (s, 1, 'Vector surveillance and control at a designated point of entry under the International Health Regulations (2005), '
      || 'as 18 requirements drawn from core capacity 5 and Annex 5. Draft for specialist review.',
      '[{"title":"WHO: International Health Regulations (2005), third edition","url":"https://www.who.int/publications/i/item/9789241580496"},
        {"title":"WHO: Vector surveillance and control at ports, airports and ground crossings","url":"https://www.who.int/publications/i/item/9789241549592"}]',
      'draft') returning id into v;
    insert into public.vv_obligation_requirements (version_id, key, sort_order, title, what, frequency, evidence, check_kind, source_ref) values
    (v, 'integrated_programme', 1, 'Integrated vector programme',
     'Keep an integrated programme for vector surveillance and control at the point of entry, including how vectors are intercepted, how an incursion is handled and the capacity to respond.',
     'Reviewed at least yearly', 'Surveillance plan including the interception and incursion plan; response arrangements', 'assessment', 'IHR core capacity 5, provision 1'),
    (v, 'area_covered', 2, 'Area covered',
     'Cover every operational area of the point of entry (terminals, cargo, external areas and service providers), with a wider survey every 2 to 3 years and the plan reviewed after surveys.',
     'Wider survey every 2 to 3 years', 'Operational areas recorded; survey report; plan review', 'assessment', 'IHR core capacity 5, provision 2'),
    (v, 'zone_400m', 3, 'Zone of at least 400 metres',
     'Keep surveillance and control in the operational areas and in a zone of at least 400 metres around them, with traps placed inside the zone.',
     'Continuous', 'Site boundary, areas and zone; traps inside the zone', 'zone', 'IHR Annex 5; core capacity 5, provision 3'),
    (v, 'surveillance', 4, 'Regular surveillance',
     'Check traps on a set schedule (for example weekly or fortnightly in the active season) and link with wider surveillance.',
     'As set in the programme', 'Checks done against the schedule', 'checks', 'IHR core capacity 5, provision 4'),
    (v, 'identification', 5, 'Identification route',
     'Have a named route for identifying vectors, and get official identification for any suspected invasive species.',
     'Each suspected invasive find', 'Named identification provider; official identification on finds', 'official_id', 'IHR core capacity 5, provision 5'),
    (v, 'pathogen_testing', 6, 'Pathogen testing',
     'Arrange pathogen testing of vectors where the risk assessment calls for it.',
     'As needed', 'Pathogen test records', 'assessment', 'IHR core capacity 5, provision 6'),
    (v, 'control_action', 7, 'Control action',
     'Take control action when vectors are found, and give the site operator a yearly survey report.',
     'When needed; report yearly', 'Control action records; yearly survey report', 'assessment', 'IHR core capacity 5, provision 7'),
    (v, 'competent_personnel', 8, 'Competent personnel',
     'Make sure the people doing surveillance and control are trained and competent, with renewal dates.',
     'Renewed as required', 'Training and competence records', 'assessment', 'IHR core capacity 5, provision 8'),
    (v, 'contractors', 9, 'Contractors supervised',
     'Supervise contractors who carry out surveillance or control, and audit their work.',
     'Audited at least yearly', 'Contractor access and audit records', 'assessment', 'IHR core capacity 5, provision 9'),
    (v, 'equipment', 10, 'Equipment and chemicals',
     'Keep a register of equipment and chemicals, with permissions and expiry dates.',
     'Kept current', 'Equipment and chemicals register', 'assessment', 'IHR core capacity 5, provision 10'),
    (v, 'sanitary_facilities', 11, 'Sanitary facilities',
     'Survey sanitary facilities and conditions that could support vectors.',
     'At least yearly', 'Sanitary and vector survey', 'assessment', 'IHR core capacity 5, provision 11'),
    (v, 'incoming_risks', 12, 'Incoming risks',
     'Record incoming risks, for example from conveyances and cargo, and liaise with the people responsible.',
     'As they arise', 'Incoming-risk log and liaison records', 'assessment', 'IHR core capacity 5, provision 12'),
    (v, 'treatment_supervision', 13, 'Supervising treatments',
     'Supervise disinsection and other vector control treatments.',
     'Each treatment', 'Treatment supervision records', 'assessment', 'IHR core capacity 5, provision 13'),
    (v, 'conveyances', 14, 'Affected or suspect conveyances',
     'Inspect affected or suspect conveyances and record what was found and done.',
     'Each conveyance', 'Conveyance inspection records', 'assessment', 'IHR core capacity 5, provision 14'),
    (v, 'follow_up', 15, 'Follow-up between points of entry',
     'Send follow-up information to the next point of entry when a conveyance needs it.',
     'When needed', 'Follow-up notices', 'assessment', 'IHR core capacity 5, provision 15'),
    (v, 'records', 16, 'Records and evidence',
     'Keep records of surveillance and control that can be relied on as evidence.',
     'Continuous', 'Records with history, file fingerprints and an audit trail', 'records', 'IHR core capacity 5, provision 16'),
    (v, 'effectiveness', 17, 'Reviewing effectiveness',
     'Review the point of entry risk assessment and how well the programme is working, and act on what the review finds.',
     'At least yearly', 'Yearly risk assessment; effectiveness review; corrective actions', 'assessment', 'IHR core capacity 5, provision 17'),
    (v, 'national_information', 18, 'National and WHO information',
     'Give the national authority the information it needs, including for reporting to WHO.',
     'As requested', 'National view; national return', 'assessment', 'IHR core capacity 5, provision 18');
    update public.vv_obligation_versions set status = 'in_review' where id = v;
  end if;

  -- ---------- Invasive Aedes surveillance (England) v1 ----------
  if not exists (select 1 from public.vv_obligation_sets where key = 'ukhsa_invasive_aedes_england') then
    insert into public.vv_obligation_sets (key, name, framework, jurisdiction, applies_to, sort_order)
    values ('ukhsa_invasive_aedes_england', 'Invasive Aedes mosquito surveillance (England)', 'national_guidance', 'England',
            '{port,airport,service_station,truck_stop,inland_border,international_rail,community}', 20) returning id into s;
    insert into public.vv_obligation_versions (set_id, version, summary, sources, status)
    values (s, 1, 'Surveillance and response for invasive Aedes mosquitoes by councils and port health authorities in England, '
      || 'drafted from UKHSA''s national contingency plan (21 May 2026). Draft: to be checked against the full plan and its annexes '
      || 'and reviewed by a specialist. Scotland, Wales and Northern Ireland need their own sets.',
      '[{"title":"UKHSA: National contingency plan for invasive Aedes mosquitoes in England","url":"https://www.gov.uk/guidance/national-contingency-plan-for-invasive-aedes-mosquitoes-in-england"},
        {"title":"UKHSA: Invasive mosquito surveillance","url":"https://www.gov.uk/guidance/invasive-mosquito-surveillance"}]',
      'draft') returning id into v;
    insert into public.vv_obligation_requirements (version_id, key, sort_order, title, what, frequency, evidence, check_kind, mandatory, source_ref) values
    (v, 'high_risk_sites', 1, 'Trap at high-risk sites',
     'At high-risk sites coordinated by UKHSA (highway service stations, truck stops, inland border facilities and international rail stations), trap from June to October.',
     'Every 2 weeks, June to October', 'Checks done against the schedule', 'checks', true, 'UKHSA contingency plan, Level 0'),
    (v, 'ports_airports', 2, 'Trap at ports and airports',
     'At ports and airports with international links, port health officers use ovitraps and, where possible, BG traps, from April to November.',
     'Every 2 weeks, April to November', 'Checks done against the schedule', 'checks', true, 'UKHSA contingency plan, Level 0'),
    (v, 'at_risk_communities', 3, 'At-risk communities',
     'Where modelling shows suitable climate and habitat, place targeted traps, run by trappers trained by UKHSA.',
     'Where modelling shows risk', 'Sites with a modelled-risk reason; training records', 'assessment', false, 'UKHSA contingency plan, Level 0'),
    (v, 'identification', 4, 'Samples to UKHSA for identification',
     'Send samples to UKHSA''s medical entomology team for identification.',
     'Each sample', 'Official identification route; lab report and species recorded', 'official_id', true, 'UKHSA contingency plan'),
    (v, 'reporting', 5, 'Report results to UKHSA',
     'Report detections and negative results to UKHSA as soon as practicable, and invasive finds immediately.',
     'As soon as practicable; invasive finds immediately', 'Reporting records with times', 'assessment', true, 'UKHSA contingency plan'),
    (v, 'training', 6, 'UKHSA training',
     'Take part in UKHSA training on surveillance, incident response and control.',
     'As offered', 'Training and competence records', 'assessment', true, 'UKHSA contingency plan'),
    (v, 'local_plan', 7, 'Local plan or procedure',
     'Keep and exercise a local plan or procedure that is proportionate to local risk.',
     'Reviewed and exercised regularly', 'Plan with review and exercise dates', 'assessment', true, 'UKHSA contingency plan'),
    (v, 'source_reduction', 8, 'Reduce breeding sites',
     'Reduce litter and breeding sites at ports of entry and high-risk sites.',
     'Ongoing', 'Control actions (source reduction)', 'assessment', true, 'UKHSA contingency plan'),
    (v, 'response', 9, 'Respond by risk level',
     'If invasive mosquitoes are found, respond according to the risk level (0 to 4): for example control within a 200 to 300 metre buffer and enhanced surveillance with adult traps, ovitraps and larval sampling, with UKHSA advice.',
     'When a detection is made', 'Risk level on the incursion; delimiting surveys; buffer zone; control actions', 'assessment', true, 'UKHSA contingency plan, Levels 1 to 4');
    update public.vv_obligation_versions set status = 'in_review' where id = v;
  end if;
end $load$;
