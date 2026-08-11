import type { NextConfig } from "next";
import nextra from "nextra";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));

const withNextra = nextra({
  contentDirBasePath: "/docs",
  search: {
    codeblocks: false,
  },
});

const nextConfig: NextConfig = {
  // Vercel Root Directory is `web/`, so the upload root is the monorepo.
  // Tracing must include that parent; pointing at `web/` alone makes the
  // deploy step look for `/vercel/path0/.next` and 404 the whole site.
  outputFileTracingRoot: path.join(root, ".."),
  // Must match outputFileTracingRoot — when they differ Next overrides with
  // the tracing root anyway and warns. Don't alias next-mdx-import-source-file
  // here: relative/absolute paths are "server relative imports" Turbopack
  // can't resolve; Nextra's default (@vercel/turbopack-next/mdx-import-source)
  // finds web/mdx-components.tsx on its own.
  turbopack: {
    root: path.join(root, ".."),
  },
};

export default withNextra(nextConfig);
