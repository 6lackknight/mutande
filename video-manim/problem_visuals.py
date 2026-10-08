"""Problem-first beats — isolated hosts, paste buffer, handles, fan-out."""

from __future__ import annotations

import script as S
from manim import *

import layout as L
import theme as T


def mono(text: str, size: float = 22, color: ManimColor = T.INK) -> Text:
    return Text(text, font=T.FONT_MONO, font_size=size, color=color, weight=NORMAL)


def _chip_for_handle(handle: str, font_size: float = 20) -> VGroup:
    t = mono(handle, font_size, T.ACCENT if handle.startswith("@") else T.INK)
    pad = 0.55
    chip = RoundedRectangle(
        corner_radius=0.1,
        width=max(4.8, t.width + pad),
        height=0.52,
        fill_color=T.STONE100,
        fill_opacity=1,
        stroke_color=T.STONE200,
        stroke_width=1,
    )
    t.move_to(chip.get_center())
    return VGroup(chip, t)


def host_silo(title: str, handle: str) -> VGroup:
    panel = RoundedRectangle(
        corner_radius=0.14,
        width=3.35,
        height=2.28,
        fill_color=T.STONE100,
        fill_opacity=1,
        stroke_color=T.STONE300,
        stroke_width=1.2,
    )
    bar = RoundedRectangle(
        corner_radius=0.08,
        width=2.95,
        height=0.34,
        fill_color=T.STONE200,
        fill_opacity=0.65,
        stroke_width=0,
    )
    bar.move_to(panel.get_top() + DOWN * 0.3)
    host = Text(title, font=T.FONT, font_size=19, color=T.STONE700)
    host.next_to(bar, DOWN, buff=0.24)
    addr = mono(handle, 19, T.MUTED)
    addr.next_to(host, DOWN, buff=0.18)
    body = RoundedRectangle(
        corner_radius=0.08,
        width=2.65,
        height=0.5,
        fill_color=WHITE,
        fill_opacity=0.92,
        stroke_color=T.STONE200,
        stroke_width=1,
    )
    body.next_to(addr, DOWN, buff=0.22)
    dots = Text("···", font=T.FONT, font_size=24, color=T.STONE400)
    dots.move_to(body.get_center())
    return VGroup(panel, bar, host, addr, body, dots)


def broken_link_between(left: Mobject, right: Mobject) -> VGroup:
    a, b = left.get_right(), left.get_right() * 0 + right.get_left() * 0 + right.get_left()
    a = left.get_right()
    b = right.get_left()
    mid = (a + b) / 2
    gap = 0.42
    line_l = DashedLine(a, mid + LEFT * gap, color=T.STONE300, stroke_width=1.8, dash_length=0.12)
    line_r = DashedLine(mid + RIGHT * gap, b, color=T.STONE300, stroke_width=1.8, dash_length=0.12)
    mark = Text("?", font=T.FONT, font_size=32, color=T.AMBER, weight=BOLD)
    mark.move_to(mid)
    return VGroup(line_l, line_r, mark)


def build_isolated_hosts() -> VGroup:
    left = host_silo("Cursor", "@cursor")
    right = host_silo("Claude", "@claude")
    left.move_to(LEFT * 2.45 + L.STAGE_SHIFT)
    right.move_to(RIGHT * 2.45 + L.STAGE_SHIFT)
    link = broken_link_between(left, right)
    return VGroup(left, right, link).move_to(L.STAGE_SHIFT)


