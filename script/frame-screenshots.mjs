#!/usr/bin/env node
// Frames raw store screenshots: a caption above the screenshot, in Live
// Wire's colors, at the size each store asks for. The screenshot itself is
// only scaled, never edited.
//
//   node script/frame-screenshots.mjs RAW_DIR OUT_DIR WIDTHxHEIGHT [--fonts DIR] [--captions FILE]
//
// RAW_DIR holds <n>-<screen>.png (as StoreScreenshotTests names them);
// OUT_DIR gets the same names, framed. Captions are keyed by <screen>
// (fastlane/screenshots/captions.json). --fonts is a folder with
// unbounded-variable.woff2 and geist-variable.woff2 (the Rails app's
// app/assets/fonts); without it the system's sans-serif is used.
// Needs Playwright where Node resolves it (npm i playwright next to the
// script), and its browser or CHROMIUM_PATH pointing at a Chromium.
import { chromium } from "playwright"
import { readFileSync, readdirSync, mkdirSync, existsSync } from "node:fs"
import { join, dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const args = process.argv.slice(2)
const option = (name) => {
  const index = args.indexOf(name)
  return index >= 0 ? args.splice(index, 2)[1] : null
}
const fonts = option("--fonts")
const here = dirname(fileURLToPath(import.meta.url))
const captionsFile = option("--captions") || resolve(here, "../fastlane/screenshots/captions.json")
const [rawDir, outDir, size] = args
if (!rawDir || !outDir || !/^\d+x\d+$/.test(size || "")) {
  console.error("usage: frame-screenshots.mjs RAW_DIR OUT_DIR WIDTHxHEIGHT [--fonts DIR] [--captions FILE]")
  process.exit(2)
}
const [width, height] = size.split("x").map(Number)
const captions = JSON.parse(readFileSync(captionsFile, "utf8"))
mkdirSync(outDir, { recursive: true })

const fontFace = (family, file) =>
  fonts && existsSync(join(fonts, file))
    ? `@font-face { font-family: "${family}"; src: url(data:font/woff2;base64,${readFileSync(join(fonts, file)).toString("base64")}) format("woff2"); font-weight: 100 900; }`
    : ""

// Sizes scale with the canvas's width, so phones and tablets share one layout.
const unit = width / 100
const landscape = width > height * 0.7

function page(screenshot, caption) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    ${fontFace("Unbounded", "unbounded-variable.woff2")}
    ${fontFace("Geist", "geist-variable.woff2")}
    * { box-sizing: border-box; margin: 0; }
    html, body { width: ${width}px; height: ${height}px; overflow: hidden; }
    body {
      background: radial-gradient(120% 60% at 50% 0%, #1a1b24 0%, #0b0b0f 60%);
      color: #f4f4f6; font-family: Geist, system-ui, sans-serif;
      display: flex; flex-direction: column; align-items: center;
      padding-top: ${(landscape ? 4.5 : 9) * unit}px;
    }
    h1 {
      font-family: Unbounded, Geist, sans-serif; font-weight: 600;
      font-size: ${(landscape ? 4.2 : 7.2) * unit}px; line-height: 1.12; letter-spacing: -0.02em;
      text-align: center; max-width: ${(landscape ? 70 : 88) * unit}px; text-wrap: balance;
    }
    p {
      margin-top: ${(landscape ? 1.4 : 2.6) * unit}px;
      font-size: ${(landscape ? 2.1 : 3.9) * unit}px; line-height: 1.35; color: #a9abb8;
      text-align: center; max-width: ${(landscape ? 62 : 82) * unit}px; text-wrap: balance;
    }
    .shot {
      margin-top: ${(landscape ? 3.5 : 6.5) * unit}px;
      width: ${(landscape ? 74 : 84) * unit}px;
      border-radius: ${(landscape ? 2.4 : 5.5) * unit}px;
      border: ${Math.max(2, 0.35 * unit)}px solid #2c2d38;
      box-shadow: 0 ${4 * unit}px ${12 * unit}px rgba(0, 0, 0, 0.55);
      overflow: hidden; flex: none;
    }
    .shot img { display: block; width: 100%; }
  </style></head><body>
    <h1>${caption.title}</h1>
    ${caption.text ? `<p>${caption.text}</p>` : ""}
    <div class="shot"><img src="data:image/png;base64,${screenshot.toString("base64")}"></div>
  </body></html>`
}

const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {})
const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 })
const tab = await context.newPage()

for (const file of readdirSync(rawDir).filter((name) => /^\d+-[\w-]+\.png$/.test(name)).sort()) {
  const screen = file.replace(/^\d+-/, "").replace(/\.png$/, "")
  const caption = captions[screen]
  if (!caption) {
    console.warn(`No caption for ${screen}, skipped`)
    continue
  }
  await tab.setContent(page(readFileSync(join(rawDir, file)), caption), { waitUntil: "load" })
  await tab.evaluate(() => document.fonts.ready)
  await tab.screenshot({ path: join(outDir, file), clip: { x: 0, y: 0, width, height } })
  console.log(`${join(outDir, file)} ${width}x${height}`)
}

await browser.close()
