# Nalori immutable reader layout contract design

Design task: `TASK-P05-002`  
Date: 2026-09-09  
Status: approved implementation contract; documentation shapes only  
Proposed semantic revision: `reader_layout_contract_v1`  
Requirements: `REQ-002`, `REQ-014`–`REQ-017`, `REQ-035`, `REQ-042`, `REQ-051`

## 1. Scope and authority

This document defines the future in-memory contract shared by canonical
pagination measurement and `ReadingCard` rendering. It is the implementation
authority for `TASK-P05-003` and the font-gate authority for `TASK-P05-004`.
It does not add Dart types, change runtime behavior, change a persistent format
or version, or revise the frozen P03/P04 source-ownership oracle.

Authority order:

> approved reader policy → this contract → shared pure resolution → paginator and renderer → focused evidence

The verified current-state inventory remains
`nalori-reader-layout-contract-inventory.md`: 91 primary fields, 116 total rows,
nine confirmed mismatches (three BLOCKER and six HIGH), and ten unresolved
inputs. This document chooses future policy where P05-002 owns the choice. It
does not turn a static observation into a runtime fact.

The contract has two immutable layers:

1. `ReaderLayoutContract`, built once for one captured environment and one
   source/layout generation. It owns environment, effective settings policy,
   geometry, typography, structural policy, font evidence, and identities.
2. `ResolvedReaderBlockLayout`, built from that contract and stable canonical
   block/source evidence. It owns the exact direction, alignment, span styles,
   spacing, width, and structural box used by both measurement and rendering.

Both layers are deeply immutable: scalar values, immutable value objects, and
unmodifiable, defensively copied collections only. They contain no
`BuildContext`, widget, controller, callback, mutable `ReadingSettings`, live
`MediaQueryData`, `TextPainter`, `ImageStream`, font future, cache service, or
source/display list view. Equality is semantic canonical-byte equality, never
object identity or `hashCode`.

Only a validated `ready` result has pagination/publication authority. A
pending or rejected result may be diagnosed or retried but cannot paginate,
publish cards, settle navigation, write checkpoints, or write display records
claimed compatible.

The normative field tables below define **211 fields** (`F001`–`F211`). A
field can be a closed immutable sub-shape; its stated members and ordering are
normative. Colors, recognizers, shadows, selection paint, and other explicitly
excluded values are not hidden contract fields.

## 2. Approved policy decisions

These are approved contract decisions, not claims about the current widget
tree:

- The actual bounded logical `ReadingCardDeck`/card constraint is the outer
  geometry authority. `MediaQuery.size` is accepted only after exact finite
  width/height equivalence with that constraint.
- Stable `MediaQuery.viewPadding` is captured once on all four sides. Raw
  bottom `viewPadding` is included in measurement and rendering; it is never
  canonicalized to zero. A stable system-safe-area change is a genuine layout
  change.
- `viewInsets`, keyboard state, controls, toolbars, overlays, gestures, deck
  transforms, and animation do not alter the canonical body rectangle.
- Card border stroke is a paint-only decoration outside the body-box
  arithmetic. Its layout inset is exactly zero. P05-003 must construct the
  render tree so this remains true. U-01 still probes current/future runtime
  conformance; this policy does not guess what today’s `AnimatedContainer`
  does.
- Card margin is outside the card face. Content padding is inside it. Stable
  safe padding, boundary padding, and header/footer reserves are explicit
  additive components of content padding.
- The measurement safety reserve is named policy and participates in
  `LayoutMetricsIdentity`, although it is not a painted spacer.
- The reader default direction is captured once. A stable source/block
  direction overrides it when source structure supports that value. LTR is
  used only when neither exists. Each block direction is finalized before
  measurement and passed unchanged to its rendered text.
- Locale, direction, alignment, and source-language metadata are distinct.
  Locale affects shaping/font resolution; direction affects bidi layout;
  alignment affects line placement/justification; source language is source
  metadata and affects layout only if an explicit resolver maps it to locale
  or direction.
- Text scaling identity is the exact output at every logical size used by the
  closed style catalog. `scale(1.0)`, runtime type, or rounded decimal strings
  are insufficient.
- A required font variant in `unresolved` or `loading` state cannot authorize
  pagination. Terminal loaded and terminal stable-fallback states require
  nonempty observable metric evidence. No unobservable resolved face name is
  invented.
- Measurement and rendering consume the same resolved span tree and structural
  box specification. Duplicated code containing similar constants is not
  contract compliance.
- An image uses terminal deterministic intrinsic/layout evidence. The v1
  contract has no guessed placeholder geometry. Pending decode returns
  `pendingImageMetrics`; later decode cannot resize a finalized body.
- Speed Reader state is excluded from layout identity. Its active rendering
  must fit the already-resolved canonical paragraph/span boxes and may not
  replace them with a differently sized tree.
- Raw settings that resolve to the same effective values, such as side margins
  that clamp to the same padding, share `LayoutMetricsIdentity`.
- `reader_layout_contract_v1` is an in-memory semantic proposal only. No
  current parser, paginator, display-cache, segmented-cache, checkpoint, or
  stable-location version changes in this task.

## 3. Contract/type hierarchy

```text
ReaderLayoutBuildOutcome
├── ready(ReaderLayoutContract)
├── pendingFontEvidence(...)
├── pendingImageMetrics(...)
└── rejected(...typed reason...)

ReaderLayoutContract
├── ReaderLayoutEnvironment
│   └── ResolvedTextScaleProfile
├── ReaderResolvedSettingsPolicy
├── ReaderCardGeometry
├── ReaderTypographyContract
│   ├── ReaderResolvedTextStyleSpec[role]
│   │   └── ReaderResolvedStrutSpec
│   └── ReaderFontRequestIdentity[variant]
├── ReaderFontResolutionEvidence
├── ReaderStructuralLayoutContract
└── ReaderLayoutIdentityBundle
    ├── LayoutMetricsIdentity
    ├── SourceCompatibilityIdentity
    ├── PaginationAlgorithmIdentity
    ├── RendererLayoutIdentity
    └── ReaderCompatibilityIdentity

ReaderLayoutContract + canonical source block
└── ResolvedReaderBlockLayout
    ├── final locale/direction/alignment/width
    ├── ordered ResolvedReaderSpanRun[]
    ├── paragraph/list/publisher spacing
    └── one ResolvedReaderStructuralBox
        ├── text/heading
        ├── list
        ├── table
        ├── preformatted
        └── image
```

### Root contract fields

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F001 `contractRevision` | fixed ASCII `reader_layout_contract_v1` | This design | Select resolver semantics | Select renderer adapter semantics | Layout + reader composite | Exact supported value | P05-003 |
| F002 `environment` | `ReaderLayoutEnvironment` | One capture | Supplies closed ambient inputs | Replaces ambient reads | Layout metrics | Validated snapshot | P05-003 |
| F003 `settingsPolicy` | `ReaderResolvedSettingsPolicy` | Pure settings resolver | Budget/spacing policy | Geometry/spacing policy | Layout metrics | Effective values only | P05-003 |
| F004 `geometry` | `ReaderCardGeometry` | Geometry resolver | Width and height authority | Exact card/body boxes | Layout metrics | Derived invariants hold | P05-003 |
| F005 `typography` | `ReaderTypographyContract` | Typography resolver | Exact styles/struts | Exact styles/struts | Layout metrics | Closed catalog | P05-003 |
| F006 `fontEvidence` | `ReaderFontResolutionEvidence` | P05-004 gate | Authorizes stable metrics | Locks same evidence | Layout metrics | Nonempty terminal evidence | P05-004 |
| F007 `structure` | `ReaderStructuralLayoutContract` | This design/shared resolver | Structural boxes | Same structural boxes | Renderer layout | Supported revision | P05-003 |
| F008 `identities` | `ReaderLayoutIdentityBundle` | Canonical encoder | Request compatibility | Card compatibility | All identity layers | Recomputed exactly | P05-003/P05-006 |

## 4. Environment capture lifecycle

Capture begins only after `ReadingCardDeck` has finite bounded constraints.
The capture owner samples stable `viewPadding`, locale, default direction, and
the text scaler in that same frame/generation. It records `MediaQuery.size`
only as equivalence evidence. It then resolves effective settings, enumerates
the closed style catalog and all logical font sizes, constructs the exact scale
profile, requests font evidence, and resolves any image metrics needed by the
bounded source operation.

No paginator or renderer receives authority before the capture, font gate,
image gate, geometry derivation, and canonical fingerprints all validate. Once
ready, the object is passed explicitly to the canonical pagination session and
each `ReadingCard`; neither path may consult ambient `MediaQuery`,
`Directionality`, `Localizations`, platform font state, or image intrinsic
state for layout.

A capture becomes stale before publication when the deck constraint, any
stable `viewPadding` side, canonical locale, reader direction, any used-size
scale response, font evidence, source snapshot, required image evidence, or
resolved policy changes. A generation/cancellation token may detect this, but
the token is not layout identity.

