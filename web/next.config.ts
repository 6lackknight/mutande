import type { NextConfig } from "next";
import nextra from "nextra";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
// Monorepo root — must match Vercel's outputFileTracingRoot (/vercel/path0).
const tracingRoot = path.join(root, "..");

const withNextra = nextra({
  contentDirBasePath: "/docs",
  search: {
    codeblocks: false,
  },
});

const nextConfig: NextConfig = {
  outputFileTracingRoot: tracingRoot,
  turbopack: {
    root: tracingRoot,
    resolveAlias: {
      "next-mdx-import-source-file": path.join(root, "mdx-components.tsx"),
    },
  },
};

export default withNextra(nextConfig);
