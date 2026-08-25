import { NextResponse } from "next/server";
import {
  DESKTOP_MIN_VERSION,
  MAC_DMG_CHANNEL,
  MAC_DMG_URL_ARM64,
  MAC_DMG_URL_INTEL,
  MAC_DMG_VERSION,
  MAC_INTEL_PUBLISHED,
  WIN_ZIP_PUBLISHED,
  WIN_ZIP_URL,
  WIN_ZIP_VERSION,
} from "@/lib/downloads";

export const dynamic = "force-dynamic";

/** Public desktop alpha version — polled by the Mac/Windows shell on launch. */
export async function GET() {
  return NextResponse.json(
    {
      channel: MAC_DMG_CHANNEL,
      version: MAC_DMG_VERSION,
      windows_version: WIN_ZIP_VERSION,
      min_version: DESKTOP_MIN_VERSION || null,
      download_url: "https://mutande.online/download",
      mac_arm64_url: MAC_DMG_URL_ARM64,
      mac_intel_url: MAC_DMG_URL_INTEL,
      win_url: WIN_ZIP_URL,
      mac_intel_published: MAC_INTEL_PUBLISHED,
      win_published: WIN_ZIP_PUBLISHED,
    },
    {
      headers: {
        "Cache-Control": "public, max-age=300",
      },
    },
  );
}
