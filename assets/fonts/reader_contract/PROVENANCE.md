# Reader-contract Lexend font provenance

These four normal static TTF files are the smallest locally bundled set for
the host-only `NaloriReaderContractLexend` family. That alias is registered by
`test/reader_contract/support/reader_contract_layout_environment.dart` through
`FontLoader`; it is not declared as a production Flutter font family and does
not change Nalori's runtime Google Fonts selection.

Production evidence is `ReadingSettings.fontFamily`'s Lexend default and
`ReadingSettings.getTextStyle` in `lib/models/reading_settings.dart`, together
with `ReadingCard` use of w600 list/structural text, w700 inline bold text and
w900 headings in `lib/widgets/reading_card.dart`. The installed
`google_fonts` 8.0.2 Lexend descriptor table publishes these exact static
Google Fonts delivery objects for the corresponding normal weights.

Upstream project and license:

- Project source: <https://github.com/google/fonts/tree/main/ofl/lexend>
- Binary delivery source: `https://fonts.gstatic.com/s/a/<sha256>.ttf`
- License: SIL Open Font License 1.1, reproduced verbatim in `OFL.txt` from
  <https://github.com/google/fonts/blob/main/ofl/lexend/OFL.txt>.
- `OFL.txt` SHA-256: `5da8505887d0fa7fe963445fd58852707fda34adfeb65af25c99d152bab285bd`.
- Retrieval: 2026-08-29. The SHA-256 values below are both the immutable
  Google Fonts object identifiers and checksums verified for the committed
  bytes. They identify assets only; they are not resolved glyph-metric or P05
  layout identities.

| Family | Weight | Original Google Fonts API filename | Official binary source | Repository asset | SHA-256 | Why required |
| --- | ---: | --- | --- | --- | --- | --- |
| Lexend | 400 | `Lexend-Regular.ttf` | `https://fonts.gstatic.com/s/a/e92ff07c5686aee1cf71ba2aaf8b3afcab70db722680d082dd2fc496e65fe383.ttf` | `assets/fonts/reader_contract/Lexend-Regular.ttf` | `e92ff07c5686aee1cf71ba2aaf8b3afcab70db722680d082dd2fc496e65fe383` | Default reader prose (`ReaderFontWeight.regular`). |
| Lexend | 600 | `Lexend-SemiBold.ttf` | `https://fonts.gstatic.com/s/a/bcac18cdf67555e75f7d747fa6055c11fc58a61ea8cc68af0ade707717018908.ttf` | `assets/fonts/reader_contract/Lexend-SemiBold.ttf` | `bcac18cdf67555e75f7d747fa6055c11fc58a61ea8cc68af0ade707717018908` | List markers and relevant structural text. |
| Lexend | 700 | `Lexend-Bold.ttf` | `https://fonts.gstatic.com/s/a/fe323c8e142d5f92b974a48973bac235966aa3a76cf0e6d76ea89d03f7a2aa3d.ttf` | `assets/fonts/reader_contract/Lexend-Bold.ttf` | `fe323c8e142d5f92b974a48973bac235966aa3a76cf0e6d76ea89d03f7a2aa3d` | Inline bold prose. |
| Lexend | 900 | `Lexend-Black.ttf` | `https://fonts.gstatic.com/s/a/6c3c72060a805613a735fdb9523152f880e1cca7577bacfe751cfa7d5ece2053.ttf` | `assets/fonts/reader_contract/Lexend-Black.ttf` | `6c3c72060a805613a735fdb9523152f880e1cca7577bacfe751cfa7d5ece2053` | Reader headings. |

The current production Lexend descriptor table has normal static variants only
for this controlled set. This support does not claim italic-form parity,
runtime fallback resolution, glyph metrics, physical-card boundaries or final
measure/render equivalence. Those remain P05 work.