### Environment fields

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F009 `captureRevision` | fixed capture-schema enum | Capture builder | Decode capture | Decode capture | Layout metrics | Supported | P05-003 |
| F010 `outerDeckWidth` | finite positive binary64 logical px | Deck `LayoutBuilder` constraint | Geometry width | Card width | Layout metrics | Finite, > 0 | P05-003 |
| F011 `outerDeckHeight` | finite positive binary64 logical px | Deck constraint | Geometry height | Card height | Layout metrics | Finite, > 0 | P05-003 |
| F012 `mediaQueryWidthEvidence` | optional finite binary64 | Captured `MediaQuery.size` | None after validation | None | Excluded/diagnostic | Present only with F014 check | P05-003 |
| F013 `mediaQueryHeightEvidence` | optional finite binary64 | Captured `MediaQuery.size` | None after validation | None | Excluded/diagnostic | Present only with F014 check | P05-003 |
| F014 `deckMediaQueryEquivalence` | `notPresent/exactlyEquivalent/incompatible` | Capture validator | Admission gate | Admission gate | Excluded; resolved deck size is hashed | MediaQuery may supply size only if exact | P05-003/P05-007 |
| F015 `viewPaddingTop` | finite nonnegative binary64 | Captured stable `viewPadding` | Content top | Content top | Layout metrics | Finite, >= 0 | P05-003 |
| F016 `viewPaddingBottom` | finite nonnegative binary64 | Captured raw `viewPadding` | Content bottom | Content bottom | Layout metrics | Finite, >= 0; never forced to zero | P05-003 |
| F017 `viewPaddingLeft` | finite nonnegative binary64 | Captured stable `viewPadding` | Content left | Content left | Layout metrics | Finite, >= 0 | P05-003 |
| F018 `viewPaddingRight` | finite nonnegative binary64 | Captured stable `viewPadding` | Content right | Content right | Layout metrics | Finite, >= 0 | P05-003 |
| F019 `readerLocale` | `ReaderCanonicalLocale` | Captured reader localization | Shaping/font locale | Same locale | Layout metrics | Canonical form below | P05-003 |
| F020 `defaultTextDirection` | optional `ltr/rtl` | Captured reader `Directionality` | Block fallback | Block fallback | Layout metrics when used | Closed enum | P05-003 |
| F021 `textScaleProfile` | `ResolvedTextScaleProfile` | Captured scaler + closed catalog | Exact scaled sizes | Exact scaled sizes | Layout metrics | Complete used-size domain | P05-003/P05-007 |
| F022 `captureFreshnessEvidence` | opaque generation-local snapshot tuple | Capture owner | Stale guard only | Stale guard only | Excluded | Must still match before authority | P05-003 |

`devicePixelRatio`, accessibility bold, high contrast, brightness, keyboard
`viewInsets`, control visibility, and platform diagnostics may be logged by a
separate diagnostic record. They are not fields F001–F211 and are not layout
identity unless a P05-007 probe proves one changes logical text/box metrics; a
proved effect requires a new documented contract revision, not an ambient
read. U-07 owns those probes.

Canonical locale is a structured tuple `(language, script?, region?,
variants[])`, not `Locale.toString()`. Language is lowercase, ISO script is
title case, region is uppercase, variants are lowercase and sorted only when
their order is semantically unordered. Empty/unknown language becomes `und`.
The encoded display form is BCP-47-like (`language[-Script][-REGION][-variant]`)
from the tuple. Locale does not imply direction. Optional source-language
metadata retains its separately canonicalized tag and provenance.

## 5. Card geometry contract

For outer deck size `D`, card margin `M`, and content padding `P`:

```text
cardWidth  = D.width  - M.left - M.right
cardHeight = D.height - M.top  - M.bottom
bodyWidth  = cardWidth  - P.left - P.right - borderLayoutInset.horizontal
bodyHeight = cardHeight - P.top  - P.bottom - borderLayoutInset.vertical
```

For v1, `borderLayoutInset` is zero. No `max(1)` coercion can turn impossible
geometry into authority. Every dimension must be finite and the resulting
card/body width and height must be strictly positive. The minimum capacity
admission rule below must also pass.

Effective policy preserves current intended values while making each one
explicit. With card depth off, margin and header/footer reserves are zero.
With depth on, ordinary density uses margin `(18,28,18,42)` and full-page uses
`(14,22,14,34)`. Horizontal reader padding is
`clamp(rawSideMargin,12,56)`. Boundary top/bottom are `14/16`, or `4/6` for
full-page. Content padding is:

```text
left   = viewPadding.left  + effectiveSidePadding
right  = viewPadding.right + effectiveSidePadding
top    = viewPadding.top   + boundaryTop    + headerReserve
bottom = viewPadding.bottom+ boundaryBottom + footerReserve
```

Density policies are effective tuples, not raw setting identity:

| Effective density | Page ratio | Tiny words | Tiny height ratio |
| --- | ---: | ---: | ---: |
| low | 0.25 | 10 | 0.35 |
| medium | 0.50 | 12 | 0.25 |
| high | 0.75 | 14 | 0.18 |
| full page | 1.00 | 16 | 0.12 |

Let `L` be the resolved scaled body line-box height. The fingerprinted
`measurementSafetyReserve` policy is
`clamp((0.65 × L) + depthBias, 14, 36)`, where `depthBias` is 4 with depth and
0 otherwise. It is measurement headroom, not a painted spacer. V1 requires
`bodyHeight - reserve >= 2.4 × L`; otherwise the environment is incompatible
and cannot paginate. Then:

```text
physicalPaginationCapacity = bodyHeight - reserve
ordinaryPaginationHeightBudget = physicalPaginationCapacity × pageRatio
publisherPaginationHeightBudget = physicalPaginationCapacity
minUsefulHeight = min(ordinaryBudget × tinyHeightRatio, 2.4 × L)
```

Publisher horizontal padding is per block: each source indent is clamped to
`[0,72]`. Dialogue inset is exactly zero in v1. A list body additionally uses
its resolved leading indent, marker width, and marker gap. These insets reduce
the block width; none reduces the session body height.

### Geometry and resolved-settings fields

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F023 `effectiveSidePadding` | finite binary64 | Clamp resolver | Base horizontal inset | Same padding | Layout metrics | 12..56 | P05-003 |
| F024 `cardDepthEnabled` | bool effective policy | Settings resolver | Margin/reserve/bias selection | Card-face composition | Layout metrics via resolved consequences and policy | Closed bool | P05-003 |
| F025 `densityPolicyName` | normalized effective enum | Settings resolver | Select tuple | Select geometry | Layout metrics | Closed mapping above | P05-003 |
| F026 `densityPageRatio` | finite binary64 | Density table | Ordinary budget | None directly | Layout metrics | (0,1] | P05-003 |
| F027 `densityTinyWordCount` | nonnegative integer | Density table | Tiny classification | None | Layout metrics | >= 0 | P05-003 |
| F028 `densityTinyHeightRatio` | finite binary64 | Density table | Tiny classification | None | Layout metrics | [0,1] | P05-003 |
| F029 `paragraphSpacingMultiplier` | finite binary64 | Effective setting | Gaps | Same gaps | Layout metrics | >= 0 | P05-003 |
| F030 `cardMarginTop` | finite nonnegative binary64 | Effective depth/density tuple | Card height | Outer margin | Layout metrics | Finite, >= 0 | P05-003 |
| F031 `cardMarginBottom` | finite nonnegative binary64 | Same | Card height | Outer margin | Layout metrics | Finite, >= 0 | P05-003 |
| F032 `cardMarginLeft` | finite nonnegative binary64 | Same | Card width | Outer margin | Layout metrics | Finite, >= 0 | P05-003 |
| F033 `cardMarginRight` | finite nonnegative binary64 | Same | Card width | Outer margin | Layout metrics | Finite, >= 0 | P05-003 |
| F034 `borderStrokeWidth` | finite nonnegative binary64; 1.8 with depth, 0 otherwise | Renderer policy | None | Painted border | Renderer layout (policy completeness) | Finite, >= 0 | P05-003/P05-007 |
| F035 `borderBodyPolicy` | `paint_only_no_body_inset` | This design | Confirms zero subtraction | Enforced composition | Renderer layout | Exact v1 enum | P05-003 |
| F036 `borderLayoutInsetTop` | finite zero | Derived policy | Body height | Body constraint | Layout metrics | Must be +0 | P05-003 |
| F037 `borderLayoutInsetBottom` | finite zero | Derived policy | Body height | Body constraint | Layout metrics | Must be +0 | P05-003 |
| F038 `borderLayoutInsetLeft` | finite zero | Derived policy | Body width | Body constraint | Layout metrics | Must be +0 | P05-003 |
| F039 `borderLayoutInsetRight` | finite zero | Derived policy | Body width | Body constraint | Layout metrics | Must be +0 | P05-003 |
| F040 `boundaryTop` | finite binary64 | Effective density policy | Content top | Same inset | Layout metrics | 14 or 4 in v1 | P05-003 |
| F041 `boundaryBottom` | finite binary64 | Effective density policy | Content bottom | Same inset | Layout metrics | 16 or 6 in v1 | P05-003 |
| F042 `headerReserve` | finite binary64 | Effective depth policy | Content top/budget | Fixed header band | Layout metrics | 40 or 0 | P05-003 |
| F043 `footerReserve` | finite binary64 | Effective depth policy | Content bottom/budget | Fixed footer band | Layout metrics | 42 or 0 | P05-003 |
| F044 `contentPaddingTop` | finite binary64 | Sum formula | Body rect | Exact `Padding` | Layout metrics | Exact recomputation | P05-003 |
| F045 `contentPaddingBottom` | finite binary64 | Sum formula incl. raw bottom safe area | Body rect | Exact `Padding` | Layout metrics | Exact recomputation | P05-003 |
| F046 `contentPaddingLeft` | finite binary64 | Sum formula | Body rect | Exact `Padding` | Layout metrics | Exact recomputation | P05-003 |
| F047 `contentPaddingRight` | finite binary64 | Sum formula | Body rect | Exact `Padding` | Layout metrics | Exact recomputation | P05-003 |
| F048 `physicalCardWidth` | finite positive binary64 | Derived | Bounds | Exact face box | Layout metrics | Exact formula, > 0 | P05-003 |
| F049 `physicalCardHeight` | finite positive binary64 | Derived | Bounds | Exact face box | Layout metrics | Exact formula, > 0 | P05-003 |
| F050 `physicalBodyWidth` | finite positive binary64 | Derived | Default max width | Exact body constraint | Layout metrics | Exact formula, > 0 | P05-003 |
| F051 `physicalBodyHeight` | finite positive binary64 | Derived | Capacity | Exact body constraint | Layout metrics | Exact formula, > 0 | P05-003 |
| F052 `minimumCapacityLineCount` | finite binary64 2.4 | This design/current intent | Admission floor | Overflow invariant | Layout metrics | > 0 | P05-003 |
| F053 `safetyReserveLineFactor` | finite binary64 0.65 | Pagination policy | Reserve | None | Layout metrics | > 0 | P05-003 |
| F054 `safetyReserveDepthBias` | finite binary64 0/4 | Depth policy | Reserve | None | Layout metrics | >= 0 | P05-003 |
| F055 `safetyReserveMinimum` | finite binary64 14 | Pagination policy | Reserve clamp | None | Layout metrics | >= 0 | P05-003 |
| F056 `safetyReserveMaximum` | finite binary64 36 | Pagination policy | Reserve clamp | None | Layout metrics | >= min | P05-003 |
| F057 `measurementSafetyReserve` | finite binary64 | Exact formula | Subtracted before budget | Not painted | Layout metrics | Exact recomputation | P05-003 |
| F058 `physicalPaginationCapacity` | finite positive binary64 | Derived | Publisher budget/base | Overflow proof | Layout metrics | >= 2.4L | P05-003 |
| F059 `ordinaryPaginationHeightBudget` | finite positive binary64 | Derived | Normal block/card packing | Canonical card content must fit | Layout metrics | <= capacity | P05-003 |
| F060 `publisherPaginationHeightBudget` | finite positive binary64 | Derived | Publisher block packing | Canonical card content must fit | Layout metrics | = capacity | P05-003 |
| F061 `minUsefulHeight` | finite nonnegative binary64 | Derived | Tiny classification | None | Layout metrics | Exact formula | P05-003 |
| F062 `publisherIndentClampMaximum` | finite binary64 72 | Structural policy | Per-block width | Same padding | Renderer layout | >= 0 | P05-003 |
| F063 `dialogueInset` | finite binary64 0 | Structural policy | Per-block width | Same inset | Renderer layout | Must be +0 in v1 | P05-003 |

