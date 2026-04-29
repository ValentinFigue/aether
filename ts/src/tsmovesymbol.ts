import * as path from "path";
import { Node } from "ts-morph";
import {
  parseSymbolRef,
  findProjectRoot,
  createProject,
  findSourceFile,
  findSymbolNode,
  saveBefore,
  collectDiffs,
  formatDiffs,
  TS_EXTENSIONS,
} from "./_common.js";

/** Resolve a module-path argument (like "src/types") to an absolute .ts path. */
function resolveDestPath(destModule: string, root: string): string {
  let absPath = path.resolve(root, destModule);
  // If no extension given, default to .ts
  if (!TS_EXTENSIONS.some((ext) => absPath.endsWith(ext))) absPath += ".ts";
  return absPath;
}

export async function doMoveSymbol(
  target: string,
  destModule: string,
  projectRoot?: string,
  dryRun = false,
): Promise<string> {
  const ref = parseSymbolRef(target);
  const root = projectRoot ?? findProjectRoot(process.cwd());
  const project = createProject(root);

  const node = findSymbolNode(project, ref, root);
  if (!node) return `Symbol "${target}" not found.`;

  const srcSf = node.getSourceFile();
  const destAbsPath = resolveDestPath(destModule, root);

  // Get or create destination source file
  const destSf =
    project.getSourceFile(destAbsPath) ??
    project.createSourceFile(destAbsPath, "", { overwrite: false });

  const before = saveBefore(project);

  // Save symbol text (full text includes leading whitespace/JSDoc)
  const symbolText = node.getFullText().trim();

  // Remove from source
  (node as any).remove();

  // Append to destination (with a leading newline for spacing)
  const existing = destSf.getFullText().trim();
  destSf.replaceWithText(existing ? existing + "\n\n" + symbolText + "\n" : symbolText + "\n");

  // Add backward-compat re-export to source file
  const relToDestFromSrc = srcSf.getRelativePathAsModuleSpecifierTo(destSf);
  const reExportText = `\n// moved to ${destModule} — kept for backward compatibility\nexport { ${ref.symbolName} } from "${relToDestFromSrc}";\n`;
  srcSf.addStatements(reExportText);

  // Find files that import the symbol from the old source and report them
  const importers: string[] = [];
  for (const sf of project.getSourceFiles()) {
    if (sf === srcSf || sf === destSf) continue;
    for (const imp of sf.getImportDeclarations()) {
      const resolvedSf = imp.getModuleSpecifierSourceFile();
      if (resolvedSf === srcSf) {
        const named = imp.getNamedImports().find((n) => n.getName() === ref.symbolName);
        if (named) importers.push(path.relative(root, sf.getFilePath()));
      }
    }
  }

  const diffs = collectDiffs(project, before);

  if (dryRun) {
    if (diffs.length === 0) return "No changes would be made.";
    const importerNote =
      importers.length > 0
        ? `\nFiles still importing from old location (will work via re-export):\n${importers.map((f) => "  " + f).join("\n")}`
        : "";
    return `[DRY RUN] Would move "${ref.symbolName}" from "${path.relative(root, srcSf.getFilePath())}" to "${destModule}":\n\n${formatDiffs(diffs)}${importerNote}`;
  }

  await project.save();

  const importerNote =
    importers.length > 0
      ? `\n${importers.length} file(s) still import from the old location — they continue to work via the re-export:\n${importers.map((f) => "  " + f).join("\n")}`
      : "";
  return `Moved "${ref.symbolName}" to "${destModule}". A backward-compat re-export was added to the original file.${importerNote}`;
}

// ── CLI ────────────────────────────────────────────────────────────────────────

import { fileURLToPath } from "url";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length < 2 || args[0] === "--help") {
    console.log("Usage: tsmovesymbol <module/path:Symbol> <dest/module> [--project-root <path>] [--dry-run]");
    process.exit(0);
  }
  const [target, destModule, ...rest] = args;
  let projectRoot: string | undefined;
  const rootIdx = rest.indexOf("--project-root");
  if (rootIdx !== -1) projectRoot = rest[rootIdx + 1];
  const dryRun = rest.includes("--dry-run");
  try {
    console.log(await doMoveSymbol(target, destModule, projectRoot, dryRun));
  } catch (err) {
    console.error(String(err));
    process.exit(1);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
