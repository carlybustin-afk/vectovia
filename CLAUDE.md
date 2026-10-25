# Claude instructions — Vectovia

@AGENTS.md

## Agreed design
- The governing design is `docs/vectovia/design-v2.md` (owner decisions 2026-10-26). The original brief and
  first-build plan (`docs/vectovia-brief.md`, `docs/vectovia-plan.md`) are background; where they differ, v2 wins.
- Priority: a functional, low-cost, fast-moving MVP to pitch to UK Government. Build what tells the pitch story
  end to end; keep the rest in the design without building it yet.
- Don't apply migrations, deploy, change access, introduce paid services or expand AI data transmission without
  the owner's explicit approval. Draft schema changes in `docs/database/` and test them locally first.
- UI, copy and documents follow `docs/brand/brand-guidelines-v1.md`: existing tokens in `src/styles.css`, the
  supplied First Line logo, the Vectovia wordmark, no new colours and no green interface colour, WCAG 2.2 AA,
  plain professional wording and honest feature status.
- Vectovia is a separate system from First Line Investigations: no case data, no case code.
