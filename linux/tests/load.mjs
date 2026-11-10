import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

export function load(name) {
    const context = {};
    runInNewContext(readFileSync(new URL(`../package/contents/code/${name}.js`, import.meta.url), "utf8"), context);
    return context;
}
