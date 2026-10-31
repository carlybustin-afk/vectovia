-- Knowledge library: first drafts of the powers and obligations register, procedures and forms
-- (owner decision 2026-11-01: drafted from official sources, then specialist review).
-- Every page loads as "in review" with no named author (like the obligation set drafts; needs v2-008):
-- nothing is visible to organisations until a reviewer approves it and a content admin publishes it.
-- Each page lists its sources and the points the reviewer must check ("review_points"). Safe to run twice.
-- Drafted 2026-11-01 from: legislation.gov.uk (EPA 1990 ss79-80; CNEA 2005 s101; WCA 1981 Sch 9A;
-- PH(CD)A 1984 Part 2A; SI 2010/657, 658; SI 1979/1434, 1435; SI 2007/1446), WHO IHR (2005) and WHO's
-- PoE vector handbook, and UKHSA's national contingency plan for invasive Aedes mosquitoes in England (2026).

create or replace function pg_temp.vv_load(_kind text, _key text, _title text, _category text, _sort int, _content jsonb, _sources jsonb) returns void
  language plpgsql as $$
declare d uuid;
begin
  insert into public.vv_library_documents (id, kind, key, title, category, sort_order, created_by)
  values (gen_random_uuid(), _kind, _key, _title, _category, _sort, '00000000-0000-0000-0000-000000000000')
  on conflict (key) do nothing;
  select id into d from public.vv_library_documents where key = _key;
  if not exists (select 1 from public.vv_library_versions where document_id = d) then
    insert into public.vv_library_versions (kind, document_id, version, content, sources, status, author_id)
    values (_kind, d, 1, _content, _sources, 'in_review', null);
  end if;
end $$;

-- ===================== Powers and obligations ==========================================================
select pg_temp.vv_load('power', 'ihr_art22_annex5_400m', 'IHR (2005): vector control at points of entry (Article 22 and Annex 5)', 'International Health Regulations', 10,
$j${
 "summary": "States must keep the facilities travellers use at points of entry free of sources of infection, including vectors and reservoirs, and keep vector control going to at least 400 metres from the areas used for travellers, conveyances, containers, cargo and postal parcels, further where vectors with a greater range are present.",
 "instrument": "International Health Regulations (2005)",
 "provision": "Article 22(1)(b); Annex 5, paragraph 4",
 "jurisdiction": "International (applies to the UK as a State Party)",
 "who_can_use": "The competent authority at each point of entry (in the UK, the port health authority or the local authority acting for it).",
 "what_it_requires": ["Facilities used by travellers kept in a sanitary condition and free of vectors and reservoirs.", "Vector surveillance and control within at least 400 m of operational areas, extended where vectors with a greater flight range are present."],
 "non_compliance": "Not a UK offence in itself. Gaps are reported through the IHR monitoring framework and can affect whether a port or airport keeps its designation and its ability to issue ship sanitation certificates.",
 "related_requirements": ["ihr_point_of_entry: zone_400m", "ihr_point_of_entry: integrated_programme"],
 "review_points": ["Check the wording of Article 22(1)(b) and Annex 5 paragraph 4 against the WHO third edition text.", "Confirm the statement on consequences for designation."]
}$j$,
$j$[{"title":"WHO: International Health Regulations (2005), third edition","url":"https://www.who.int/publications/i/item/9789241580496"},
    {"title":"WHO: Vector surveillance and control at ports, airports and ground crossings","url":"https://www.who.int/publications/i/item/9789241549592"}]$j$);

