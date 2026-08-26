# Mog Site

Official landing page and documentation site for the Mog programming language.

## Commands

Run these from the repository root:

- `npm install`
- `npm run site:dev`
- `npm run site:check`
- `npm run site:build`
- `npm run site:preview`

## Environment

- `SITE_URL` sets the canonical site URL used for sitemap and metadata.
- `MOG_SITE_EDIT_BASE_URL` enables Starlight edit links for docs pages.
- `BASE_PATH` sets the deployment subpath. The GitHub Pages workflow supplies this automatically.

## Deployment

Pushes to `main` that change the site or its build inputs publish `apps/site/dist` to GitHub Pages. In the repository settings, set **Pages** to **GitHub Actions** as the source before the first deployment.

## Structure

- `src/pages/` contains the landing page, manifesto page, and custom 404 page.
- `src/content/docs/` contains the official docs content rendered by Starlight.
- `src/styles/site.css` defines the Mog visual system for both docs and marketing pages.