U-02 remains open: P05-007 must prove the production deck/card actually
receives the captured outer constraint in full-screen and nontrivial bounded
parents. A failed probe is a P05-003 conformance defect; it does not authorize
falling back silently to `MediaQuery.size`.

## 6. Typography and text-scaling contract

### Exact scale profile

`ResolvedTextScaleProfile` is created after the complete style catalog is
known. Its domain is the sorted, duplicate-free set of every logical font size
used by body, heading, rich variants, footnote markers, list markers, table
headers/cells, preformatted content, heading divider, and any publisher role.
Each entry stores exact canonical binary64 input and output. Consumers use the
recorded scaled output; they do not retain or call the ambient `TextScaler`.

Two scaler implementations share layout identity iff their output binary64
values are equal after positive-zero normalization at every domain size. An
unlisted font size is unsupported and requires rebuilding a new profile before
authority. No runtime type, `scale(1.0)`, tolerance, decimal truncation, or
two-decimal rounding participates.

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F064 `scaleProfileRevision` | fixed enum | This design | Decode mapping | Decode mapping | Layout metrics | Supported | P05-003 |
| F065 `logicalSizes` | sorted immutable binary64 list | Style catalog | Lookup domain | Lookup domain | Layout metrics | Finite, >0, unique, complete | P05-003 |
| F066 `scaledSizes` | same-length immutable binary64 list | Captured scaler results | Exact sizes | Exact sizes | Layout metrics | Finite, >0 | P05-003 |
| F067 `sizeResponsePairs` | ordered `(logicalBits,scaledBits)` tuples | Canonical resolver | Fingerprint input | Fingerprint input | Layout metrics | Bijection with F065/F066 | P05-003 |
| F068 `positiveZeroNormalized` | fixed true | Encoder | Numeric equality | Numeric equality | Layout metrics | Reject false | P05-003 |
| F069 `domainCompletenessDigest` | SHA-256 of role→logical-size uses | Catalog resolver | Prevent missed size | Prevent missed size | Layout metrics | Recompute | P05-003 |
| F070 `scaleResponseDigest` | SHA-256 of F064–F069 canonical bytes | Encoder | Compatibility | Compatibility | Layout metrics | Recompute | P05-003 |

### Resolved strut and style specifications

Every text-bearing render node is constructed from a
`ReaderResolvedTextStyleSpec`. A catalog spec contains captured-default locale,
direction, and alignment. `ResolvedReaderBlockLayout` creates the final spec
for each run with block overrides already applied. `TextPainter`, `Text.rich`,
`SelectableText.rich`, table cells, and marker widgets receive values from that
same spec. Paint-only color/decorations and recognizers are supplied separately.

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F071 `strutFontRequest` | `ReaderFontRequestIdentity` | Typography resolver | Strut font | Same strut | Layout metrics | Variant evidence exists | P05-003/P05-004 |
| F072 `strutLogicalFontSize` | finite binary64 | Style role | Scale/profile lookup | Same | Layout metrics | In scale domain | P05-003 |
| F073 `strutScaledFontSize` | finite binary64 | Scale profile | Line box | Same | Layout metrics | Exact lookup | P05-003 |
| F074 `strutHeightMultiplier` | finite binary64 | Effective typography | Line box | Same | Layout metrics | > 0 | P05-003 |
| F075 `strutLeading` | finite binary64 | Typography policy | Line box | Same | Layout metrics | Finite | P05-003 |
| F076 `strutForceHeight` | bool | Typography policy | Strut behavior | Same | Layout metrics | Explicit | P05-003 |
| F077 `strutLeadingDistribution` | normalized enum | Typography policy | Line metrics | Same | Layout metrics | Closed enum | P05-003 |
| F078 `strutTextHeightBehavior` | explicit apply-first/apply-last flags | Typography policy | Painter height | Widget height | Layout metrics | No ambient default | P05-003 |
| F079 `styleRole` | normalized role enum | Closed catalog | Select style | Select style | Layout metrics | Known role | P05-003 |
| F080 `declaredFontRequest` | `ReaderFontRequestIdentity` | Typography resolver | Font request | Same request | Layout metrics | Nonempty | P05-003/P05-004 |
| F081 `requestedWeight` | integer 100..900 | Role policy | Glyph metrics | Same | Layout metrics | Valid CSS/Flutter weight | P05-003 |
| F082 `requestedStyle` | `normal/italic` | Role policy | Glyph metrics | Same | Layout metrics | Closed enum | P05-003 |
| F083 `logicalFontSize` | finite binary64 | Effective role | Scale key | Scale key | Layout metrics | >0 and in domain | P05-003 |
| F084 `scaledFontSize` | finite binary64 | Scale profile | Painter size | Widget size | Layout metrics | Exact response | P05-003 |
| F085 `lineHeightMultiplier` | finite binary64 | Effective role | Text height | Same | Layout metrics | > 0 | P05-003 |
| F086 `effectiveLineBoxHeight` | finite binary64 | Resolved strut/metric policy | Budgets/gaps | Same line box | Layout metrics | > 0; evidence-covered | P05-003/P05-004 |
| F087 `letterSpacing` | explicit finite binary64 | Role policy | Width/shaping | Same | Layout metrics | Finite; null forbidden | P05-003 |
| F088 `wordSpacing` | explicit finite binary64 | Role policy | Width/shaping | Same | Layout metrics | Finite; null forbidden | P05-003 |
| F089 `locale` | `ReaderCanonicalLocale` | Block resolver | Shaping | Same | Block layout/Layout metrics default | Canonical | P05-003 |
| F090 `direction` | `ltr/rtl` | Block resolver | `TextPainter.textDirection` | Explicit widget direction | Block layout | Final/non-null | P05-003 |
| F091 `alignment` | `left/center/right/justify/start/end` normalized | Block resolver | Painter alignment | Widget alignment | Block layout | Final/non-null | P05-003 |
| F092 `softWrap` | bool | Role/box policy | Line breaking | Same | Renderer layout/block | Explicit | P05-003 |
| F093 `widthBasis` | normalized enum (`body/block/list_cell/table_cell/intrinsic_line`) | Box resolver | Exact max width | Exact constraint | Renderer layout/block | Resolves finite width | P05-003 |
| F094 `maxLines` | explicit optional positive integer | Role policy | Painter cap | Widget cap | Renderer layout/block | Presence encoded; >0 | P05-003 |
| F095 `overflowPolicy` | `clip/ellipsis/visible/reject_overflow` | Role policy | Fit/authority | Same | Renderer layout/block | Closed enum | P05-003 |
| F096 `textWidthBasis` | explicit Flutter-compatible width-basis enum | Role policy | Painter | Widget | Layout metrics | Closed enum | P05-003 |
| F097 `textLeadingDistribution` | explicit normalized enum | Role policy | Painter line metrics | Widget | Layout metrics | Closed enum | P05-003 |
| F098 `fontFeatures` | ordered immutable feature/value tuples | Role policy | Shaping | Same | Layout metrics | Unique sorted tags | P05-003 |