select pg_temp.vv_load('power', 'ihr_annex1b_core_capacity', 'IHR (2005): core capacities at designated points of entry (Annex 1B)', 'International Health Regulations', 20,
$j${
 "summary": "Designated airports and ports must have the core capacities in Annex 1B at all times, including, as far as practicable, a programme and trained personnel for controlling vectors and reservoirs in and near the point of entry.",
 "instrument": "International Health Regulations (2005)",
 "provision": "Article 20; Annex 1, Part B",
 "jurisdiction": "International (applies to the UK as a State Party)",
 "who_can_use": "Government designates the points of entry; the competent authority at each one keeps the capacities.",
 "what_it_requires": ["A vector control programme in and near the point of entry.", "Trained personnel.", "Arrangements to respond to events that may be a public health emergency of international concern."],
 "non_compliance": "Designated points of entry are expected to keep these capacities; persistent gaps can put designation at risk.",
 "related_requirements": ["ihr_point_of_entry: integrated_programme", "ihr_point_of_entry: competent_personnel"],
 "review_points": ["Check the Annex 1B wording on vector control.", "Confirm how UK designation is managed and reviewed."]
}$j$,
$j$[{"title":"WHO: International Health Regulations (2005), third edition","url":"https://www.who.int/publications/i/item/9789241580496"}]$j$);

select pg_temp.vv_load('power', 'epa_s79_insects', 'Statutory nuisance from insects (EPA 1990 s79(1)(fa))', 'UK legislation: nuisance', 30,
$j${
 "summary": "Insects coming from relevant industrial, trade or business premises that are prejudicial to health or a nuisance are a statutory nuisance. Councils must inspect their area for statutory nuisances and investigate complaints.",
 "instrument": "Environmental Protection Act 1990 (insects added by the Clean Neighbourhoods and Environment Act 2005, s101)",
 "provision": "Section 79(1)(fa), (5A) and (7C)",
 "jurisdiction": "England and Wales (Scotland has its own, broader provision)",
 "who_can_use": "The local authority (environmental health).",
 "what_it_requires": ["Only insects from relevant industrial, trade or business premises are covered.", "Excluded land includes agricultural land, woodland, nurseries, orchards, sites of special scientific interest, and rivers, watercourses (other than sewers and drains), lakes and ponds.", "Protected wild insects in Schedule 5 of the Wildlife and Countryside Act 1981 are excluded."],
 "non_compliance": "Leads to an abatement notice under section 80.",
 "related_requirements": [],
 "review_points": ["Confirm how far s79(1)(fa) reaches mosquito breeding at ports, service stations and tyre yards.", "Confirm the exclusions list against the current text."]
}$j$,
$j$[{"title":"legislation.gov.uk: Environmental Protection Act 1990, section 79","url":"https://www.legislation.gov.uk/ukpga/1990/43/section/79"},
    {"title":"legislation.gov.uk: Clean Neighbourhoods and Environment Act 2005, section 101","url":"https://www.legislation.gov.uk/ukpga/2005/16/section/101"}]$j$);

select pg_temp.vv_load('power', 'epa_s80_abatement', 'Abatement notices (EPA 1990 s80)', 'UK legislation: nuisance', 40,
$j${
 "summary": "Where a council is satisfied that a statutory nuisance exists, or is likely to occur or recur, it must serve an abatement notice requiring it to be abated or restricted, with the steps and the time to comply.",
 "instrument": "Environmental Protection Act 1990",
 "provision": "Section 80",
 "jurisdiction": "England and Wales (separate Scottish version)",
 "who_can_use": "The local authority.",
 "what_it_requires": ["Serve on the person responsible; on the owner if it arises from a structural defect; on the owner or occupier if the person responsible cannot be found or the nuisance has not yet occurred.", "The person served can appeal to the magistrates' court within 21 days of service."],
 "non_compliance": "Failing to comply without reasonable excuse is an offence, with a higher maximum fine for industrial, trade or business premises. Defences, including best practicable means, may apply.",
 "related_requirements": [],
 "review_points": ["Confirm the best practicable means defence as it applies to insect nuisance.", "Confirm current penalty levels."]
}$j$,
$j$[{"title":"legislation.gov.uk: Environmental Protection Act 1990, section 80","url":"https://www.legislation.gov.uk/ukpga/1990/43/section/80"}]$j$);

