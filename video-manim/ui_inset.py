"""Simplified mutande thread UI for the Manim explainer."""

from __future__ import annotations

from pathlib import Path

from manim import *

import layout as L
import script as S
import theme as T


def _mono(text: str, size: float = 22) -> Text:
    return Text(text, font=T.FONT_MONO, font_size=size, color=T.INK, weight=NORMAL)


def build_thread_inset() -> VGroup:
    """Full thread panel."""
    shell, first, reply, seal = _thread_parts()
    return VGroup(shell, first, reply, seal).move_to(L.STAGE_SHIFT)


def build_thread_staged() -> tuple[VGroup, VGroup, VGroup, VGroup]:
    """shell, first message block, reply block, seal — for staggered reveal."""
    return _thread_parts()


def _thread_parts() -> tuple[VGroup, VGroup, VGroup, VGroup]:
    outer = RoundedRectangle(
        corner_radius=0.16,
        width=6.85,
        height=4.85,
        fill_color=T.STONE100,
        fill_opacity=1,
        stroke_color=T.STONE300,
        stroke_width=1.2,
    )
    header = RoundedRectangle(
        corner_radius=0.1,
        width=6.35,
        height=0.48,
        fill_color=T.STONE200,
        fill_opacity=0.55,
        stroke_width=0,
    )
    header.move_to(outer.get_top() + DOWN * 0.38)
    title = _mono("Q3 plan review", size=19)
    title.next_to(header, DOWN, buff=0.28).align_to(outer, LEFT).shift(RIGHT * 0.38)
    shell = VGroup(outer, header, title)

    msg_a = RoundedRectangle(
        corner_radius=0.09,
        width=5.55,
        height=0.98,
        fill_color=WHITE,
        fill_opacity=0.9,
        stroke_color=T.STONE200,
        stroke_width=1,
    )
    msg_a.next_to(title, DOWN, buff=0.28).align_to(outer, LEFT).shift(RIGHT * 0.38)
    from_line = _mono("@cursor", size=17)
    from_line.set_color(T.MUTED)
    from_line.next_to(msg_a.get_top(), DOWN, buff=0.1).align_to(msg_a, LEFT).shift(RIGHT * 0.16)
    body_a = Text(
        S.COMPOSE_PROMPT,
        font=T.FONT,
        font_size=17,
        color=T.STONE700,
        t2c={S.COMPOSE_HIGHLIGHT: T.ACCENT},
        line_spacing=0.86,
    )
    body_a.next_to(from_line, DOWN, buff=0.06).align_to(from_line, LEFT)
    first = VGroup(msg_a, from_line, body_a)

    msg_b = msg_a.copy()
    msg_b.set(height=0.88)
    msg_b.next_to(msg_a, DOWN, buff=0.22)
    from_b = _mono("bob@acme/openclaw", size=17)
    from_b.set_color(T.ALICE)
    from_b.next_to(msg_b.get_top(), DOWN, buff=0.1).align_to(msg_b, LEFT).shift(RIGHT * 0.16)
    body_b = Text(
        "Reviewed — routing to alice@acme/research for numbers.",
        font=T.FONT,
        font_size=17,
        color=T.STONE700,
        line_spacing=0.86,
    )
    body_b.next_to(from_b, DOWN, buff=0.06).align_to(from_b, LEFT)
    reply = VGroup(msg_b, from_b, body_b)

    seal = Circle(
        radius=0.1,
        color=T.ACCENT,
        fill_color=T.ACCENT_SOFT,
        fill_opacity=0.85,
        stroke_width=1,
    )
    seal.move_to(msg_b.get_right() + LEFT * 0.32 + DOWN * 0.05)
    lock = Text("◆", font=T.FONT, font_size=12, color=T.ACCENT)
    lock.move_to(seal.get_center())
    seal_group = VGroup(seal, lock)

    return shell, first, reply, seal_group


def glyph_path() -> Path:
    return Path(__file__).resolve().parent / T.GLYPH_WHITE
