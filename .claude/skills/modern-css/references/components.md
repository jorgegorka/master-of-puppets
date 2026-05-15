# Components

Recipes for the components in `app/assets/stylesheets/`. Each component
configures via CSS custom properties — to make a variant, override
those properties rather than write a new selector tree.

## Buttons

### Base

```css
.btn {
  --btn-background:    var(--color-canvas);
  --btn-border-color:  var(--color-ink-lighter);
  --btn-color:         inherit;
  --btn-padding:       0.5em 1.25em;
  --btn-font-weight:   500;
  --btn-border-radius: 99rem;

  background: var(--btn-background);
  border:     1px solid var(--btn-border-color);
  color:      var(--btn-color);
  padding:    var(--btn-padding);
  font-weight:   var(--btn-font-weight);
  border-radius: var(--btn-border-radius);
}
```

### Variants

| Class | Purpose |
|---|---|
| `.btn--link` | Text-only, no background |
| `.btn--plain` | Minimal styling |
| `.btn--circle` | Circular icon button |
| `.btn--negative` | Destructive (red) |
| `.btn--positive` | Affirmative (green) |
| `.btn--reversed` | Inverted colors |
| `.btn--circle-mobile` | Circle on small screens |

A variant looks like this — only the custom properties that change:

```css
.btn--negative {
  --btn-background: var(--color-negative);
  --btn-color:      var(--color-canvas);
}
```

### States

```css
.btn:disabled { opacity: 0.3; pointer-events: none; }
```

Loading state: `form[aria-busy] button:disabled` overlays a `submitting`
spinner via the global `.btn--success` / `form[aria-busy]` rules.

### Icon-only buttons

Buttons with only an icon (detected via `aria-label` or
`.for-screen-reader` child) auto-size to a square:

```css
.btn[aria-label]:where(:has(.icon)),
.btn:where(:has(.for-screen-reader):has(.icon)) {
  --btn-padding: 0;
  --icon-size:   75%;
  aspect-ratio:  1;
  display:       grid;
  place-items:   center;
}
```

Usage:

```erb
<%= button_to path, class: "btn", aria: { label: "Edit" } do %>
  <%= icon_tag "pencil" %>
<% end %>
```

## Inputs

### Base

```css
.input {
  --input-accent-color: var(--color-ink);
  --input-background:   transparent;
  --input-border-radius: 0.5em;
  --input-border-color: var(--color-ink-medium);
  --input-border-size:  1px;
  --input-color:        var(--color-ink);
  --input-padding:      0.5em 0.8em;

  font-size:   max(16px, 1em);    /* prevents iOS zoom */
  inline-size: 100%;
  resize:      none;
}
```

### Text input

```erb
<%= form.text_field :name, class: "input", placeholder: "Enter name…" %>
```

### Actor input pattern

A label wraps the input to act as the visual container, giving a
larger touch target:

```erb
<label class="flex align-center gap input input--actor">
  <%= icon_tag "search" %>
  <%= form.text_field :query, class: "input full-width", placeholder: "Search…" %>
</label>
```

```css
.input--actor {
  &:focus-within {
    --input-border-color: var(--color-selected-dark);
    outline: var(--focus-ring-size) solid var(--focus-ring-color);
  }

  .input {
    --input-padding:     0;
    --input-border-size: 0;
    --input-background:  transparent;
  }
}
```

### Select

```erb
<%= form.select :status, options, {}, class: "input input--select" %>
```

```css
.input--select {
  --input-border-radius: 2em;
  --input-padding: 0.5em 1.8em 0.5em 1.2em;
  appearance: none;
  background-image:    url("caret-down.svg");
  background-position: right 0.5em center;
  background-repeat:   no-repeat;
  background-size:     1em;
}
```

### Textarea (auto-resize)

```erb
<%= form.text_area :description, class: "input input--textarea", rows: 1 %>
```

```css
.input--textarea {
  min-block-size: calc(3lh + (2 * var(--input-padding)));

  @supports (field-sizing: content) {
    field-sizing:    content;
    max-block-size:  calc(3lh + (2 * var(--input-padding)));
    min-block-size:  calc(1lh + (2 * var(--input-padding)));
  }
}
```

### File input (hidden, label as button)

```erb
<label class="btn input--file">
  <%= icon_tag "upload" %>
  <span>Choose file</span>
  <%= form.file_field :attachment, class: "input", accept: "image/*" %>
</label>
```

```css
.input--file {
  cursor:      pointer;
  display:     grid;
  place-items: center;

  input[type="file"] {
    cursor:    pointer;
    font-size: 0;
    inset:     0;
    opacity:   0;
    position:  absolute;
  }
}
```

### One-time code

```erb
<%= form.text_field :code, class: "input", autocomplete: "one-time-code" %>
```

```css
.input[autocomplete='one-time-code'] {
  font-family:    var(--font-mono);
  font-size:      var(--text-large);
  font-weight:    900;
  inline-size:    18ch;
  letter-spacing: 1ch;
  text-align:     center;
}
```

### Input states

