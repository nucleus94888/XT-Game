import { defineConfig } from 'vite';

// GitHub Pages 部署在 https://<user>.github.io/XT-Game/，需要設定 base
export default defineConfig({
  base: process.env.GITHUB_PAGES ? '/XT-Game/' : '/',
  build: { chunkSizeWarningLimit: 1000 },
});
