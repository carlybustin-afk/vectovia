// Vectovia build settings, standard and portable: no hosting-specific code.
// The server build targets Cloudflare Workers for the MVP (free plan, commercial use allowed);
// change the nitro preset (e.g. "aws-lambda" or "node-server") to move hosts.
import { defineConfig, loadEnv } from "vite";
import tailwindcss from "@tailwindcss/vite";
import tsConfigPaths from "vite-tsconfig-paths";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import { nitro } from "nitro/vite";

export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, process.cwd(), "VITE_");
  return {
    server: { port: 8080, strictPort: true },
    define: Object.fromEntries(Object.entries(env).map(([k, v]) => [`import.meta.env.${k}`, JSON.stringify(v)])),
    css: { transformer: "lightningcss" },
    resolve: {
      alias: { "@": `${process.cwd()}/src` },
      dedupe: ["react", "react-dom", "react/jsx-runtime", "react/jsx-dev-runtime", "@tanstack/react-query", "@tanstack/query-core"],
    },
    plugins: [
      tailwindcss(),
      tsConfigPaths({ projects: ["./tsconfig.json"] }),
      tanstackStart({
        // Our SSR error wrapper (src/server.ts).
        server: { entry: "server" },
        importProtection: { behavior: "error", client: { files: ["**/server/**"], specifiers: ["server-only"] } },
      }),
      ...(command === "build" ? [nitro({ preset: process.env["NITRO_PRESET"] || "cloudflare-module", cloudflare: { nodeCompat: true, deployConfig: true } })] : []),
      viteReact(),
    ],
  };
});
