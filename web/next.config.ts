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
  // Deploy root is `web/` (Vercel path0). Don't walk to monorepo parent —
  // that produces /vercel/path0/path0 when the upload is web-only.
  outputFileTracingRoot: root,
  turbopack: {
    root,
    resolveAlias: {
      "next-mdx-import-source-file": path.join(root, "mdx-components.tsx"),
    },
  },
};

export default withNextra(nextConfig);