select pg_temp.vv_load('power', 'phcda_part2a_orders', 'Part 2A orders (Public Health (Control of Disease) Act 1984)', 'UK legislation: health protection', 50,
$j${
 "summary": "Where voluntary measures fail, a council can apply to a justice of the peace for an order requiring action in relation to people, things or premises to remove or reduce a significant risk to human health, for example infection or contamination.",
 "instrument": "Public Health (Control of Disease) Act 1984, Part 2A; Health Protection (Part 2A Orders) Regulations 2010 (SI 2010/658)",
 "provision": "Part 2A",
 "jurisdiction": "England and Wales (separate regulations in Wales)",
 "who_can_use": "The local authority, by application to a justice of the peace.",
 "what_it_requires": ["Evidence that the risk is significant and that an order is necessary and proportionate.", "The regulations set out procedure and notice."],
 "non_compliance": "Failing to comply with a Part 2A order is an offence.",
 "related_requirements": [],
 "review_points": ["Confirm which sections (people, things, premises) apply to vector control.", "Confirm the offence provision."]
}$j$,
$j$[{"title":"legislation.gov.uk: Public Health (Control of Disease) Act 1984, Part 2A","url":"https://www.legislation.gov.uk/ukpga/1984/22/part/2A"},
    {"title":"legislation.gov.uk: Health Protection (Part 2A Orders) Regulations 2010","url":"https://www.legislation.gov.uk/uksi/2010/658/contents"}]$j$);

select pg_temp.vv_load('power', 'hp_local_authority_powers', 'Health Protection (Local Authority Powers) Regulations 2010', 'UK legislation: health protection', 60,
$j${
 "summary": "Gives councils in England health protection powers, including powers to request co-operation from people and organisations for health protection purposes.",
 "instrument": "Health Protection (Local Authority Powers) Regulations 2010 (SI 2010/657)",
 "provision": "Whole instrument",
 "jurisdiction": "England",
 "who_can_use": "The local authority.",
 "what_it_requires": [],
 "non_compliance": "To be confirmed by the reviewer.",
 "related_requirements": [],
 "review_points": ["Summarise the powers relevant to vector control (for example the request for co-operation).", "Confirm whether any offence applies."]
}$j$,
$j$[{"title":"legislation.gov.uk: Health Protection (Local Authority Powers) Regulations 2010","url":"https://www.legislation.gov.uk/uksi/2010/657/contents"}]$j$);

select pg_temp.vv_load('power', 'wca_sch9a_species_control', 'Species control agreements and orders (Wildlife and Countryside Act 1981, Schedule 9A)', 'UK legislation: invasive species', 70,
$j${
 "summary": "Environmental authorities can make species control agreements with owners or occupiers, and species control orders where agreement fails, to control invasive non-native species on their land.",
 "instrument": "Wildlife and Countryside Act 1981, Schedule 9A",
 "provision": "Schedule 9A",
 "jurisdiction": "England and Wales",
 "who_can_use": "Environmental authorities: in England the Secretary of State, the Environment Agency, Natural England and the Forestry Commissioners; in Wales the Welsh Ministers and Natural Resources Wales. Not local authorities directly.",
 "what_it_requires": ["Covers species of special concern, other invasive non-native species, and animals no longer normally present in Great Britain.", "An agreement is offered first; an order follows if it is refused or not kept."],
 "non_compliance": "Failing to comply with an order without reasonable excuse, or obstructing operations under it, is an offence (up to 51 weeks' imprisonment, a fine, or both).",
 "related_requirements": [],
 "review_points": ["UKHSA's contingency plan lists species control orders among local authority powers; confirm how a council would ask an environmental authority to use them for invasive mosquitoes.", "Confirm whether invasive Aedes species meet the Schedule 9A definitions."]
}$j$,
$j$[{"title":"legislation.gov.uk: Wildlife and Countryside Act 1981, Schedule 9A","url":"https://www.legislation.gov.uk/ukpga/1981/69/schedule/9A"},
    {"title":"UKHSA: National contingency plan for invasive Aedes mosquitoes in England","url":"https://www.gov.uk/guidance/national-contingency-plan-for-invasive-aedes-mosquitoes-in-england"}]$j$);

