#!/usr/bin/env python3
import argparse
import gzip
import hashlib
import json
import re
import shutil
import sqlite3
import tarfile
import tempfile
import time
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

NS = {
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "dcterms": "http://purl.org/dc/terms/",
    "pgterms": "http://www.gutenberg.org/2009/pgterms/",
}

SCHEMA_VERSION = 1
DEFAULT_SOURCE_URL = "https://www.gutenberg.org/cache/epub/feeds/rdf-files.tar.bz2"
USER_AGENT = "Nalori Gutenberg catalog generator (naloriapp@gmail.com)"


@dataclass
class CatalogBook:
    id: int
    title: str
    authors: list[dict]
    languages: list[str]
    subjects: list[str]
    bookshelves: list[str]
    epub_url: str
    cover_url: str | None
    download_count: int
    media_type: str = "Text"


@dataclass
class SkipCounts:
    missing_title: int = 0
    missing_language: int = 0
    non_public_domain: int = 0
    missing_usable_epub: int = 0
    malformed_identifier: int = 0
    malformed_url: int = 0
    duplicate_gutenberg_id: int = 0
    malformed_record: int = 0
    included: int = 0
    no_author: int = 0
    details: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "included": self.included,
            "missing_title": self.missing_title,
            "missing_language": self.missing_language,
            "non_public_domain": self.non_public_domain,
            "missing_usable_epub": self.missing_usable_epub,
            "malformed_identifier": self.malformed_identifier,
            "malformed_url": self.malformed_url,
            "duplicate_gutenberg_id": self.duplicate_gutenberg_id,
            "malformed_record": self.malformed_record,
            "no_author": self.no_author,
        }


