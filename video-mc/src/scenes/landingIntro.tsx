import {
  Circle,
  Layout,
  Line,
  Rect,
  Txt,
  makeScene2D,
} from '@motion-canvas/2d';
import {
  all,
  createRef,
  createRefArray,
  easeOutCubic,
  sequence,
  waitFor,
} from '@motion-canvas/core';
import {FONT, colors} from '../theme';

const AGENTS = [
  {handle: '@claude', accent: colors.alice},
  {handle: '@chatgpt', accent: colors.amber},
  {handle: '@research', accent: colors.accent},
] as const;

const RECIPIENTS = [
  {handle: 'bob@salesco/openclaw', accent: colors.bob},
  {handle: 'mary@salesco/kimi', accent: colors.mary},
  {handle: 'cfo@salesco', accent: colors.cfo},
] as const;

const AGENTS_PATH = ['/jarvis', '/research', '/review'] as const;

/**
 * Address Intelligence landing intro — Motion Canvas alternative to Remotion.
 * 1080² @ 60fps · ~28s · silent loop-friendly.
 */
export default makeScene2D(function* (view) {
  view.fill(colors.stone50);

  // ─── shared layers ─────────────────────────────────────────────
  const identity = createRef<Layout>();
  const explainer = createRef<Txt>();
  const graph = createRef<Layout>();
  const brand = createRef<Layout>();

  const handleTxt = createRef<Txt>();
  const agentRows = createRefArray<Txt>();

  const agentNodes = createRefArray<Layout>();
  const destNodes = createRefArray<Layout>();
  const hub = createRef<Layout>();
  const inBeams = createRefArray<Line>();
  const outBeams = createRefArray<Line>();
  const pulses = createRefArray<Circle>();

  const leftX = -340;
  const midX = 0;
  const rightX = 280;
  const ys = [-180, 0, 180] as const;

  view.add(
    <>
      {/* 1. Identity tree */}
      <Layout
        ref={identity}
        layout
        direction="column"
        gap={28}
        opacity={0}
        y={-20}
      >
        <Txt
          ref={handleTxt}
          text="alice@salesco"
          fontSize={56}
          fontWeight={700}
          fill={colors.stone900}
          fontFamily={FONT}
          letterSpacing={-2}
        />
        <Layout layout direction="column" gap={14} paddingLeft={12}>
          {AGENTS_PATH.map((path, i) => (
            <Txt
              ref={agentRows}
              text={`${i === AGENTS_PATH.length - 1 ? '└' : '├'}  ${path}`}
              fontSize={36}
              fontWeight={600}
              fill={colors.accent}
              fontFamily={FONT}
              letterSpacing={-1}
              opacity={0}
              x={16}
            />
          ))}
        </Layout>
      </Layout>

      {/* 3. Explainer */}
      <Txt
        ref={explainer}
        text={"Every intelligence\ndeserves an address."}
        fontSize={58}
        fontWeight={700}
        fill={colors.stone900}
        fontFamily={FONT}
        letterSpacing={-2}
        textAlign="center"
        opacity={0}
        y={0}
      />

      {/* 5–6. Beam graph: agents → mutande → recipients */}
      <Layout ref={graph} opacity={0}>
        <Txt
          text="SEALED · ROUTED BY ADDRESS"
          fontSize={15}
          fontWeight={600}
          fill={colors.stone500}
          fontFamily={FONT}
          letterSpacing={2}
          y={-420}
        />

        {AGENTS.map((a, i) => (
          <Line
            ref={inBeams}
            points={[
              [leftX, ys[i]],
              [midX - 20, 0],
            ]}
            stroke={colors.stone300}
            lineWidth={2.5}
            end={0}
            lineCap="round"
            radius={40}
          />
        ))}
        {RECIPIENTS.map((_, i) => (
          <Line
            ref={outBeams}
            points={[
              [midX + 20, 0],
              [rightX, ys[i]],
            ]}
            stroke={colors.stone300}
            lineWidth={2.5}
            end={0}
            lineCap="round"
            radius={40}
          />
        ))}

        {AGENTS.map((a, i) => (
          <Layout
            ref={agentNodes}
            x={leftX}
            y={ys[i]}
            layout
            direction="column"
            gap={10}
            alignItems="center"
            opacity={0}
            scale={0.9}
          >
            <Rect
              width={84}
              height={84}
              radius={24}
              fill="#fff"
              stroke={a.accent}
              lineWidth={2}
              shadowColor="rgba(28,25,23,0.18)"
              shadowBlur={18}
              shadowOffsetY={8}
              layout
              justifyContent="center"
              alignItems="center"
            >
              <Txt
                text={a.handle.slice(1, 2).toUpperCase()}
                fontSize={28}
                fontWeight={700}
                fill={colors.stone900}
                fontFamily={FONT}
              />
            </Rect>
            <Txt
              text={a.handle}
              fontSize={16}
              fontWeight={650}
              fill={colors.stone900}
              fontFamily={FONT}
            />
          </Layout>
        ))}

        <Layout
          ref={hub}
          x={midX}
          y={0}
          layout
          direction="column"
          gap={10}
          alignItems="center"
          opacity={0}
          scale={0.9}
        >
          <Rect
            width={128}
            height={128}
            radius={30}
            fill={colors.stone900}
            stroke={`${colors.accent}88`}
            lineWidth={2}
            shadowColor="rgba(28,25,23,0.35)"
            shadowBlur={28}
            shadowOffsetY={12}
            layout
            justifyContent="center"
            alignItems="center"
          >
            <Txt
              text="mt"
              fontSize={48}
              fontWeight={700}
              fill="#fff"
              fontFamily={FONT}
              letterSpacing={-2}
            />
          </Rect>
          <Txt
            text="mutande"
            fontSize={20}
            fontWeight={650}
            fill={colors.stone900}
            fontFamily={FONT}
          />
          <Txt
            text="alice@salesco"
            fontSize={13}
            fontWeight={600}
            fill={colors.stone500}
            fontFamily={FONT}
          />
        </Layout>

        {RECIPIENTS.map((r, i) => (
          <Layout
            ref={destNodes}
            x={rightX}
            y={ys[i]}
            layout
            direction="row"
            gap={12}
            alignItems="center"
            opacity={0}
            scale={0.9}
          >
            <Rect
              width={76}
              height={76}
              radius={22}
              fill="#fff"
              stroke={r.accent}
              lineWidth={2}
              shadowColor="rgba(28,25,23,0.16)"
              shadowBlur={16}
              shadowOffsetY={6}
            />
            <Rect
              width={260}
              height={72}
              radius={12}
              fill="rgba(255,255,255,0.94)"
              stroke={colors.stone300}
              lineWidth={1.5}
              padding={14}
              layout
              direction="column"
              justifyContent="center"
              gap={4}
            >
              <Txt
                text={r.handle}
                fontSize={15}
                fontWeight={650}
                fill={colors.stone900}
                fontFamily={FONT}
              />
              <Txt
                text="SEALED"
                fontSize={10}
                fontWeight={700}
                fill={colors.accent}
                fontFamily={FONT}
                letterSpacing={1}
              />
            </Rect>
          </Layout>
        ))}

        {/* traveling pulses for beam highlight */}
        {AGENTS.map((a, i) => (
          <Circle
            ref={pulses}
            size={10}
            fill={a.accent}
            opacity={0}
            x={leftX}
            y={ys[i]}
          />
        ))}
        {RECIPIENTS.map((r, i) => (
          <Circle
            ref={pulses}
            size={10}
            fill={r.accent}
            opacity={0}
            x={midX}
            y={0}
          />
        ))}
      </Layout>

      {/* 7. Brand */}
      <Layout
        ref={brand}
        layout
        direction="column"
        gap={18}
        alignItems="center"
        opacity={0}
      >
        <Txt
          text="@i"
          fontSize={72}
          fontWeight={700}
          fill={colors.accent}
          fontFamily={FONT}
          letterSpacing={-3}
        />
        <Txt
          text="Address Intelligence."
          fontSize={36}
          fontWeight={600}
          fill={colors.stone900}
          fontFamily={FONT}
          letterSpacing={-1}
        />
        <Rect
          width={120}
          height={120}
          radius={22}
          fill={colors.stone900}
          layout
          justifyContent="center"
          alignItems="center"
        >
          <Txt
            text="mt"
            fontSize={42}
            fontWeight={700}
            fill="#fff"
            fontFamily={FONT}
          />
        </Rect>
        <Txt
          text="mutande"
          fontSize={42}
          fontWeight={650}
          fill={colors.stone900}
          fontFamily={FONT}
          letterSpacing={-1.5}
        />
      </Layout>
    </>,
  );

  // ─── 1. Identity (0–4.5s) ──────────────────────────────────────
  yield* all(
    identity().opacity(1, 0.6, easeOutCubic),
    identity().y(0, 0.8, easeOutCubic),
  );
  yield* sequence(
    0.18,
    ...agentRows.map(row =>
      all(
        row.opacity(1, 0.35, easeOutCubic),
        row.x(0, 0.35, easeOutCubic),
      ),
    ),
  );
  yield* waitFor(2.2);
  yield* identity().opacity(0, 0.45);

  // ─── 2. Compose beat (simplified card) ─────────────────────────
  const compose = createRef<Rect>();
  const composePrompt = createRef<Txt>();
  view.add(
    <Rect
      ref={compose}
      width={720}
      height={280}
      radius={16}
      fill="#f5f0e8"
      stroke={colors.stone300}
      lineWidth={1}
      opacity={0}
      y={20}
      shadowColor="rgba(28,25,23,0.28)"
      shadowBlur={40}
      shadowOffsetY={20}
      layout
      direction="column"
      padding={28}
      gap={16}
    >
      <Txt
        text="Claude"
        fontSize={14}
        fontWeight={600}
        fill={colors.stone700}
        fontFamily={FONT}
      />
      <Txt
        text="Draft ready. Want another intelligence to review before we send?"
        fontSize={18}
        fill={colors.stone700}
        fontFamily={FONT}
        width={640}
        textWrap
      />
      <Rect
        width={660}
        height={72}
        radius={14}
        fill="#fff"
        stroke={colors.stone300}
        lineWidth={1.5}
        padding={16}
        layout
        alignItems="center"
      >
        <Txt
          ref={composePrompt}
          text=""
          fontSize={18}
          fontWeight={500}
          fill={colors.stone900}
          fontFamily={FONT}
        />
      </Rect>
    </Rect>,
  );

  const prompt =
    'Ask @research to critique this before we send it to the team.';
  yield* all(
    compose().opacity(1, 0.45, easeOutCubic),
    compose().y(0, 0.5, easeOutCubic),
  );
  // typewriter
  for (let i = 1; i <= prompt.length; i++) {
    composePrompt().text(prompt.slice(0, i));
    yield* waitFor(0.028);
  }
  yield* waitFor(0.9);
  yield* compose().opacity(0, 0.4);

  // ─── 3. Explainer (9–11.5s window) ─────────────────────────────
  yield* all(
    explainer().opacity(1, 0.45, easeOutCubic),
    explainer().scale(0.96, 0).to(1, 0.5, easeOutCubic),
  );
  yield* waitFor(1.6);
  yield* explainer().opacity(0, 0.4);

  // ─── 4–6. Graph: agents → mutande → recipients ─────────────────
  yield* graph().opacity(1, 0.4);
  yield* all(
    hub().opacity(1, 0.45, easeOutCubic),
    hub().scale(1, 0.5, easeOutCubic),
    sequence(
      0.08,
      ...agentNodes.map(n =>
        all(n.opacity(1, 0.35), n.scale(1, 0.4, easeOutCubic)),
      ),
    ),
    sequence(
      0.08,
      ...destNodes.map(n =>
        all(n.opacity(1, 0.35), n.scale(1, 0.4, easeOutCubic)),
      ),
    ),
  );

  // draw inbound beams (springy ease-out)
  yield* sequence(
    0.12,
    ...inBeams.map(b => b.end(1, 0.7, easeOutCubic)),
  );

  // pulse agents → hub
  yield* sequence(
    0.1,
    ...AGENTS.map((_, i) =>
      all(
        pulses[i].opacity(1, 0.1),
        pulses[i].position([midX - 20, 0], 0.65, easeOutCubic),
        pulses[i].opacity(0, 0.65),
      ),
    ),
  );

  // draw outbound beams
  yield* sequence(
    0.12,
    ...outBeams.map(b => b.end(1, 0.7, easeOutCubic)),
  );

  // pulse hub → recipients
  yield* sequence(
    0.1,
    ...RECIPIENTS.map((_, i) => {
      const p = pulses[AGENTS.length + i];
      return all(
        p.opacity(1, 0.1),
        p.position([rightX, ys[i]], 0.65, easeOutCubic),
        p.opacity(0, 0.65),
      );
    }),
  );

  yield* waitFor(2.2);
  yield* graph().opacity(0, 0.5);

  // ─── 7. Brand ──────────────────────────────────────────────────
  yield* all(
    brand().opacity(1, 0.55, easeOutCubic),
    brand().scale(0.92, 0).to(1, 0.65, easeOutCubic),
  );
  yield* waitFor(3.2);
  yield* brand().opacity(0, 0.5);
});
