import { spawn } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const [suite, ...args] = process.argv.slice(2);
if (suite !== "test" && suite !== "bench") {
  throw new Error("Expected test or bench suite");
}

async function discover(directory) {
  const files = [];
  for (const entry of await readdir(path.join(root, directory), { withFileTypes: true })) {
    const relative = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await discover(relative));
    else if (entry.isFile() && entry.name.endsWith(".test.ts")) files.push(relative);
  }
  return files;
}

// Explicit test files take precedence, preserving `npm test -- test/foo.test.ts`.
// Flags such as --grep and --no-compile still apply to the selected suite.
const explicitFiles = args.some(arg => arg.endsWith(".test.ts"));
const files = explicitFiles ? [] : (await discover("test"))
  .filter(file => file.endsWith(".bench.test.ts") === (suite === "bench"))
  .sort();
if (!explicitFiles && files.length === 0) {
  throw new Error(`No files found for the ${suite} suite`);
}

if (args.includes("--list")) {
  console.log((explicitFiles ? args.filter(arg => arg.endsWith(".test.ts")) : files).join("\n"));
} else {
  // Invoke the installed CLI with Node, without shell globbing or Windows .cmd handling.
  const packagePath = fileURLToPath(import.meta.resolve("hardhat/package.json"));
  const hardhat = JSON.parse(await readFile(packagePath, "utf8"));
  const cli = path.resolve(path.dirname(packagePath), hardhat.bin.hardhat);
  const child = spawn(process.execPath, [cli, "test", ...files, ...args], {
    cwd: root,
    stdio: "inherit",
  });
  child.on("error", error => {
    console.error(error);
    process.exitCode = 1;
  });
  child.on("exit", (code, signal) => {
    process.exitCode = code ?? (signal === "SIGINT" ? 130 : 1);
  });
}
