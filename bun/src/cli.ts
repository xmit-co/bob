#!/usr/bin/env bun
import { serve } from "./server";
import { file } from "bun";
import { resolve, join } from "path";
import type { PackageJson } from "./config";

async function main() {
  const args = process.argv.slice(2);

  // Parse arguments
  let command = "preview";
  let listenAddr: string | undefined;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--listen") {
      listenAddr = args[++i];
    } else if (arg.startsWith("--listen=")) {
      listenAddr = arg.slice("--listen=".length);
    } else if (!arg.startsWith("--")) {
      command = arg;
    }
  }

  if (command === "preview") {
    // Find package.json in current directory or parent directories
    let currentDir = process.cwd();
    let packageJsonPath: string | null = null;

    while (currentDir !== "/") {
      const candidatePath = join(currentDir, "package.json");
      if (await file(candidatePath).exists()) {
        packageJsonPath = candidatePath;
        break;
      }
      currentDir = resolve(currentDir, "..");
    }

    if (!packageJsonPath) {
      console.error("Error: Could not find package.json in current directory or any parent directory");
      process.exit(1);
    }

    let pkg: PackageJson;
    try {
      const pkgContent = await file(packageJsonPath).text();
      pkg = JSON.parse(pkgContent);
    } catch (err) {
      console.error(`Error reading package.json: ${err}`);
      process.exit(1);
    }

    const directory = pkg.bob?.directory;
    if (!directory) {
      console.error('Error: No "bob.directory" field found in package.json');
      process.exit(1);
    }

    const projectRoot = resolve(packageJsonPath, "..");
    const absoluteDirectory = resolve(projectRoot, directory);

    if (!(await file(absoluteDirectory).exists())) {
      console.error(`Error: Directory "${directory}" does not exist (resolved to ${absoluteDirectory})`);
      process.exit(1);
    }

    await serve(absoluteDirectory, listenAddr);
  } else {
    console.error(`Unknown command: ${command}`);
    console.error("Usage: bob [preview] [--listen ADDRESS]");
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
