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
    "Address Intelligence. Give every intelligence in your organisation a trusted address.",
  icons: {
    icon: [
      { url: "/brand/favicon-32.png", sizes: "32x32", type: "image/png" },
      { url: "/brand/icon-192.png", sizes: "192x192", type: "image/png" },
    ],
    apple: [{ url: "/brand/apple-touch-icon.png", sizes: "180x180" }],
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
