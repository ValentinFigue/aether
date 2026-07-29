import * as path from "path";
import { parseSymbolRef, findProjectRoot, createProject, findSymbolNode, classifyRef } from "./_common.js";

interface RefEntry {
  filepath: string;
  line: number;
  ref_type: string;
  snippet: string;
}

export function findRefs(target: string, projectRoot?: string): string {
  const ref = parseSymbolRef(target);
  const root = projectRoot ?? findProjectRoot(process.cwd());
  const project = createProject(root);

  const node = findSymbolNode(project, ref, root);
  if (!node) {
    return `Symbol "${target}" not found. Check the module path and symbol name.`;
  }

  // Use the name identifier node for proper Language Service reference finding.
  // Calling findReferencesAsNodes() on the declaration itself may miss the definition site.
  const nameNode: any = (node as any).getNameNode?.() ?? node;
  const refNodes: any[] = nameNode.findReferencesAsNodes?.() ?? [];

  // Always include the definition site (the name node itself) if missing from results.
  const defPos = nameNode.getPos();
  const defSf = nameNode.getSourceFile();
  const hasDefinition = refNodes.some(
    (r: any) => r.getSourceFile() === defSf && Math.abs(r.getPos() - defPos) < 5,
  );
  if (!hasDefinition) refNodes.unshift(nameNode);

  const entries: RefEntry[] = refNodes.map((refNode: any) => {
    const sf = refNode.getSourceFile();
    const line: number = refNode.getStartLineNumber();
    const lineText: string = sf.getFullText().split("\n")[line - 1]?.trim() ?? "";
    return {
      filepath: path.relative(root, sf.getFilePath()),
      line,
      ref_type: classifyRef(refNode),
      snippet: lineText.slice(0, 120),
    };
  });

  if (entries.length === 0) return `No references found for "${target}".`;

  const byType = new Map<string, RefEntry[]>();
  for (const e of entries) {
    const bucket = byType.get(e.ref_type) ?? [];
    bucket.push(e);
    byType.set(e.ref_type, bucket);
  }

  const typeOrder = ["definition", "import", "call", "base_class", "decorator", "attribute", "export", "name"];
  const lines: string[] = [`References for "${target}" (${entries.length} total):\n`];

  for (const type of [...typeOrder, ...Array.from(byType.keys()).filter((t) => !typeOrder.includes(t))]) {
    const group = byType.get(type);
    if (!group) continue;
    lines.push(`${type.toUpperCase()} (${group.length}):`);
    for (const e of group) lines.push(`  ${e.filepath}:${e.line}  ${e.snippet}`);
    lines.push("");
  }

  return lines.join("\n");
}

// ── CLI ────────────────────────────────────────────────────────────────────────

import { fileURLToPath } from "url";

function main(): void {
  const args = process.argv.slice(2);
  if (args.length === 0 || args[0] === "--help") {
    console.log("Usage: tsfindrefs <module/path:Symbol> [--project-root <path>]");
    process.exit(0);
  }
  const target = args[0];
  let projectRoot: string | undefined;
  const rootIdx = args.indexOf("--project-root");
  if (rootIdx !== -1) projectRoot = args[rootIdx + 1];
  try {
    console.log(findRefs(target, projectRoot));
  } catch (err) {
    console.error(String(err));
    process.exit(1);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