def normalize_text(value: str) -> str:
    value = value.lower().replace("&", " and ")
    value = re.sub(r"[^a-z0-9]+", " ", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def display_person_name(value: str) -> str:
    compact = re.sub(r"\s+", " ", value.strip())
    parts = [part.strip() for part in compact.split(",") if part.strip()]
    if len(parts) < 2:
        return compact
    return f"{' '.join(parts[1:])} {parts[0]}".strip()


def text_at(parent: ET.Element, path: str) -> str:
    node = parent.find(path, NS)
    return (node.text or "").strip() if node is not None else ""


def values_at(parent: ET.Element, path: str) -> list[str]:
    values = []
    for node in parent.findall(path, NS):
        value = (node.text or "").strip()
        if value:
            values.append(value)
    return values


def int_or_none(value: str) -> int | None:
    return int(value) if value and value.lstrip("-").isdigit() else None


def ebook_id(ebook: ET.Element) -> int | None:
    about = ebook.attrib.get(f"{{{NS['rdf']}}}about", "")
    match = re.search(r"(?:^|/)ebooks/(\d+)$", about)
    return int(match.group(1)) if match else None


def is_public_domain(ebook: ET.Element) -> bool:
    rights = " ".join(values_at(ebook, "dcterms:rights")).lower()
    if not rights:
        return True
    if "not public domain" in rights:
        return False
    return "public domain" in rights


def file_url(file_node: ET.Element) -> str:
    return file_node.attrib.get(f"{{{NS['rdf']}}}about", "").strip()


def file_mime(file_node: ET.Element) -> str:
    return text_at(file_node, "dcterms:format/rdf:Description/rdf:value")


def find_format(files: list[ET.Element], suffixes: list[str], mime: str) -> str | None:
    for suffix in suffixes:
        for file_node in files:
            url = file_url(file_node)
            if not url.lower().endswith(suffix):
                continue
            if mime and mime not in file_mime(file_node).lower():
                continue
            return url
    return None


def parse_book(raw: bytes, skips: SkipCounts) -> CatalogBook | None:
    try:
        root = ET.fromstring(raw)
        ebook = root.find("pgterms:ebook", NS)
        if ebook is None:
            skips.malformed_record += 1
            return None

        book_id = ebook_id(ebook)
        if book_id is None:
            skips.malformed_identifier += 1
            return None

        title = text_at(ebook, "dcterms:title")
        if not title:
            skips.missing_title += 1
            return None

        languages = values_at(ebook, "dcterms:language/rdf:Description/rdf:value")
        if not languages:
            skips.missing_language += 1
            return None

        if not is_public_domain(ebook):
            skips.non_public_domain += 1
            return None

        files = ebook.findall("dcterms:hasFormat/pgterms:file", NS)
        epub_url = find_format(
            files,
            [
                ".epub3.images",
                ".epub.images",
                ".epub.noimages",
                ".epub",
            ],
            "application/epub+zip",
        )
        if not epub_url:
            skips.missing_usable_epub += 1
            return None
        parsed_url = urllib.parse.urlparse(epub_url)
        if parsed_url.scheme not in {"http", "https"}:
            skips.malformed_url += 1
            return None

        authors = []
        for creator in ebook.findall("dcterms:creator/pgterms:agent", NS):
            raw_name = text_at(creator, "pgterms:name")
            if not raw_name:
                continue
            authors.append(
                {
                    "name": display_person_name(raw_name),
                    "birth_year": int_or_none(text_at(creator, "pgterms:birthdate")),
                    "death_year": int_or_none(text_at(creator, "pgterms:deathdate")),
                }
            )
        if not authors:
            skips.no_author += 1

        cover_url = find_format(
            files,
            [".cover.medium.jpg", ".cover.small.jpg"],
            "image/jpeg",
        )
        downloads = text_at(ebook, "pgterms:downloads")
        return CatalogBook(
            id=book_id,
            title=title,
            authors=authors,
            languages=[language.lower() for language in languages],
            subjects=values_at(ebook, "dcterms:subject/rdf:Description/rdf:value"),
            bookshelves=values_at(
                ebook,
                "pgterms:bookshelf/rdf:Description/rdf:value",
            ),
            epub_url=epub_url,
            cover_url=cover_url,
            download_count=int(downloads) if downloads.isdigit() else 0,
        )
    except ET.ParseError:
        skips.malformed_record += 1
        return None


def iter_rdf_files(path: Path) -> Iterable[tuple[str, bytes]]:
    if path.is_dir():
        for file_path in sorted(path.rglob("*.rdf")):
            yield str(file_path), file_path.read_bytes()
        return
    if tarfile.is_tarfile(path):
        with tarfile.open(path) as archive:
            for member in archive:
                if not member.isfile() or not member.name.endswith(".rdf"):
                    continue
                extracted = archive.extractfile(member)
                if extracted is not None:
                    yield member.name, extracted.read()
        return
    yield str(path), path.read_bytes()


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE catalog_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        CREATE TABLE books (
          id INTEGER PRIMARY KEY,
          title TEXT NOT NULL,
          summary TEXT,
          cover_url TEXT,
          epub_url TEXT NOT NULL,
          download_count INTEGER NOT NULL DEFAULT 0,
          media_type TEXT,
          title_search TEXT NOT NULL,
          title_author_search TEXT NOT NULL,
          topics_search TEXT NOT NULL
        );
        CREATE TABLE book_authors (
          book_id INTEGER NOT NULL,
          ordinal INTEGER NOT NULL,
          name TEXT NOT NULL,
          normalized_name TEXT NOT NULL,
          birth_year INTEGER,
          death_year INTEGER,
          PRIMARY KEY (book_id, ordinal)
        );
        CREATE TABLE book_languages (
          book_id INTEGER NOT NULL,
          language TEXT NOT NULL,
          PRIMARY KEY (book_id, language)
        );
        CREATE TABLE book_topics (
          book_id INTEGER NOT NULL,
          kind TEXT NOT NULL,
          ordinal INTEGER NOT NULL,
          value TEXT NOT NULL,
          normalized_value TEXT NOT NULL,
          PRIMARY KEY (book_id, kind, ordinal)
        );
        CREATE INDEX idx_books_downloads ON books(download_count DESC, id ASC);
        CREATE INDEX idx_book_authors_norm ON book_authors(normalized_name, book_id);
        CREATE INDEX idx_book_languages ON book_languages(language, book_id);
        """
    )


def insert_book(conn: sqlite3.Connection, book: CatalogBook) -> None:
    author_names = " ".join(author["name"] for author in book.authors)
    topics = book.subjects + book.bookshelves
    conn.execute(
        """
        INSERT INTO books (
          id, title, summary, cover_url, epub_url, download_count, media_type,
          title_search, title_author_search, topics_search
        ) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            book.id,
            book.title,
            book.cover_url,
            book.epub_url,
            book.download_count,
            book.media_type,
            normalize_text(book.title),
            normalize_text(f"{book.title} {author_names}"),
            normalize_text(" ".join(topics)),
        ),
    )
    for index, author in enumerate(book.authors):
        conn.execute(
            """
            INSERT INTO book_authors (
              book_id, ordinal, name, normalized_name, birth_year, death_year
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                book.id,
                index,
                author["name"],
                normalize_text(author["name"]),
                author["birth_year"],
                author["death_year"],
            ),
        )
    for language in book.languages:
        conn.execute(
            "INSERT OR IGNORE INTO book_languages (book_id, language) VALUES (?, ?)",
            (book.id, language),
        )
    for kind, values in (("subject", book.subjects), ("bookshelf", book.bookshelves)):
        for index, value in enumerate(values):
            conn.execute(
                """
                INSERT INTO book_topics (
                  book_id, kind, ordinal, value, normalized_value
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (book.id, kind, index, value, normalize_text(value)),
            )


def download_source(url: str, output: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        with output.open("wb") as handle:
            shutil.copyfileobj(response, handle)


def build_catalog(args: argparse.Namespace) -> dict:
    started = time.monotonic()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    source_path = Path(args.input) if args.input else None
    temp_dir = None
    if source_path is None:
        temp_dir = tempfile.TemporaryDirectory()
        source_path = Path(temp_dir.name) / "rdf-files.tar.bz2"
        download_source(args.source_url, source_path)
    source_size = source_path.stat().st_size if source_path.exists() else 0

    sqlite_path = output_dir / f"gutenberg_catalog_{args.catalog_version}.sqlite"
    compressed_path = sqlite_path.with_suffix(".sqlite.gz")
    manifest_path = output_dir / "manifest.json"
    if sqlite_path.exists():
        sqlite_path.unlink()
    if compressed_path.exists():
        compressed_path.unlink()

    skips = SkipCounts()
    seen_ids: set[int] = set()
    conn = sqlite3.connect(sqlite_path)
    try:
        create_schema(conn)
        conn.execute(
            "INSERT INTO catalog_meta (key, value) VALUES (?, ?)",
            ("schema_version", str(SCHEMA_VERSION)),
        )
        conn.execute(
            "INSERT INTO catalog_meta (key, value) VALUES (?, ?)",
            ("catalog_version", args.catalog_version),
        )
        for name, raw in iter_rdf_files(source_path):
            book = parse_book(raw, skips)
            if book is None:
                continue
            if book.id in seen_ids:
                skips.duplicate_gutenberg_id += 1
                continue
            seen_ids.add(book.id)
            try:
                insert_book(conn, book)
                skips.included += 1
            except sqlite3.IntegrityError:
                skips.duplicate_gutenberg_id += 1
                skips.details.append(f"duplicate insert: {name}")
        conn.execute(
            "INSERT INTO catalog_meta (key, value) VALUES (?, ?)",
            ("record_count", str(skips.included)),
        )
        conn.commit()
        conn.execute("VACUUM")
    finally:
        conn.close()
        if temp_dir is not None:
            temp_dir.cleanup()

    raw_size = sqlite_path.stat().st_size
    with sqlite_path.open("rb") as source, compressed_path.open("wb") as raw_dest:
        with gzip.GzipFile(fileobj=raw_dest, mode="wb", mtime=0) as dest:
            shutil.copyfileobj(source, dest)
    compressed_bytes = compressed_path.read_bytes()
    digest = hashlib.sha256(compressed_bytes).hexdigest()
    download_url = f"{args.artifact_base_url.rstrip('/')}/{compressed_path.name}"
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "catalog_version": args.catalog_version,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "record_count": skips.included,
        "compressed_size_bytes": len(compressed_bytes),
        "installed_size_bytes": raw_size,
        "sha256": digest,
        "download_url": download_url,
        "minimum_app_catalog_version": 1,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    report = {
        "source_metadata_size_bytes": source_size,
        "record_count": skips.included,
        "raw_sqlite_size_bytes": raw_size,
        "compressed_distribution_size_bytes": len(compressed_bytes),
        "installed_size_bytes": raw_size,
        "generation_seconds": round(time.monotonic() - started, 3),
        "skip_counts": skips.as_dict(),
        "sqlite_path": str(sqlite_path),
        "compressed_path": str(compressed_path),
        "manifest_path": str(manifest_path),
    }
    (output_dir / "generation_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="RDF file, RDF directory, or RDF tar archive")
    parser.add_argument("--source-url", default=DEFAULT_SOURCE_URL)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--catalog-version", required=True)
    parser.add_argument(
        "--artifact-base-url",
        default="https://example.com/nalori-gutenberg-catalog",
    )
    return parser.parse_args()


if __name__ == "__main__":
    build_catalog(parse_args())
