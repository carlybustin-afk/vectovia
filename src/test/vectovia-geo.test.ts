import { describe, expect, it } from "vitest";
import { hectares, inSiteZone, inZone, polygonFrom, ringOf, zoneOutline, type Polygon } from "@/modules/vectovia/geo";

// The same square as supabase/tests/v2-002-sites-obligations.test.sql, so browser and database agree.
const square: Polygon = { type: "Polygon", coordinates: [[[1.33, 51.12], [1.332, 51.12], [1.332, 51.122], [1.33, 51.122], [1.33, 51.12]]] };

describe("site geometry", () => {
  it("closes a polygon from clicked points and reads it back", () => {
    const p = polygonFrom([[51.12, 1.33], [51.12, 1.332], [51.122, 1.332]])!;
    expect(p.coordinates[0]).toHaveLength(4);
    expect(p.coordinates[0]![0]).toEqual(p.coordinates[0]![3]);
    expect(ringOf(p)).toEqual([[51.12, 1.33], [51.12, 1.332], [51.122, 1.332]]);
    expect(polygonFrom([[51, 1], [51, 2]])).toBeNull();
  });

  it("matches the database zone check", () => {
    expect(inZone(square, 400, 51.121, 1.331)).toBe(true);
    expect(inZone(square, 400, 51.121, 1.3363)).toBe(true);
    expect(inZone(square, 400, 51.121, 1.3463)).toBe(false);
    expect(inZone(square, 200, 51.121, 1.3363)).toBe(false);
    expect(inZone(null, 400, 51.121, 1.331)).toBe(false);
  });

  it("counts any area towards the site zone", () => {
    const yard: Polygon = { type: "Polygon", coordinates: [[[1.34, 51.12], [1.341, 51.12], [1.341, 51.121], [1.34, 51.121], [1.34, 51.12]]] };
    expect(inSiteZone([square], 400, 51.1205, 1.3463)).toBe(false);
    expect(inSiteZone([square, yard], 400, 51.1205, 1.3463)).toBe(true);
  });

  it("draws a zone outline that contains the boundary and stays about the zone width away", () => {
    const outline = zoneOutline([square], 400);
    expect(outline.length).toBeGreaterThan(8);
    const lons = outline.map((p) => p[1]);
    // 400 m east of 1.332 at 51.12 N is about 0.0057 degrees.
    expect(Math.max(...lons)).toBeGreaterThan(1.337);
    expect(Math.max(...lons)).toBeLessThan(1.3385);
  });

  it("works out an approximate area", () => {
    expect(hectares(square)).toBeGreaterThan(2.9);
    expect(hectares(square)).toBeLessThan(3.4);
  });
});
