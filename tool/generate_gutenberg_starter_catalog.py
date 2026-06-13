#!/usr/bin/env python3
import json
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

NS = {
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "dcterms": "http://purl.org/dc/terms/",
    "pgterms": "http://www.gutenberg.org/2009/pgterms/",
}

CURATED_IDS = [
    1342, 84, 2701, 11, 1661, 98, 174, 345, 2554, 5200,
    76, 43, 1952, 1080, 1400, 1260, 2591, 6130, 2542, 844,
    4300, 2600, 1232, 74, 1497, 28054, 408, 120, 514, 768,
    45, 55, 215, 2852, 16328, 236, 2814, 863, 730, 219,
    36, 16, 209, 244, 205, 902, 1399, 3825, 25344, 1184,
    8800, 1250, 34901, 19942, 160, 829, 100, 158, 161, 105,
    121, 1727, 521, 5740, 1064, 3207, 20203, 37106, 4217, 600,
    27761, 1998, 4363, 61, 2680, 2148, 1404, 47629, 33283, 8297,
    135, 24518, 28145, 23684, 27827, 32242, 23, 203, 20228, 1513,
    2500, 996, 9966, 34206, 5827, 41, 42, 46, 47, 50,
    70, 75, 86, 90, 110, 139, 153, 171, 172, 193,
    208, 22381, 34970, 1200, 8295, 28885, 15474, 147, 145, 217,
]


def text_at(parent, path):
    node = parent.find(path, NS)
    return (node.text or "").strip() if node is not None else ""


def values_at(parent, path):
    values = []
    for node in parent.findall(path, NS):
        value = (node.text or "").strip()
        if value:
            values.append(value)
    return values


def fetch_rdf(book_id):
    url = f"https://www.gutenberg.org/ebooks/{book_id}.rdf"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Nalori catalog generator (naloriapp@gmail.com)"},
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return response.read()


def find_format(files, suffixes):
    for suffix in suffixes:
        for file_node in files:
            about = file_node.attrib.get(f"{{{NS['rdf']}}}about", "")
            if not about.lower().endswith(suffix):
                continue
            file_format = text_at(file_node, "dcterms:format/rdf:Description/rdf:value")
            if "application/epub+zip" in file_format or suffix.endswith(".jpg"):
                return about
    return None


def parse_book(book_id, raw):
    root = ET.fromstring(raw)
    ebook = root.find("pgterms:ebook", NS)
    if ebook is None:
        return None

    title = text_at(ebook, "dcterms:title")
    languages = values_at(ebook, "dcterms:language/rdf:Description/rdf:value")
    if "en" not in [lang.lower() for lang in languages]:
        return None

    authors = []
    author_details = []
    for creator in ebook.findall("dcterms:creator/pgterms:agent", NS):
        raw_name = text_at(creator, "pgterms:name")
        if not raw_name:
            continue
        name = raw_name
        birth = text_at(creator, "pgterms:birthdate")
        death = text_at(creator, "pgterms:deathdate")
        authors.append(name)
        author_details.append(
            {
                "name": name,
                "birth_year": int(birth) if birth.lstrip("-").isdigit() else None,
                "death_year": int(death) if death.lstrip("-").isdigit() else None,
            }
        )

    subjects = values_at(ebook, "dcterms:subject/rdf:Description/rdf:value")
    bookshelves = values_at(ebook, "pgterms:bookshelf/rdf:Description/rdf:value")
    downloads = text_at(ebook, "pgterms:downloads")

    files = ebook.findall("dcterms:hasFormat/pgterms:file", NS)
    epub_url = find_format(
        files,
        [".epub3.images", ".epub.images", ".epub.noimages"],
    )
    if not epub_url:
        return None

    cover_url = find_format(files, [".cover.medium.jpg", ".cover.small.jpg"])

    return {
        "id": book_id,
        "title": title or f"Project Gutenberg #{book_id}",
        "authors": authors,
        "authorDetails": author_details,
        "subjects": subjects[:12],
        "bookshelves": bookshelves[:8],
        "languages": languages,
        "copyright": False,
        "coverUrl": cover_url,
        "epubUrl": epub_url,
        "downloadCount": int(downloads) if downloads.isdigit() else 0,
        "mediaType": "Text",
    }


def main():
    out = Path("assets/catalog/gutenberg_starter_catalog.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    books_by_id = {}
    failures = []

    def load(book_id):
        return book_id, parse_book(book_id, fetch_rdf(book_id))

    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(load, book_id): book_id for book_id in CURATED_IDS}
        for index, future in enumerate(as_completed(futures), start=1):
            book_id = futures[future]
            try:
                _, book = future.result()
                if book is not None:
                    books_by_id[book_id] = book
                    print(f"[{index}/{len(CURATED_IDS)}] ok {book_id}", flush=True)
                else:
                    print(f"[{index}/{len(CURATED_IDS)}] skip {book_id}", flush=True)
            except Exception as exc:
                failures.append({"id": book_id, "error": type(exc).__name__})
                print(
                    f"[{index}/{len(CURATED_IDS)}] fail {book_id} {type(exc).__name__}",
                    flush=True,
                )

    books = [books_by_id[book_id] for book_id in CURATED_IDS if book_id in books_by_id]

    payload = {
        "source": "Project Gutenberg RDF per-book metadata",
        "generatedBy": "tool/generate_gutenberg_starter_catalog.py",
        "books": books,
    }
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {len(books)} books to {out}")
    if failures:
        print(f"skipped {len(failures)} ids", file=sys.stderr)


if __name__ == "__main__":
    main()