def build_paste_buffer(hosts: VGroup) -> VGroup:
    left, right = hosts[0], hosts[1]
    circle = Circle(
        radius=0.26,
        color=T.ACCENT,
        fill_color=T.ACCENT_SOFT,
        fill_opacity=0.45,
        stroke_width=1.8,
    )
    you_label = Text("You", font=T.FONT, font_size=19, color=T.ACCENT, weight=MEDIUM)
    you_label.next_to(circle, DOWN, buff=0.1)
    human = VGroup(circle, you_label)
    human.move_to(DOWN * 1.35 + L.STAGE_SHIFT * 0.35)

    snippet = RoundedRectangle(
        corner_radius=0.06,
        width=0.88,
        height=0.58,
        fill_color=T.AMBER_SOFT,
        fill_opacity=1,
        stroke_color=T.AMBER,
        stroke_width=1,
    )
    snippet_lbl = Text("paste", font=T.FONT_MONO, font_size=11, color=T.ACCENT)
    snippet_lbl.move_to(snippet.get_center())
    packet = VGroup(snippet, snippet_lbl)

    def path_for(start: np.ndarray, end: np.ndarray, sign: float) -> CubicBezier:
        c1 = start + UP * 0.65 + RIGHT * sign * 0.35
        c2 = end + UP * 0.65 + LEFT * sign * 0.35
        return CubicBezier(start, c1, c2, end)

    a = left[0].get_bottom() + DOWN * 0.05
    b = right[0].get_bottom() + DOWN * 0.05
    h = circle.get_top()
    path_out = path_for(a, h + LEFT * 0.08, 1.0)
    path_in = path_for(h + RIGHT * 0.08, b, -1.0)
    path_out.set_color(T.STONE400).set_stroke(width=1.6, opacity=0.7)
    path_in.set_color(T.STONE400).set_stroke(width=1.6, opacity=0.7)
    packet.move_to(path_out.get_start())

    return VGroup(human, path_out, path_in, packet)


def build_compose_chip() -> VGroup:
    shell = RoundedRectangle(
        corner_radius=0.14,
        width=7.1,
        height=1.65,
        fill_color=T.STONE100,
        fill_opacity=0.55,
        stroke_color=T.STONE200,
        stroke_width=1,
    )
    field = RoundedRectangle(
        corner_radius=0.1,
        width=6.5,
        height=0.95,
        fill_color=WHITE,
        fill_opacity=0.98,
        stroke_color=T.STONE300,
        stroke_width=1.2,
    )
    field.move_to(shell.get_center() + DOWN * 0.12)
    prompt = Text(
        S.COMPOSE_PROMPT,
        font=T.FONT,
        font_size=19,
        color=T.STONE700,
        t2c={S.COMPOSE_HIGHLIGHT: T.ACCENT},
        line_spacing=0.88,
    )
    prompt.move_to(field.get_center())
    label = Text("Claude Desktop", font=T.FONT, font_size=17, color=T.MUTED)
    label.next_to(shell, UP, buff=0.12).align_to(shell, LEFT)
    return VGroup(shell, label, field, prompt)


def build_participant_stack(handles: tuple[str, ...]) -> VGroup:
    rows = VGroup(*[_chip_for_handle(h) for h in handles])
    rows.arrange(DOWN, buff=0.12, aligned_edge=LEFT)
    title = Text("Trusted handles", font=T.FONT, font_size=21, color=T.CAPTION, weight=MEDIUM)
    title.next_to(rows, UP, buff=0.32)
    return VGroup(title, rows)


def build_fanout(from_label: str, targets: tuple[str, ...]) -> VGroup:
    sender = _chip_for_handle(from_label, 22)
    sender.move_to(UP * 1.55 + L.STAGE_SHIFT * 0.5)
    nodes = VGroup()
    angles = np.linspace(-PI * 0.68, -PI * 0.32, len(targets))
    for handle, ang in zip(targets, angles):
        pos = 2.15 * np.array([np.cos(ang), np.sin(ang), 0]) + L.STAGE_SHIFT * 0.15
        node = _chip_for_handle(handle, 17)
        node.move_to(pos)
        arr = Arrow(
            sender.get_bottom(),
            node.get_top(),
            buff=0.1,
            color=T.STONE300,
            stroke_width=1.8,
            max_tip_length_to_length_ratio=0.1,
        )
        nodes.add(VGroup(arr, node))
    proto = VGroup(*[Text(p, font=T.FONT_MONO, font_size=13, color=T.MUTED) for p in S.PROTOCOL_LABELS])
    proto.arrange(RIGHT, buff=0.42)
    proto.to_edge(DOWN, buff=0.62)
    band = Text("mutande", font=T.FONT, font_size=24, color=T.ACCENT, weight=MEDIUM)
    band.next_to(proto, UP, buff=0.14)
    return VGroup(sender, nodes, band, proto)
