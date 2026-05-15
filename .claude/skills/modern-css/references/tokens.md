# Design Tokens

The complete catalogue of CSS custom properties. Reference this when
the SKILL.md summary doesn't tell you which variable to reach for.

## Color — raw OKLCH palette

Defined in `_global.css`. Never reference these directly in component
CSS — use the semantic aliases below.

```
--lch-black:  0% 0 0
--lch-white:  100% 0 0
```

Each family has 7+ intensity levels (lightest → darkest):

```
--lch-ink-1    --lch-ink-2  …  --lch-ink-8       (neutrals)
--lch-red-1    --lch-red-2  …  --lch-red-7
--lch-yellow-1 …
--lch-lime-1   …
--lch-green-1  …
--lch-aqua-1   …
--lch-blue-1   …
--lch-violet-1 …
--lch-purple-1 …
--lch-pink-1   …
```

Use these in OKLCH with explicit alpha when needed:

```css
background: oklch(var(--lch-blue-medium) / 30%);
```

## Color — semantic aliases (use these)

| Variable | Purpose |
|---|---|
| `--color-ink` | Primary text |
| `--color-ink-light` | Secondary text |
| `--color-ink-lighter` | Tertiary / muted text |
| `--color-ink-medium` | Borders, dividers |
| `--color-ink-inverted` | Text on dark backgrounds |
| `--color-canvas` | Page / element background |
| `--color-selected` | Selected row background |
| `--color-selected-dark` | Selected row, darker variant |
| `--color-link` | Interactive blue |
| `--color-positive` | Success green |
| `--color-negative` | Error red |
| `--color-highlight` | Yellow marker / focus highlight |

### Card colors

8 categorical card colours plus default and complete:

```css
--color-card-1  --color-card-2  …  --color-card-8
--color-card-default
--color-card-complete
```

Backgrounds use `color-mix` for tints:

```css
background: color-mix(in srgb, var(--card-color) 4%, var(--color-canvas));
```

## Typography

### Font stack

```css
--font-sans: "Adwaita Sans", -apple-system, BlinkMacSystemFont,
             "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif,
             "Apple Color Emoji", "Segoe UI Emoji";
--font-serif: ui-serif, serif;
--font-mono:  ui-monospace, monospace;
```

### Text size scale

| Variable | Desktop | Mobile |
|---|---|---|
| `--text-xx-small` | 0.55rem | 0.65rem |
| `--text-x-small`  | 0.75rem | 0.85rem |
| `--text-small`    | 0.85rem | 0.95rem |
| `--text-normal`   | 1rem    | 1.1rem  |
| `--text-medium`   | 1.1rem  | 1.2rem  |
| `--text-large`    | 1.5rem  | 1.5rem  |
| `--text-x-large`  | 1.8rem  | 1.8rem  |
| `--text-xx-large` | 2.5rem  | 2.5rem  |

### Typography utilities

```
.txt-xx-small  .txt-x-small  .txt-small  .txt-normal  .txt-medium  .txt-large
.txt-ink  .txt-subtle  .txt-negative  .txt-positive  .txt-alert
.txt-tight-lines       /* reduced line-height */
.font-weight-black     /* 900 */
.font-weight-normal    /* 400 */
.font-weight-bold
```

### Global rendering

```css
-webkit-font-smoothing: antialiased;
-moz-osx-font-smoothing: grayscale;
text-rendering: optimizeLegibility;
line-height: 1.375;
```

## Spacing

### Base variables

```css
--inline-space:        1ch;
--inline-space-half:   0.5ch;
--inline-space-double: 2ch;

--block-space:        1rem;
--block-space-half:   0.5rem;
--block-space-double: 2rem;
```

### Layout sizing

```css
--main-padding: clamp(1ch, 3vw, 3ch);
--main-width:   1400px;
```

### Padding utilities

```
.pad                /* full padding */
.pad-double         /* 2× padding */
.pad-block          /* vertical only */
.pad-block-start    /* top only */
.pad-block-end      /* bottom only */
.pad-block-half     /* half vertical */
.pad-inline         /* horizontal only */
.pad-inline-start   /* left only (LTR) */
.pad-inline-end     /* right only (LTR) */
.pad-inline-half    /* half horizontal */
.unpad
.unpad-block-end
.unpad-inline
```

### Margin utilities

```
.margin             .margin-block         .margin-inline
.margin-block-start .margin-block-end     .margin-block-half  .margin-block-double
.margin-inline-start .margin-inline-end
.center             /* margin-inline: auto */
.margin-none .margin-block-none .margin-inline-none
```

