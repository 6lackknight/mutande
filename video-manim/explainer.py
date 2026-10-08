"""~60s mutande explainer — problem-first (hero-aligned)."""

from __future__ import annotations

import layout as L
import script as S
import theme as T
from captions import caption_rule, make_caption
from motion import EASE, RT_CAPTION, RT_ENTER, RT_EXIT, RT_SWAP
from problem_visuals import (
    build_compose_chip,
    build_fanout,
    build_isolated_hosts,
    build_participant_stack,
    build_paste_buffer,
)
from ui_inset import build_thread_staged, glyph_path

from manim import *


def _dur(start: float, end: float) -> float:
    return max(0.0, end - start)


def _beat(beat_id: str) -> tuple[float, float, int | None]:
    for row in S.BEATS:
        if row[0] == beat_id:
            return row[1], row[2], row[3]
    raise KeyError(beat_id)


class MutandeExplainer(MovingCameraScene):
    def setup(self) -> None:
        super().setup()
        self.camera.background_color = T.BG

    def _show_caption(self, index: int) -> Text:
        cap = make_caption(S.CAPTIONS[index])
        self.play(FadeIn(cap, shift=UP * 0.08), run_time=RT_CAPTION, rate_func=EASE)
        return cap

    def _swap_caption(self, old: Mobject | None, index: int | None) -> Text | None:
        if index is None:
            if old is not None:
                self.play(FadeOut(old), run_time=RT_EXIT, rate_func=EASE)
            return None
        new = make_caption(S.CAPTIONS[index])
        if old is None:
            self.play(FadeIn(new, shift=UP * 0.08), run_time=RT_CAPTION, rate_func=EASE)
            return new
        self.play(FadeOut(old, shift=DOWN * 0.06), FadeIn(new, shift=UP * 0.06), run_time=RT_SWAP, rate_func=EASE)
        return new

    def _reset_camera(self) -> None:
        self.play(
            self.camera.frame.animate.set(width=config.frame_width).move_to(ORIGIN),
            run_time=RT_ENTER,
            rate_func=EASE,
        )

    def construct(self) -> None:
        rule = caption_rule()
        self.add(rule)
        cap: Text | None = None

        t0, t1, c0 = _beat("isolated_hosts")
        cap = self._show_caption(c0)
        hosts = build_isolated_hosts()
        self.play(FadeIn(hosts, shift=UP * 0.12, scale=0.98), run_time=RT_ENTER, rate_func=EASE)
        question = hosts[2][2]
        self.play(question.animate.set_color(T.AMBER), run_time=RT_CAPTION * 0.7, rate_func=EASE)
        self.wait(_dur(t0, t1) - RT_ENTER - RT_CAPTION * 0.7)

        t0, t1, c1 = _beat("paste_buffer")
        cap = self._swap_caption(cap, c1)
        paste = build_paste_buffer(hosts)
        packet = paste[3]
        paths = VGroup(paste[1], paste[2])
        self.play(FadeIn(paste[0]), Create(paths), FadeIn(packet, scale=0.9), run_time=RT_ENTER, rate_func=EASE)
        self.play(MoveAlongPath(packet, paths[0]), run_time=1.35, rate_func=EASE)
        self.play(MoveAlongPath(packet, paths[1]), run_time=1.35, rate_func=EASE)
        self.wait(_dur(t0, t1) - RT_ENTER - 2.7)

        t0, t1, c2 = _beat("handles")
        cap = self._swap_caption(cap, c2)
        stack = build_participant_stack(S.PARTICIPANTS)
        compose = build_compose_chip()
        stack.move_to(L.STAGE_SHIFT + UP * 0.35)
        compose.next_to(stack, DOWN, buff=0.38)
        chips = stack[1]
        self.play(FadeOut(hosts), FadeOut(paste), run_time=RT_EXIT, rate_func=EASE)
        self.play(
            LaggedStart(*[FadeIn(row, shift=LEFT * 0.08) for row in chips], lag_ratio=0.14),
            FadeIn(stack[0]),
            run_time=RT_ENTER + 0.15,
            rate_func=EASE,
        )
        self.play(FadeIn(compose, shift=UP * 0.1), run_time=RT_ENTER, rate_func=EASE)
        self.wait(_dur(t0, t1) - RT_EXIT - RT_ENTER - 0.15 - RT_ENTER)

        t0, t1, c3 = _beat("thread_ui")
        cap = self._swap_caption(cap, c3)
        shell, first, reply, seal = build_thread_staged()
        panel = VGroup(shell, first, reply, seal)
        self.play(FadeOut(stack), FadeOut(compose), run_time=RT_EXIT, rate_func=EASE)
        self.play(FadeIn(shell, scale=0.98), run_time=RT_ENTER, rate_func=EASE)
        self.play(FadeIn(first, shift=UP * 0.06), run_time=RT_ENTER, rate_func=EASE)
        self.wait(0.55)
        self.play(FadeIn(reply, shift=UP * 0.06), FadeIn(seal, scale=0.85), run_time=RT_ENTER, rate_func=EASE)
        self.wait(_dur(t0, t1) - RT_EXIT - RT_ENTER * 2 - 0.55 - RT_ENTER)

        t0, t1, c4 = _beat("org_fanout")
        cap = self._swap_caption(cap, c4)
        fanout = build_fanout("@cursor", S.FANOUT_HANDLES)
        sender, branches, band, proto = fanout
        self.play(FadeOut(panel), run_time=RT_EXIT, rate_func=EASE)
        self.play(FadeIn(sender), run_time=RT_CAPTION, rate_func=EASE)
        self.play(
            LaggedStart(*[FadeIn(b, shift=UP * 0.05) for b in branches], lag_ratio=0.12),
            run_time=RT_ENTER + 0.35,
            rate_func=EASE,
        )
        self.play(FadeIn(band), FadeIn(proto, shift=UP * 0.05), run_time=RT_CAPTION, rate_func=EASE)
        self.play(
            self.camera.frame.animate.scale(1.08).move_to(UP * 0.15),
            run_time=RT_ENTER + 0.1,
            rate_func=EASE,
        )
        self.wait(_dur(t0, t1) - RT_EXIT - RT_CAPTION - RT_ENTER - 0.35 - RT_CAPTION - RT_ENTER - 0.1)

        t0, t1, _ = _beat("end_card")
        cap = self._swap_caption(cap, None)
        self._reset_camera()
        self.play(FadeOut(fanout), FadeOut(rule), run_time=RT_EXIT, rate_func=EASE)

        plate = FullScreenRectangle(fill_color=BLACK, fill_opacity=1)
        gpath = glyph_path()
        mark = ImageMobject(str(gpath)).scale(0.52) if gpath.is_file() else Text("@i", font=T.FONT, font_size=96, color=WHITE, weight=BOLD)
        word = Text("mutande", font=T.FONT, font_size=50, color=WHITE, weight=MEDIUM)
        sub = Text("Address Intelligence", font=T.FONT, font_size=26, color=T.STONE300)
        tag = Text("Trusted handles for people and assistants.", font=T.FONT, font_size=19, color=T.STONE400)
        word.next_to(mark, DOWN, buff=0.32)
        sub.next_to(word, DOWN, buff=0.2)
        tag.next_to(sub, DOWN, buff=0.24)
        end = Group(mark, word, sub, tag)
        self.play(FadeIn(plate), run_time=0.25, rate_func=EASE)
        self.play(FadeIn(end, shift=UP * 0.06), run_time=0.55, rate_func=EASE)
        self.wait(_dur(t0, t1) - 0.8)


class MutandeStoryboard(Scene):
    def construct(self) -> None:
        self.camera.background_color = T.BG
        title = Text("Problem-first beats", font=T.FONT, font_size=28, color=T.MUTED)
        title.to_edge(UP)
        rows = VGroup()
        for row in S.BEATS:
            bid, start, end, cap_i = row
            cap_txt = S.CAPTIONS[cap_i] if cap_i is not None else "(end card)"
            line = Text(
                f"{start:4.1f}–{end:4.1f}s  {bid:14s}  {cap_txt}",
                font=T.FONT_MONO,
                font_size=16,
                color=T.INK,
            )
            rows.add(line)
        rows.arrange(DOWN, aligned_edge=LEFT, buff=0.2)
        rows.next_to(title, DOWN, buff=0.45)
        self.add(title, rows)
        self.wait(2)
