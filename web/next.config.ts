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
  turbopack: {
    root,
    resolveAlias: {
      "next-mdx-import-source-file": "./mdx-components.tsx",
    },
  },
};

export default withNextra(nextConfig);
