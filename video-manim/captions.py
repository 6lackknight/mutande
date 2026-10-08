"""On-screen copy styling."""

from __future__ import annotations

from manim import DOWN, MEDIUM, Text, VGroup

import layout as L
import theme as T


def make_caption(text: str) -> Text:
    size = 26 if len(text) > 44 else 30
    return Text(
        text,
        font=T.FONT,
        font_size=size,
        color=T.CAPTION,
        weight=MEDIUM,
        line_spacing=0.92,
    ).to_edge(DOWN, buff=L.CAPTION_EDGE_BUFF)


def caption_rule() -> VGroup:
    """Subtle separator between stage and caption."""
    from manim import Line

    rule = Line(
        [-L.CONTENT_WIDTH / 2, -2.95, 0],
        [L.CONTENT_WIDTH / 2, -2.95, 0],
        color=T.STONE200,
        stroke_width=1,
        stroke_opacity=0.85,
    )
    return VGroup(rule)
