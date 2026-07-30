import { Composition } from "remotion";
import { LandingIntro } from "./LandingIntro";
import { DURATION_FRAMES, FPS } from "./timing";

export const MyComposition = () => {
  return (
    <Composition
      id="LandingIntro"
      component={LandingIntro}
      durationInFrames={DURATION_FRAMES}
      fps={FPS}
      width={1080}
      height={1080}
    />
  );
};
