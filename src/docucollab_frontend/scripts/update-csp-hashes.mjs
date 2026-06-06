import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";

const htmlPath = "dist/index.html";
const assetsConfigPath = "dist/.ic-assets.json5";
const placeholder = "__INLINE_SCRIPT_HASHES__";

const html = readFileSync(htmlPath, "utf8");
const assetsConfig = readFileSync(assetsConfigPath, "utf8");

const inlineScripts = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)]
  .map((match) => match[1])
  .filter((script) => script.trim().length > 0);

const hashDirectives = inlineScripts
  .map((script) => {
    const hash = createHash("sha256").update(script).digest("base64");
    return `'sha256-${hash}'`;
  })
  .join(" ");

if (!assetsConfig.includes(placeholder)) {
  throw new Error(`Missing ${placeholder} in ${assetsConfigPath}`);
}

writeFileSync(
  assetsConfigPath,
  assetsConfig.replace(placeholder, hashDirectives),
);

console.log(`Updated CSP with ${inlineScripts.length} inline script hash${inlineScripts.length === 1 ? "" : "es"}.`);
