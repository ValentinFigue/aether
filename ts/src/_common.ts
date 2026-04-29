import * as fs from "fs";
import * as path from "path";
import { Node, Project, SyntaxKind } from "ts-morph";
import { createTwoFilesPatch } from "diff";

export const SKIP_DIRS = new Set([
  ".git", ".hg", "__pycache__", "node_modules", ".next", ".nuxt",
  "dist", "build", "out", ".turbo", "coverage", ".cache",
]);

export const TS_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx", ".mts", ".cts"];

export interface SymbolRef {
  modulePath: string;    // path without extension: "src/models/user"
  symbolName: string;    // e.g. "User"
  memberName?: string;   // e.g. "save" for "User.save"
}

export function parseSymbolRef(ref: string): SymbolRef {
  const colonIdx = ref.indexOf(":");
  if (colonIdx === -1) {
    throw new Error(
      `Invalid symbol ref "${ref}": expected "path/to/module:Symbol" or "path/to/module:Class.method"`,
    );
  }
  let modulePath = ref.slice(0, colonIdx);
  for (const ext of TS_EXTENSIONS) {
    if (modulePath.endsWith(ext)) {
      modulePath = modulePath.slice(0, -ext.length);
      break;
    }
  }
  const symbolPart = ref.slice(colonIdx + 1);
  const dotIdx = symbolPart.indexOf(".");
  if (dotIdx === -1) return { modulePath, symbolName: symbolPart };
  return {
    modulePath,
    symbolName: symbolPart.slice(0, dotIdx),
    memberName: symbolPart.slice(dotIdx + 1),
  };
}

export function findProjectRoot(start: string): string {
  let current = path.resolve(start);
  while (true) {
    if (fs.existsSync(path.join(current, "tsconfig.json"))) return current;
    if (fs.existsSync(path.join(current, "package.json"))) return current;
    if (fs.existsSync(path.join(current, ".git"))) return current;
    const parent = path.dirname(current);
    if (parent === current) return path.resolve(start);
    current = parent;
  }
}

export function collectTsFiles(root: string): string[] {
  const results: string[] = [];
  function walk(dir: string): void {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (SKIP_DIRS.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (TS_EXTENSIONS.some((ext) => entry.name.endsWith(ext))) {
        results.push(full);
      }
    }
  }
  walk(root);
  return results.sort();
}

export function createProject(root: string): Project {
  const tsConfigPath = path.join(root, "tsconfig.json");
  if (fs.existsSync(tsConfigPath)) {
    return new Project({
      tsConfigFilePath: tsConfigPath,
      skipAddingFilesFromTsConfig: false,
    });
  }
  const project = new Project({ compilerOptions: { allowJs: true } });
  for (const file of collectTsFiles(root)) project.addSourceFileAtPath(file);
  return project;
}

export function findSourceFile(project: Project, modulePath: string, root: string) {
  for (const ext of TS_EXTENSIONS) {
    const sf = project.getSourceFile(path.resolve(root, modulePath + ext));
    if (sf) return sf;
  }
  const direct = project.getSourceFile(path.resolve(root, modulePath));
  if (direct) return direct;
  const normalized = modulePath.replace(/\\/g, "/");
  return project.getSourceFiles().find((sf) => {
    const fp = sf.getFilePath().replace(/\\/g, "/");
    return TS_EXTENSIONS.some((ext) => fp.endsWith("/" + normalized + ext))
      || fp.endsWith("/" + normalized);
  });
}

export function findSymbolNode(project: Project, ref: SymbolRef, root: string): Node | undefined {
  const sf = findSourceFile(project, ref.modulePath, root);
  if (!sf) return undefined;

  if (ref.memberName) {
    const cls = sf.getClass(ref.symbolName);
    if (cls) {
      return (
        cls.getMethod(ref.memberName) ??
        cls.getProperty(ref.memberName) ??
        cls.getGetAccessor(ref.memberName) ??
        cls.getSetAccessor(ref.memberName)
      );
    }
    const iface = sf.getInterface(ref.symbolName);
    if (iface) return iface.getMethod(ref.memberName) ?? iface.getProperty(ref.memberName);
    return undefined;
  }

  return (
    sf.getFunction(ref.symbolName) ??
    sf.getClass(ref.symbolName) ??
    sf.getInterface(ref.symbolName) ??
    sf.getTypeAlias(ref.symbolName) ??
    sf.getVariableDeclaration(ref.symbolName) ??
    sf.getEnum(ref.symbolName)
  );
}

// ── Diff utilities ─────────────────────────────────────────────────────────────

export interface FileDiff {
  filepath: string;
  before: string;
  after: string;
  patch: string;
}

export function computeDiff(filepath: string, before: string, after: string): FileDiff {
  const patch = createTwoFilesPatch(filepath, filepath, before, after, "before", "after", {
    context: 3,
  });
  return { filepath, before, after, patch };
}

export function formatDiffs(diffs: FileDiff[]): string {
  if (diffs.length === 0) return "No changes.";
  return diffs.map((d) => `Would modify: ${d.filepath}\n${d.patch}`).join("\n");
}

export function saveBefore(project: Project): Map<string, string> {
  const map = new Map<string, string>();
  for (const sf of project.getSourceFiles()) map.set(sf.getFilePath(), sf.getFullText());
  return map;
}

export function collectDiffs(project: Project, before: Map<string, string>): FileDiff[] {
  const diffs: FileDiff[] = [];
  for (const sf of project.getSourceFiles()) {
    const fp = sf.getFilePath();
    const beforeText = before.get(fp) ?? "";
    const afterText = sf.getFullText();
    if (beforeText !== afterText) diffs.push(computeDiff(fp, beforeText, afterText));
  }
  return diffs;
}

// ── Reference classification ───────────────────────────────────────────────────

export function classifyRef(node: Node): string {
  const parent = node.getParent();
  if (!parent) return "name";
  const kind = parent.getKind();

  if (
    kind === SyntaxKind.FunctionDeclaration ||
    kind === SyntaxKind.ClassDeclaration ||
    kind === SyntaxKind.InterfaceDeclaration ||
    kind === SyntaxKind.TypeAliasDeclaration ||
    kind === SyntaxKind.MethodDeclaration ||
    kind === SyntaxKind.PropertyDeclaration ||
    kind === SyntaxKind.GetAccessor ||
    kind === SyntaxKind.SetAccessor ||
    kind === SyntaxKind.EnumDeclaration ||
    kind === SyntaxKind.EnumMember ||
    kind === SyntaxKind.VariableDeclaration
  ) return "definition";

  if (kind === SyntaxKind.ImportSpecifier || kind === SyntaxKind.ImportClause) return "import";
  if (kind === SyntaxKind.ExportSpecifier) return "export";
  if (kind === SyntaxKind.ExpressionWithTypeArguments) return "base_class";
  if (kind === SyntaxKind.Decorator) return "decorator";

  if (kind === SyntaxKind.PropertyAccessExpression) {
    const gp = parent.getParent();
    if (gp?.getKind() === SyntaxKind.CallExpression) {
      const call = gp.asKind(SyntaxKind.CallExpression)!;
      if (call.getExpression() === parent) return "call";
    }
    return "attribute";
  }

  if (kind === SyntaxKind.CallExpression) return "call";
  return "name";
}
