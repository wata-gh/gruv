# GitHub Repository Update Viewer

A lightweight interface for browsing weekly GitHub activity summaries. The backend indexes Markdown reports generated from a Codex workflow, and the Next.js frontend renders them with a searchable, theme-aware UI.

## Overview
- Ruby Roda API exposes repository listings, release history, and pre-rendered Markdown/HTML summaries backed by a DuckDB catalog for fast lookups.
- Next.js app (shadcn UI, Tailwind) consumes the API and presents switchable repositories and date ranges.
- Markdown snapshots live at the repo root using the `[organization]_[repository]_[YYYY-MM-DD].md` naming pattern.

## Architecture
- `backend/`: Roda application (`app.rb`, `server.rb`, `config.ru`) plus a lightweight TCP server that serves Rack responses and enforces CORS via `ALLOWED_ORIGINS`.
- `frontend/`: Next.js 14 app with routes in `app/`, shared primitives in `components/` (`components/ui/` for shadcn), and utilities in `lib/`. Tailwind setup in `tailwind.config.ts` and global styles in `app/globals.css`.
- Automation scripts (`update_summary.sh`, `update_starred_reps.sh`) generate Markdown summaries via Codex and GitHub APIs.

## Getting Started
1. Install Ruby 3.4.2 (via `mise` is recommended) and Node.js 18+.
2. Backend: `HOST=127.0.0.1 PORT=9292 ./start_server.sh` (or run under Bundler with `BUNDLE_GEMFILE=backend/Gemfile bundle exec ruby backend/server.rb`). Set `UPDATES_ROOT` if Markdown lives outside the repo, `UPDATE_VIEWER_DATABASE` to override the DuckDB file location, and `ALLOWED_ORIGINS` for stricter CORS.
3. Frontend: `cd frontend && npm install`, then `npm run dev` (`NEXT_PUBLIC_API_BASE_URL` defaults to `http://localhost:9292`). Build and lint with `npm run build` and `npm run lint`.

## Production Deployment
- Production builds (`npm run build`) emit a static export in `frontend/out/`, eliminating the need to run `next start` and cutting memory usage versus the Node.js runtime server. The `next start` command will fail with this configuration; use the static preview instead.
- Serve the bundle with any static host (e.g., `npm run preview`, `npx serve@latest out`, Nginx, S3 + CDN). Ensure `NODE_ENV=production` during the build to trigger the export path.
- `./frontend/start_server.sh --prod` wraps this flow locally by running `npm run build` followed by `npm run preview -- --listen tcp://$HOST:$PORT` (defaults: `0.0.0.0:3000`).
- Keep environment variables such as `NEXT_PUBLIC_API_BASE_URL` available at build time if you rely on non-default API origins.

## Automated Provisioning (ansible-pull)
Systemd unit templates for both services live under `ansible/templates/` and are wired into the playbook at `ansible/site.yml`. The playbook copies the units into `/etc/systemd/system/`, reloads the daemon, and ensures `gruv-backend` and `gruv-frontend` are enabled and running with the production settings used in our EC2 environment.

The frontend unit now loads public runtime configuration from `/etc/gruv/gruv-frontend.env`, keeping deployment-specific values
such as `NEXT_PUBLIC_API_BASE_URL` out of source control. Provide the API base URL when running the playbook so Ansible can
render the environment file before starting the service.

Run the playbook directly from this repository with `ansible-pull` after cloning to `/home/ec2-user/ws/gruv`:

```bash
sudo ansible-pull \
  -U <repository_url> \
  -d /home/ec2-user/ws/gruv \
  -e "next_public_api_base_url=https://your.backend.domain" \
  ansible/site.yml
```

## Testing & Quality
- Backend tests are not scaffolded yet; add `_test.rb` files using Minitest or RSpec and mock filesystem access to the Markdown catalog.
- Frontend relies on ESLint + Prettier; consider adding Playwright or Cypress suites for end-to-end coverage and snapshot key Markdown views.
- Smoke-check the API via `curl http://localhost:9292/repos` before shipping changes.

## Updating Summaries
- Run `./update_summary.sh <org> <repo>` to regenerate a single report (requires Codex CLI access).
- Use `./update_starred_reps.sh --dry-run` to preview bulk updates for recently active starred repositories; omit `--dry-run` to execute.

## Contributing
Follow the commit style `<type>: imperative` (e.g., `feat: add history sidebar`) and describe UI/backend impacts, linked issues, screenshots, and manual test steps in pull requests. Review the detailed contributor notes in `AGENTS.md` before opening PRs.
