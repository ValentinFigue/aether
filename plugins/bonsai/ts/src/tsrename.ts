import { parseSymbolRef, findProjectRoot, createProject, findSymbolNode, saveBefore, collectDiffs, formatDiffs } from "./_common.js";

export async function doRename(
  target: string,
  newName: string,
  projectRoot?: string,
  dryRun = false,
): Promise<string> {
  const ref = parseSymbolRef(target);
  const root = projectRoot ?? findProjectRoot(process.cwd());
  const project = createProject(root);

  const node = findSymbolNode(project, ref, root);
  if (!node) return `Symbol "${target}" not found. Check the module path and symbol name.`;

  const before = saveBefore(project);

  try {
    (node as any).rename(newName);
  } catch (err) {
    return `Rename failed: ${String(err)}`;
  }

  const diffs = collectDiffs(project, before);

  if (dryRun) {
    if (diffs.length === 0) return "No changes would be made.";
    return `[DRY RUN] Would rename "${target}" → "${newName}":\n\n${formatDiffs(diffs)}`;
  }

  await project.save();
  const fileCount = diffs.length;
  const changeCount = diffs.reduce((n, d) => n + d.patch.split("\n").filter((l) => l.startsWith("+") || l.startsWith("-")).length, 0);
  return `Renamed "${target}" → "${newName}" across ${fileCount} file(s), ${changeCount} line change(s).`;
}

// ── CLI ────────────────────────────────────────────────────────────────────────

import { fileURLToPath } from "url";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length < 2 || args[0] === "--help") {
    console.log("Usage: tsrename <module/path:Symbol> <newName> [--project-root <path>] [--dry-run]");
    process.exit(0);
  }
  const [target, newName, ...rest] = args;
  let projectRoot: string | undefined;
  const rootIdx = rest.indexOf("--project-root");
  if (rootIdx !== -1) projectRoot = rest[rootIdx + 1];
  const dryRun = rest.includes("--dry-run");
  try {
    console.log(await doRename(target, newName, projectRoot, dryRun));
  } catch (err) {
    console.error(String(err));
    process.exit(1);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
