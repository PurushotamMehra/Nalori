import json
import sqlite3
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "tool" / "generate_gutenberg_catalog.py"


class GutenbergCatalogGeneratorTest(unittest.TestCase):
    def test_generates_manifest_sqlite_and_report_from_rdf_fixture(self):
        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            rdf_dir = temp_path / "rdf"
            out_dir = temp_path / "out"
            rdf_dir.mkdir()
            (rdf_dir / "100.rdf").write_text(
                _rdf(
                    100,
                    "The Sea &amp; Stars",
                    authors="""
                      <dcterms:creator>
                        <pgterms:agent>
                          <pgterms:name>Verne, Jules</pgterms:name>
                          <pgterms:birthdate>1828</pgterms:birthdate>
                          <pgterms:deathdate>1905</pgterms:deathdate>
                        </pgterms:agent>
                      </dcterms:creator>
                    """,
                    formats="""
                      <dcterms:hasFormat>
                        <pgterms:file rdf:about="https://www.gutenberg.org/ebooks/100.epub.noimages">
                          <dcterms:format><rdf:Description><rdf:value>application/epub+zip</rdf:value></rdf:Description></dcterms:format>
                        </pgterms:file>
                      </dcterms:hasFormat>
                      <dcterms:hasFormat>
                        <pgterms:file rdf:about="https://www.gutenberg.org/ebooks/100.epub.images">
                          <dcterms:format><rdf:Description><rdf:value>application/epub+zip</rdf:value></rdf:Description></dcterms:format>
                        </pgterms:file>
                      </dcterms:hasFormat>
                      <dcterms:hasFormat>
                        <pgterms:file rdf:about="https://www.gutenberg.org/ebooks/100.epub3.images">
                          <dcterms:format><rdf:Description><rdf:value>application/epub+zip</rdf:value></rdf:Description></dcterms:format>
                        </pgterms:file>
                      </dcterms:hasFormat>
                      <dcterms:hasFormat>
                        <pgterms:file rdf:about="https://www.gutenberg.org/cache/epub/100/pg100.cover.medium.jpg">
                          <dcterms:format><rdf:Description><rdf:value>image/jpeg</rdf:value></rdf:Description></dcterms:format>
                        </pgterms:file>
                      </dcterms:hasFormat>
                    """,
                ),
                encoding="utf-8",
            )
            (rdf_dir / "101.rdf").write_text(
                _rdf(
                    101,
                    "No EPUB",
                    formats="""
                      <dcterms:hasFormat>
                        <pgterms:file rdf:about="https://www.gutenberg.org/ebooks/101.txt">
                          <dcterms:format><rdf:Description><rdf:value>text/plain</rdf:value></rdf:Description></dcterms:format>
                        </pgterms:file>
                      </dcterms:hasFormat>
                    """,
                ),
                encoding="utf-8",
            )
            (rdf_dir / "102.rdf").write_text(
                _rdf(
                    102,
                    "Copyrighted",
                    rights="Copyrighted. Not public domain in the United States.",
                ),
                encoding="utf-8",
            )

            subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "--input",
                    str(rdf_dir),
                    "--output-dir",
                    str(out_dir),
                    "--catalog-version",
                    "fixture-2026-06-14",
                    "--artifact-base-url",
                    "https://static.example/catalog",
                ],
                check=True,
                cwd=ROOT,
            )

            manifest = json.loads((out_dir / "manifest.json").read_text())
            report = json.loads((out_dir / "generation_report.json").read_text())
            sqlite_path = out_dir / "gutenberg_catalog_fixture-2026-06-14.sqlite"
            compressed_path = sqlite_path.with_suffix(".sqlite.gz")

            self.assertEqual(manifest["schema_version"], 1)
            self.assertEqual(manifest["record_count"], 1)
            self.assertEqual(manifest["download_url"], f"https://static.example/catalog/{compressed_path.name}")
            self.assertEqual(manifest["compressed_size_bytes"], compressed_path.stat().st_size)
            self.assertEqual(report["skip_counts"]["missing_usable_epub"], 1)
            self.assertEqual(report["skip_counts"]["non_public_domain"], 1)

            conn = sqlite3.connect(sqlite_path)
            try:
                row = conn.execute(
                    "SELECT title, epub_url, cover_url, download_count, title_author_search "
                    "FROM books WHERE id = 100"
                ).fetchone()
                self.assertEqual(row[0], "The Sea & Stars")
                self.assertTrue(row[1].endswith(".epub3.images"))
                self.assertTrue(row[2].endswith(".cover.medium.jpg"))
                self.assertEqual(row[3], 42)
                self.assertIn("sea and stars jules verne", row[4])
                author = conn.execute(
                    "SELECT name, birth_year, death_year FROM book_authors WHERE book_id = 100"
                ).fetchone()
                self.assertEqual(author, ("Jules Verne", 1828, 1905))
                subject = conn.execute(
                    "SELECT value FROM book_topics WHERE kind = 'subject'"
                ).fetchone()
                self.assertEqual(subject[0], "Sea stories")
            finally:
                conn.close()

    def test_compressed_catalogue_is_reproducible(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_path = Path(first)
            second_path = Path(second)
            rdf_dir = first_path / "rdf"
            rdf_dir.mkdir()
            (rdf_dir / "100.rdf").write_text(_rdf(100, "Repeatable"), encoding="utf-8")

            for out in (first_path / "out", second_path / "out"):
                subprocess.run(
                    [
                        sys.executable,
                        str(GENERATOR),
                        "--input",
                        str(rdf_dir),
                        "--output-dir",
                        str(out),
                        "--catalog-version",
                        "fixture",
                    ],
                    check=True,
                    cwd=ROOT,
                    stdout=subprocess.DEVNULL,
                )

            first_manifest = json.loads((first_path / "out" / "manifest.json").read_text())
            second_manifest = json.loads((second_path / "out" / "manifest.json").read_text())
            self.assertEqual(first_manifest["sha256"], second_manifest["sha256"])


def _rdf(
    book_id,
    title,
    *,
    authors="",
    formats=None,
    rights="Public domain in the USA.",
):
    if formats is None:
        formats = f"""
          <dcterms:hasFormat>
            <pgterms:file rdf:about="https://www.gutenberg.org/ebooks/{book_id}.epub.images">
              <dcterms:format><rdf:Description><rdf:value>application/epub+zip</rdf:value></rdf:Description></dcterms:format>
            </pgterms:file>
          </dcterms:hasFormat>
        """
    return textwrap.dedent(
        f"""\
        <?xml version="1.0" encoding="utf-8"?>
        <rdf:RDF
          xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
          xmlns:dcterms="http://purl.org/dc/terms/"
          xmlns:pgterms="http://www.gutenberg.org/2009/pgterms/">
          <pgterms:ebook rdf:about="ebooks/{book_id}">
            <dcterms:title>{title}</dcterms:title>
            <dcterms:rights>{rights}</dcterms:rights>
            <dcterms:language><rdf:Description><rdf:value>en</rdf:value></rdf:Description></dcterms:language>
            <dcterms:subject><rdf:Description><rdf:value>Sea stories</rdf:value></rdf:Description></dcterms:subject>
            <pgterms:bookshelf><rdf:Description><rdf:value>Adventure</rdf:value></rdf:Description></pgterms:bookshelf>
            <pgterms:downloads>42</pgterms:downloads>
            {authors}
            {formats}
          </pgterms:ebook>
        </rdf:RDF>
        """
    )


if __name__ == "__main__":
    unittest.main()
