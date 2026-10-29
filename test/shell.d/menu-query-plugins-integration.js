// End-to-end check of the query-plugin path with the real bins
// (omarchy-query-calc / omarchy-query-web) and the real MenuModel.js:
//   query -> queryPluginsForQuery -> run bin -> queryPluginRow
// Every fixed query names the plugins that must fire and the exact output
// each must produce, so a missing or broken helper fails the run.

const { execFileSync } = require("child_process");
const path = require("path");
const menu = require(path.join(__dirname, "..", "..", "shell/plugins/menu/MenuModel.js"));

const binDir = path.join(__dirname, "..", "..", "bin");
function runBin(name, args) {
  try {
    return { ok: true, out: execFileSync(path.join(binDir, name), args, { encoding: "utf8", timeout: 10000 }).replace(/\s+$/, "") };
  } catch (e) {
    return { ok: false, out: String(e.stdout || "").trim(), err: String(e.stderr || e.message).trim() };
  }
}

// Mirror the built-in plugin defs from Menu.qml (args: "url" -> --print mode).
const map = {
  "omarchy.query.calc": { id: "omarchy.query.calc", kind: "math", icon: "calc", enabled: true,
    action: "copy", command: "omarchy-query-calc", builtin: true },
  "omarchy.query.web": { id: "omarchy.query.web", kind: "web", icon: "search", enabled: true,
    action: "run", command: "omarchy-query-web", args: "url", builtin: true },
};

const cases = [
  { q: "2+2", expect: { "omarchy.query.calc": "4", "omarchy.query.web": "https://www.google.com/search?q=2%2B2" } },
  { q: "2^10", expect: { "omarchy.query.calc": "1024", "omarchy.query.web": "https://www.google.com/search?q=2%5E10" } },
  { q: "sqrt(16)+1", expect: { "omarchy.query.calc": "5", "omarchy.query.web": "https://www.google.com/search?q=sqrt%2816%29%2B1" } },
  { q: "omarchy linux", expect: { "omarchy.query.web": "https://www.google.com/search?q=omarchy%20linux" } },
  { q: "youtube omarchy", expect: { "omarchy.query.web": "https://www.youtube.com/results?search_query=omarchy" } },
  { q: "youtube", expect: { "omarchy.query.web": "https://www.google.com/search?q=youtube" } },
  { q: "https://example.com", expect: { "omarchy.query.web": "https://example.com" } },
];

let failures = 0;
function fail(message) {
  failures++;
  console.log("FAIL: " + message);
}

for (const { q, expect } of cases) {
  const fired = menu.queryPluginsForQuery(map, q).map(p => p.id);
  const wanted = Object.keys(expect);
  if (fired.join(",") !== wanted.join(",")) {
    fail(`query "${q}" fired [${fired}] instead of [${wanted}]`);
    continue;
  }
  for (const id of wanted) {
    const p = map[id];
    const result = runBin(p.command, p.args === "url" ? ["--print", q] : [q]);
    if (!result.ok) {
      fail(`query "${q}": ${p.command} failed: ${result.err}`);
      continue;
    }
    if (result.out !== expect[id]) {
      fail(`query "${q}": ${p.command} printed "${result.out}", expected "${expect[id]}"`);
      continue;
    }
    const row = menu.queryPluginRow(p, q, result.out, "en");
    if (row.kind !== "query" || !row.icon || !row.label) fail(`query "${q}": bad row for ${id}`);
    console.log(`ok - "${q}" -> [${p.kind}] ${row.label}`);
  }
}

// The web helper also joins separate CLI words into one query.
const split = runBin("omarchy-query-web", ["--print", "hello", "world"]);
if (!split.ok || split.out !== "https://www.google.com/search?q=hello%20world") {
  fail(`omarchy-query-web --print hello world printed "${split.out}"`);
}

// Rejected and runaway expressions fail cleanly instead of producing a row.
for (const expr of ["os.system('id')", "9^9^9", "1/0"]) {
  const result = runBin("omarchy-query-calc", [expr]);
  if (result.ok || result.out !== "Error") fail(`calc "${expr}" should fail with Error, got ok=${result.ok} "${result.out}"`);
}

console.log(failures === 0 ? "INTEGRATION OK" : `INTEGRATION FAILED: ${failures} problem(s)`);
process.exit(failures === 0 ? 0 : 1);
