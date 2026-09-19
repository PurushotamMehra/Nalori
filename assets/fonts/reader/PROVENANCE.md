# Nalori production reader fonts

These files are production reader assets. They are separate from the
`assets/fonts/reader_contract/` test-only Lexend fixtures.

## Source and integrity

- Descriptor authority: `google_fonts` 8.0.2 source installed with this
  repository's locked dependency graph.
- Binary authority: the descriptor-provided
  `https://fonts.gstatic.com/s/a/<sha256>.ttf` URLs.
- Licence authority: each family's `OFL.txt` from the official
  `google/fonts` repository at revision branch `main`, under `ofl/<family>/`.
- Acquisition date: 2026-09-09.
- Format: static TTF only; no WOFF/WOFF2 and no platform-installed fonts.

`manifest.json` records every binary's family, upstream URL, local path,
effective weight/style, byte length, SHA-256, licence path, and every nominal
request-to-delivery mapping preserved from the installed descriptors. The
production gate verifies those fields against root-bundle bytes before the
assets can authorize font evidence.

## Families and delivered files

| Family | Static files | Effective delivery |
|---|---:|---|
| Inter | 12 | normal 300–900; italic 300–700 |
| Roboto Mono | 10 | normal 300–700; italic 300–700; 800/900 normal map to 700 |
| Merriweather | 12 | normal 300–900; italic 300–700 |
| Lora | 8 | normal/italic 400–700; 300 maps to 400 and 800/900 normal map to 700 |
| EB Garamond | 9 | normal 400–800; italic 400–700; 300 maps to 400 and 900 normal maps to 800 |
| Literata | 12 | normal 300–900; italic 300–700 |
| Atkinson Hyperlegible | 4 | normal/italic 400 and 700; 300/500 map to 400 and 600/800/900 map to 700 where requested |
| Lexend | 7 | normal 300–900; italic requests preserve the provider's same-weight normal-file delivery and retain italic styling |

Roboto Mono owns the explicit preformatted role. The selected bundled reader
family at 400 normal owns the heading-divider role. P05-003 connects those
roles to shared measurement/rendering.

## Size

- Font binaries: 74 files, 19,348,768 raw bytes.
- Gzip estimate over the font binaries: 9,893,824 bytes. Actual store-package
  contribution is toolchain- and platform-dependent.

All eight families are licensed under the SIL Open Font License 1.1. The
family-specific notices are retained under `licenses/` and must ship with the
fonts.
