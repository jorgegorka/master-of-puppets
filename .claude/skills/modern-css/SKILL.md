---
name: modern-css
description: Use whenever editing or generating CSS for master-of-puppets, or when asked about styling, colors, typography, spacing, components, layout, icons, design tokens, or dark mode. The app uses pure custom CSS — no Tailwind, no Bootstrap, no utility framework — built on CSS @layer, OKLCH color, semantic custom properties, and logical properties for RTL support. Load this skill BEFORE writing styles so OKLCH tokens, layer ordering, logical-property naming, and component variables match the existing system instead of generic CSS conventions. Includes the icon system (mask-image with currentColor) and forms (CSS custom properties per input variant).
---

# Modern CSS — Project Styling

This project uses **pure custom CSS**. There is no Tailwind, no
Bootstrap, no utility framework. Styling relies on modern CSS features:
`@layer` for predictable specificity, OKLCH color for perceptual
uniformity, CSS custom properties for theming, and logical properties
(`block`/`inline`) for RTL support.

The canonical reference is `docs/style-guide.md`. This skill is the
working distillation.

## The mindset

- **Use semantic variables, never raw values.** Write
  `color: var(--color-ink)`, not `color: #1a1a1a`. The same goes for
  fonts, spacing, shadows, z-index.
- **Use logical properties, not physical.** Write `padding-block-start`,
  not `padding-top`. Write `inline-size`, not `width`. The site supports
  RTL and dark mode through these primitives.
- **Components configure via custom properties.** A `.btn` exposes
  `--btn-background`, `--btn-color`, `--btn-padding`, etc. Variants
  override those properties instead of duplicating selectors.
- **Existing utilities first.** Before writing new CSS, check whether
  a `.flex`, `.pad`, `.txt-small`, `.gap`, `.border-radius` already
  exists. The system is dense; most layouts don't need new CSS.

## Layer order — non-negotiable

```css
@layer reset;       /* browser normalization */
@layer base;        /* element styles */
@layer components;  /* button, input, card, dialog */
@layer modules;     /* feature-scoped CSS */
@layer utilities;   /* .flex, .pad, .txt-* */
@layer native;      /* native-app overrides */
@layer platform;    /* platform-specific */
```

Place new component CSS in `@layer components`, new feature CSS in
`@layer modules`, new utility classes in `@layer utilities`. Never
write CSS outside a layer — it wins specificity wars unintentionally.

## File organization

Styles live in `app/assets/stylesheets/`:

```
_global.css     root variables + layer definitions
base.css        base element styling (html, body, headings)
utilities.css   layout/typography/spacing utilities
buttons.css     .btn and variants
inputs.css      form inputs
cards.css       .card and variants
layout.css      grid layout, header, main
header.css      header component
dialog.css      modals, popups
animation.css   keyframes
<feature>.css   feature-specific (e.g. cards.css)
```

One file per concern. Variables for the design system go in
`_global.css`; feature variables go in their feature file.

## Color — OKLCH, layered

Colors are defined in OKLCH for perceptual consistency across light
and dark modes. The system has two levels:

**Raw palette** — perceptual triples, never used directly in components:

```css
--lch-black: 0% 0 0;
--lch-white: 100% 0 0;
--lch-blue-medium: …;
--lch-red-medium: …;
```

**Semantic aliases** — what components actually use:

```css
--color-ink         /* primary text */
--color-ink-light   /* secondary text */
--color-ink-lighter /* tertiary / muted */
--color-canvas      /* background */
--color-link        /* interactive blue */
--color-positive    /* success green */
--color-negative    /* error red */
--color-highlight   /* yellow marker */
```

In components, always reference the semantic alias. The raw `--lch-*`
values only appear in `_global.css` (to define the semantic alias) or
when you need `oklch(var(--lch-x) / 50%)` for explicit alpha.

### Card colors and tints

Cards use 8 categorical colors plus default/complete. Backgrounds use
`color-mix` for subtle tints:

```css
.card {
  --card-color: var(--color-card-default);
  background: color-mix(in srgb, var(--card-color) 4%, var(--color-canvas));
}
```

When you need a tinted background of any color, prefer `color-mix`
over hand-picked hex values — the result tracks dark mode automatically.

## Spacing — logical properties everywhere

Base variables:

```css
--inline-space:        1ch;     /* horizontal rhythm */
--inline-space-half:   0.5ch;
--inline-space-double: 2ch;

--block-space:        1rem;     /* vertical rhythm */
--block-space-half:   0.5rem;
--block-space-double: 2rem;
```

Utility classes (use these rather than writing margin/padding):

```
.pad                .margin              .gap, .gap-half, .gap-none
.pad-double         .margin-block        .flex, .flex-column, .flex-1
.pad-block          .margin-inline       .justify-*, .align-*
.pad-inline         .margin-block-half
.pad-block-half     .margin-block-double
.unpad              .center              .full-width, .max-width
```

`.center` sets `margin-inline: auto`. `.gap` works with `.flex`.
`.full-width` sets `inline-size: 100%`.

## Typography

```
--text-xx-small  --text-x-small  --text-small  --text-normal
--text-medium    --text-large    --text-x-large --text-xx-large
```

Each scales mobile-up via `clamp()`. Use `.txt-small`, `.txt-large`,
etc., on elements. Color variants: `.txt-subtle`, `.txt-negative`,
`.txt-positive`, `.txt-alert`. Weight: `.font-weight-black` (900),
`.font-weight-normal` (400), `.font-weight-bold`.

