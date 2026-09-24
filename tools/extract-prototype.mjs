// Evaluates the data section of prototype/index.html and prints it as JSON.
// Usage: node tools/extract-prototype.mjs > out.json
import { readFileSync } from "node:fs";

const html = readFileSync(new URL("../prototype/index.html", import.meta.url), "utf8");
const start = html.indexOf("const PRONOUNS_IT");
const end = html.indexOf("const LENGTH_OPTIONS");
const code = html.slice(start, end);

const snapshot = new Function(code + `
  return { VERBS, VERB_GROUPS, PARTICIPLES, DU_IMPERATIV, TENSE_LABELS, TENSE_INFO };
`)();
process.stdout.write(JSON.stringify(snapshot, null, 2));
