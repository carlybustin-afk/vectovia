/**
 * The First Line line-and-node motif, used sparingly to show
 * connection and progression (ASSESS → DECIDE → ACT).
 */
export function NodeLine({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 320 24"
      fill="none"
      aria-hidden="true"
      className={className}
      preserveAspectRatio="xMidYMid meet"
    >
      <line x1="12" y1="12" x2="308" y2="12" stroke="var(--color-ring)" strokeWidth="2" />
      <circle cx="12" cy="12" r="8" fill="var(--color-background)" stroke="var(--color-ring)" strokeWidth="2" />
      <circle cx="160" cy="12" r="8" fill="var(--color-background)" stroke="var(--color-accent)" strokeWidth="2" />
      <circle cx="308" cy="12" r="8" fill="var(--color-background)" stroke="var(--color-primary)" strokeWidth="2" />
    </svg>
  );
}
