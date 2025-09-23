# Repository Guidelines

## Project Structure & Module Organization
The backend lives in `backend/` and is a Ruby Roda API that indexes Markdown summaries; core entrypoints are `app.rb`, `server.rb`, and `config.ru`, with `start_server.sh` for local bootstrapping. The Next.js frontend sits in `frontend/`, using `app/` for routes, `components/` for shared UI (shadcn primitives under `components/ui/`), and `lib/` for helpers. Tailwind configuration is at `frontend/tailwind.config.ts`, global styles in `frontend/app/globals.css`. Markdown source files are stored at the repo root as `[organization]_[repository]_[YYYY-MM-DD].md`.

## Build, Test, and Development Commands
- `HOST=127.0.0.1 PORT=9292 ./start_server.sh`: launch the Roda server with the vendored Ruby 3.4.2 runtime.
- `BUNDLE_GEMFILE=backend/Gemfile bundle exec ruby backend/server.rb`: run the API under Bundler when you need gem resolution.
- `npm install` (once) then `npm run dev` inside `frontend/`: start the Next.js dev server; `NEXT_PUBLIC_API_BASE_URL` defaults to `http://localhost:9292`.
- `npm run build` compiles the production bundle; `npm run lint` enforces ESLint.

## Coding Style & Naming Conventions
Prefer frozen string literals and double quotes for interpolation in Ruby, following idiomatic `route do |r|` structures. TypeScript components use PascalCase functional components, hooks prefixed with `use`, and Tailwind utility classes. Keep filenames ASCII, and use ISO8601 dates for Markdown summaries. Formatting relies on ESLint + Prettier defaults in the frontend; respect any `.editorconfig` settings present.

## Testing Guidelines
Ruby tests should use Minitest or RSpec (not yet scaffolded); mock file catalog interactions and add `_test.rb` files alongside code. For frontend E2E you can introduce Playwright or Cypress suites (also not yet scaffolded) and prefer snapshot testing for complex Markdown rendering. Smoke check the API with `curl http://localhost:9292/repos` after changes. Add tests close to the touched codepaths.

## Commit & Pull Request Guidelines
Follow `<type>: short imperative` commit messages (e.g., `feat: add history sidebar`) and keep unrelated changes split. Pull requests should explain UI or backend impact, reference issues, attach before/after screenshots for UI updates, call out API modifications, and document manual test steps once lint/build succeed locally.

## Security & Configuration Tips
Never expose the Markdown root outside the repository; configure `UPDATES_ROOT` as read-only. Restrict `ALLOWED_ORIGINS` to trusted domains and serve the backend behind HTTPS in deployments. Keep secrets out of source control and rely on environment variables for configuration.
