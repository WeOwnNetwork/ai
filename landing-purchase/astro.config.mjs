import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Static output — this is a marketing/landing page, no server runtime
// needed. Ships as plain HTML/CSS/JS.
export default defineConfig({
  output: "static",
  vite: {
    plugins: [tailwindcss()],
  },
});