## Borders and radii

```css
--border-color:   var(--color-ink-lighter);
--border-radius:  0.5em;
```

Utilities:

```
.border          /* 1px solid var(--border-color) */
.border-block    /* top + bottom only */
.border-top
.border-bottom
.borderless
.border-radius   /* uses --border-radius */
```

## Shadows

```css
--shadow:
  0 0 0 1px        oklch(var(--lch-black) / 5%),
  0 0.2em 0.2em    oklch(var(--lch-black) / 5%),
  0 0.4em 0.4em    oklch(var(--lch-black) / 5%),
  0 0.8em 0.8em    oklch(var(--lch-black) / 5%);
```

Utility: `.shadow` applies the layered shadow.

Dark mode redefines `--shadow` with six layers instead of four for
deeper depth — components don't need to know.

## Animations

### Easings

```css
--ease-out-expo:             cubic-bezier(0.16, 1, 0.3, 1);
--ease-out-overshoot:        cubic-bezier(0.25, 1.75, 0.5, 1);
--ease-out-overshoot-subtle: cubic-bezier(0.25, 1.25, 0.5, 1);
```

Default transition (applied to most interactive elements):

```css
transition: 100ms ease-out;
transition-property: background-color, border-color, box-shadow, filter, outline;
```

### Reusable keyframes

| Name | Purpose |
|---|---|
| `shake` | Horizontal error shake |
| `react` | Scale up reaction |
| `scale-fade-out` | Shrink + fade |
| `slide-up`, `slide-down` | Vertical movement |
| `slide-up-fade-in` | Combined slide + fade |
| `pulse` | Opacity pulse |
| `submitting` | Spinner animation |
| `success` | Scale on success |
| `wiggle` | Rotation wiggle |

Reuse before authoring a new keyframe. New keyframes live in
`animation.css`.

### Reduced motion

The global stylesheet honours `@media (prefers-reduced-motion: reduce)`:

```css
animation-duration: 0.01ms !important;
transition-duration: 0.01ms !important;
```

## Focus

```css
--focus-ring-color:  var(--color-link);
--focus-ring-offset: 1px;
--focus-ring-size:   2px;
--focus-ring:        2px solid var(--color-link);
```

Applied via `:focus-visible` for keyboard-only styling. Inputs use
`--focus-ring-offset: -1px` so the ring sits inside the border.

## Z-index scale

Don't invent new values. Add to this list in `_global.css` if you
genuinely need a new stacking level.

| Variable | Value | Purpose |
|---|---|---|
| `--z-events-column-header` | 1 | Column headers |
| `--z-events-day-header` | 3 | Day headers |
| `--z-popup` | 10 | Popups / dropdowns |
| `--z-nav` | 20 | Navigation |
| `--z-flash` | 30 | Flash messages |
| `--z-tooltip` | 40 | Tooltips |
| `--z-bar` | 50 | Action bars |
| `--z-tray` | 51 | Side trays |
| `--z-welcome` | 52 | Welcome overlay |
| `--z-nav-open` | 100 | Open navigation |

## Responsive

Breakpoints:

- Small: `< 640px` (mobile)
- Medium: `640px – 800px` (tablet)
- Large: `> 800px` (desktop)

Mobile-first; use `max-width` media queries for larger screens. Prefer
`clamp()` for fluid sizing over hard breakpoints:

```css
--main-padding: clamp(1ch, 3vw, 3ch);
font-size:      clamp(0.85rem, 2vw, 1rem);
```

### Safe area insets

```css
padding-inline:      calc(var(--main-padding) + env(safe-area-inset-left));
padding-block-start: calc(var(--block-space-half) + env(safe-area-inset-top));
```

## Visibility utilities

```
.visually-hidden, .for-screen-reader   /* screen reader only */
[hidden]                                /* display: none */
.display-contents                       /* remove wrapper from layout */

.hide-on-touch     .show-on-touch       /* touch-device gating */
.show-on-native                         /* native app only */
.hide-in-pwa       .hide-in-browser
```

## Flexbox utilities

```
.flex, .flex-inline, .flex-column, .flex-wrap
.flex-1, .flex-item-grow, .flex-item-shrink, .flex-item-no-shrink
.gap, .gap-half, .gap-none
.justify-start, .justify-end, .justify-center, .justify-space-between
.align-start, .align-end, .align-center
```

## Sizing utilities

```
.full-width, .max-width, .half-width
.min-width, .min-content, .fit-content
.overflow-x, .overflow-y
.overflow-ellipsis
.overflow-line-clamp     /* use with --lines custom property */
```
