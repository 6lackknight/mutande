import React from "react";
import { Img, staticFile } from "remotion";
import { colors } from "../theme";

export type BrandId = "claude" | "chatgpt" | "kimi" | "openclaw" | "default";

const ink = colors.stone900;

/** Same family as Mac `AiHostIcon` — Simple Icons where we have them. */
export const BrandMark: React.FC<{ brand: BrandId; size: number }> = ({
  brand,
  size,
}) => {
  if (brand === "claude" || brand === "chatgpt") {
    return (
      <Img
        src={staticFile(`hosts/${brand}.png`)}
        style={{
          width: size,
          height: size,
          objectFit: "contain",
          // Match app: monochrome ink
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

  if (brand === "openclaw") {
    // Abstract claw mark
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
        <path
          fill={ink}
          d="M12 2.5c-2.2 3.4-5.8 5.6-9.5 6.2 2.1 1.1 3.6 3.2 4.1 5.7-.9-.4-1.7-1-2.4-1.8-.2 3.8 1.6 7.4 4.8 9.2-1.5-2.6-1.6-5.7-.2-8.3 1.2 2.4 3.5 4.2 6.2 4.8-.4-1.5-.4-3.1.1-4.6 1.8 1.5 2.9 3.7 3.1 6.1 2.6-2.2 4-5.6 3.6-9.1-1.8.9-3.3 2.3-4.2 4.1.2-2.8-1-5.5-3.2-7.3.7 1.6.9 3.4.5 5.1C13.8 8.4 12.6 5.2 12 2.5z"
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
