#!/usr/bin/env python3
"""Privacy-safe EPUB archive diagnostics for Nalori parser investigations."""

from __future__ import annotations

import argparse
import hashlib
import html.parser
import json
import os
import posixpath
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter
from dataclasses import dataclass, asdict
from pathlib import Path


HTML_EXTS = {".html", ".htm", ".xhtml", ".xml"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".avif"}
FONT_EXTS = {".otf", ".ttf", ".woff", ".woff2"}
CSS_EXTS = {".css"}
SVG_EXTS = {".svg"}


class StructureParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.max_depth = 0
        self.tags: Counter[str] = Counter()
        self.nodes = 0
        self.large_inline_style_chars = 0
        self.base64_data_uris = 0
        self.max_attr_len = 0

    def handle_starttag(self, tag: str, attrs) -> None:
        self.depth += 1
        self.max_depth = max(self.max_depth, self.depth)
        self.tags[tag.lower()] += 1
        self.nodes += 1
        for key, value in attrs:
            if value is None:
                continue
            self.max_attr_len = max(self.max_attr_len, len(value))
            if key.lower() == "style" and len(value) > 1000:
                self.large_inline_style_chars += len(value)
            if "data:" in value and "base64" in value:
                self.base64_data_uris += 1

    def handle_endtag(self, tag: str) -> None:
        self.depth = max(0, self.depth - 1)

    def handle_startendtag(self, tag: str, attrs) -> None:
        self.tags[tag.lower()] += 1
        self.nodes += 1
        for key, value in attrs:
            if value:
                self.max_attr_len = max(self.max_attr_len, len(value))
                if key.lower() == "style" and len(value) > 1000:
                    self.large_inline_style_chars += len(value)
                if "data:" in value and "base64" in value:
                    self.base64_data_uris += 1

    def handle_data(self, data: str) -> None:
        if data.strip():
            self.nodes += 1


@dataclass
class HtmlMetric:
    name: str
    size: int
    max_depth: int
    nodes: int
    paragraphs: int
    headings: int
    tables: int
    images: int
    lists: int
    anchors: int
    footnotes: int
    large_inline_style_chars: int
    base64_data_uris: int
    max_attr_len: int
    parse_error: str | None = None


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower()


def ns_find(root: ET.Element, path: str) -> ET.Element | None:
    return root.find(path, {"c": "urn:oasis:names:tc:opendocument:xmlns:container"})


def get_opf_path(zf: zipfile.ZipFile) -> str | None:
    try:
        container = ET.fromstring(zf.read("META-INF/container.xml"))
    except Exception:
        return None
    rootfile = ns_find(container, ".//c:rootfile")
    if rootfile is None:
        return None
    return rootfile.attrib.get("full-path")


def parse_opf(zf: zipfile.ZipFile, opf_path: str):
    root = ET.fromstring(zf.read(opf_path))
    manifest = {}
    spine = []
    for el in root.iter():
        name = local_name(el.tag)
        if name == "item":
            item_id = el.attrib.get("id")
            if item_id:
                manifest[item_id] = {
                    "href": el.attrib.get("href", ""),
                    "media_type": el.attrib.get("media-type", ""),
                    "properties": el.attrib.get("properties", ""),
                }
        elif name == "itemref":
            spine.append(el.attrib.get("idref", ""))
    return manifest, spine


def resolve_href(opf_path: str, href: str) -> str:
    base = posixpath.dirname(opf_path)
    return posixpath.normpath(posixpath.join(base, href.split("#", 1)[0]))


def analyze_html(zf: zipfile.ZipFile, name: str) -> HtmlMetric:
    raw = zf.read(name)
    text = raw.decode("utf-8", errors="replace")
    parser = StructureParser()
    parse_error = None
    try:
        parser.feed(text)
        parser.close()
    except Exception as exc:
        parse_error = repr(exc)
    tags = parser.tags
    lower = text.lower()
    footnotes = len(re.findall(r"(epub:type=[\"']noteref|id=[\"'](?:fn|note|footnote|endnote))", lower))
    return HtmlMetric(
        name=name,
        size=len(raw),
        max_depth=parser.max_depth,
        nodes=parser.nodes,
        paragraphs=tags["p"],
        headings=sum(tags[f"h{i}"] for i in range(1, 7)),
        tables=tags["table"],
        images=tags["img"],
        lists=tags["ul"] + tags["ol"] + tags["li"],
        anchors=tags["a"],
        footnotes=footnotes,
        large_inline_style_chars=parser.large_inline_style_chars,
        base64_data_uris=parser.base64_data_uris,
        max_attr_len=parser.max_attr_len,
        parse_error=parse_error,
    )


def classify(name: str) -> str:
    ext = Path(name.lower()).suffix
    if ext in HTML_EXTS:
        return "html"
    if ext in IMAGE_EXTS:
        return "image"
    if ext in FONT_EXTS:
        return "font"
    if ext in CSS_EXTS:
        return "css"
    if ext in SVG_EXTS:
        return "svg"
    return "other"


