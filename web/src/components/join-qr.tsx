"use client";

import { QRCodeSVG } from "qrcode.react";

export function JoinQr({
  url,
  caption,
}: {
  url: string;
  caption?: string;
}) {
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-xl border border-stone-300/70 bg-white p-3">
        <QRCodeSVG
          value={url}
          size={220}
          bgColor="#ffffff"
          fgColor="#1c1917"
          level="M"
          className="h-auto w-full"
          aria-label="Join org QR code"
        />
      </div>
      <p className="text-[13px] leading-relaxed text-stone-600">
        {caption ?? "Scan to join this org."}
        <span className="mt-1 block break-all text-[12px] text-muted">{url}</span>
      </p>
    </div>
  );
}