The closed v1 catalog contains at least these roles and cannot omit a role used
by a resolved block:

| Role | V1 derivation and required behavior |
| --- | --- |
| `body` | Effective reader family/weight, compensated logical size, effective line height, forced body strut. |
| `heading` | Same family, logical size `body + 14×fontSizeMultiplier`, w900 normal, height 1.3, letter spacing 2, forced heading strut, centered. |
| `inlineBold` | Body with w700. |
| `inlineItalic` | Body weight with italic style. |
| `inlineBoldItalic` | Body with w700 italic. |
| `footnoteMarker` | Body at 0.75 logical size and w600; recognizer/color excluded. |
| `listMarker` | Body at w600, right aligned, one line; paint color excluded. |
| `tableHeader` | Body logical size clamped to 13..18, height clamped to 1.2..1.45, w800. |
| `tableCell` | Same table size/height, w500. |
| `preformatted` | Requested monospace family, logical size clamped to 12..16, height 1.35, no soft wrap. |
| `headingDivider` | Explicit logical size 14, letter spacing 2, one line, no wrap; paint color excluded. |
| `publisherProse`, `publisherPoem`, `publisherQuote`, `publisherLetter` | Explicit roles even when values equal body; any metric divergence creates a catalog/fingerprint divergence. |

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F099 `typographyRevision` | fixed semantic enum | This design | Resolver selection | Renderer selection | Layout metrics | Supported | P05-003 |
| F100 `stylesByRole` | immutable role-sorted map of F079–F098 | Typography resolver | Every span/cell/marker | Same instances/specs | Layout metrics | Closed, no unused ambient style | P05-003 |
| F101 `strutsByRole` | immutable role-sorted map of F071–F078 | Typography resolver | Every text painter | Same widgets | Layout metrics | Required roles present | P05-003 |
| F102 `styleCatalogSizeDomain` | immutable sorted binary64 set | Catalog | Scale profile domain | Same | Layout metrics | Equals F065 | P05-003 |
| F103 `defaultLocale` | canonical locale | Environment | Catalog default | Catalog default | Layout metrics | = F019 | P05-003 |
| F104 `defaultDirection` | final `ltr/rtl` after fallback | Environment/direction policy | Catalog default | Catalog default | Layout metrics | source-independent; LTR only last fallback | P05-003 |
| F105 `defaultBodyAlignment` | final normalized alignment | Effective settings | Body default | Body default | Layout metrics | Explicit | P05-003 |

## 7. Font readiness and metric-evidence contract

Flutter does not provide Nalori with a trustworthy resolved face identifier.
The design therefore separates a declared request from observable metric
evidence and never labels a request or asset hash as the resolved face.

Every renderer-used request variant requires evidence: body selected weight;
heading w900; inline w700 normal; body-weight italic; w700 italic; footnote and
list w600; table w500 and w800; explicit bundled Roboto Mono preformatted
text; the selected bundled reader family at the divider role; plus any distinct
publisher-role request. Duplicate delivered assets may share delivery evidence,
but every role/request identity remains present in the capture catalog.

The readiness state is one of:

- `pendingAssetReadiness`: typed pending, no authority;
- `readyTerminalBundled`: every manifest byte/licence/mapping is valid, the
  application-font loader completed, and complete repeated source observations
  agree;
- missing asset, digest mismatch, incomplete variant coverage, unavailable or
  contradictory metrics, stale capture, and cancellation: typed rejected, no
  authority. A platform fallback is never called bundled.

CHANGE-20260909-025 corrects the earlier snapshot/window wording. Production
delivery evidence is session-level and signs shipped asset bytes, effective
variant mappings, loader completion, and the text-engine probe revision.
Source-specific repertoire and fallback evidence is scoped only to the stable
canonical source unit or exact source slice currently being resolved. It is
never the union of a mutable loaded window. The same stable source slice has
the same input repertoire regardless of load window, request order,
forward/backward construction, display index, or neighboring sources. A newly
encountered unit is gated before measurement/finalization/publication; already
finalized cards retain their source evidence, and card identity consumes
ordered source/block evidence rather than redefining unrelated cards.

The gate may inspect only text already supplied for that bounded source
operation. It streams the UTF-16 repertoire digest, stores no source text or
unbounded grapheme set, and partitions giant inputs into exact stable slices of
at most 2,048 UTF-16 code units. It does not pre-scan an EPUB. For every used
variant and scaled size, it records or hashes exact binary64 outputs for:

- unconstrained single-line advance/width and height;
- alphabetic and ideographic baselines where exposed;
- every `LineMetrics` value (hard break, ascent, descent, unscaled ascent,
  height, width, left, baseline, and line number);
- bounded multi-line layout at the canonical probe widths, including line
  count and exact UTF-16 line boundaries;
- shaping-sensitive selection boxes/positions for the probe runs; and
- source-repertoire glyph-coverage/fallback status when exposed.

Missing-glyph fallback is never silently omitted. If the engine exposes the
fallback/missing-glyph signal, the evidence records it per repertoire run. If
it does not, the evidence records `opaqueFallbackMetricProbe` and hashes the
complete source-repertoire metric/shaping observations. If those observations
cannot be made complete and stable, the state is `unavailableEvidence` and
pagination fails closed. A stable face name is not required: terminal loader
state plus complete stable observable metrics is sufficient. Any changed
layout-relevant observation necessarily changes the canonical evidence bytes
and `LayoutMetricsIdentity`; a face substitution with identical observations
may legitimately share layout identity.

The P02 Lexend SHA-256 values prove only that specific test asset bytes loaded
under a test-only alias. They do not prove production `GoogleFonts` selection,
platform fallback order, source-glyph fallback, shaping, or resolved metrics,
and are never substituted for this evidence.

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F106 `requestFamily` | nonempty canonical requested family string | Settings/role resolver | Font request | Same request | Layout metrics declaration | UTF-8, nonempty | P05-003 |
| F107 `requestPackage` | explicit optional package/provider string | Resolver | Font request | Same | Layout metrics declaration | Presence encoded | P05-003 |
| F108 `requestWeight` | integer 100..900 | Role | Variant request | Same | Layout metrics | Valid | P05-003 |
| F109 `requestStyle` | `normal/italic` | Role | Variant request | Same | Layout metrics | Closed | P05-003 |
| F110 `requestAxes` | sorted immutable axis-tag/exact-value tuples | Resolver | Variable-font request | Same | Layout metrics | Unique tags, finite values | P05-003/P05-004 |
| F111 `requestFeatures` | sorted immutable feature tuples | Resolver | Shaping | Same | Layout metrics | Unique tags | P05-003 |
| F112 `requestLocale` | canonical locale | Block/catalog | Font fallback request | Same | Layout metrics/block | Canonical | P05-003 |
| F113 `evidenceRevision` | fixed probe semantic enum | P05-004 | Interpret evidence | Lock same observations | Layout metrics | Supported | P05-004 |
| F114 `readinessState` | enum above | Font gate | Authority gate | Authority gate | Layout metrics | Terminal loaded/fallback only when ready | P05-004 |
| F115 `terminalRequestOutcome` | loaded/failed/unavailable tuple per request | Font loader boundary | Explains chosen metrics | Same | Layout metrics | Complete request coverage | P05-004 |
| F116 `coveredVariantRequests` | canonical sorted F106–F112 identities | Font gate | Proves all styles covered | Same | Layout metrics | Equals used request set | P05-004 |
| F117 `probeCorpusRevision` | fixed text-engine/source-slice probe revision | Font gate | Reproducible observations | Same | Layout metrics | Session delivery revision + exact source-slice semantics | P05-004 |
| F118 `sourceRepertoireDigest` | streaming SHA-256 of the exact stable source unit/slice UTF-16 repertoire; no source text retained | Canonical source operation/probe builder | Source-local coverage scope | Same | Layout metrics + ordered source compatibility linkage | Recompute independent of window/order/neighbors | P05-004 |
| F119 `probeWidths` | sorted exact binary64 widths | Geometry/probe policy | Multiline evidence | Same | Layout metrics | Finite, >0, complete | P05-004 |
| F120 `singleLineObservations` | sorted variant/size/run exact metrics | Text engine probe | Metric identity | Same | Layout metrics | Nonempty/complete | P05-004 |
| F121 `lineMetricObservations` | sorted exact `LineMetrics` records | Text engine probe | Line identity | Same | Layout metrics | Complete | P05-004 |
| F122 `baselineObservations` | explicit optional alphabetic/ideographic values | Text engine probe | Baseline identity | Same | Layout metrics | Presence encoded; finite | P05-004 |
| F123 `lineBoundaryObservations` | ordered UTF-16 half-open boundaries | Text engine probe | Wrap identity | Same | Layout metrics | Gap-free over probe | P05-004 |
| F124 `shapingBoxObservations` | ordered exact selection/glyph-position boxes | Text engine probe | Shaping identity | Same | Layout metrics | Finite/canonical order | P05-004 |
| F125 `fallbackObservationKind` | exposed signal/opaque metric probe | Platform capability | Fail-closed classification | Same | Layout metrics | Explicit | P05-004 |
| F126 `glyphFallbackObservations` | complete per-slice observation digest plus bounded metric records | Probe | Missing-glyph identity for the current source unit | Same | Layout metrics/source block | Opaque branch names no face; repeated observations agree or reject | P05-004 |
| F127 `stabilityObservationCount` | positive integer | Font gate | Terminal stability gate | Same | Excluded as count; observations hashed | Meets gate policy | P05-004 |
| F128 `metricEvidenceDigest` | SHA-256 of canonical F113–F126 bytes; F127 is validation-only | Encoder | Layout identity | Layout identity | Layout metrics | Nonempty/recompute | P05-004 |

