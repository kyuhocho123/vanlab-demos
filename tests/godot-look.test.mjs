// Drives the exported Godot look check (task V1) in headless Chrome with real touch events.
// Usage: node tests/godot-look.test.mjs <folder holding the published site> [folder for screenshots]
// (needs puppeteer-core and Google Chrome; set PUPPETEER_FROM to a package.json where puppeteer-core is installed)
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFileSync, existsSync, statSync, mkdirSync } from "node:fs";
import { extname, join } from "node:path";
import { createRequire } from "node:module";
const require = createRequire(process.env.PUPPETEER_FROM ?? import.meta.url);
const puppeteer = require("puppeteer-core");

const root = process.argv[2];
const shots = process.argv[3] ?? "look-shots";
mkdirSync(shots, { recursive: true });
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json", ".txt": "text/plain" };
const server = createServer((req, res) => {
  let name = req.url.split("?")[0];
  if (name.endsWith("/")) name += "index.html";
  const file = join(root, name);
  if (!existsSync(file) || statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" });
  res.end(readFileSync(file));
}).listen(0);
const url = `http://127.0.0.1:${server.address().port}/godot-look/`;
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME ?? "/usr/bin/google-chrome", headless: true,
  args: ["--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = false;
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 412, height: 915, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const errors = [], warnings = [];
  page.on("console", (m) => {
    const text = m.text();
    if (text.includes("GL Driver Message")) return;
    if (m.type() === "error") errors.push(text);
    if (m.type() === "warning" || /WARNING|ERROR/.test(text)) warnings.push(text);
  });
  page.on("pageerror", (e) => errors.push(String(e)));
  const t0 = Date.now();
  await page.goto(url, { waitUntil: "load" });
  await page.waitForFunction("window.__vanlabLook && window.__vanlabLook.ready", { timeout: 180000 });
  const loadMs = Date.now() - t0;
  const G = () => page.evaluate("window.__vanlabLook");
  const until = async (what, cond) => {
    for (let i = 0; i < 80; i++) { const g = await G(); if (cond(g)) return g; await sleep(250); }
    throw new Error(`timed out waiting for: ${what}; state ${JSON.stringify(await G())}`);
  };
  const group = (name) => console.log(`ok  ${name}`);

  let g = await until("first state", (s) => s.stats.calls > 0);
  assert.equal(g.parts, 49, "49 parts in the day mood");
  assert.equal(g.mood, "day");
  assert.equal(g.renderer, "gl_compatibility");
  assert.ok(g.sunEnergy > 0, "the sun is on by day");
  group(`loads with 49 parts by day (${g.engine}, ${g.renderer}, built in ${g.buildMs} ms, page ready in ${loadMs} ms)`);
  await sleep(1500);
  await page.screenshot({ path: join(shots, "godot-day.png") });

  const vw = await page.evaluate("window.innerWidth"), vh = await page.evaluate("window.innerHeight"); // CSS pixels
  // the mood button works by touch
  await page.touchscreen.tap(g.button.cx * vw, g.button.cy * vh);
  g = await until("evening", (s) => s.mood === "evening");
  assert.equal(g.parts, 49, "49 parts in the evening mood");
  assert.equal(g.sunEnergy, 0, "the sun is off in the evening");
  assert.ok(g.ledEnergy > 1, "the light strips are up in the evening");
  assert.ok(/evening/.test(g.button.text));
  group("the light button switches to evening by touch, still 49 parts");
  await sleep(1500);
  await page.screenshot({ path: join(shots, "godot-evening.png") });
  await page.touchscreen.tap(g.button.cx * vw, g.button.cy * vh);
  g = await until("day again", (s) => s.mood === "day");
  group("and back to day");

  // one-finger drag on empty space orbits the camera
  const yaw0 = g.camYaw;
  await page.touchscreen.touchStart(vw * 0.5, vh * 0.45);
  for (let i = 1; i <= 8; i++) await page.touchscreen.touchMove(vw * 0.5 + i * 5, vh * 0.45);
  await page.touchscreen.touchEnd();
  g = await until("orbit", (s) => Math.abs(s.camYaw - yaw0) > 0.05);
  assert.ok(g.camYaw > 0.13, "a 40-pixel swipe must not throw the camera to its limit");
  group(`one-finger drag orbits (yaw ${yaw0.toFixed(2)} to ${g.camYaw.toFixed(2)})`);

  const overflow = await page.evaluate("document.documentElement.scrollWidth - window.innerWidth");
  assert.ok(overflow <= 0, `no sideways overflow (got ${overflow})`);
  group("no sideways overflow at phone width");

  assert.deepEqual(errors, [], "no errors in the browser console");
  assert.deepEqual(warnings, [], "no warnings in the browser console");
  group("no error or warning in the browser console in either mood");
  console.log(`stats in the test (software rendering, says nothing about a phone): ${JSON.stringify(g.stats)}`);
} catch (e) {
  failed = true;
  console.error(String(e && e.stack || e));
} finally {
  await browser.close();
  server.close();
}
process.exit(failed ? 1 : 0);
