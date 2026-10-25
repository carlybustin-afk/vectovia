import { createFileRoute } from "@tanstack/react-router";
import { LegalPlaceholder, legalHead } from "../components/legal-placeholder";

export const Route = createFileRoute("/terms")({
  head: () =>
    legalHead(
      "Terms (preview placeholder) — First Line",
      "Development preview placeholder for the First Line website terms. Full terms will be completed before public launch.",
    ),
  component: () => (
    <LegalPlaceholder
      label="Terms"
      title="Website terms"
      points={[
        "This website provides general information about First Line tools, which are in development.",
        "The website does not provide legal, regulatory or enforcement advice.",
        "Tool features, access tiers and availability described on this site are planned and may change.",
      ]}
    />
  ),
});