P05-004 supplies this catalog/gate. U-05 and U-06, and therefore RISK-006,
remain open until P05-003 consumes it in the shared measurement/render path and
P05-007 proves transition behavior. This document does not claim that
`pendingFonts` success reveals a face or that source fallback faces are known.

## 8. Structural block specifications

`ReaderStructuralLayoutContract` defines shared resolver semantics. Each
resolver emits one `ResolvedReaderBlockLayout`; both the paginator and renderer
consume it. Source structure and text remain owned by the P04 canonical source
snapshot. P05 resolves presentation without changing source ownership.

### Normative structural policy

- Ordinary and continued paragraphs use the same explicit final-layout
  segments and source offsets. Structural separators create explicit gap
  boxes; they are not inferred independently from raw newline regexes.
- Paragraph gap is `resolvedBodyLineBoxHeight × paragraphSpacingMultiplier`.
  Continued fragments preserve their canonical paragraph start/end evidence;
  a fragment path cannot substitute a different segmenter.
- Source and generated headings use heading text plus an explicit 20 logical-px
  gap and one heading-divider line. Measurement includes all three boxes.
- Publisher prose/poem/stanza/quote/epigraph/letter resolve source alignment,
  clamped left/right padding, preserve-line-break and preserve-whitespace
  policy once. Current `BookChunk` has no production first-line-indent field;
  v1 therefore resolves first-line indent to +0 unless a future source schema
  explicitly supplies it and changes source/renderer identities.
- Lists resolve their source display segments in order. Leading indent is
  `min(36, depth×12)`. Marker width is measured with the resolved `listMarker`
  spec and clamped to `[18,52]`; marker gap is 8. Gap before a new block in the
  same item is `0.42×bodyLineBox×paragraphSpacing`; a new item is
  `0.28×...`; the same block is zero.
- Inline bold, italic, bold-italic, links, and footnote marker boundaries are
  resolved into one ordered, nonoverlapping span plan before measurement.
  Links add recognizers separately and do not alter the plan. Footnote markers
  use the `footnoteMarker` role.
- Tables use the decoded normalized `ReaderTableBlock.headers/rows` grid
  produced from cell rows/spans as the v1 layout grid. Header context and exact
  body-row ownership remain P04 source evidence. The canonical table width is
  `max(blockAvailableWidth, 156×columnCount)` with equal columns and horizontal
  scrolling. Each cell uses 10 horizontal and 9 vertical padding. The table has
  10 top and 10 bottom outer padding, one explicit outer border, and explicit
  internal borders. The shared table resolver measures every cell at its exact
  column width with its final style/strut/direction and emits resolved row
  heights; the renderer must consume those widths/heights, not ask `Table` to
  derive a second answer. Cell-span expansion order is the parser’s canonical
  left-to-right occupancy expansion. U-04 verifies runtime parity.
- Preformatted blocks use the final monospace spec, preserve whitespace and
  explicit line breaks, never soft-wrap, horizontally scroll, use 10 padding
  on all sides, 10 top/bottom outer padding, and an explicit paint-only border.
  Height is the measured explicit-line stack plus padding; normal paragraph
  measurement is forbidden.
- Images are atomic. Evidence supplies orientation-corrected intrinsic logical
  width/height and a rational aspect ratio. V1 uses deterministic contain fit,
  no upscaling, within block width and
  `publisherPaginationHeightBudget - 16`; bottom padding is 16. The fitted box
  is stored. Missing/pending evidence yields `pendingImageMetrics`.
- Explicit fragments retain ordered source intervals, boundary kinds, and
  synthesized-separator ownership. Measurement and rendering receive the same
  resolved segments; neither re-parses separators.

### Structural policy fields

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F129 `rendererRulesRevision` | fixed semantic enum | This design | Resolver semantics | Renderer semantics | Renderer layout | Supported | P05-003 |
| F130 `paragraphSegmentPolicy` | explicit-boundary-first closed enum | P04 boundaries + resolver | Segment text | Same segments | Renderer layout/block | Complete offsets | P05-003 |
| F131 `continuedParagraphPolicy` | preserve fragment/paragraph flags | P04 source evidence | Fragment measurement | Same fragment | Renderer layout/block | Exact ownership | P05-003 |
| F132 `paragraphGapFormula` | named formula above | This design | Gap height | Same spacer | Renderer layout | Exact | P05-003 |
| F133 `headingTextBoxPolicy` | final heading style/width | This design | Heading height | Same box | Renderer layout/block | Explicit | P05-003 |
| F134 `headingGap` | finite binary64 20 | Current visual policy approved for parity | Add height | `SizedBox` equivalent | Renderer layout | =20 | P05-003 |
| F135 `headingDividerText` | length-delimited `─────── ◆ ───────` | Current visual policy | Divider measurement | Same text | Renderer layout | Exact scalar sequence | P05-003 |
| F136 `headingDividerBoxPolicy` | one line/no wrap/headingDivider role | This design | Divider height | Same box | Renderer layout | Explicit | P05-003 |
| F137 `publisherRolePolicies` | role-sorted immutable map | Source role resolver | Select segment/width | Same | Renderer layout/block | All roles present | P05-003 |
| F138 `publisherFirstLineIndentDefault` | finite +0 | Current source capability | Width/line start | Same | Renderer layout | +0 unless schema supplies | P05-003 |
| F139 `publisherPreserveLineBreaksPolicy` | explicit bool per block | Source | Segment/shaping | Same | Block/source compatibility | Final | P05-003 |
| F140 `publisherPreserveWhitespacePolicy` | explicit bool per block | Source | Segment/shaping | Same | Block/source compatibility | Final | P05-003 |
| F141 `listDepthStep` | finite binary64 12 | List policy | Width | Same spacer | Renderer layout | >=0 | P05-003 |
| F142 `listMaxIndent` | finite binary64 36 | List policy | Width | Same spacer | Renderer layout | >=step | P05-003 |
| F143 `listMarkerWidthMinimum` | finite binary64 18 | List policy | Width clamp | Same width | Renderer layout | >=0 | P05-003 |
| F144 `listMarkerWidthMaximum` | finite binary64 52 | List policy | Width clamp | Same width | Renderer layout | >=min | P05-003 |
| F145 `listMarkerGap` | finite binary64 8 | List policy | Width | Same spacer | Renderer layout | >=0 | P05-003 |
| F146 `listSameBlockGapFactor` | finite +0 | List policy | Height | Same gap | Renderer layout | >=0 | P05-003 |
| F147 `listSameItemGapFactor` | finite binary64 0.42 | List policy | Height | Same gap | Renderer layout | >=0 | P05-003 |
| F148 `listNewItemGapFactor` | finite binary64 0.28 | List policy | Height | Same gap | Renderer layout | >=0 | P05-003 |
| F149 `richSpanResolutionPolicy` | ordered interval sweep + role precedence | P04 rich metadata | Build exact span tree | Same tree | Renderer layout/block | No gaps/overlaps/out-of-range | P05-003 |
| F150 `footnoteMarkerPolicy` | exact label interval + role | P04 footnote metadata | Exact run metrics | Same run; recognizer separate | Renderer layout/block | Marker matches source | P05-003 |
| F151 `tableGridPolicy` | canonical decoded normalized grid | Parser/P04 structure | Cell/row geometry | Same grid | Renderer layout/block | Rectangular, >=2 columns | P05-003 |
| F152 `tableColumnMinimum` | finite binary64 156 | Approved renderer parity policy | Table/column width | Same width | Renderer layout | >0 | P05-003 |
| F153 `tableOuterVerticalPadding` | top/bottom finite 10 | Table policy | Add height | Same padding | Renderer layout | >=0 | P05-003 |
| F154 `tableCellHorizontalPadding` | left/right finite 10 | Table policy | Cell max width | Same padding | Renderer layout | >=0 | P05-003 |
| F155 `tableCellVerticalPadding` | top/bottom finite 9 | Table policy | Row height | Same padding | Renderer layout | >=0 | P05-003 |
| F156 `tableBorderPolicy` | explicit outer/internal paint-only strokes | Table policy | Row/width bookkeeping only where explicit | Same borders | Renderer layout | Finite widths; zero layout inset unless specified | P05-003 |
| F157 `preformattedOuterVerticalPadding` | top/bottom finite 10 | Pre policy | Add height | Same | Renderer layout | >=0 | P05-003 |
| F158 `preformattedInnerPadding` | four finite values 10 | Pre policy | Add box dimensions | Same | Renderer layout | >=0 | P05-003 |
| F159 `preformattedOverflowPolicy` | horizontal scroll/no wrap | Pre policy | Explicit-line height | Same scroll box | Renderer layout | Exact enum | P05-003 |
| F160 `imageFitPolicy` | contain/no-upscale | This design | Fitted dimensions | Same fixed box | Renderer layout/block | Exact enum | P05-003 |
| F161 `imageBottomPadding` | finite binary64 16 | Current visual policy | Add height | Same padding | Renderer layout | >=0 | P05-003 |
| F162 `imageReadinessPolicy` | require terminal deterministic metrics | This design | Gate | Fixed box | Renderer layout | Pending otherwise | P05-003/P05-007 |
| F163 `separatorSynthesisPolicy` | explicit boundary-owned gap/fragment plan | P04 boundaries | Same sequence | Same sequence | Renderer layout/block | Ownership/offset validation | P05-003 |

