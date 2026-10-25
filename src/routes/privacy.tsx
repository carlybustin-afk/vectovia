import { createFileRoute } from "@tanstack/react-router";
import { LegalPlaceholder, legalHead } from "../components/legal-placeholder";

export const Route = createFileRoute("/privacy")({
  head: () =>
    legalHead(
      "Privacy (preview placeholder) — First Line",
      "Development preview placeholder for the First Line privacy notice. A full notice will be completed before public launch.",
    ),
  component: () => (
    <LegalPlaceholder
      label="Privacy"
      title="Privacy notice"
      points={[
        "This website has no accounts, sign-in or forms that collect personal information.",
        "No application-level tracking or analytics tools are used on this website.",
        "Like most websites, the hosting provider may process technical information such as IP addresses and access logs to deliver and secure the site.",
        "If you email us, we will receive the information you choose to include in your message.",
      ]}
    />
  ),
});
