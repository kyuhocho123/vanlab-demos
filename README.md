# vanlab-demos

Throwaway test scenes for VanLab, kept public so GitHub can host them as a web page. The real code lives in the private `vanlab` repository.

- `godot-scene/` — the engine test scene built in Godot 4 (all in `main.gd`; see `SCENE-SPEC.md`).
- `site/` — the page that lists the scenes, plus the prebuilt three.js scenes (`web-scene/`, `look-test/`) copied from `vanlab`.
- `.github/workflows/build.yml` — on every push, GitHub downloads Godot, exports the scene for the web and publishes everything to the `gh-pages` branch with `build-log.txt` and `status.json`.

Hosted page (after GitHub Pages is switched on for the `gh-pages` branch): https://kyuhocho123.github.io/vanlab-demos/
