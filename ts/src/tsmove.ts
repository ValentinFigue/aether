import * as fs from "fs";
import * as path from "path";
import { findProjectRoot, createProject, saveBefore, collectDiffs, formatDiffs } from "./_common.js";

export async function executeMove(
  source: string,
  destination: string,
  projectRoot?: string,
  dryRun = false,
): Promise<string> {
  const root = projectRoot ?? findProjectRoot(process.cwd());
  const project = createProject(root);

  const srcAbs = path.resolve(root, source);
  const destAbs = path.resolve(root, destination);

  // Collect all source files to move (single file or directory)
  const filesToMove: Array<{ from: string; to: string }> = [];

  if (fs.existsSync(srcAbs) && fs.statSync(srcAbs).isDirectory()) {
    // Directory move: collect all TS files inside
    for (const sf of project.getSourceFiles()) {
      const fp = sf.getFilePath();
      if (fp.startsWith(srcAbs + path.sep) || fp.startsWith(srcAbs + "/")) {
        const rel = path.relative(srcAbs, fp);
        filesToMove.push({ from: fp, to: path.join(destAbs, rel) });
      }
    }
    if (filesToMove.length === 0) {
      return `No TypeScript files found in "${source}".`;
    }
  } else {
    // Single file — accept with or without extension
    const sf =
      project.getSourceFile(srcAbs) ??
      project.getSourceFiles().find((s) => s.getFilePath().startsWith(srcAbs));
    if (!sf) return `File "${source}" not found in the project. Check the path and tsconfig.`;
    filesToMove.push({ from: sf.getFilePath(), to: destAbs });
  }

  const before = saveBefore(project);

  for (const { from, to } of filesToMove) {
    const sf = project.getSourceFile(from);
    if (!sf) continue;
    sf.move(to, { overwrite: false });
  }

  const diffs = collectDiffs(project, before);

  if (dryRun) {
    if (diffs.length === 0) return "No changes would be made.";
    return `[DRY RUN] Would move "${source}" → "${destination}":\n\n${formatDiffs(diffs)}`;
  }

  await project.save();

  const movedCount = filesToMove.length;
  const affectedCount = diffs.length;
  const note = "Note: dynamic require() strings and barrel re-exports may need manual review.";
  return `Moved ${movedCount} file(s). Updated imports in ${affectedCount} file(s).\n${note}`;
}

// ── CLI ────────────────────────────────────────────────────────────────────────

import { fileURLToPath } from "url";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length < 2 || args[0] === "--help") {
    console.log("Usage: tsmove <source> <destination> [--project-root <path>] [--dry-run]");
    process.exit(0);
  }
  const [source, destination, ...rest] = args;
  let projectRoot: string | undefined;
  const rootIdx = rest.indexOf("--project-root");
  if (rootIdx !== -1) projectRoot = rest[rootIdx + 1];
  const dryRun = rest.includes("--dry-run");
  try {
    console.log(await executeMove(source, destination, projectRoot, dryRun));
  } catch (err) {
    console.error(String(err));
    process.exit(1);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
