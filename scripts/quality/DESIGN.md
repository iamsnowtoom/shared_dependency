---
name: quality-report-design
version: "1.1"
scope: scripts/quality/generate-report.py (live), scripts/quality/template.html (reference)
theme: github-dark (default dark, light available)
layout: simple-main (current live) / sidebar-main (template.html reference)
---

# Quality Report — Design Spec

> **Live HTML owner:** `generate-report.py` → `render_html()`. This function writes the inline CSS/JS/HTML to `quality-report.html`. `template.html` is a reference design (richer sidebar/main layout) and is **not** wired into generation yet.
>
> To apply `template.html` as the live source: update `render_html()` to read `template.html` and substitute content into `<!-- INJECT_BODY -->` / `// INJECT_DATA`.

Source of truth for visual design. Change tokens here first, then apply to `render_html()` (and `template.html` if used). The output must remain self-contained (inline CSS/JS, no build step).

## Layout model

```
┌──────────────────────┬────────────────────────────────────────────┐
│  Sidebar (320px)     │  Main content (flex: 1)                    │
│  File navigator      │  ┌── Gate banner ─────────────────────┐   │
│  • Duplicates tab    │  │  PASSED / FAILED + metrics          │   │
│  • Coverage tab      │  └────────────────────────────────────┘   │
│                      │  ┌── Stat cards (4-col grid) ──────────┐   │
│  Sidebar hidden when │  └────────────────────────────────────┘   │
│  on Overview tab.    │  ┌── Tab bar ─────────────────────────┐   │
│                      │  │  Overview · Duplicates · Coverage   │   │
│                      │  └────────────────────────────────────┘   │
│                      │  Tab panel content                         │
└──────────────────────┴────────────────────────────────────────────┘
```

- `--layout-sidebar-width: 320px` controls sidebar width.
- Sidebar is conditionally shown/hidden via `switchMainTab()` JS.
- Theme toggle button is fixed `top: 16px; right: 24px` above the main area.

## Color tokens

### Dark theme (default `:root`)

| Token | Value | Usage |
|---|---|---|
| `--color-canvas-dark` | `#0d1117` | Page background |
| `--color-surface-dark` | `#161b22` | Card / sidebar background |
| `--color-surface-raised-dark` | `#21262d` | Elevated surfaces, modal headers |
| `--color-border-dark` | `#30363d` | All borders |
| `--color-text-dark` | `#e6edf3` | Primary text |
| `--color-text-muted-dark` | `#8b949e` | Secondary / dimmed text |
| `--color-success-dark` | `#3fb950` | Pass state, covered lines |
| `--color-danger-dark` | `#f85149` | Fail state, uncovered lines |
| `--color-accent-dark` | `#58a6ff` | Links, active tabs, focus rings |
| `--color-warning-dark` | `#d29922` | Warning badges |
| `--color-info-dark` | `#39d2c0` | Info / coverage accent |

### Light theme (`[data-theme="light"]`)

| Token | Value | Usage |
|---|---|---|
| `--color-canvas` | `#ffffff` | Page background |
| `--color-surface` | `#f6f8fa` | Card / sidebar background |
| `--color-surface-raised` | `#e8ecf0` | Elevated surfaces |
| `--color-border` | `#d0d7de` | All borders |
| `--color-text` | `#1f2328` | Primary text |
| `--color-text-muted` | `#656d76` | Secondary text |
| `--color-success` | `#1a7f37` | Pass state |
| `--color-danger` | `#cf222e` | Fail state |
| `--color-accent` | `#0969da` | Links, active tabs, focus rings |
| `--color-warning` | `#9a6700` | Warning badges |
| `--color-info` | `#0550ae` | Info accent |

### Theme switching

- Attribute: `data-theme="light"` on `<html>` (default is dark in `:root`, flipped by `[data-theme="light"]`).
- JS key: `localStorage.getItem('dup-report-theme')` → `'dark'` | `'light'`.
- Fallback when no saved preference: `prefers-color-scheme` media query.
- Toggle function: `toggleTheme()` in inline `<script>`.
- highlight.js stylesheet pair: `#hljs-light` / `#hljs-dark` swapped alongside the theme.

## Legacy CSS aliases

These aliases map short legacy names to semantic tokens. Keep them — generated report HTML uses them.

