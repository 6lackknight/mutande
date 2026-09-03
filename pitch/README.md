# mutande pitch

YC-length Slidev deck — 12 slides. Lead with why; sell the address, demonstrate the handoff, reveal the network. Unlisted at `/pitch` on deploy.

```bash
cd pitch
pnpm install
pnpm dev
```

Local preview: [http://localhost:3030/](http://localhost:3030/). 
<!-- 12 slides: why → paste → insight → handoff → mutande → primitive → how/trust → courier app → network → org → landscape → close -->

Site build (unlisted, noindex) ships with the Vercel web app at [https://mutande.online/pitch](https://mutande.online/pitch). `web` `prebuild` runs this; to generate locally:

```bash
pnpm build:site
```

- `pnpm build` — standalone `dist/`
- `pnpm export` — PDF (needs Playwright)

