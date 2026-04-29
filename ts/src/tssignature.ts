import { Node, SyntaxKind, CallExpression, FunctionDeclaration, MethodDeclaration, ParameterDeclaration } from "ts-morph";
import {
  parseSymbolRef,
  findProjectRoot,
  createProject,
  findSymbolNode,
  saveBefore,
  collectDiffs,
  formatDiffs,
} from "./_common.js";

export interface AddParam {
  name: string;
  type?: string;
  default?: string;
}
export interface RenameParam {
  from: string;
  to: string;
}
export interface SetDefaultParam {
  name: string;
  value: string;
  type?: string;
}

export interface SignatureOptions {
  add?: AddParam[];
  remove?: string[];
  rename?: RenameParam[];
  reorder?: string[];
  setDefault?: SetDefaultParam[];
}

type FnNode = FunctionDeclaration | MethodDeclaration;

function getFnNode(node: Node): FnNode | undefined {
  if (node.getKind() === SyntaxKind.FunctionDeclaration) return node as FunctionDeclaration;
  if (node.getKind() === SyntaxKind.MethodDeclaration) return node as MethodDeclaration;
  return undefined;
}

function getCallExpression(refNode: Node): CallExpression | undefined {
  const parent = refNode.getParent();
  if (!parent) return undefined;
  // foo()
  const asCall = parent.asKind(SyntaxKind.CallExpression);
  if (asCall && asCall.getExpression() === refNode) return asCall;
  // obj.foo()
  const asProp = parent.asKind(SyntaxKind.PropertyAccessExpression);
  if (asProp) {
    const gp = asProp.getParent()?.asKind(SyntaxKind.CallExpression);
    if (gp && gp.getExpression() === asProp) return gp;
  }
  return undefined;
}

export async function doSignature(
  target: string,
  options: SignatureOptions,
  projectRoot?: string,
  dryRun = false,
): Promise<string> {
  const ref = parseSymbolRef(target);
  const root = projectRoot ?? findProjectRoot(process.cwd());
  const project = createProject(root);

  const node = findSymbolNode(project, ref, root);
  if (!node) return `Symbol "${target}" not found.`;

  const fn = getFnNode(node);
  if (!fn) return `"${target}" is not a function or method — tssignature only works on functions and methods.`;

  // Collect call sites BEFORE modifying the declaration
  const refNodes = (fn as any).findReferencesAsNodes() as Node[];
  const callExprs = refNodes
    .map(getCallExpression)
    .filter((c): c is CallExpression => c !== null && c !== undefined);

  // Save original param order (for reorder + remove position tracking)
  const originalParams = fn.getParameters().map((p) => p.getName());

  const before = saveBefore(project);

  // ── Apply declaration changes ──────────────────────────────────────────────

  // 1. Remove params (in reverse order to preserve indices)
  for (const name of options.remove ?? []) {
    const idx = fn.getParameters().findIndex((p) => p.getName() === name);
    if (idx !== -1) fn.getParameters()[idx].remove();
  }

  // 2. Rename params
  for (const { from, to } of options.rename ?? []) {
    const param = fn.getParameters().find((p) => p.getName() === from);
    if (param) param.rename(to);
  }

  // 3. Add params
  for (const item of options.add ?? []) {
    fn.addParameter({
      name: item.name,
      type: item.type,
      initializer: item.default,
    });
  }

  // 4. Reorder params
  if (options.reorder && options.reorder.length > 0) {
    const currentParams = fn.getParameters();
    const nameToParam = new Map<string, ParameterDeclaration>();
    for (const p of currentParams) nameToParam.set(p.getName(), p);

    // Build ordered list (params not mentioned in reorder go at end)
    const reordered: ParameterDeclaration[] = [];
    for (const name of options.reorder) {
      const p = nameToParam.get(name);
      if (p) { reordered.push(p); nameToParam.delete(name); }
    }
    for (const p of nameToParam.values()) reordered.push(p);

    // Rebuild param list by replacing structure text
    const paramTexts = reordered.map((p) => p.getText());
    // Remove all then re-insert
    while (fn.getParameters().length > 0) fn.getParameters()[0].remove();
    for (const text of paramTexts) {
      (fn as any).addParameter({ name: "_placeholder_" });
      const inserted = fn.getParameters()[fn.getParameters().length - 1];
      inserted.replaceWithText(text);
    }
  }

  // 5. Set defaults
  for (const item of options.setDefault ?? []) {
    const param = fn.getParameters().find((p) => p.getName() === item.name);
    if (param) {
      param.setInitializer(item.value);
      if (item.type) param.setType(item.type);
    }
  }

  // ── Update call sites ──────────────────────────────────────────────────────

  for (const callExpr of callExprs) {
    // Remove
    for (const name of options.remove ?? []) {
      const idx = originalParams.indexOf(name);
      const currentArgs = callExpr.getArguments();
      if (idx !== -1 && idx < currentArgs.length) {
        callExpr.removeArgument(idx);
      }
    }

    // Add (no default → insert placeholder)
    for (const item of options.add ?? []) {
      if (item.default === undefined) {
        callExpr.addArgument(`undefined /* TODO: provide ${item.name} */`);
      }
    }

    // Reorder call arguments
    if (options.reorder && options.reorder.length > 0) {
      const currentArgs = callExpr.getArguments().map((a) => a.getText());
      if (currentArgs.length > 0) {
        // Map old param positions to new positions
        const newOrder = options.reorder
          .map((name) => {
            const origIdx = originalParams.indexOf(name);
            return origIdx !== -1 && origIdx < currentArgs.length ? currentArgs[origIdx] : "undefined";
          });
        // Remaining params not in reorder
        const mentionedOrigIdxs = new Set(options.reorder.map((n) => originalParams.indexOf(n)));
        for (let i = 0; i < currentArgs.length; i++) {
          if (!mentionedOrigIdxs.has(i)) newOrder.push(currentArgs[i]);
        }

        // Replace all args
        while (callExpr.getArguments().length > 0) callExpr.removeArgument(0);
        for (const text of newOrder) callExpr.addArgument(text);
      }
    }
  }

  const diffs = collectDiffs(project, before);

  if (dryRun) {
    if (diffs.length === 0) return "No changes would be made.";
    return `[DRY RUN] Would update signature for "${target}":\n\n${formatDiffs(diffs)}`;
  }

  await project.save();

  const ops: string[] = [];
  if (options.remove?.length) ops.push(`removed: ${options.remove.join(", ")}`);
  if (options.rename?.length) ops.push(`renamed: ${options.rename.map((r) => `${r.from}→${r.to}`).join(", ")}`);
  if (options.add?.length) ops.push(`added: ${options.add.map((a) => a.name).join(", ")}`);
  if (options.reorder?.length) ops.push("reordered params");
  if (options.setDefault?.length) ops.push(`set defaults: ${options.setDefault.map((s) => s.name).join(", ")}`);

  const callNote =
    callExprs.length > 0
      ? `\nUpdated ${callExprs.length} call site(s). Check for any "TODO: provide" markers.`
      : "";
  return `Updated signature for "${target}" (${ops.join("; ")}).${callNote}`;
}

// ── CLI ────────────────────────────────────────────────────────────────────────

import { fileURLToPath } from "url";

async function main(): Promise<void> {
  console.log("Use the MCP tool tssignature or import doSignature() programmatically.");
  console.log("CLI: tssignature <target> --add name[:type[:default]] --remove name --rename old:new --project-root <path> --dry-run");
  process.exit(0);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
