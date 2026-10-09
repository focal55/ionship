"""Writes the Ode mark and wordmark SVGs with "de" outlined from Nunito ExtraBold.

Usage: python wordmark.py <Nunito[wght].ttf> <output dir>

The loop is the "o": 1.27 x-heights tall, dropped 0.115 x-heights below the baseline, so it
reads as the same size and weight as the letters beside it. Geometry matches CLAUDE.md.
"""
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

INK, PAPER, ACCENT = "#14161C", "#F6F4EF", "#2F4BE0"
LOOP = "M 183.4 81.9 A 74 74 0 1 1 84.1 55.3"
STROKE, DOT = 60, (139.2, 48.5, 23)
INK_BOX = (16, 224)  # the mark's drawn extent inside its 240 box (radius 74 + half stroke)


def mark(ink, transform="translate(0 0)"):
    x, y, r = DOT
    return (f'<g transform="{transform}">'
            f'<path d="{LOOP}" fill="none" stroke="{ink}" stroke-width="{STROKE}" stroke-linecap="round"/>'
            f'<circle cx="{x}" cy="{y}" r="{r}" fill="{ACCENT}"/></g>')


def main(font_path, out_dir):
    font = instantiateVariableFont(TTFont(font_path), {"wght": 800})
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    xh = font["OS/2"].sxHeight
    tracking = -2 / 120 * font["head"].unitsPerEm

    size = 1.27 * xh
    drop = 0.115 * xh
    scale = size / 240
    loop_left, loop_right = INK_BOX[0] * scale, INK_BOX[1] * scale
    loop_top = size - drop - INK_BOX[0] * scale
    loop_bottom = size - drop - INK_BOX[1] * scale

    d, e = glyphs[cmap[ord("d")]], glyphs[cmap[ord("e")]]
    d_x = size - 0.02 * xh
    e_x = d_x + d.width + tracking
    bounds = BoundsPen(glyphs)
    d.draw(TransformPen(bounds, (1, 0, 0, 1, d_x, 0)))
    e.draw(TransformPen(bounds, (1, 0, 0, 1, e_x, 0)))
    _, y_min, x_max, y_max = bounds.bounds
    top, bottom = max(y_max, loop_top), min(y_min, loop_bottom)

    def outline(glyph, x):
        pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
        glyph.draw(TransformPen(pen, (1, 0, 0, -1, x, top)))
        return pen.getCommands()

    letters = outline(d, d_x) + outline(e, e_x)
    width, height = x_max - loop_left, top - bottom
    box = f"{loop_left:.1f} 0 {width:.1f} {height:.1f}"
    loop_at = f"translate(0 {top - (size - drop):.1f}) scale({scale:.5f})"

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for name, ink in (("ode-wordmark.svg", INK), ("ode-wordmark-on-dark.svg", PAPER)):
        (out / name).write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{box}" role="img" aria-label="Ode">'
            f'{mark(ink, loop_at)}<path d="{letters}" fill="{ink}"/></svg>\n')
    for name, ink in (("ode-mark.svg", INK), ("ode-mark-on-dark.svg", PAPER)):
        (out / name).write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="16 16 208 208" role="img" aria-label="Ode">'
            f'{mark(ink)}</svg>\n')


if __name__ == "__main__":
    main(*sys.argv[1:3])
