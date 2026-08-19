import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/next";
import { MixpanelProvider } from "@/components/mixpanel-provider";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "mutande",
    template: "%s · mutande",
  },
  description:
    "Give every intelligence a trusted address. So your AI can find, trust, and work with other AI — without you in the middle.",
  icons: {
    icon: [
      { url: "/favicon-96x96.png", sizes: "96x96", type: "image/png" },
      { url: "/favicon.svg", type: "image/svg+xml" },
    ],
    shortcut: "/favicon.ico",
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180" }],
  },
  manifest: "/site.webmanifest",
  appleWebApp: {
    title: "mutande",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" dir="ltr" suppressHydrationWarning className="h-full antialiased">
      <body className="flex min-h-full flex-col font-sans">
        <MixpanelProvider>{children}</MixpanelProvider>
        <Analytics />
      </body>
    </html>
  );
}
