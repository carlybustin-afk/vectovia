// Vectovia map (V-D5): switchable tile provider. OpenStreetMap tiles in
// development; Mapbox once VITE_MAPBOX_TOKEN is set (a paid service above its
// free tier: owner approval before live council use). The tile provider learns
// which area is being viewed, never any record details: points are drawn in the
// browser from data the person can already see.
import { useEffect, useRef } from "react";
import "leaflet/dist/leaflet.css";

export type MapPoint = { id: string; lat: number; lon: number; label: string; muted?: boolean };
/** A circular area (e.g. an incursion response area), drawn as an outline. */
export type MapCircle = { id: string; lat: number; lon: number; radius_m: number; label: string };

const MAPBOX = import.meta.env["VITE_MAPBOX_TOKEN"] as string | undefined;
export const mapProvider = MAPBOX ? "Mapbox" : "OpenStreetMap";

function tiles() {
  return MAPBOX
    ? {
        url: `https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${MAPBOX}`,
        attribution: '© <a href="https://www.mapbox.com/about/maps/">Mapbox</a> © <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }
    : {
        url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      };
}

const token = (name: string, fallback: string) =>
  (typeof document !== "undefined" && getComputedStyle(document.documentElement).getPropertyValue(name).trim()) || fallback;

/**
 * points: what to show. onPick: when given, clicking the map picks a location (and shows it).
 * picked: the currently picked location. onSelect: a point was clicked.
 */
export function SurveillanceMap({ points, circles = [], onPick, picked, onSelect, height = 360, label }: {
  points: MapPoint[]; circles?: MapCircle[]; onPick?: (lat: number, lon: number) => void; picked?: { lat: number; lon: number } | null;
  onSelect?: (id: string) => void; height?: number; label: string;
}) {
  const el = useRef<HTMLDivElement>(null);
  const map = useRef<import("leaflet").Map | null>(null);
  const layer = useRef<import("leaflet").LayerGroup | null>(null);
  const L = useRef<typeof import("leaflet") | null>(null);
  const handlers = useRef({ onPick, onSelect });
  handlers.current = { onPick, onSelect };

  // Create the map once (Leaflet needs the browser, so it loads after the page renders).
  useEffect(() => {
    let cancelled = false;
    void import("leaflet").then((mod) => {
      if (cancelled || !el.current || map.current) return;
      L.current = mod;
      const m = mod.map(el.current, { zoomControl: true, attributionControl: true }).setView([52.5, -1.5], 6);
      const t = tiles();
      mod.tileLayer(t.url, { attribution: t.attribution, maxZoom: 19 }).addTo(m);
      layer.current = mod.layerGroup().addTo(m);
      m.on("click", (e: import("leaflet").LeafletMouseEvent) => handlers.current.onPick?.(e.latlng.lat, e.latlng.lng));
      map.current = m;
      draw();
    });
    return () => { cancelled = true; map.current?.remove(); map.current = null; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const draw = () => {
    const mod = L.current, m = map.current, g = layer.current;
    if (!mod || !m || !g) return;
    g.clearLayers();
    const primary = token("--primary", "#0b2545"), accent = token("--accent", "#13a89e");
    for (const p of points) {
      mod.circleMarker([p.lat, p.lon], { radius: 7, color: primary, weight: 2, fillColor: p.muted ? "#ffffff" : accent, fillOpacity: 0.9 })
        .bindTooltip(p.label).on("click", () => handlers.current.onSelect?.(p.id)).addTo(g);
    }
    const circleBounds: [number, number][] = [];
    for (const c of circles) {
      const shape = mod.circle([c.lat, c.lon], { radius: c.radius_m, color: primary, weight: 2, dashArray: "6 4", fillColor: accent, fillOpacity: 0.12 })
        .bindTooltip(c.label).addTo(g);
      const b = shape.getBounds();
      if (b.isValid()) circleBounds.push([b.getSouth(), b.getWest()], [b.getNorth(), b.getEast()]);
      else { const d = c.radius_m / 111_320; circleBounds.push([c.lat - d, c.lon - d], [c.lat + d, c.lon + d]); }
    }
    if (picked) mod.circleMarker([picked.lat, picked.lon], { radius: 9, color: accent, weight: 3, fillColor: primary, fillOpacity: 1 }).bindTooltip("Chosen location").addTo(g);
    const all = [...points.map((p) => [p.lat, p.lon] as [number, number]), ...circleBounds, ...(picked ? [[picked.lat, picked.lon] as [number, number]] : [])];
    if (all.length === 1) m.setView(all[0]!, Math.max(m.getZoom(), 14));
    else if (all.length > 1) m.fitBounds(mod.latLngBounds(all), { padding: [30, 30], maxZoom: 15 });
  };
  useEffect(draw); // redraw whenever the points or picked location change

  return (
    <div>
      <div ref={el} role="region" aria-label={label} style={{ height }} className="z-0 w-full rounded-md border border-border" />
      <p className="mt-1 text-[11px] text-muted-foreground">
        Map: {mapProvider}.{onPick ? " Click the map to set the location." : ""} The list below shows the same records.
      </p>
    </div>
  );
}
