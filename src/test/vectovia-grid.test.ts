// GPS ⇄ British National Grid (src/modules/vectovia/grid.ts).
import { fromGridRef, metresBetween, toEastingNorthing, toGridRef } from "@/modules/vectovia/grid";

describe("British National Grid", () => {
  it("matches the Ordnance Survey reference point within a few metres", () => {
    // OS worked example (Caister water tower): 52°39'27.2531"N 1°43'4.5177"E (OSGB36) is E 651409.903, N 313177.270.
    // Its WGS84 position is about 52.65798 N, 1.71605 E; allow 5 m for the 3-parameter-class Helmert transform.
    const { e, n } = toEastingNorthing(52.65798, 1.71605);
    expect(Math.abs(e - 651409.9)).toBeLessThan(6);
    expect(Math.abs(n - 313177.3)).toBeLessThan(6);
  });

  it("gives the right 100 km square letters", () => {
    expect(toGridRef(51.5007, -0.1246)?.slice(0, 2)).toBe("TQ"); // Westminster
    expect(toGridRef(51.95, 1.3)?.slice(0, 2)).toBe("TM"); // Felixstowe area
    expect(toGridRef(55.9533, -3.1883)?.slice(0, 2)).toBe("NT"); // Edinburgh
    expect(toGridRef(50.3755, -4.1427)?.slice(0, 2)).toBe("SX"); // Plymouth
  });

  it("round-trips a location to within a few metres", () => {
    for (const p of [{ lat: 51.95, lon: 1.3 }, { lat: 53.4808, lon: -2.2426 }, { lat: 57.1497, lon: -2.0943 }]) {
      const back = fromGridRef(toGridRef(p.lat, p.lon, 10)!)!;
      expect(metresBetween(p, back)).toBeLessThan(5);
    }
  });

  it("accepts references with or without spaces, and refuses nonsense", () => {
    const a = fromGridRef("TM 27350 34800")!, b = fromGridRef("tm2735034800")!;
    expect(metresBetween(a, b)).toBeLessThan(0.01);
    expect(fromGridRef("TM 273 34")).toBeNull();
    expect(fromGridRef("IQ 1234 5678")).toBeNull();
    expect(fromGridRef("hello")).toBeNull();
  });

  it("says when a place is outside the National Grid", () => {
    expect(toGridRef(48.8566, 2.3522)).toBeNull(); // Paris
  });
});