select pg_temp.vv_load('power', 'ph_ships_aircraft_1979', 'Public Health (Ships) and (Aircraft) Regulations 1979', 'UK legislation: port health', 80,
$j${
 "summary": "The main port health regulations for ships and aircraft, amended in England in 2007 to implement the International Health Regulations (2005), including ship sanitation certificates.",
 "instrument": "Public Health (Ships) Regulations 1979 (SI 1979/1435); Public Health (Aircraft) Regulations 1979 (SI 1979/1434); amended in England in 2007",
 "provision": "Whole instruments",
 "jurisdiction": "England (separate arrangements elsewhere in the UK)",
 "who_can_use": "Port health authorities and their authorised officers.",
 "what_it_requires": [],
 "non_compliance": "To be confirmed by the reviewer.",
 "related_requirements": ["ihr_point_of_entry: conveyances", "ihr_point_of_entry: treatment_supervision"],
 "review_points": ["Summarise the provisions on inspecting ships and aircraft and requiring disinsection or other measures.", "Confirm the current amended position."]
}$j$,
$j$[{"title":"legislation.gov.uk: Public Health (Ships) Regulations 1979","url":"https://www.legislation.gov.uk/uksi/1979/1435/contents"},
    {"title":"legislation.gov.uk: Public Health (Aircraft) Regulations 1979","url":"https://www.legislation.gov.uk/uksi/1979/1434/contents"},
    {"title":"legislation.gov.uk: Public Health (Ships) (Amendment) (England) Regulations 2007","url":"https://www.legislation.gov.uk/uksi/2007/1446/contents"}]$j$);

select pg_temp.vv_load('power', 'ukhsa_contingency_plan', 'UKHSA national contingency plan for invasive Aedes mosquitoes in England', 'UK guidance', 90,
$j${
 "summary": "National guidance (2026) setting out surveillance at Level 0 and the response at Levels 1 to 4, from a first detection to widespread establishment with local cases. It is guidance, not legislation, and it names the legal powers councils and others rely on.",
 "instrument": "UKHSA guidance (published 21 May 2026)",
 "provision": "Whole plan",
 "jurisdiction": "England",
 "who_can_use": "UKHSA (health protection teams; Medical Entomology and Zoonoses Ecology team), local authorities and port health authorities.",
 "what_it_requires": ["Level 0: trapping at high-risk sites June to October and at ports and airports April to November, checked every 2 weeks.", "Level 1 (detection): joint investigation, incident management team, enhanced surveillance, and targeted control within about 200 to 300 m of the detection (source reduction, larviciding, community engagement).", "Levels 2 to 4: established populations and local cases, with wider control."],
 "non_compliance": "Guidance; the legal consequences come from the powers it cites.",
 "related_requirements": ["ukhsa_invasive_aedes_england: all"],
 "review_points": ["Check the levels and buffer distances against the full plan and its annexes."]
}$j$,
$j$[{"title":"UKHSA: National contingency plan for invasive Aedes mosquitoes in England","url":"https://www.gov.uk/guidance/national-contingency-plan-for-invasive-aedes-mosquitoes-in-england"}]$j$);

-- ===================== Procedures ========================================================================
select pg_temp.vv_load('procedure', 'proc_suspected_invasive_find', 'Responding to a suspected invasive Aedes find', 'Response', 10,
$j${
 "summary": "What to do from the moment a suspected invasive Aedes mosquito (egg, larva or adult) is found, until UKHSA confirms or rules it out.",
 "when": "Any find provisionally identified as an invasive Aedes species, at any site.",
 "steps": ["Record the find in Vectovia as provisional with the species suspected; it is flagged for official identification automatically.", "Send the specimen to UKHSA's Medical Entomology and Zoonoses Ecology (MEZE) team for identification, and record the dispatch.", "Tell the local health protection team (UKHSA) and your environmental health lead the same day.", "Do not wait for confirmation to remove obvious breeding sites near the trap (source reduction).", "If confirmed, the health protection team convenes an incident management team; start a delimiting survey in Vectovia (about 200 to 300 m around the detection, radius set by the IMT).", "Record every inspection, sample, control action and notification against the survey or incursion."],
 "records": ["Provisional result and official identification", "Notifications (UKHSA, others)", "Delimiting survey, inspections and control actions"],
 "safety": "Handle specimens with gloves; follow your organisation's lone-working and site access rules.",
 "related_requirements": ["ihr_point_of_entry: identification", "ukhsa_invasive_aedes_england: identification", "ukhsa_invasive_aedes_england: reporting", "ukhsa_invasive_aedes_england: response"],
 "review_points": ["Confirm current UKHSA contact routes and sample submission arrangements.", "Confirm the default delimiting radius."]
}$j$,
$j$[{"title":"UKHSA: National contingency plan for invasive Aedes mosquitoes in England","url":"https://www.gov.uk/guidance/national-contingency-plan-for-invasive-aedes-mosquitoes-in-england"},
    {"title":"UKHSA: Invasive mosquito surveillance","url":"https://www.gov.uk/guidance/invasive-mosquito-surveillance"}]$j$);

