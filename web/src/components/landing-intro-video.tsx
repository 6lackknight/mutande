"use client";

import { useEffect, useRef } from "react";
import {
  LANDING_INTRO_MP4_URL,
  LANDING_INTRO_POSTER_URL,
  LANDING_INTRO_WEBM_URL,
} from "@/lib/brand-assets";

export function LandingIntroVideo() {
  const ref = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const video = ref.current;
    if (!video) return;
    // iOS Safari often ignores the muted attribute for autoplay unless set in JS.
    video.muted = true;
    video.defaultMuted = true;
    void video.play().catch(() => {
      // Autoplay can still be blocked; poster remains visible.
    });
  }, []);

  return (
    <video
      ref={ref}
      className="absolute inset-0 size-full object-cover"
      width={1080}
      height={1080}
      muted
      autoPlay
      loop
      playsInline
      preload="metadata"
      poster={LANDING_INTRO_POSTER_URL}
      aria-label="mutande intro: agents critique a draft on mutande, then seal and send"
    >
      {/* WebM first for Chrome/Firefox; Safari falls through to H.264 MP4. */}
      <source src={LANDING_INTRO_WEBM_URL} type="video/webm" />
      <source src={LANDING_INTRO_MP4_URL} type="video/mp4" />
    </video>
  );
}
