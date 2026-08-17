import { NextResponse } from "next/server";
import {
  MAC_DMG_CHANNEL,
  MAC_DMG_URL_ARM64,
  MAC_DMG_URL_INTEL,
  MAC_DMG_VERSION,
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
      download_url: "https://mutande.online/download",
      mac_arm64_url: MAC_DMG_URL_ARM64,
      mac_intel_url: MAC_DMG_URL_INTEL,
      win_url: WIN_ZIP_URL,
    },
    {
      headers: {
        "Cache-Control": "public, max-age=300",
      },
    },
  );
}