select pg_temp.vv_load('procedure', 'proc_ovitrap_check', 'Checking an ovitrap', 'Field procedures', 20,
$j${
 "summary": "Routine check of an ovitrap (egg trap): collect the egg substrate, reset the trap and record the visit.",
 "when": "On the schedule set for the programme (for example every 2 weeks in season).",
 "steps": ["Find the trap at its recorded location; note if it is missing, damaged, dry or flooded.", "Remove the egg substrate (paper, stick or strip) without touching the eggs; place it in a labelled bag or container.", "Empty, rinse and refill the trap with clean water to the marked level; fit a new substrate.", "Record the visit in Vectovia (working or not, sample taken) and label the sample with its Vectovia reference.", "Send substrates for counting and identification as your programme requires."],
 "records": ["Visit with trap condition", "Sample with reference"],
 "safety": "Avoid traffic and operational areas without permission; wear gloves.",
 "related_requirements": ["ihr_point_of_entry: surveillance", "ukhsa_invasive_aedes_england: ports_airports", "ukhsa_invasive_aedes_england: high_risk_sites"],
 "review_points": ["Check against UKHSA's ovitrap protocol (substrate, water, any larvicide, check interval)."]
}$j$,
$j$[{"title":"UKHSA: Invasive mosquito surveillance","url":"https://www.gov.uk/guidance/invasive-mosquito-surveillance"},
    {"title":"ECDC: Guidelines for the surveillance of invasive mosquitoes in Europe","url":"https://www.ecdc.europa.eu/en/publications-data/guidelines-surveillance-invasive-mosquitoes-europe"}]$j$);

select pg_temp.vv_load('procedure', 'proc_larval_dip', 'Larval sampling from containers and standing water', 'Field procedures', 30,
$j${
 "summary": "Sampling larvae and pupae from containers, tyres, drains and other standing water during an inspection or delimiting survey.",
 "when": "Ad hoc inspections, sanitary surveys and delimiting surveys.",
 "steps": ["Look for water-holding containers: tyres, buckets, plant-pot saucers, gutters, drains, tarpaulins.", "Use a dipper or pipette to sample; for small containers, pour through a sieve or into a white tray.", "Transfer larvae and pupae to a labelled tube; record the habitat and location.", "Record the inspection in Vectovia with the samples; mark it as part of a survey if it is one.", "Remove or empty the container if it is safe and you are allowed to (source reduction), and record that as a control action."],
 "records": ["Inspection with habitat and location", "Samples", "Control action if a breeding site was removed"],
 "safety": "Wear gloves; take care near deep water and drains.",
 "related_requirements": ["ihr_point_of_entry: surveillance", "ukhsa_invasive_aedes_england: source_reduction"],
 "review_points": ["Check sample preservation instructions against UKHSA guidance."]
}$j$,
$j$[{"title":"ECDC: Guidelines for the surveillance of invasive mosquitoes in Europe","url":"https://www.ecdc.europa.eu/en/publications-data/guidelines-surveillance-invasive-mosquitoes-europe"},
    {"title":"WHO: Vector surveillance and control at ports, airports and ground crossings","url":"https://www.who.int/publications/i/item/9789241549592"}]$j$);