def analyze(path: Path) -> dict:
    with zipfile.ZipFile(path) as zf:
        infos = [i for i in zf.infolist() if not i.is_dir()]
        entries = []
        totals = Counter()
        counts = Counter()
        for info in infos:
            kind = classify(info.filename)
            counts[kind] += 1
            totals[kind] += info.file_size
            entries.append(
                {
                    "name": info.filename,
                    "compressed": info.compress_size,
                    "uncompressed": info.file_size,
                    "kind": kind,
                    "ratio": round(info.file_size / max(1, info.compress_size), 2),
                }
            )

        opf_path = get_opf_path(zf)
        manifest = {}
        spine = []
        spine_paths = []
        missing_spine = []
        duplicate_spine_paths = []
        nav_items = []
        if opf_path:
            manifest, spine = parse_opf(zf, opf_path)
            seen = Counter()
            names = {i.filename for i in infos}
            for idref in spine:
                item = manifest.get(idref)
                if not item:
                    missing_spine.append(idref)
                    continue
                resolved = resolve_href(opf_path, item["href"])
                spine_paths.append(resolved)
                seen[resolved] += 1
                if resolved not in names:
                    missing_spine.append(f"{idref}:{resolved}")
            duplicate_spine_paths = [name for name, count in seen.items() if count > 1]
            for item in manifest.values():
                if "nav" in item.get("properties", "").split():
                    nav_path = resolve_href(opf_path, item["href"])
                    try:
                        nav_text = zf.read(nav_path).decode("utf-8", errors="replace")
                        nav_items.append(nav_text.lower().count("<a "))
                    except Exception:
                        pass

        html_names = [e["name"] for e in entries if e["kind"] == "html"]
        html_metrics = [analyze_html(zf, name) for name in html_names]
        largest_html = max(html_metrics, key=lambda m: m.size, default=None)
        total_uncompressed = sum(i.file_size for i in infos)
        total_compressed = path.stat().st_size
        result = {
            "path": str(path.resolve()),
            "sha256": sha256(path),
            "compressed_size": total_compressed,
            "total_uncompressed_size": total_uncompressed,
            "compression_ratio": round(total_uncompressed / max(1, total_compressed), 2),
            "entry_count": len(infos),
            "counts": dict(counts),
            "totals": dict(totals),
            "opf_path": opf_path,
            "spine_item_count": len(spine),
            "toc_nav_item_count": sum(nav_items),
            "missing_spine_refs": missing_spine,
            "duplicate_spine_paths": duplicate_spine_paths,
            "spine_paths": spine_paths,
            "largest_20_entries": sorted(entries, key=lambda e: e["uncompressed"], reverse=True)[:20],
            "html_metrics": [asdict(m) for m in sorted(html_metrics, key=lambda m: m.size, reverse=True)],
            "html_totals": {
                "size": sum(m.size for m in html_metrics),
                "nodes": sum(m.nodes for m in html_metrics),
                "paragraphs": sum(m.paragraphs for m in html_metrics),
                "headings": sum(m.headings for m in html_metrics),
                "tables": sum(m.tables for m in html_metrics),
                "images": sum(m.images for m in html_metrics),
                "lists": sum(m.lists for m in html_metrics),
                "anchors": sum(m.anchors for m in html_metrics),
                "footnotes": sum(m.footnotes for m in html_metrics),
                "max_depth": max((m.max_depth for m in html_metrics), default=0),
                "largest_html": asdict(largest_html) if largest_html else None,
            },
            "zip_bomb_indicators": {
                "ratio_over_100": total_uncompressed / max(1, total_compressed) > 100,
                "any_entry_ratio_over_1000": any(e["ratio"] > 1000 for e in entries),
                "uncompressed_over_100mb": total_uncompressed > 100 * 1024 * 1024,
            },
        }
        return result


def create_control_epub(path: Path) -> None:
    mimetype = b"application/epub+zip"
    chapter = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Control</title></head>
<body><h1>Chapter One</h1><p>This is a small valid EPUB used as a parser control.</p>
<p>It has ordinary paragraphs and a simple table.</p>
<table><tr><th>A</th><th>B</th></tr><tr><td>One</td><td>Two</td></tr></table>
</body></html>"""
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("mimetype", mimetype, compress_type=zipfile.ZIP_STORED)
        zf.writestr(
            "META-INF/container.xml",
            """<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""",
        )
        zf.writestr(
            "OEBPS/content.opf",
            """<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">control</dc:identifier><dc:title>Control EPUB</dc:title><dc:creator>Nalori</dc:creator><dc:language>en</dc:language></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chap1" href="chapter1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chap1"/></spine></package>""",
        )
        zf.writestr(
            "OEBPS/nav.xhtml",
            """<html xmlns="http://www.w3.org/1999/xhtml"><body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">Chapter One</a></li></ol></nav></body></html>""",
        )
        zf.writestr("OEBPS/chapter1.xhtml", chapter)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("epubs", nargs="*", type=Path)
    parser.add_argument("--make-control", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.make_control:
        create_control_epub(args.make_control)
    results = [analyze(path) for path in args.epubs]
    payload = json.dumps(results, indent=2) + "\n"
    if args.output:
        args.output.write_text(payload, encoding="utf-8")
    else:
        sys.stdout.write(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
