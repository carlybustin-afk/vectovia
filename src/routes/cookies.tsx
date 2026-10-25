import { createFileRoute } from "@tanstack/react-router";
import { LegalPlaceholder, legalHead } from "../components/legal-placeholder";

export const Route = createFileRoute("/cookies")({
  head: () =>
    legalHead(
      "Cookies (preview placeholder) — First Line",
      "Development preview placeholder for the First Line cookies notice. A full notice will be completed before public launch.",
    ),
  component: () => (
    <LegalPlaceholder
      label="Cookies"
      title="Cookies notice"
      points={[
        "This website does not set its own tracking or analytics cookies.",
        "This public website does not use browser storage to save cases, accounts or tool activity.",
        "The hosting platform may use technical mechanisms needed to deliver the site; these will be confirmed in the final notice.",
      ]}
    />
  ),
});
