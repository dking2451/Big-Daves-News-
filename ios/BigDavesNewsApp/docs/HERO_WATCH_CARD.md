# Tonight’s Pick — `HeroWatchCardView`

## Why this layout

| Choice | Effect |
|--------|--------|
| **Full-bleed poster + gradient** | One dominant object; text stays readable without a separate “card inside a card.” |
| **Top label + optional badge** | “Tonight’s pick” is scannable; status (“New Episode” / “New”) is in a predictable corner. |
| **Title → subtitle → provider** | Matches how people decide: *what* → *context* → *where*. |
| **Actions in a separate bar** | Avoids competing tap targets; matches common streaming patterns. |

**Cognitive load vs. list rows:** List cells mix poster, title, meta, score, and many icons in one horizontal band. The hero stacks **priority** vertically and hides secondary metrics, so the first fixation lands on the title and primary CTA.

## Files

- `Sources/HeroWatchCardView.swift` — `HeroWatchCardModel`, `HeroWatchCardView`, previews.
- `WatchView` — builds `HeroWatchCardModel(show:)` from `WatchShowItem`; **Watch Now** → `StreamingProviderLauncher.open`; **Save** → existing save API.

Broader Watch chrome (header bookmark / filter, Saved list screen): [`WATCH_TAB.md`](WATCH_TAB.md).

## Behavior

- **Watch Now:** Opens the provider using the shared launcher (app → web → App Store fallbacks).
- **Save:** Toggles saved state via existing `setSaved`.
- **Card tap (poster + text):** On iPad split layout, selects the show for the detail column + light haptic. On iPhone, `onCardTap` is `nil` until a dedicated detail route exists (buttons still work).

## Customization

Add fields to `HeroWatchCardModel` or adjust `HeroWatchCardModel.init(show:)` if the API gains short taglines or marketing copy for the subtitle.