select pg_temp.vv_load('procedure', 'proc_conveyance_inspection', 'Inspecting a conveyance for vectors', 'Point of entry', 40,
$j${
 "summary": "Inspecting a ship, aircraft, vehicle or container that is affected or suspected of carrying vectors, and deciding what action and follow-up is needed.",
 "when": "Affected or suspect conveyances, and routine inspections set by the port health authority.",
 "steps": ["Record why the conveyance is being inspected (routine, affected or suspect), where it came from and where it goes next.", "Look for adult mosquitoes, larvae in standing water (deck areas, tarpaulins, containers, tyres) and other vectors.", "Take samples of anything found and record them.", "Agree and supervise any treatment (for example removing water, larviciding, disinsection) and record it as a control action with the supervisor named.", "If there were findings and the conveyance travels on, send a follow-up notice to the next point of entry and record it in Vectovia."],
 "records": ["Conveyance inspection", "Samples", "Control action with supervisor", "Follow-up notice and acknowledgement"],
 "safety": "Follow the conveyance operator's safety rules and your organisation's boarding procedures.",
 "related_requirements": ["ihr_point_of_entry: conveyances", "ihr_point_of_entry: follow_up", "ihr_point_of_entry: treatment_supervision"],
 "review_points": ["Confirm the legal basis for inspection and treatment of ships and aircraft (see the port health regulations entry)."]
}$j$,
$j$[{"title":"WHO: Vector surveillance and control at ports, airports and ground crossings","url":"https://www.who.int/publications/i/item/9789241549592"},
    {"title":"WHO: International Health Regulations (2005), third edition","url":"https://www.who.int/publications/i/item/9789241580496"}]$j$);

-- ===================== Forms ========================================================================
select pg_temp.vv_load('form', 'form_sanitary_survey', 'Sanitary and vector survey checklist', 'Survey forms', 10,
$j${
 "summary": "Checklist for the yearly sanitary and vector survey of a site and its zone. Record the result in Vectovia as a site review.",
 "sections": [
  {"title": "Water-holding containers", "items": ["Tyres stored outside (covered, drilled or under cover?)", "Buckets, drums, plant pots and saucers", "Tarpaulins and covers that pond water", "Abandoned equipment and vehicles"]},
  {"title": "Drainage", "items": ["Blocked gullies and drains", "Gutters holding water", "Standing water after rain"]},
  {"title": "Waste and litter", "items": ["Litter that can hold water", "Waste storage areas covered"]},
  {"title": "Vegetation", "items": ["Dense vegetation near terminals and cargo areas", "Plants that hold water (for example bromeliads)"]},
  {"title": "Follow-up", "items": ["Corrective actions agreed, with owners and dates", "Breeding sites removed during the survey (record as control actions)"]}
 ],
 "related_requirements": ["ihr_point_of_entry: sanitary_facilities"],
 "review_points": ["Check items against WHO's PoE handbook survey forms."]
}$j$,
$j$[{"title":"WHO: Vector surveillance and control at ports, airports and ground crossings","url":"https://www.who.int/publications/i/item/9789241549592"}]$j$);

select pg_temp.vv_load('form', 'form_conveyance_inspection', 'Conveyance inspection checklist', 'Survey forms', 20,
$j${
 "summary": "Checklist to take on board when inspecting a conveyance. Record the result in Vectovia as a conveyance inspection.",
 "sections": [
  {"title": "About the conveyance", "items": ["Type and name or identifier", "Arrived from; next point of entry", "Reason for inspection (routine, affected, suspect)"]},
  {"title": "What to check", "items": ["Standing water on deck, in tarpaulins, containers and tyres", "Adult mosquitoes in cabins, holds or cargo areas", "Evidence of other vectors or reservoirs"]},
  {"title": "Action", "items": ["Treatment agreed and who supervised it", "Samples taken", "Follow-up notice needed to the next point of entry"]}
 ],
 "related_requirements": ["ihr_point_of_entry: conveyances"],
 "review_points": ["Align with WHO handbook and port health practice."]
}$j$,
$j$[{"title":"WHO: Vector surveillance and control at ports, airports and ground crossings","url":"https://www.who.int/publications/i/item/9789241549592"}]$j$);
