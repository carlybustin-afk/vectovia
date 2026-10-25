// Site geometry in the browser: GeoJSON polygons (lon/lat), the zone check and the zone outline.
// inZone mirrors public.vv_in_zone in the database (same flat projection), so what the map shows
// agrees with what compliance counts. The database stays the authority.

export type Polygon = { type: "Polygon"; coordinates: [number, number][][] };
export type LatLon = [number, number];

/** A closed GeoJSON polygon from points clicked on the map ([lat, lon]); null if fewer than 3. */
export function polygonFrom(points: LatLon[]): Polygon | null {
  if (points.length < 3) return null;
  const ring = points.map(([lat, lon]) => [+lon.toFixed(6), +lat.toFixed(6)] as [number, number]);
  ring.push([...ring[0]!] as [number, number]);
  return { type: "Polygon", coordinates: [ring] };
}

/** The outer ring as [lat, lon] points, without the closing repeat. */
export function ringOf(p: Polygon | null | undefined): LatLon[] {
  const ring = p?.coordinates?.[0] ?? [];
  return ring.slice(0, Math.max(0, ring.length - 1)).map(([lon, lat]) => [lat, lon]);
}

const proj = (lat: number, lon: number, k: number) => [lon * k * 111320, lat * 110540] as const;

/** Inside the polygon's outer ring, or within zoneM metres of its edge. */
export function inZone(p: Polygon | null | undefined, zoneM: number, lat: number, lon: number): boolean {
  const ring = p?.coordinates?.[0];
  if (!ring || ring.length < 4) return false;
  const k = Math.cos((lat * Math.PI) / 180);
  const [px, py] = proj(lat, lon, k);
  let inside = false, best = Infinity;
  for (let i = 0; i < ring.length - 1; i++) {
    const [ax, ay] = ring[i]!, [bx, by] = ring[i + 1]!;
    if ((ay > lat) !== (by > lat) && lon < ((bx - ax) * (lat - ay)) / (by - ay) + ax) inside = !inside;
    const [x1, y1] = proj(ay, ax, k), [x2, y2] = proj(by, bx, k);
    const dx = x2 - x1, dy = y2 - y1;
    const t = dx === 0 && dy === 0 ? 0 : Math.max(0, Math.min(1, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)));
    best = Math.min(best, Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy)));
  }
  return inside || best <= zoneM;
}

/** In the site's zone: within zoneM of the site boundary or any area boundary. */
export function inSiteZone(shapes: (Polygon | null | undefined)[], zoneM: number, lat: number, lon: number) {
  return shapes.some((s) => inZone(s, zoneM, lat, lon));
}

/**
 * An outline of the zone for the map: the convex hull of circles of zoneM around every vertex.
 * Exact for convex shapes and slightly generous for concave ones; for display only.
 */
export function zoneOutline(shapes: (Polygon | null | undefined)[], zoneM: number): LatLon[] {
  const pts: LatLon[] = [];
  for (const s of shapes) {
    for (const [lat, lon] of ringOf(s)) {
      const k = Math.cos((lat * Math.PI) / 180);
      for (let a = 0; a < 360; a += 15) {
        const r = (a * Math.PI) / 180;
        pts.push([lat + (zoneM * Math.sin(r)) / 110540, lon + (zoneM * Math.cos(r)) / (111320 * k)]);
      }
    }
  }
  return hull(pts);
}

function hull(points: LatLon[]): LatLon[] {
  const p = [...points].sort((a, b) => a[1] - b[1] || a[0] - b[0]);
  if (p.length < 3) return p;
  const cross = (o: LatLon, a: LatLon, b: LatLon) => (a[1] - o[1]) * (b[0] - o[0]) - (a[0] - o[0]) * (b[1] - o[1]);
  const lower: LatLon[] = [], upper: LatLon[] = [];
  for (const x of p) { while (lower.length >= 2 && cross(lower[lower.length - 2]!, lower[lower.length - 1]!, x) <= 0) lower.pop(); lower.push(x); }
  for (const x of [...p].reverse()) { while (upper.length >= 2 && cross(upper[upper.length - 2]!, upper[upper.length - 1]!, x) <= 0) upper.pop(); upper.push(x); }
  return [...lower.slice(0, -1), ...upper.slice(0, -1)];
}

/** Approximate area in hectares, for a sanity check under the map. */
export function hectares(p: Polygon | null | undefined): number {
  const ring = p?.coordinates?.[0];
  if (!ring || ring.length < 4) return 0;
  const k = Math.cos((ring[0]![1] * Math.PI) / 180);
  let a = 0;
  for (let i = 0; i < ring.length - 1; i++) {
    const [x1, y1] = proj(ring[i]![1], ring[i]![0], k), [x2, y2] = proj(ring[i + 1]![1], ring[i + 1]![0], k);
    a += x1 * y2 - x2 * y1;
  }
  return Math.abs(a) / 2 / 10_000;
}
