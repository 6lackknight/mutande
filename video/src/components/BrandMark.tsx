import React from "react";
import { Img, staticFile } from "remotion";
import { colors } from "../theme";

export type BrandId =
  | "claude"
  | "chatgpt"
  | "cursor"
  | "kimi"
  | "openclaw"
  | "n8n"
  | "default";

const ink = colors.stone900;

/** Product marks for the intro cast — Simple Icons / official favicons as gray+alpha PNGs. */
export const BrandMark: React.FC<{ brand: BrandId; size: number }> = ({
  brand,
  size,
}) => {
  if (
    brand === "cursor" ||
    brand === "claude" ||
    brand === "chatgpt" ||
    brand === "openclaw" ||
    brand === "n8n"
  ) {
    return (
      <Img
        src={staticFile(`hosts/${brand}.png`)}
        style={{
          width: size,
          height: size,
          objectFit: "contain",
          // Match app AiHostIcon: monochrome ink on light plates
          filter: "brightness(0) saturate(100%)",
          opacity: 0.92,
        }}
      />
    );
  }

  if (brand === "kimi") {
    // Moonshot/Kimi-style lettermark — no official asset in repo
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
        <path
          fill={ink}
          d="M4.5 4.2h3.2v6.1L13.4 4.2h3.8l-6.2 7.1 6.6 8.5h-3.9l-4.7-6.2v6.2H4.5z"
        />
      </svg>
    );
  }

  // Default agent inbox — quiet envelope
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <path
        fill={ink}
        d="M3.5 6.5A2.5 2.5 0 0 1 6 4h12a2.5 2.5 0 0 1 2.5 2.5v11A2.5 2.5 0 0 1 18 20H6a2.5 2.5 0 0 1-2.5-2.5zm2.2.7 6.3 4.4 6.3-4.4H5.7zm12.6 1.9-5.9 4.1a1.2 1.2 0 0 1-1.4 0L5.1 9.1v8.4c0 .5.4.9.9.9h12c.5 0 .9-.4.9-.9z"
      />
    </svg>
  );
};
