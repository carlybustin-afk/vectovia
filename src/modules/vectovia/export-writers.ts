// Writes an ExportDoc as PDF (jsPDF + jspdf-autotable) or Word (docx). Loaded
// only when someone downloads a report, so these libraries don't slow other pages.
import type { ExportDoc } from "./export-doc";

const NAVY = "082B4C", TEAL = "14A38B", GREY = "5B6770";

/** The standard PDF fonts cover Western European text; swap the few symbols they lack. */
export const pdfText = (s: string) => s
  .replace(/→/g, "->").replace(/←/g, "<-").replace(/≥/g, ">=").replace(/≤/g, "<=").replace(/×/g, "x").replace(/▲/g, "")
  .replace(/[‐-‒]/g, "-").replace(/[^\x09\x0A\x0D\x20-\x7E -ÿ–—‘’“”•…€]/g, "?");

export async function toPdf(doc: ExportDoc): Promise<Blob> {
  const [{ jsPDF }, { autoTable }] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
  const pdf = new jsPDF({ unit: "mm", format: "a4" });
  const W = pdf.internal.pageSize.getWidth(), H = pdf.internal.pageSize.getHeight(), M = 15;
  let y = M;
  const room = (h: number) => { if (y + h > H - 18) { pdf.addPage(); y = M; } };
  const text = (s: string, size: number, color: string, bold = false, gap = 1.5) => {
    pdf.setFont("helvetica", bold ? "bold" : "normal"); pdf.setFontSize(size); pdf.setTextColor(`#${color}`);
    const lines = pdf.splitTextToSize(pdfText(s), W - 2 * M) as string[];
    const lh = size * 0.42;
    for (const l of lines) { room(lh); pdf.text(l, M, y + lh * 0.8); y += lh; }
    y += gap;
  };
  text(doc.title, 18, NAVY, true, 1);
  text(doc.subtitle, 10, GREY, false, 3);
  pdf.setDrawColor(`#${TEAL}`); pdf.setLineWidth(0.6); pdf.line(M, y, W - M, y); y += 4;
  const kv = (rows: [string, string][]) => {
    autoTable(pdf, {
      startY: y, margin: { left: M, right: M }, theme: "plain", styles: { fontSize: 9, cellPadding: 0.8, textColor: `#${NAVY}` },
      columnStyles: { 0: { cellWidth: 45, textColor: `#${GREY}` } }, body: rows.map(([k, v]) => [pdfText(k), pdfText(v)]),
    });
    y = (pdf as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 4;
  };
  kv(doc.meta);
  for (const b of doc.blocks) {
    if (b.t === "h1") { room(14); y += 2; text(b.text, 14, NAVY, true, 2); }
    else if (b.t === "h2") { room(10); text(b.text, 11, NAVY, true, 1.5); }
    else if (b.t === "p") text(b.text, 9.5, NAVY, false, 2);
    else if (b.t === "note") text(b.text, 8, GREY, false, 2);
    else if (b.t === "kv") kv(b.rows);
    else if (b.t === "table") {
      if (b.caption) { room(10); text(b.caption, 9, GREY, true, 1); }
      if (!b.rows.length) { text("None in this report.", 9, GREY, false, 3); continue; }
      autoTable(pdf, {
        startY: y, margin: { left: M, right: M, bottom: 18 }, head: [b.head.map(pdfText)], body: b.rows.map((r) => r.map(pdfText)),
        styles: { fontSize: 8, cellPadding: 1.2, textColor: `#${NAVY}`, lineColor: "#D9DEE2", lineWidth: 0.1, overflow: "linebreak" },
        headStyles: { fillColor: `#${NAVY}`, textColor: "#FFFFFF", fontStyle: "bold" }, alternateRowStyles: { fillColor: "#F2F7F6" },
        ...(b.widths ? { columnStyles: Object.fromEntries(b.widths.map((w, i) => [i, { cellWidth: w }])) } : {}),
      });
      y = (pdf as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 5;
    }
  }
  const n = pdf.getNumberOfPages();
  for (let i = 1; i <= n; i++) {
    pdf.setPage(i); pdf.setFont("helvetica", "normal"); pdf.setFontSize(7.5); pdf.setTextColor(`#${GREY}`);
    pdf.text(pdfText(`${doc.footer} · Page ${i} of ${n}`), M, H - 8);
  }
  return pdf.output("blob");
}

export async function toDocx(doc: ExportDoc): Promise<Blob> {
  const d = await import("docx");
  const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType, HeadingLevel, ShadingType, Footer, PageNumber, AlignmentType, BorderStyle } = d;
  const run = (text: string, o: { bold?: boolean; color?: string; size?: number } = {}) =>
    new TextRun({ text, bold: o.bold ?? false, color: o.color ?? NAVY, size: o.size ?? 20, font: "Arial" });
  const border = { style: BorderStyle.SINGLE, size: 2, color: "D9DEE2" };
  const borders = { top: border, bottom: border, left: border, right: border };
  const table = (head: string[] | null, rows: string[][]) => new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    rows: [
      ...(head ? [new TableRow({ tableHeader: true, children: head.map((h) => new TableCell({ borders,
        shading: { type: ShadingType.CLEAR, color: "auto", fill: NAVY }, children: [new Paragraph({ children: [run(h, { bold: true, color: "FFFFFF", size: 18 })] })] })) })] : []),
      ...rows.map((r, i) => new TableRow({ children: r.map((c, j) => new TableCell({ borders,
        ...(head && i % 2 ? { shading: { type: ShadingType.CLEAR, color: "auto", fill: "F2F7F6" } } : {}),
        children: c.split("\n").map((line) => new Paragraph({ children: [run(line, { size: 18, color: !head && j === 0 ? GREY : NAVY })] })) })) })),
    ],
  });
  const children: (InstanceType<typeof Paragraph> | InstanceType<typeof Table>)[] = [
    new Paragraph({ heading: HeadingLevel.TITLE, children: [run(doc.title, { bold: true, size: 36 })] }),
    new Paragraph({ spacing: { after: 200 }, children: [run(doc.subtitle, { color: GREY })] }),
    table(null, doc.meta),
  ];
  for (const b of doc.blocks) {
    if (b.t === "h1") children.push(new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 300, after: 120 }, children: [run(b.text, { bold: true, size: 28 })] }));
    else if (b.t === "h2") children.push(new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { before: 200, after: 80 }, children: [run(b.text, { bold: true, size: 22 })] }));
    else if (b.t === "p") children.push(new Paragraph({ spacing: { after: 120 }, children: [run(b.text)] }));
    else if (b.t === "note") children.push(new Paragraph({ spacing: { after: 120 }, children: [run(b.text, { color: GREY, size: 16 })] }));
    else if (b.t === "kv") children.push(table(null, b.rows));
    else if (b.t === "table") {
      if (b.caption) children.push(new Paragraph({ spacing: { before: 120, after: 60 }, children: [run(b.caption, { bold: true, color: GREY, size: 18 })] }));
      children.push(b.rows.length ? table(b.head, b.rows) : new Paragraph({ children: [run("None in this report.", { color: GREY, size: 18 })] }));
    }
  }
  const document = new Document({
    creator: "First Line · Vectovia", title: doc.title, description: doc.subtitle,
    sections: [{
      footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.LEFT, children: [
        run(`${doc.footer} · Page `, { color: GREY, size: 14 }), new TextRun({ children: [PageNumber.CURRENT], color: GREY, size: 14, font: "Arial" }),
        run(" of ", { color: GREY, size: 14 }), new TextRun({ children: [PageNumber.TOTAL_PAGES], color: GREY, size: 14, font: "Arial" }),
      ] })] }) },
      children,
    }],
  });
  return Packer.toBlob(document);
}
