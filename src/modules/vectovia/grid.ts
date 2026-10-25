// GPS (WGS84 latitude/longitude) ⇄ British National Grid references (V-D6).
// Ordnance Survey method: a Helmert transform between WGS84 and OSGB36, then
// the national Transverse Mercator projection. Accurate to a few metres, which
// is right for site and trap locations (it is not survey-grade). Locations are
// stored as WGS84; grid references are worked out for display and entry.

const toRad = (d: number) => (d * Math.PI) / 180;
const toDeg = (r: number) => (r * 180) / Math.PI;

type Ellipsoid = { a: number; b: number };
const WGS84: Ellipsoid = { a: 6378137, b: 6356752.314245 };
const AIRY: Ellipsoid = { a: 6377563.396, b: 6356256.909 };
// WGS84 → OSGB36 (metres, ppm, arc-seconds)
const HELMERT = { tx: -446.448, ty: 125.157, tz: -542.06, s: 20.4894, rx: -0.1502, ry: -0.247, rz: -0.8421 };

function toCartesian(lat: number, lon: number, e: Ellipsoid) {
  const φ = toRad(lat), λ = toRad(lon);
  const e2 = 1 - (e.b * e.b) / (e.a * e.a);
  const ν = e.a / Math.sqrt(1 - e2 * Math.sin(φ) ** 2);
  return { x: ν * Math.cos(φ) * Math.cos(λ), y: ν * Math.cos(φ) * Math.sin(λ), z: ν * (1 - e2) * Math.sin(φ) };
}
function fromCartesian(p: { x: number; y: number; z: number }, e: Ellipsoid) {
  const e2 = 1 - (e.b * e.b) / (e.a * e.a);
  const pr = Math.hypot(p.x, p.y);
  let φ = Math.atan2(p.z, pr * (1 - e2));
  for (let i = 0; i < 10; i++) {
    const ν = e.a / Math.sqrt(1 - e2 * Math.sin(φ) ** 2);
    φ = Math.atan2(p.z + e2 * ν * Math.sin(φ), pr);
  }
  return { lat: toDeg(φ), lon: toDeg(Math.atan2(p.y, p.x)) };
}
function helmert(p: { x: number; y: number; z: number }, sign: 1 | -1) {
  const tx = sign * HELMERT.tx, ty = sign * HELMERT.ty, tz = sign * HELMERT.tz;
  const s = 1 + (sign * HELMERT.s) / 1e6;
  const rx = toRad((sign * HELMERT.rx) / 3600), ry = toRad((sign * HELMERT.ry) / 3600), rz = toRad((sign * HELMERT.rz) / 3600);
  return {
    x: tx + s * p.x - rz * p.y + ry * p.z,
    y: ty + rz * p.x + s * p.y - rx * p.z,
    z: tz - ry * p.x + rx * p.y + s * p.z,
  };
}

// National Grid projection constants
const F0 = 0.9996012717, φ0 = toRad(49), λ0 = toRad(-2), N0 = -100000, E0 = 400000;

function meridional(φ: number) {
  const { a, b } = AIRY;
  const n = (a - b) / (a + b), n2 = n * n, n3 = n2 * n;
  const d = φ - φ0, s = φ + φ0;
  return b * F0 * (
    (1 + n + (5 / 4) * n2 + (5 / 4) * n3) * d
    - (3 * n + 3 * n2 + (21 / 8) * n3) * Math.sin(d) * Math.cos(s)
    + ((15 / 8) * n2 + (15 / 8) * n3) * Math.sin(2 * d) * Math.cos(2 * s)
    - (35 / 24) * n3 * Math.sin(3 * d) * Math.cos(3 * s));
}
function radii(φ: number) {
  const { a, b } = AIRY;
  const e2 = 1 - (b * b) / (a * a);
  const sin2 = Math.sin(φ) ** 2;
  const ν = (a * F0) / Math.sqrt(1 - e2 * sin2);
  const ρ = (a * F0 * (1 - e2)) / (1 - e2 * sin2) ** 1.5;
  return { ν, ρ, η2: ν / ρ - 1 };
}

/** WGS84 latitude/longitude → OSGB36 easting and northing (metres). */
export function toEastingNorthing(lat: number, lon: number): { e: number; n: number } {
  const osgb = fromCartesian(helmert(toCartesian(lat, lon, WGS84), 1), AIRY);
  const φ = toRad(osgb.lat), λ = toRad(osgb.lon);
  const { ν, ρ, η2 } = radii(φ);
  const sin = Math.sin(φ), cos = Math.cos(φ), tan2 = Math.tan(φ) ** 2;
  const I = meridional(φ) + N0;
  const II = (ν / 2) * sin * cos;
  const III = (ν / 24) * sin * cos ** 3 * (5 - tan2 + 9 * η2);
  const IIIA = (ν / 720) * sin * cos ** 5 * (61 - 58 * tan2 + tan2 * tan2);
  const IV = ν * cos;
  const V = (ν / 6) * cos ** 3 * (ν / ρ - tan2);
  const VI = (ν / 120) * cos ** 5 * (5 - 18 * tan2 + tan2 * tan2 + 14 * η2 - 58 * tan2 * η2);
  const dλ = λ - λ0;
  return {
    n: I + II * dλ ** 2 + III * dλ ** 4 + IIIA * dλ ** 6,
    e: E0 + IV * dλ + V * dλ ** 3 + VI * dλ ** 5,
  };
}

