// Vectovia exports (src/modules/vectovia/export-doc.ts, export-writers.ts).
import { blobBytes, safeName, sha256Hex, toCsv, type ExportDoc } from "@/modules/vectovia/export-doc";
import { pdfText, toDocx, toPdf } from "@/modules/vectovia/export-writers";

describe("CSV", () => {
  it("quotes commas, quotes and line breaks, and starts with a byte-order mark for Excel", () => {
    const csv = toCsv(["a", "b"], [["x, y", 'say "hi"'], ["line\nbreak", null]]);
    expect(csv.startsWith("﻿a,b\r\n")).toBe(true);
    expect(csv).toContain('"x, y","say ""hi"""\r\n');
    expect(csv).toContain('"line\nbreak",\r\n');
  });
  it("never lets a cell run as a spreadsheet formula", () => {
    const csv = toCsv(["v"], [["=HYPERLINK(\"http://x\")"], ["+1+1"], ["@SUM(A1)"], ["-2+3"], ["-12.5"], [42]]);
    expect(csv).toContain(`"'=HYPERLINK(""http://x"")"`);
    expect(csv).toContain("'+1+1");
    expect(csv).toContain("'@SUM(A1)");
    expect(csv).toContain("'-2+3");
    expect(csv).toContain("\r\n-12.5\r\n"); // plain negative numbers stay numbers
    expect(csv).toContain("\r\n42\r\n");
  });
  it("makes safe file names", () => {
    expect(safeName("Test Council (made-up) / Port")).toBe("Test-Council-made-up-Port");
  });
});

describe("fingerprints", () => {
  it("is the SHA-256 of the file", async () => {
    expect(await sha256Hex(new Blob(["abc"]))).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });
});

describe("report files", () => {
  const doc: ExportDoc = {
    title: "Vector surveillance report", subtitle: "SYNTHETIC Council · 1 Jan 2026 to 17 Oct 2026",
    meta: [["Council", "SYNTHETIC Council"], ["Report ID", "test"]],
    blocks: [
      { t: "h1", text: "Summary" }, { t: "kv", rows: [["Trap-nights", "12"]] },
      { t: "table", caption: "Sites", head: ["Site", "Findings"], rows: [["VS-0001 · Dock 4", "1"]] },
      { t: "table", head: ["Empty"], rows: [] }, { t: "note", text: "Collection → result ≥ 1 day ▲" },
    ],
    footer: "Vectovia by First Line",
  };
  it("swaps symbols the standard PDF fonts can't show", () => {
    expect(pdfText("Collection → result ≥ 1 day ▲ 3 × 4")).toBe("Collection -> result >= 1 day  3 x 4");
    expect(pdfText("VS-0001 · Dock 4 – café ‘quoted’")).toBe("VS-0001 · Dock 4 – café ‘quoted’");
  });
  it("writes a PDF", async () => {
    const blob = await toPdf(doc);
    const head = new TextDecoder().decode(new Uint8Array(await blobBytes(blob)).slice(0, 5));
    expect(head).toBe("%PDF-");
    expect(blob.size).toBeGreaterThan(1000);
  });
  it("writes a Word file", async () => {
    const blob = await toDocx(doc);
    const head = new Uint8Array(await blobBytes(blob)).slice(0, 2);
    expect([...head]).toEqual([0x50, 0x4b]); // a .docx is a zip file ("PK")
  });
});