### Per-block resolved fields

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F164 `stableBlockOwner` | P04 stable source/logical owner tuple | Canonical snapshot | Select content | Select content | Source compatibility/physical card | Resolves exactly | P05-003 |
| F165 `blockKind` | paragraph/heading/list/table/pre/image/etc. | P04 source role | Select resolver | Select renderer | Block + source | Supported | P05-003 |
| F166 `sourceLanguageMetadata` | optional canonical tag + provenance | Source snapshot | Only through explicit locale/direction resolution | Diagnostic/semantic attribute | Source compatibility; block layout if used | Presence explicit | P05-003 |
| F167 `resolvedLocale` | canonical locale | Source override or environment | Every run/painter | Explicit widgets | Block layout | Final | P05-003 |
| F168 `directionSource` | `source_block/reader_capture/ltr_fallback` | Direction resolver | Audit | Audit | Block layout | Matches F169 | P05-003 |
| F169 `resolvedDirection` | `ltr/rtl` | Direction resolver | Every painter/list/table | Explicit `Directionality`/textDirection | Block layout | Final/nonambient | P05-003 |
| F170 `resolvedAlignment` | normalized alignment | Heading/source/settings resolver | Every painter | Every text widget | Block layout | Final for direction | P05-003 |
| F171 `resolvedBlockWidth` | finite positive binary64 | Body minus resolved insets | maxWidth | Exact constraint | Block layout | Exact formula | P05-003 |
| F172 `publisherPaddingLeft` | finite binary64 | Source clamp | Width | Same padding | Block layout | 0..72 | P05-003 |
| F173 `publisherPaddingRight` | finite binary64 | Source clamp | Width | Same padding | Block layout | 0..72 | P05-003 |
| F174 `firstLineIndent` | finite binary64 | Source/default policy | Line layout | Same | Block layout | +0 in current v1 source | P05-003 |
| F175 `listLeadingIndent` | finite binary64 | List resolver | Width | Same spacer | Block layout | 0..36 | P05-003 |
| F176 `listMarkerWidth` | finite binary64 | Marker measurement with final spec | Width | Exact marker box | Block layout | 18..52 | P05-003 |
| F177 `listMarkerGap` | finite binary64 | List policy | Width | Same spacer | Block layout | =8 v1 | P05-003 |
| F178 `orderedParagraphSegments` | immutable text/source half-open interval descriptors | Boundary resolver | Measure each | Render each | Block layout | Ordered, complete | P05-003 |
| F179 `orderedSpanRuns` | immutable `ResolvedReaderSpanRun[]` | Rich resolver | Exact `TextSpan` tree | Same tree | Block layout | Ordered, no metric ambiguity | P05-003 |
| F180 `gapBoxes` | ordered explicit gap descriptors | Paragraph/list/heading resolver | Add exact heights | Same boxes | Block layout | Finite/nonnegative | P05-003 |
| F181 `lineBreakPolicy` | normal/preserve/source-explicit | Block resolver | Shaping | Same | Block layout | Closed | P05-003 |
| F182 `whitespacePolicy` | collapse/preserve | Block resolver | Shaping | Same | Block layout | Closed | P05-003 |
| F183 `structuralBoxKind` | text/heading/list/table/pre/image | Resolver | Dispatch | Dispatch | Block layout | Exactly one | P05-003 |
| F184 `resolvedTableGrid` | optional immutable normalized cells/spans/owners | Table resolver | Cell measures | Same cells | Block + source | Present only for table | P05-003 |
| F185 `resolvedTableColumnWidths` | optional ordered finite widths | Table resolver | Cell max widths | Fixed columns | Block layout | Count matches grid | P05-003 |
| F186 `resolvedTableRowHeights` | optional ordered finite heights | Shared cell measurement | Table height | Fixed rows | Block layout | Count matches grid | P05-003 |
| F187 `preformattedLineBoxes` | optional ordered explicit-line metrics | Pre resolver | Height | Fixed line stack | Block layout | Complete | P05-003 |
| F188 `imageMetricEvidence` | optional intrinsic/decode evidence identity | Image gate | Fit input | Same fixed image | Layout + block | Terminal/complete for image | P05-003/P05-007 |
| F189 `resolvedImageWidth` | optional finite positive binary64 | Image fit resolver | Atomic width | Fixed box | Block layout | Fits bounds/aspect | P05-003 |
| F190 `resolvedImageHeight` | optional finite positive binary64 | Image fit resolver | Atomic height | Fixed box | Block layout | Fits budget/aspect | P05-003 |
| F191 `resolvedTotalHeight` | finite nonnegative binary64 | Shared block resolver | Packing | Exact box invariant | Block layout | Recomputes from children | P05-003 |
| F192 `overflowAuthority` | `fits/reject` | Shared resolver | Authorize/reject | Assert no overflow | Block layout | No silent clip for body | P05-003 |
| F193 `blockLayoutFingerprint` | SHA-256 canonical F164–F192 | Encoder | Card layout input | Card verification | Physical card layout | Recompute/nonempty | P05-003 |
| F194 `sourceStructureDigestLink` | P04 structural/rich/list/publisher digest tuple | Canonical source slice | Proves resolver input | Proves same input | Source + physical card | Exact P04 evidence | P05-003 |

## 9. Identity and compatibility layering

The term “layout fingerprint” is not used for unrelated values. The future
types are:

| Identity | Exact contents | Explicit exclusions | Consumer |
| --- | --- | --- | --- |
| `LayoutMetricsIdentity` | Contract revision; resolved deck/safe geometry; effective margins/padding/reserves/density/budgets/safety policy; exact scale profile; resolved typography/struts; terminal bundled delivery evidence; resolved values only | Raw settings that collapse to same values, book ID, mutable loaded-window membership, source/parser, cache format, display indexes, tokens | Paginator/renderer metric equality and genuine layout classification |
| `SourceCompatibilityIdentity` | Publication fingerprint; parser/source schema and revision; pinned snapshot digest; canonical P04 structural-ownership revision/digests; source-repertoire digest link | Access time, display/window ordinals, controller state | Source reconstruction and compatibility |
| `PaginationAlgorithmIdentity` | Canonical packing/finalization/continuation algorithm semantic identity | Geometry, source content, cache format | Canonical session compatibility |
| `RendererLayoutIdentity` | Renderer-rule revision and every structural/text-box policy F129–F163 that can affect metrics | Colors, recognizers, shadows, animation, controls | Ensures structural renderer semantics agree |
| `ReaderCompatibilityIdentity` | Tagged composite of the four identities above, plus explicit classification revision | Book access time, request/generation tokens | P05-006 cache/checkpoint classification input |
| Physical-card identity | Existing P04 stable ordered source slices/owners/ranges plus publication/source compatibility, `LayoutMetricsIdentity`, each slice's ordered F117–F128 source-font evidence, ordered F193 block fingerprints, `RendererLayoutIdentity`, and `PaginationAlgorithmIdentity` | Display index/card ordinal/window position/neighboring sources/runtime identity | Canonical physical-card construction; one source's later evidence cannot redefine unrelated finalized cards |

`ReaderLayoutIdentityBundle` stores the five named identities and their
canonical component fingerprints. The future adapter may feed a canonical
composite into the existing P04 `controlledLayoutIdentity` seam, but this task
does not change `ReaderCardIdentity`, its signature, checkpoints, or persistent
caches.