For font sizes, never use `px`. Use `rem` or the `--text-*` variables.

## Components configure via custom properties

The button is the archetype. The component sets defaults; variants
override custom properties:

```css
.btn {
  --btn-background: var(--color-canvas);
  --btn-border-color: var(--color-ink-lighter);
  --btn-color: inherit;
  --btn-padding: 0.5em 1.25em;
  --btn-font-weight: 500;
  --btn-border-radius: 99rem;
}

.btn--negative { --btn-background: var(--color-negative); --btn-color: var(--color-canvas); }
.btn--positive { --btn-background: var(--color-positive); --btn-color: var(--color-canvas); }
.btn--circle   { aspect-ratio: 1; --btn-padding: 0; }
```

New variants follow the same shape: a single CSS rule overriding
exactly the custom properties that change. Don't duplicate the base
selector.

When you make a new component, expose `--<name>-*` variables for
anything a caller might reasonably tweak (background, color, padding,
radius).

## Routing table — load when you need depth

| If you're working on… | Read |
|---|---|
| Colors, type scale, spacing tokens | `references/tokens.md` |
| Buttons, inputs, cards, dialogs, switches | `references/components.md` |

The body of this skill is enough for most styling tasks; load the
references when you need the full palette or a component recipe you
don't remember.

## Icons — mask-image with currentColor

Icons are individual SVGs in `app/assets/images/`. Render with the
`icon_tag` helper:

```erb
<%= icon_tag "check" %>
<%= icon_tag "pencil", class: "txt-subtle" %>
```

The helper outputs `<span class="icon icon--check" aria-hidden="true"></span>`.
The CSS uses `mask-image` with `background-color: currentColor`, so
icons inherit colour from their parent text colour. Size via
`--icon-size` (default `1em`).

SVG requirements: `viewBox="0 0 24 24"` (or 32), no `width`/`height`
attributes, monochrome with `fill="currentColor"` or no fill. For
multi-colour icons, fall back to `image_tag "name-color.svg"` —
naming convention `*-color.svg`.

## Forms — inputs configure via custom properties

The `.input` base exposes `--input-background`, `--input-border-color`,
`--input-padding`, etc. Variants like `.input--select`,
`.input--textarea`, `.input--actor` override those. iOS auto-zoom is
prevented with `font-size: max(16px, 1em)` on every input.

Wrap inputs in labels for larger touch targets (`.input--actor` pattern).
Textareas use `field-sizing: content` for auto-resize. See
`references/components.md` for the full input catalogue.

## Dark mode

Dark mode reuses the same semantic variables; only the OKLCH palette
shifts. Triggered by `html[data-theme="dark"]` or by
`@media (prefers-color-scheme: dark)` when no explicit theme is set.

If you write a new component and reference only semantic variables,
dark mode "just works." If you hard-code an OKLCH or hex, you'll
break it.

## Z-index — use the named scale

Don't invent new z-indexes. The scale is centralised:

```css
--z-events-column-header: 1
--z-events-day-header:    3
--z-popup:                10
--z-nav:                  20
--z-flash:                30
--z-tooltip:              40
--z-bar:                  50
--z-tray:                 51
--z-welcome:              52
--z-nav-open:             100
```

If you genuinely need a new stacking layer, add it to the scale in
`_global.css` with a comment explaining what stacks above and below.

## Animations and transitions

Default transition: `100ms ease-out` on
`background-color, border-color, box-shadow, filter, outline`.

Named easings:

```css
--ease-out-expo:             cubic-bezier(0.16, 1, 0.3, 1);
--ease-out-overshoot:        cubic-bezier(0.25, 1.75, 0.5, 1);
--ease-out-overshoot-subtle: cubic-bezier(0.25, 1.25, 0.5, 1);
```

Reusable keyframes: `shake`, `react`, `scale-fade-out`, `slide-up`,
`slide-down`, `slide-up-fade-in`, `pulse`, `submitting`, `success`,
`wiggle`. Reach for these before writing a new keyframe.

Always honour `@media (prefers-reduced-motion: reduce)` — the global
reset shortens durations to `0.01ms`, so as long as you use
`transition` and `animation` properties (not JS movement) you're
covered.

## Focus states

Every interactive element needs a visible focus ring:

```css
--focus-ring-color:  var(--color-link);
--focus-ring-offset: 1px;
--focus-ring-size:   2px;

:focus-visible {
  outline: var(--focus-ring-size) solid var(--focus-ring-color);
  outline-offset: var(--focus-ring-offset);
}
```

Inputs use an internal offset (`-1px`) for the focus ring to sit
inside the border. Don't strip focus rings; if you don't like the
default, change the variables.

## Quick checklist before finishing CSS

- [ ] No hard-coded colours; only `var(--color-*)`.
- [ ] No `top`/`right`/`bottom`/`left`; only `block`/`inline`
      logical properties.
- [ ] No `width`/`height` where `inline-size`/`block-size` would do.
- [ ] No `px` for font sizes; `rem` or `--text-*`.
- [ ] Rule placed in the right `@layer`.
- [ ] Component exposes its tweakable values as `--<name>-*` custom
      properties.
- [ ] Dark mode tested mentally (only semantic variables referenced).
- [ ] Focus state visible.
- [ ] If a utility already exists for this, use it instead of new CSS.

## See also

- `references/tokens.md` — full palette, type scale, spacing
- `references/components.md` — buttons, inputs, cards, dialogs, switches
- `docs/style-guide.md` — canonical source
