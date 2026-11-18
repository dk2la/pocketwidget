# Pocket website

The Pocket website: an [Astro](https://astro.build) project that builds to
static files and is served by Cloudflare Workers as static assets. There is no
Worker script. (`worker/` at the repository root is a different thing: the
Trial server.)

## Build

Requires Node 22 or newer. From this directory:

```sh
npm ci && npm run build
```

The site is written to `dist/`.

## Preview

```sh
npm run dev      # development server with live reload, http://localhost:4321
npm run preview  # serves the built dist/ as-is, http://localhost:4321
```

## Layout

- `src/config.ts` — the checkout URL, the download URL and the prices. Every
  Buy and Download button reads them from here. `checkoutURL` must stay equal
  to `LicensingConfig.checkoutURL` in `Sources/Licensing/LicensingConfig.swift`.
- `src/layouts/Base.astro` — the shared layout (head with link preview tags,
  header, footer). Every page wraps its content in it. Props: `title`
  (optional, rendered as "Title — Pocket") and `description` (optional meta
  description). A named `head` slot accepts extra `<head>` tags.
- `src/styles/global.css` — design tokens as CSS custom properties (palette,
  the two font stacks, spacing, layout, easings), plus the shared pieces:
  `.container`, `.section`, `.indent`, the type classes (`.h`, `.lede`,
  `.body`, `.label`), `.marker`, `.btn` and `.prose` for the legal pages. Use
  the tokens instead of raw values. The design rules:
  - Dark only (`color-scheme: dark`); there is no light theme.
  - Everything sits on a 64px grid (`--u`). The ground carries the grid as a
    tiled image, `src/assets/grid.svg`. The content column is 1088px
    (17 units) and text starts one unit (`--indent`) right of the section
    marker.
  - Square corners everywhere except the widget screenshots.
  - The accent green is only for the price band and for Buy buttons on
    hover.
  - Buy and Download appear twice: in the header and in the price section.
    The first screen has no buttons.
  - Copy is typed in lowercase in the markup, never with `text-transform`, so
    the glossary terms Trial, License and License key keep their capitals.
  - Breakpoints: below 1152px the column is fluid, below 900px the first
    screen stacks, below 700px is the phone layout.
  - Only `transform` and `opacity` animate, and every animation is switched
    off or reduced to a fade under `prefers-reduced-motion`.
- Fonts — Geist and Geist Mono (OFL), self-hosted from the
  `@fontsource-variable/*` packages and imported in `Base.astro`. The site
  must not load anything from another origin: the Privacy page says so.
- `src/pages/` — one file per page. `index.astro` is the landing page;
  `404.astro` is served for unknown paths.
- `src/components/` — `Marker` (the 64px box with a solid shape that opens
  every section) and the landing page sections in order: `Hero` (first screen
  with the selected widget on a picture), `Desk` (a laptop on a
  desk playing a screen recording), `Sky`, `Price`, `Faq`.
- `src/scripts/` — plain TypeScript, no framework: `hero-demo.ts` (the hero
  widget switching tabs in place, and dragging it by hand) and
  `motion.ts` (everything that plays when scrolled into view, including the
  screen recording). Both
  honour `prefers-reduced-motion`, and the page is complete without them.
- `src/assets/pictures/` — the three halftone pictures and the laptop that
  stands on one of them. `src/assets/video/` — the screen recording played on
  the laptop's screen and its first frame; keep both at the same size. `src/assets/screens/` —
  copies of `docs/screenshots/*.png`; update the copies when the screenshots
  change. Astro resizes all of them to AVIF and WebP at build time. The
  screenshots are laid over the pictures as separate images so they can move
  on their own. They must all stay the same 565 × 900 frame: the first screen
  stacks six of them in one box and fades between them, and `Hero.astro`
  holds the position of the lit strip icon in each.
- `public/` — files copied to the site root unchanged, including `og.png`,
  the link preview image.
- `scripts/og.html` — the source of `public/og.png`. Not part of the build;
  the command to regenerate the PNG is at the top of the file.

## Site URL

The site lives at `https://pocketwidget.tech`. Set the `SITE_URL` environment
variable at build time to that origin, without a trailing path:

```sh
SITE_URL=https://pocketwidget.tech npm run build
```

It makes the link preview image URL (`og:image`, `twitter:image`) absolute,
which link previews require, and adds the canonical link and `og:url` to every
page. Without it the build still works: the image tags point to `/og.png`,
which most services will not load, and the canonical link and `og:url` are
left out. In CI the build step in `.github/workflows/site.yml` reads it from
the `SITE_URL` repository variable.

## Deploy

Deploys run from GitHub Actions, never from a local machine. The workflow
`.github/workflows/site.yml` runs on every push to `master` that changes
`site/**` (or the workflow itself), and can be started by hand from the Actions
tab. It runs on a GitHub-hosted runner, builds the site and runs
`wrangler deploy`, which uploads `dist/` to the Worker named `pocket-site`
(see `wrangler.toml`). The same workflow then deploys the Worker in
`www-redirect/`.

### Domain

The domain `pocketwidget.tech` is registered at Cloudflare, in the same
account as the Workers. `wrangler.toml` attaches it to the site as a custom
domain; Cloudflare creates the DNS record and the certificate on deploy.
`www.pocketwidget.tech` is attached to a second, tiny Worker,
`www-redirect/`, that answers every request with a 301 to the same path on
`pocketwidget.tech`. It is separate because the site Worker has no script and
cannot tell hosts apart. The site also stays reachable at
`https://pocket-site.<account-subdomain>.workers.dev`; the canonical link on
every page points to the domain.

### Required repository secrets

| Secret | Value |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | A Cloudflare API token created from the "Edit Cloudflare Workers" template. Its zone resources must include `pocketwidget.tech`, or attaching the domain fails |
| `CLOUDFLARE_ACCOUNT_ID` | The ID of the Cloudflare account that owns the Worker |

Set them under Settings → Secrets and variables → Actions.