```css
--bg       → --color-canvas
--surface  → --color-surface
--surface2 → --color-surface-raised
--border   → --color-border
--text     → --color-text
--text-dim → --color-text-muted
--green    → --color-success
--red      → --color-danger
--blue     → --color-accent
--yellow   → --color-warning
--cyan     → --color-info
--sidebar-w → --layout-sidebar-width
--code-bg  → --color-code-bg
--badge-text → --color-on-badge
--gate-pass-bg → --color-gate-pass-bg
--gate-fail-bg → --color-gate-fail-bg
--filter-bg → --color-filter-bg
--active-bg → --color-active-bg
```

## Typography

| Token | Value |
|---|---|
| `--font-sans` | `'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif` |
| `--font-mono` | `'JetBrains Mono', 'SF Mono', SFMono-Regular, Consolas, monospace` |

Loaded from Google Fonts CDN (`Inter` + `JetBrains Mono`). The template falls back to system fonts if offline.

## Spacing scale

| Token | Value |
|---|---|
| `--space-1` | `4px` |
| `--space-2` | `6px` |
| `--space-3` | `8px` |
| `--space-4` | `10px` |
| `--space-5` | `12px` |
| `--space-6` | `14px` |
| `--space-7` | `16px` |
| `--space-8` | `20px` |
| `--space-9` | `24px` |

## Border radius

| Token | Value |
|---|---|
| `--radius-sm` | `4px` |
| `--radius-md` | `6px` |
| `--radius-lg` | `8px` |
| `--radius-xl` | `10px` |
| `--radius-pill` | `20px` (theme toggle, badges) |

## Shadows / elevation

| Token | Value | Usage |
|---|---|---|
| `--shadow-card` | `0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.08)` | Resting card |
| `--shadow-card-hover` | `0 4px 12px rgba(0,0,0,0.20), 0 2px 4px rgba(0,0,0,0.12)` | Hovered stat card |
| `--shadow-popover` | `0 18px 60px rgba(0,0,0,0.35)` | Copilot prompt modal |

## Motion

| Token | Value |
|---|---|
| `--duration-fast` | `0.15s` |
| `--duration-med` | `0.2s` |

Transitions use `ease` by default (browser default). Do not add `prefers-reduced-motion` overrides unless reported as an issue.

## Core components

### Gate banner
```html
<div class="gate passed|failed">PASSED | FAILED — …metrics…</div>
```
- `.passed` → `--color-gate-pass-bg` background, `--color-success` text/border.
- `.failed` → `--color-gate-fail-bg` background, `--color-danger` text/border.

### Stat cards
```html
<div class="stats">
  <div class="stat-card">
    <div class="stat-value">…</div>
    <div class="stat-label">…</div>
  </div>
</div>
```
- 4-column grid. Drops to 2-column below 1000px.
- Hover: `--shadow-card-hover` + `--color-accent` border.

### Sidebar file tree
- Folder/file nodes rendered by `generate-report.py` inside `<!-- INJECT_BODY -->`.
- Active file: `--color-active-bg` background.
- Tab underline: `--color-accent`.

### Theme toggle button
```html
<button class="theme-toggle" onclick="toggleTheme()" aria-label="Toggle colour theme">
  <span class="theme-toggle-icon" id="themeIcon">☀</span>
  <span id="themeLabel">Light</span>
</button>
```
- Fixed position, top-right, `z-index: 999`.
- IDs `themeIcon` and `themeLabel` are required — the JS IIFE and `toggleTheme()` update them.

### Copilot prompt modal
- Triggered per-file via `.copilot-btn`.
- `z-index: 2000`, dimmed backdrop via `--color-overlay`.
- Close via Escape key or clicking outside.

## Editing guidelines

- **Tokens first**: change a colour or size in `:root` / `[data-theme="light"]`, not inline.
- **Legacy aliases**: do not remove or rename — generated HTML depends on them.
- **Self-contained**: template must work by opening the HTML file directly. No external assets except CDN fonts/highlight.js.
- **Inject placeholders**: `<!-- INJECT_BODY -->` and `// INJECT_DATA` are replaced at generation time. Do not move or duplicate them.
- **Sidebar visibility**: controlled by `switchMainTab()`. Do not hard-code `display: none` on `.sidebar`.
- **Dark default**: `:root` holds dark values; `[data-theme="light"]` overrides. Keep this direction — inverting it would break the startup IIFE logic.