/** OSGB36 easting and northing → WGS84 latitude/longitude. */
export function fromEastingNorthing(e: number, n: number): { lat: number; lon: number } {
  const { a } = AIRY;
  let φ = φ0, M = 0;
  do { φ = (n - N0 - M) / (a * F0) + φ; M = meridional(φ); } while (Math.abs(n - N0 - M) >= 0.00001);
  const { ν, ρ, η2 } = radii(φ);
  const tan = Math.tan(φ), tan2 = tan * tan, tan4 = tan2 * tan2, sec = 1 / Math.cos(φ);
  const VII = tan / (2 * ρ * ν);
  const VIII = (tan / (24 * ρ * ν ** 3)) * (5 + 3 * tan2 + η2 - 9 * tan2 * η2);
  const IX = (tan / (720 * ρ * ν ** 5)) * (61 + 90 * tan2 + 45 * tan4);
  const X = sec / ν;
  const XI = (sec / (6 * ν ** 3)) * (ν / ρ + 2 * tan2);
  const XII = (sec / (120 * ν ** 5)) * (5 + 28 * tan2 + 24 * tan4);
  const XIIA = (sec / (5040 * ν ** 7)) * (61 + 662 * tan2 + 1320 * tan4 + 720 * tan4 * tan2);
  const dE = e - E0;
  const lat = φ - VII * dE ** 2 + VIII * dE ** 4 - IX * dE ** 6;
  const lon = λ0 + X * dE - XI * dE ** 3 + XII * dE ** 5 - XIIA * dE ** 7;
  const wgs = fromCartesian(helmert(toCartesian(toDeg(lat), toDeg(lon), AIRY), -1), WGS84);
  return wgs;
}

const LETTERS = "ABCDEFGHJKLMNOPQRSTUVWXYZ"; // no I

/** e.g. "TM 2735 3480" (10 m precision by default). Null if outside the National Grid. */
export function toGridRef(lat: number, lon: number, digits: 6 | 8 | 10 = 8): string | null {
  const { e, n } = toEastingNorthing(lat, lon);
  if (!(e >= 0 && e < 700000 && n >= 0 && n < 1300000)) return null;
  const e100 = Math.floor(e / 100000), n100 = Math.floor(n / 100000);
  const l1 = (19 - n100) - ((19 - n100) % 5) + Math.floor((e100 + 10) / 5);
  const l2 = (((19 - n100) * 5) % 25) + (e100 % 5);
  const half = digits / 2, div = 10 ** (5 - half);
  const ee = Math.floor((e % 100000) / div).toString().padStart(half, "0");
  const nn = Math.floor((n % 100000) / div).toString().padStart(half, "0");
  return `${LETTERS[l1]}${LETTERS[l2]} ${ee} ${nn}`;
}

/** Parses "TM 27352 34801", "TM2735034801", "TM 273 348" → WGS84. Null if not a valid reference. */
export function fromGridRef(ref: string): { lat: number; lon: number } | null {
  const m = ref.toUpperCase().replace(/\s+/g, "").match(/^([A-HJ-Z])([A-HJ-Z])(\d+)$/);
  const [, c1 = "", c2 = "", digits = ""] = m ?? [];
  if (!m || digits.length % 2 !== 0 || digits.length < 2 || digits.length > 10) return null;
  const l1 = LETTERS.indexOf(c1), l2 = LETTERS.indexOf(c2);
  const e100 = ((l1 - 2) % 5) * 5 + (l2 % 5);
  const n100 = 19 - Math.floor(l1 / 5) * 5 - Math.floor(l2 / 5);
  if (e100 < 0 || e100 > 6 || n100 < 0 || n100 > 12) return null;
  const half = digits.length / 2, scale = 10 ** (5 - half);
  // The centre of the square named by the reference.
  const e = e100 * 100000 + Number(digits.slice(0, half)) * scale + scale / 2;
  const n = n100 * 100000 + Number(digits.slice(half)) * scale + scale / 2;
  return fromEastingNorthing(e, n);
}

/** Distance in metres between two WGS84 points (for tests and sanity checks). */
export function metresBetween(a: { lat: number; lon: number }, b: { lat: number; lon: number }) {
  const R = 6371000, dφ = toRad(b.lat - a.lat), dλ = toRad(b.lon - a.lon);
  const h = Math.sin(dφ / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dλ / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