| Field | Type/shape | Authority | Measurement use | Rendering use | Fingerprint layer | Validation | Implementation owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F195 `layoutMetricsIdentityRevision` | fixed semantic enum | This design | Interpret metric identity | Same | Layout metrics | Supported | P05-003 |
| F196 `layoutMetricsFingerprint` | SHA-256 of resolved metric fields and policies | Canonical encoder | Layout compatibility | Layout compatibility | Layout metrics | Recompute/nonempty | P05-003 |
| F197 `publicationFingerprint` | nonempty stable publication digest | P04 source snapshot | Source scope | Source scope | Source compatibility/physical card | Exact snapshot match | P05-003 |
| F198 `parserSourceSchemaIdentity` | canonical parser/schema tuple | Parser/source owner | Structure compatibility | Same source structure | Source compatibility | Nonempty/supported | P05-003/P05-006 |
| F199 `sourceRevision` | stable revision value | P04 pinned snapshot | Reconstruct blocks | Same blocks | Source compatibility | Exact snapshot match | P05-003 |
| F200 `sourceSnapshotDigest` | SHA-256 pinned source snapshot | P04 snapshot | Source integrity | Source integrity | Source compatibility | Recompute/nonempty | P05-003 |
| F201 `structuralOwnershipRevision` | canonical P04 ownership semantic identity | P04 | Interpret F194 | Same | Source compatibility/physical card | Supported | P05-003 |
| F202 `sourceCompatibilityFingerprint` | SHA-256 F197–F201 plus source-repertoire link | Canonical encoder | Source compatibility | Source compatibility | Source compatibility | Recompute/nonempty | P05-003/P05-006 |
| F203 `paginationSemanticRevision` | canonical algorithm identity | P04 paginator | Packing/finalization | Card compatibility | Pagination algorithm | Nonempty/supported | P05-003 |
| F204 `paginationAlgorithmFingerprint` | SHA-256 canonical F203 record | Canonical encoder | Session compatibility | Card compatibility | Pagination algorithm | Recompute/nonempty | P05-003/P05-006 |
| F205 `rendererRulesRevisionLink` | exact F129 identity | Structural contract | Resolver dispatch | Renderer dispatch | Renderer layout | Equals F129 | P05-003 |
| F206 `rendererLayoutFingerprint` | SHA-256 F129–F163 canonical policy | Canonical encoder | Structural measure compatibility | Structural render compatibility | Renderer layout | Recompute/nonempty | P05-003 |
| F207 `compatibilityClassifierRevision` | fixed semantic enum | P05 design | None directly | None directly | Reader compatibility | Supported | P05-006 |
| F208 `readerCompatibilityFingerprint` | tagged SHA-256 of F196/F202/F204/F206 plus F207 | Canonical encoder | Build classification input | Build classification input | Reader compatibility | Recompute/nonempty | P05-003/P05-006 |
| F209 `orderedBlockLayoutFingerprints` | ordered immutable F193 list for one physical card | Block resolver/P04 finalized membership | Physical card layout | Physical card verification | Physical card | Order matches source slices | P05-003 |
| F210 `physicalLayoutCompositeFingerprint` | tagged SHA-256 of F196/F206/F209 | Canonical encoder | P04 controlled-layout seam | Card identity input | Physical card | Recompute/nonempty | P05-003 |
| F211 `physicalCardIdentityComponents` | immutable tuple F197/F202/F204/F210 + ordered P04 source slices | P04 identity builder adapter | Final identity construction | Final identity verification | Physical card | No display/index/runtime fields; exact owners | P05-003 |

Book ID is cache/store scoping evidence, not a physical metric. It may remain
outside or alongside `ReaderCompatibilityIdentity` for lookup isolation but
cannot make two physically identical layouts different. Publication identity
belongs to source compatibility and remains part of physical-card ownership.
Parser/source and pagination revisions are compatibility, not geometry.

Direction and alignment are represented twice at appropriate granularity: the
captured defaults affect `LayoutMetricsIdentity`, while a block override and
its final values affect F193 and therefore the physical card. Source language
alone affects only source compatibility unless it changes the resolved locale
or direction.

## 10. Canonical encoding and fingerprint rules

All future identities use one strict binary tagged encoding:

1. Begin with a length-delimited ASCII record kind and semantic revision.
2. Encode fields in ascending fixed numeric tag order. Each field is
   `tag:uint32-be`, `type:uint8`, `presence:uint8`, `length:uint64-be`, then
   payload. Required fields still encode presence `1`; absent optional fields
   encode presence `0` and zero length.
3. Text is NFC-normalized UTF-8 only where the field contract defines Unicode
   semantic text; opaque IDs remain their exact declared UTF-8. Every string is
   length-delimited. No delimiter concatenation is allowed.
4. Enums use fixed lowercase ASCII snake-case wire names defined by the
   semantic revision. Dart indexes, localized labels, `toString()`, and future
   unknown enum names are rejected.
5. Locale encodes the structured language/script/region/variant fields from
   section 4, each with presence and length; it never uses platform display
   text.
6. A double must be finite. Normalize negative zero to positive zero, then
   encode its IEEE-754 binary64 bits big-endian. Reject NaN and both infinities.
   Do not use decimal formatting, tolerance, rounding, truncation, or integer
   viewport coercion.
7. Integers use signed or unsigned fixed-width big-endian types declared by
   the field. Booleans are one byte `0` or `1`.
8. Ordered semantic collections preserve order and include an explicit count.
   Sets are sorted by canonical element bytes. Maps are sorted by canonical key
   bytes (field-tag order for tagged records); duplicates are rejected.
9. Nested records are length-delimited canonical records. Unknown, duplicate,
   missing, out-of-order, or trailing fields are rejected.
10. The fingerprint is lowercase hexadecimal SHA-256 over the complete
    canonical record bytes, with the record kind and revision included.

This encoding has no known precision collision for accepted binary64 inputs.
The current cache string’s `toStringAsFixed`, rounded safe areas,
integer-truncated screen sizes, `scale(1.0)`, ambiguous `|` concatenation, and
runtime object identity are prohibited. Display/card/window indexes never enter
the encoding.

## 11. Validation and typed outcomes

`ReaderLayoutContractBuilder.build` conceptually returns a sealed outcome:

| Outcome | Trigger | Authority |
| --- | --- | --- |
| `ReaderLayoutReady(contract)` | All capture, geometry, catalog, font, image, structure, and identity checks pass and capture remains fresh | Full authority, subject to normal P04 generation/seam checks |
| `ReaderLayoutPendingFontEvidence(missingRequests)` | Any used request is unresolved/loading or evidence is not yet complete | None |
| `ReaderLayoutPendingImageMetrics(stableImageOwners)` | A required image lacks terminal deterministic intrinsic/layout evidence | None |
| `ReaderLayoutIncompatibleEnvironment(reason)` | Unbounded/nonpositive deck, non-equivalent MediaQuery-only size, unsupported platform effect, or too-small capacity | None |
| `ReaderLayoutUnsupportedStructuralInput(owner,kind)` | Unknown role/span/widget/table/pre/image form cannot resolve under v1 | None |
| `ReaderLayoutContradictoryDerivedGeometry(fields)` | Arithmetic, widths, heights, inset sums, row/grid, aspect ratio, or recomputed totals disagree | None |
| `ReaderLayoutInvalidNumericValue(field)` | NaN, infinity, forbidden negative, overflow, or invalid zero | None |
| `ReaderLayoutStaleCapture(captured,current)` | Any authoritative capture input changes before validation/publication | None |

Validation order is numeric/enum/collection well-formedness; environment
equivalence/freshness; effective policy derivation; geometry invariants;
closed typography/scale domain; required font evidence; source/structural
resolution; image evidence; block total recomputation; canonical encoding and
fingerprint recomputation. A failure cannot be downgraded to approximate
pagination.

A pending/rejected outcome cannot:

- call canonical pagination with authoritative layout;
- create/finalize/publish a card or continuation;
- mutate `ProgressiveDisplayState`;
- settle navigation or become committed-card evidence;
- create or rewrite a checkpoint; or
- write a whole, segmented, or memory display record marked compatible.

## 12. Transient/excluded state

The following remain outside F001–F211 and every physical-layout identity:
display/current/preview/window/card indexes; `PageController` position;
controller attachment; deck drag offset, transform, depth lift, animation and
opacity; active/preview card state; gesture, tap, long-press, selection, menu,
recognizer and pointer state; highlights, notes, character colors/shadows;
bookmark/chapter/progress text and animation inside fixed reserves; control,
toolbar, FAB and overlay visibility; keyboard `viewInsets`; Speed Reader
active state, cursor, WPM and visual mode; cache access times; diagnostic
timestamps; generation/request/cancellation/publication tokens; scheduler;
and runtime object identity.

Paint-only color, background, border color, shadow, radius, selection style,
text decoration and recognizers remain excluded. Border *geometry policy* and
stroke width remain in `RendererLayoutIdentity` so a future layout-consuming
border change cannot hide behind paint classification.

Speed Reader may change paint and overlay composition only. P05-003/P05-005
must retain F178–F191 geometry and span advances; if a speed presentation
cannot fit, it must clip/overlay within the canonical box or decline that
presentation, never repaginate by transient state.

## 13. M-01–M-09 reconciliation

“Specification resolved” means this document chose the future invariant; it
does not mean current production conforms.

| ID | Contract field/resolver or invariant | P05-002 result | Implementing task | Verifying task | May change P03 physical boundaries? |
| --- | --- | --- | --- | --- | --- |
| M-01 | F015–F018, F044–F051; raw bottom `viewPadding` included once in both paths | Specification resolved | P05-003; overlay invariant P05-005 | P05-005/P05-007 | Yes; cause must map to bottom safe inset |
| M-02 | F133–F136, F180/F191; heading text + 20 gap + divider measured/rendered as one spec | Ownership fixed | P05-003 | P05-007 | Yes |
| M-03 | F079–F105, F149–F150, F179; one rich/footnote span plan | Ownership fixed | P05-003 | P05-007 | Yes |
| M-04 | `listMarker` role, F143–F145, F176–F177; marker measured w600 | Ownership fixed | P05-003 | P05-007 | Yes |
| M-05 | F151–F156, F184–F186; shared normalized table grid/columns/rows/box | Ownership fixed | P05-003 | P05-007 | Yes |
| M-06 | `preformatted` role, F157–F159, F181–F182/F187 | Ownership fixed | P05-003 | P05-007 | Yes |
| M-07 | F160–F162, F188–F191; deterministic terminal image box or pending | Ownership fixed | P05-003 | P05-007 | Yes |
| M-08 | F020/F104, F167–F170; source override → captured direction → LTR fallback, explicit both paths | Specification resolved | P05-003 | P05-007 | Yes for bidi/RTL |
| M-09 | F178–F193 invariant; Speed Reader is paint/overlay-only and cannot replace layout tree | Ownership fixed | P05-003/P05-005 | P05-005/P05-007 | No for intended correction |

P05-007 must rerun the complete P03 matrix after the implementation and map
every changed range/signature to M-01–M-08 or another explicit contract field.
P04 construction-order equality and P04 source ownership remain the oracle.

