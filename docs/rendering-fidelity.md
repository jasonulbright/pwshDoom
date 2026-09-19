# Rendering fidelity: first reference comparison and HUD repairs

2026-09-19. These are offline image fixtures, not live terminal runs or performance measurements. The reference is the adopted, locally adapted PowerShell renderer. It is useful for finding disagreements with our new rasterizer, but it is not independently verified original-executable output.

## What the comparison establishes

`scripts/Compare-RendererReference.ps1` loads a real IWAD map, advances 35 idle updates, and renders the same endpoint at three explicit camera headings. The reference uses its 320x168 scene plus 32-row status bar. The current renderer receives the corresponding fraction-one snapshot. Reference column-major pixels are converted to row-major before comparison. Local PNGs show reference, current, and a white mask of different palette indices; they use the base palette and square pixels. Commercial image content remains under ignored `local/`.

The first E1M1 comparison found 1,511 differing HUD pixels at each heading. Inspection showed missing weapon-ownership digits, ignored patch-origin offsets (including the face), and variable-width digit placement. These are presentation defects, not campaign-bot failures. The new HUD path now respects WAD patch offsets, renders the six ownership indicators, spaces numbers by the zero glyph width, and copies unlit palette indices directly. It also follows the reference's three-digit truncation, negative-number clamp/minus, and 1994 sentinel behavior. The world renderer's patch path is unchanged.

| Heading | Initial scene differences / 53,760 | Final scene differences / 53,760 | Initial HUD differences / 10,240 | Final HUD differences / 10,240 |
| --- | ---: | ---: | ---: | ---: |
| 0 | 42,379 | 42,379 | 1,511 | 0 |
| 90 | 36,380 | 36,380 | 1,511 | 0 |
| 180 | 42,700 | 42,700 | 1,511 | 0 |

Receipts: `results/render-reference-e1m1-first.json` and `results/render-reference-e1m1-hud-final.json`. The scene counts are deliberately retained: a repaired HUD does not imply a faithful 3D scene. Texture sampling, lighting and projected boundaries need separate diagnosis and a trusted external reference. Raw palette-index disagreement is not a perceptual quality score.

An intermediate diagnostic (`render-reference-e1m1-hud.json`) observed 171 remaining HUD differences, leading to the fixed-width number repair. The source file changed around completion of that run, and its end-only hash cannot reliably identify the loaded implementation. Treat that receipt as diagnostic history, not source-qualified evidence. The final comparison and HUD suite record source hashes before work and report any changes at completion; neither final run reports changed sources.

## Broader HUD checks

`scripts/Test-HudReference.ps1` passes 64 synthetic single-player states against the adopted status renderer, comparing all 10,240 HUD indices for each. States cover all 64 weapon/key bit combinations, every face index, ready weapons including no-ammo weapons, and numeric boundaries including negative values and the sentinel. The same states also match after real binary asset serialization and seven uneven drawing strips. This checks the flattened ownership-patch array used by render workers without changing the asset format.

`results/hud-reference-first.json` retains these 64 checks. `results/render-partitions-hud-matrix.json` additionally matches 320,000 complete image pixels across five views and seven actual rendering processes, plus 35 Matrix/katakana encoded-strip comparisons at a fixed frame number and viewport origin. No console is presented by these checks, so these are not recordings or display-FPS evidence. Classic and color-art share the corrected source image; their latest live captures still predate this change.

## Remaining work

Compare additional real gameplay endpoints, moving sectors, sprites, sky, palettes and invisibility against an independently established reference. Diagnose sampling and lighting differences separately before changing 3D algorithms. Measure full-host pacing after presentation changes. Record the next E1M4-to-E1M5 terminal continuation with the completed seven-track catalog, retaining footage and audio evidence. Campaign completion, sound at the speakers and 35/60 pacing remain separate gates.

## Fixed-lighting diagnostic

A subsequent `-FixedColorMap 16` fixture applies the same explicit override to the live reference player and numeric snapshot. Scene disagreement falls to 15,772 / 16,347 / 15,603 pixels for headings 0 / 90 / 180; all three HUDs remain exact. Receipt: `results/render-reference-e1m1-fixed16.json`, with unchanged source pins during the run. Source inspection shows different distance-lighting formulas and missing horizontal/vertical wall contrast in the current renderer. This makes lighting a concrete next investigation. A darker common palette can also merge different texel colors, so the reduced mismatch is not a mathematical partition of all errors into lighting versus geometry. No production lighting algorithm changed in this diagnostic.

The corrected HUD is now exercised in the [recorded E1M4 continuation](campaign-e1m4.md). Its full-host performance and audio limits remain visible there. The next rendering step is to compare the 16-level scale/distance light tables and their wall-orientation, sector, extra-light and fixed-map selection against the adopted reference, then check actual images and cost before adoption. A trusted original-executable reference is still needed for a vanilla-fidelity claim.