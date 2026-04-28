import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The build output lives both at viewer/dist (so the dev workflow with
// `tca-graph serve` finds it via the relative-path search) AND at the SPM
// target's Resources/ directory (so the Swift binary embeds it via
// Bundle.module — that's what makes Mint installs and tarball builds
// self-contained without separate viewer files). Vite emptyOutDir is on by
// default but we leave it explicit for the dist path; the second copy is
// handled by an `npm run build:swift` post-step that mirrors dist into the
// SPM resources directory.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: "127.0.0.1",
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