## 14. U-01–U-10 probe ownership

| ID | Contract field/invariant retaining the question | P05-002 result | Implementing task | Verifying task | May change P03 physical boundaries? |
| --- | --- | --- | --- | --- | --- |
| U-01 | F034–F039 paint-only border | Closed by CHANGE-029: production border overlay consumes zero body inset | P05-003/P05-007 | Exact descendant constraint/card-body probe | No range change; renderer composition corrected |
| U-02 | F010–F014 deck constraint authority | Closed by CHANGE-029: standard and bounded parent agree; incompatible MediaQuery rejects | P05-003/P05-007 | Parent/deck/card probe | No |
| U-03 | F130–F132/F137–F140/F178–F182 publisher segmentation | Closed by CHANGE-029 with parser-produced prose/poem/stanza/quote/epigraph/letter parity | P05-003/P05-007 | Parser/renderer probe | No |
| U-04 | F151–F156/F184–F186 span-grid and row geometry | Closed by CHANGE-029 with decoded row/column-span occupancy | P05-003/P05-007 | Table resolver/widget probe | No |
| U-05 | F113–F128 observable terminal evidence | Closed by CHANGE-025/029; pending/rejected states have zero authority and changed observations change identity | P05-004/P05-007 | Transition matrix | Yes only for genuine evidence change |
| U-06 | F106–F128 renderer-used variants | Closed by CHANGE-025/029: 11 roles/10 unique variants covered | P05-004/P05-007 | Coverage matrix | Yes only for genuine evidence change |
| U-07 | F064–F070 plus diagnostic platform inputs | Closed by CHANGE-029: DPR, bold-text, contrast and brightness preserve logical metrics and stay excluded | P05-007 | Parameter probe | No |
| U-08 | F091/F105/F170 and block fingerprint | Closed by CHANGE-029 for LTR/RTL/fallback and all supported alignments | P05-003/P05-007 | Painter/widget/hit probe | Yes when captured direction/alignment changes |
| U-09 | F160–F162/F188–F191 deterministic image box | Closed by CHANGE-029: provisional/stale/contradictory evidence rejects; terminal evidence fixes the box | P05-003/P05-007 | Delayed/terminal image probe | Yes for genuine terminal evidence change |
| U-10 | F002/F022 explicit contract injection | Closed by CHANGE-027/029: active/preview/Speed Reader wrappers preserve current geometry and stale cards cannot publish | P05-003/P05-005/P05-007 | Freshness/authority probe | No |

All ten runtime questions are closed for P05 by `CHANGE-20260910-029`.

## 15. P05-003 implementation handoff

P05-003 can proceed without choosing ownership boundaries:

1. Add documentation-shaped immutable in-memory types (names may vary, field
   semantics may not) and a sealed builder result.
2. Capture deck constraint/environment once and remove downstream ambient
   layout reads from the authoritative paginator/`ReadingCard` path.
3. Convert raw `ReadingSettings` into effective F023–F029 values, then derive
   and validate F030–F063 once.
4. Build the closed typography catalog and exact scale response profile. Do not
   call the scaler after construction.
5. Accept only terminal font evidence from the P05-004 gate: complete metric
   evidence for a nonempty renderer-used repertoire, or the explicit canonical
   empty-repertoire outcome defined below. Keep every missing, pending,
   incomplete, stale, cancelled or contradictory path non-authoritative rather
   than forge evidence.
6. Resolve each canonical source block through one pure resolver to F164–F194.
   The resolver owns paragraphs, heading decoration, rich/footnote spans,
   lists, tables, preformatted blocks, images, and publisher roles.
7. Make paginator measurement and renderer adapters consume the same resolved
   objects. Remove duplicate calculations; similar constants in two places do
   not satisfy the contract.
8. Feed the appropriate identity composite through the current in-memory P04
   controlled-layout seam without changing persistent cache/checkpoint formats
   or version constants.
9. Preserve Speed Reader as transient presentation within resolved boxes.
10. Return typed pending/rejection before any canonical publication authority.

M-01 through M-09 are the implementation acceptance map. Do not combine
P05-003 with P05-004 font discovery, P05-006 persistent compatibility policy,
or P05-007 oracle updates/reruns.

## 16. P05-004 font-gate handoff

P05-004 owns the separately callable runtime boundary that turns F106–F128
into honest evidence. P05-003 consumes it while replacing shared
measure/render typography; no temporary paginator adapter is permitted. The
gate must:

- enumerate every request actually used by the resolved catalog, including
  italic, w500/w600/w700/w800/w900 and monospace variants;
- validate all 74 production root-bundle assets and eight family-specific OFL
  notices, preserve the installed 8.0.2 nominal-to-delivered mappings, and
  complete explicit application-font loader events without HTTP;
- construct evidence only for the canonical source unit/exact slice being
  resolved, independent of mutable reader-window membership and construction
  order, before that source may be measured or published;
- record exact widths, line metrics, baselines, line boundaries, and shaping
  boxes at every used scaled size and probe width;
- represent exposed missing-glyph/fallback signals, or explicitly use the
  opaque metric-probe branch and fail closed if completeness/stability cannot
  be established;
- classify complete delivery only as `readyTerminalBundled`; use
  `opaqueFallbackMetricProbe` for unavailable glyph-face identity without ever
  assigning a resolved platform face;
- cause any changed layout-relevant observation to change F128 and therefore
  `LayoutMetricsIdentity`; and
- invalidate/stale the build if font evidence changes before publication.

Test-only Lexend asset digests remain controlled-harness asset evidence, never
production delivery or runtime resolution proof. The source bound is 2,048
UTF-16 units, 11 role requests, six scaled sizes, two finite widths and 33
TextPainter runs per capture; retained canonical evidence is capped at 32,768
bytes per source and 25 LRU records/819,200 bytes. `CHANGE-20260910-029`
closes U-05/U-06 through the production consumer and late-transition probes.

### Canonically empty render repertoires

`CHANGE-20260911-031` restores terminal authority for an exact source slice
whose final shared block/span resolution proves that nothing can produce a
glyph or consume text layout. Its source evidence is explicit rather than
absent: it binds the pinned snapshot owner, exact zero-length slice, canonical
empty UTF-16 digest and an ordered observation collection of length zero. The
terminal outcome still carries and validates the complete 11-role renderer
request catalog plus bundled delivery/catalog readiness and digests. It runs
zero metric probes, resolves zero text spans and zero text height, and gives
the paginator no authority to fabricate a physical card.

This branch is valid only when the shared renderer/measurement repertoire is
empty. Raw `trim().isEmpty` is not authority. Headings and generated headings,
list markers or latent list semantics, heading dividers, tables, preformatted
content, dialogue markers, rich/decorated visible spans, replacement/fallback
glyphs, structural separators and layout-significant preserved whitespace all
remain normal nonempty repertoires and require the complete 33-observation
metric matrix for every renderer-used role/variant. The layout builder
recomputes the exact slice digest and canonical evidence bytes, verifies stable
owner/slice/probe/delivery bindings, and rejects false-empty, missing,
incomplete, stale, cancelled or contradictory evidence. Discovering any later
renderable glyph changes the repertoire digest and compatibility identity and
therefore requires the normal font gate again. No cache, checkpoint, schema,
format, key or version changes follow from this in-memory authority.

## 17. P05-005–P05-007 verification handoff

P05-005 proves controls, overlays, keyboard `viewInsets`, gestures, active/
preview state, transforms, and Speed Reader state cannot change F044–F051 or
F178–F191. Raw stable `viewPadding` changes must change layout; control
visibility must not.

P05-006 builds the classifier over the separated identities. It must report at
least exact compatible, layout metrics changed, source/parser changed,
pagination algorithm changed, renderer layout changed, incomplete evidence,
and corrupt/unsupported. It must not implement P06 persistent formats,
migration, or version changes.

P05-007 owns focused evidence for:

- outer deck/MediaQuery equivalence, border treatment, and all four safe sides;
- one-field exact fingerprint changes and effective-value equivalence (including
  clamped side margins and subpixel doubles);
- nonlinear scalers with equal `scale(1.0)` but different used-size outputs;
- LTR/RTL, locale, alignment, ordinary/continued/publisher paragraphs;
- heading/gap/divider, rich bold/italic/footnote, lists/markers;
- decoded tables including spans, preformatted content, and delayed images;
- font loaded/fallback metric transitions and all renderer-used variants;
- active/preview cached widget environment freshness and every Speed Reader
  state; and
- exact overflow/line/card identity evidence from production painter and
  renderer adapters.

After a proved correction, P05-007 reruns the complete P03 construction-order
matrix. It records old/new physical ranges and the exact F-field/M-ID cause for
every legitimate boundary change. It may not change P04 source ownership,
fixtures, expected construction-order relation, or silently update signatures.

## 18. Closed P05 runtime questions

`CHANGE-20260910-029` closes U-01–U-10. No probed DPR, accessibility-bold,
high-contrast or brightness input changed production logical metrics, so those
inputs remain diagnostic and excluded. The shared image resolver now validates
positive intrinsic dimensions, recomputes the source-byte SHA-256 and
`reader-image-metrics` digest, and rejects stale or contradictory evidence
atomically before measurement. A future platform effect still requires an
explicit reviewed contract revision; it may not enter identity ambiently.

P05 exit criteria are met. Cache compatibility/migration, restoration,
navigation, settlement and lifecycle consumers remain in P06 and later phases.
