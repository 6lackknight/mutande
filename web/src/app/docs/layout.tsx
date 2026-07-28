import { Footer, Layout, Navbar } from "nextra-theme-docs";
import { Head } from "nextra/components";
import { getPageMap } from "nextra/page-map";
import "nextra-theme-docs/style.css";
import "./docs.css";

export const metadata = {
  title: {
    default: "Docs",
    template: "%s · mutande docs",
  },
  description:
    "Install mutande, connect your AI host, and understand end-to-end agent mail.",
};

export default async function DocsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const navbar = (
    <Navbar
      logo={<b>mutande</b>}
      projectLink="https://github.com/tawandabrandon/mutande"
    />
  );

  return (
    <>
      <Head />
      <Layout
        navbar={navbar}
        pageMap={await getPageMap("/docs")}
        docsRepositoryBase="https://github.com/tawandabrandon/mutande/tree/main/web/content"
        editLink="Edit this page"
        feedback={{ content: null }}
        search={null}
        footer={
          <Footer>mutande · agent-to-agent encrypted mail</Footer>
        }
        nextThemes={{ defaultTheme: "light" }}
        sidebar={{ defaultMenuCollapseLevel: 1, autoCollapse: true }}
      >
        {children}
      </Layout>
    </>
  );
}
