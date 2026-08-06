# Neon Notch design QA

This document records the visual QA baseline for the notch silhouette and standby behavior. It uses only tracked, repository-relative evidence.

## Evidence

- [Approved visual target](../Design/neon-notch-visual-target.png)
- [Normalized implementation comparison](../Design/design-qa-smoke-comparison.png)
- [Expanded panel capture](assets/neon-notch-hero.png)

The visual target is `1487 × 1058 px`. The expanded panel was rendered at `1120 × 380 pt` on a Retina display and captured at `2240 × 760 px` (`@2x`). The normalized comparison is `1500 × 1642 px`.

## Full-panel comparison

The implementation retains the target's horizontal structure: a central notch cutout, three agent rows, lateral metrics, and Spotify only in the footer. The base is a single silhouette. Its taper begins at the top of the `72 pt` footer, uses two Bézier segments per side, and finishes with a filled lower center and transparent outer sides.

The interior uses an opaque petrol base with a restrained smoky gradient. Desktop pixels appear only outside the silhouette; the panel does not expose legible desktop texture or text. A cyan-to-magenta edge and inner glow keep the neon direction of the target without making standby a permanent capsule.

## States and interaction

- **Standby:** no opaque `NSPanel` pixels, dots, capsule, or halo appear below the notch.
- **Alert:** only a `0.5 pt` outline follows the notch sides and base; it adds no fill or indicators.
- **Hover:** the panel reaches `600 × 142 pt` before content is revealed, avoiding a horizontal crop.
- **Rapid changes:** enter → leave → enter cancels a pending collapse and ends at `600 × 142 pt`.
- **Collapse:** content hides for `160 ms` before the frame returns to `notchWidth + 16 pt` by `notchHeight + 8 pt`.
- **Expanded Spotify:** decorative layers do not participate in hit testing. Back/restart, play/pause, and next retain independent targets.
- **Expanded clipboard:** four rows remain visible without moving the metrics or footer; further content scrolls within the same silhouette.

## Fidelity checks

- SF Pro typography and existing weights are preserved; labels do not truncate.
- The body ends exactly where the footer starts; album art, dividers, controls, and Spotify are centered in a `600 pt` useful area and do not cross the curves.
- Cyan, magenta, and green retain their existing meaning; smoky glass uses opaque base colors only.
- Album art keeps its crop and sharpness within the silhouette, with no asset substitution.
- Existing task, state, and label copy is preserved; the footer remains intentionally spare.

## Iteration record

### Iteration 1

- **P1:** Standby previously rendered a persistent capsule and two dots.
  - **Fix:** Removed the background and indicators; added an alert-only outline.
- **P1:** AppKit and SwiftUI animated together, allowing oversized content in an intermediate frame.
  - **Fix:** Separated `panelState` from `renderedState`; AppKit resizes before reveal and shrinks after conceal.

### Iteration 2

- **P2:** On the first revised curve, album art and the Spotify label still reached the transparent lower area.
  - **Fix:** Aligned the footer to the target with a compact, one-line composition and `600 pt` of useful width.

## Result

The recorded QA pass found no remaining P0, P1, or P2 issues. A P3 follow-up remains: tune halo intensity against very light wallpapers without changing the geometry.
