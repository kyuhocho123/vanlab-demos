// Drives the exported Godot scene in headless Chrome with real touch events.
// Usage: node tests/godot-scene.test.mjs <folder holding the published site>
// (needs puppeteer-core and Google Chrome; run from a folder where puppeteer-core is installed)
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFileSync, existsSync, statSync } from "node:fs";
import { extname, join } from "node:path";
import { createRequire } from "node:module";
const require = createRequire(process.env.PUPPETEER_FROM ?? import.meta.url);
const puppeteer = require("puppeteer-core");

const root = process.argv[2];
const shot = process.argv[3] ?? "godot-shot.png";
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json", ".txt": "text/plain" };
const server = createServer((req, res) => {
  let name = req.url.split("?")[0];
  if (name.endsWith("/")) name += "index.html";
  const file = join(root, name);
  if (!existsSync(file) || statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" });
  res.end(readFileSync(file));
}).listen(0);
const url = `http://127.0.0.1:${server.address().port}/godot/`;
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME ?? "/usr/bin/google-chrome", headless: true,
  args: ["--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 412, height: 915, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("GL Driver Message")) errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push(String(e)));
  const t0 = Date.now();
  await page.goto(url, { waitUntil: "load" });
  await page.waitForFunction("window.__vanlabGodot && window.__vanlabGodot.ready", { timeout: 120000 });
  const loadMs = Date.now() - t0;
  const G = () => page.evaluate("window.__vanlabGodot");
  // The scene republishes its state 4 times a second; wait until the published state satisfies a condition.
  const until = async (fn, what, ms = 15000) => {
    const end = Date.now() + ms; let s;
    while (Date.now() < end) { s = await G(); if (fn(s)) return s; await sleep(150); }
    throw new Error(`timed out waiting for: ${what}; last state ${JSON.stringify({ sel: s.selected, total: s.total, ov: s.overlapCount, counters: s.counters })}`);
  };
  const css = async () => page.evaluate("(() => { const r = document.querySelector('canvas').getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; })()");
  const at = async (id) => { const s = await G(); const c = await css(); const it = s.items.find((i) => i.id === id); return { x: c.x + it.sx * c.w, y: c.y + it.sy * c.h + 6 }; };
  const item = (s, id) => s.items.find((i) => i.id === id);
  const button = async (text) => { const s = await G(); const c = await css(); const b = s.buttons.find((x) => x.text.startsWith(text)); return { x: c.x + b.cx * c.w, y: c.y + b.cy * c.h }; };
  const tap = async (p) => { await page.touchscreen.tap(p.x, p.y); await sleep(350); };
  const touchDrag = async (from, to, steps = 10) => {
    const f = await page.touchscreen.touchStart(from.x, from.y);
    for (let i = 1; i <= steps; i++) { await f.move(from.x + ((to.x - from.x) * i) / steps, from.y + ((to.y - from.y) * i) / steps); await sleep(30); }
    await f.end(); await sleep(400);
  };

  // 1. Loads with 12 items, none overlapping.
  let s = await G();
  assert.equal(s.items.length, 12, "12 items");
  assert.equal(s.total, 12);
  assert.equal(s.overlapCount, 0, "start layout has no overlaps");

  // 2. A finger on an item moves it on the first touch; the camera stays put.
  const before = item(s, "Table");
  const p = await at("Table");
  await touchDrag(p, { x: p.x + 60, y: p.y + 10 });
  s = await until((x) => x.selected === "Table", "Table selected");
  const after = item(s, "Table");
  assert.ok(Math.hypot(after.x - before.x, after.z - before.z) > 0.1, "item moved on first touch");
  assert.ok(Math.abs(s.camYaw - 0.8) < 1e-6 && Math.abs(s.camDist - 9.8) < 1e-6, "camera did not move during item drag");

  // 3. Snapped to 5 cm.
  for (const v of [after.x, after.z]) assert.ok(Math.abs(v / 0.05 - Math.round(v / 0.05)) < 1e-4, `snapped to 5 cm (${v})`);

  // 4. Cannot leave the box.
  const p2 = await at("Table");
  await touchDrag(p2, { x: p2.x + 380, y: p2.y + 400 }, 14);
  s = await G();
  const t = item(s, "Table");
  assert.ok(Math.abs(t.x) <= s.box.length / 2 - t.hx + 1e-4 && Math.abs(t.z) <= s.box.width / 2 - t.hz + 1e-4, "item stays inside the box");

  // 5. Dragging one item onto another flags the overlap.
  await tap(await button("Reset"));
  await until((x) => x.selected === null && item(x, "Table").x === -0.25, "reset");
  await touchDrag(await at("Step"), await at("Bed platform"), 14);
  await until((x) => x.overlapCount >= 2, "overlap flagged");

  // 6. A finger on empty space orbits the camera and moves no item.
  await tap(await button("Reset"));
  s = await until((x) => x.overlapCount === 0 && x.selected === null, "reset again");
  const positions = JSON.stringify(s.items.map((i) => [i.x, i.z]));
  const c = await css();
  const empty = { x: c.x + c.w * 0.5, y: c.y + c.h * 0.22 };
  await touchDrag(empty, { x: empty.x - 120, y: empty.y + 10 });
  s = await until((x) => Math.abs(x.camYaw - 0.8) > 0.2, "camera orbited");
  assert.equal(JSON.stringify(s.items.map((i) => [i.x, i.z])), positions, "no item moved while orbiting");
  assert.equal(s.selected, null);

  // 6b. A pinch that starts on an item zooms and leaves the item in place.
  await tap(await button("Reset"));
  s = await until((x) => Math.abs(x.camYaw - 0.8) < 1e-6, "camera reset");
  const bench = item(s, "Bench");
  const b0 = await at("Bench");
  const f1 = await page.touchscreen.touchStart(b0.x, b0.y);
  await f1.move(b0.x - 6, b0.y - 4); await sleep(40);
  const f2 = await page.touchscreen.touchStart(b0.x + 60, b0.y + 60);
  for (let i = 1; i <= 8; i++) { await f1.move(b0.x - 6 - i * 9, b0.y - 4 - i * 9); await f2.move(b0.x + 60 + i * 9, b0.y + 60 + i * 9); await sleep(30); }
  await f1.end();
  // 6c. The finger that lifts last keeps sliding for a moment, as real fingers do. It must not spin the camera.
  for (let i = 1; i <= 6; i++) { await f2.move(b0.x + 132 + i * 14, b0.y + 132 + i * 3); await sleep(30); }
  await f2.end();
  s = await until((x) => x.camDist < 9.8 - 0.3, "pinch zoomed in");
  assert.ok(Math.abs(s.camYaw - 0.8) < 1e-6 && Math.abs(s.camPitch - 0.48) < 1e-6, `camera angle unchanged after a pinch (yaw ${s.camYaw}, pitch ${s.camPitch})`);
  assert.deepEqual([item(s, "Bench").x, item(s, "Bench").z], [bench.x, bench.z], "item is back where it was after a pinch that began on it");
  assert.equal(s.counters.pinchHandovers, 1);

  // 7. Buttons: stress, rotate, reset.
  await tap(await button("Reset"));
  await until((x) => Math.abs(x.camDist - 9.8) < 1e-6, "reset before buttons");
  await tap(await button("+500"));
  await until((x) => x.total === 512, "+500 boxes");
  await tap(await at("Galley"));
  await until((x) => x.selected === "Galley", "Galley selected by tap");
  await tap(await button("Rotate"));
  await until((x) => item(x, "Galley").quarter === 1, "rotated");
  await tap(await button("Reset"));
  s = await until((x) => x.total === 12 && item(x, "Galley").quarter === 0 && x.overlapCount === 0, "final reset");

  // 8. No page errors.
  assert.deepEqual(errors, [], "no console or page errors");
  await sleep(600);
  s = await G();
  await page.screenshot({ path: shot });
  console.log(`PASS: 10 groups of checks. Godot ${s.engine}. Load ${loadMs} ms. Canvas ${s.viewport.join("x")}. Screenshot: ${shot}`);
  console.log("software-render stats (not a phone):", JSON.stringify(s.stats));
} catch (e) {
  try { const pages = await browser.pages(); await pages[pages.length - 1].screenshot({ path: shot }); console.log("failure screenshot:", shot); } catch {}
  throw e;
} finally { await browser.close(); server.close(); }
