# vanlab-demos — notes for agents

- Public repository of throwaway test scenes for VanLab. Never put real product code, keys or private data here.
- Every push to `main` runs `.github/workflows/build.yml`: GitHub downloads the latest stable Godot, exports `godot-scene/` for the web and force-pushes the site to the `gh-pages` branch with `status.json` and `build-log.txt`. The page is https://kyuhocho123.github.io/vanlab-demos/.
- To check a build: `git fetch --depth 1 origin gh-pages`, read `status.json` and `build-log.txt` from `FETCH_HEAD`, unpack it, then run `node tests/godot-scene.test.mjs <folder>` from a place where `puppeteer-core` is installed (set `PUPPETEER_FROM` to that package.json). Godot cannot be installed in Claude's cloud workspace; GitHub's build is the only way to run it.
- `site/web-scene/` and `site/look-test/` are prebuilt copies from the private `vanlab` repository.
- Kyu allows direct pushes to `main` (decision D16, 2026-11-23). The plan lives in the "VanLab" project on claude.ai.