```css
.input:focus {
  outline:        var(--focus-ring-size) solid var(--focus-ring-color);
  outline-offset: -1px;
}

.input:disabled {
  cursor:         not-allowed;
  opacity:        0.5;
  pointer-events: none;
}

.input[readonly] { --focus-ring-size: 0; }

.input:autofill,
.input:-webkit-autofill {
  -webkit-text-fill-color: var(--color-ink);
  -webkit-box-shadow:      0 0 0px 1000px var(--color-selected) inset;
}
```

### Input variable reference

| Property | Default | Purpose |
|---|---|---|
| `--input-accent-color` | `var(--color-ink)` | Checkbox/radio accent |
| `--input-background` | `transparent` | Background |
| `--input-border-radius` | `0.5em` | Corner radius |
| `--input-border-color` | `var(--color-ink-medium)` | Border |
| `--input-border-size` | `1px` | Border width |
| `--input-color` | `var(--color-ink)` | Text |
| `--input-padding` | `0.5em 0.8em` | Padding |

## Switch (toggle)

```erb
<label class="switch">
  <%= form.check_box :enabled, class: "switch__input" %>
  <span class="switch__btn"></span>
  <span class="for-screen-reader">Enable feature</span>
</label>
```

```css
.switch {
  --switch-color: var(--color-ink-medium);
  block-size:     1.75em;
  inline-size:    3em;
  border-radius:  2em;
}

.switch__btn {
  background-color: var(--switch-color);
  transition:       150ms ease;

  &::before {
    background-color: var(--color-ink-inverted);
    block-size:       1.35em;
    border-radius:    50%;
    transition:       150ms ease;
  }
}

.switch__input:checked + .switch__btn {
  --switch-color: var(--color-link);

  &::before { transform: translateX(1.2em); }
}

.switch__input:disabled + .switch__btn {
  cursor:  not-allowed;
  opacity: 0.5;
}
```

## Checkboxes / radios as buttons

Style native checkboxes and radios as toggle buttons:

```erb
<label class="btn">
  <%= form.radio_button :color, "red" %>
  Red
</label>
```

```css
.btn:has(input[type=radio], input[type=checkbox]) {
  input {
    appearance: none;
    cursor:     pointer;
    inset:      0;
    position:   absolute;
  }

  &:has(input:checked) {
    --btn-background: var(--color-ink);
    --btn-color:      var(--color-ink-inverted);
  }
}
```

## Cards

```css
.card {
  --card-color:    var(--color-card-default);
  --card-bg-color: color-mix(in srgb, var(--card-color) 4%, var(--color-canvas));
}

.card__header { … }
.card__board  { … }
.card__id     { … }
```

To recolour a card: set `--card-color` on the element. The tinted
background follows automatically.

## Dialogs

Dialogs use CSS transitions with `allow-discrete` for smooth
open/close:

```css
.dialog {
  --dialog-duration: 150ms;
  /* scale from 0.2 to 1 with opacity, transitions allow-discrete */
}
```

## Layout

### Grid header

```css
.header {
  display: grid;
  grid-template-columns: var(--actions-start-size) 1fr var(--actions-end-size);
}

.header--mobile-actions-stack { /* stacked variant for mobile */ }
```

### Main content

```css
body {
  display: grid;
  grid-template-rows: auto 1fr auto 9em;
}

#main {
  inline-size:     100dvw;
  max-inline-size: var(--main-width);
}
```

## Form layout pattern

Use flexbox utilities for the form skeleton; let inputs and labels
flow naturally:

```erb
<%= form_with model: @user, class: "flex flex-column gap" do |form| %>
  <div class="flex flex-column gap-half">
    <label>Email</label>
    <%= form.email_field :email, class: "input" %>
  </div>

  <div class="flex flex-column gap-half">
    <label>Password</label>
    <%= form.password_field :password, class: "input" %>
  </div>

  <button type="submit" class="btn btn--positive">Save</button>
<% end %>
```

### Error display

```erb
<% if @user.errors.any? %>
  <div class="txt-negative txt-small margin-block-half">
    <p class="font-weight-bold margin-block-none">Your changes couldn't be saved:</p>
    <ul class="margin-block-none">
      <% @user.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

### Auto-submit forms

```erb
<%= auto_submit_form_with model: @settings do |form| %>
  <%= form.select :theme, options, {},
        class: "input input--select",
        data: { action: "change->form#submit" } %>
<% end %>
```

## Icons — quick recipes

```erb
<%# basic %>
<%= icon_tag "check" %>

<%# styled %>
<%= icon_tag "pencil", class: "txt-subtle" %>

<%# inside an icon-only button (auto-sized via :has selector) %>
<%= button_to path, class: "btn", aria: { label: "Delete" } do %>
  <%= icon_tag "trash" %>
<% end %>

<%# multi-color icon (mask not supported) %>
<%= image_tag "boost-color.svg", aria: { hidden: true }, class: "icon" %>
```

Icon sizing via context-specific custom properties:

| Context | Size | Variable |
|---|---|---|
| Default | `1em` | `--icon-size` |
| In a button | `1.3em` | `--btn-icon-size` |
| Header button | `1rem` | `--btn-icon-size` |
| Popup | `24px` | `--popup-icon-size` |
| Navigation | `2em` | `--icon-size` |
| Card metadata | `0.9em` | `--icon-size` |
