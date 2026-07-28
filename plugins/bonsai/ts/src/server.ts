import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { findRefs } from "./tsfindrefs.js";
import { doRename } from "./tsrename.js";
import { executeMove } from "./tsmove.js";
import { doMoveSymbol } from "./tsmovesymbol.js";
import { doSignature } from "./tssignature.js";

const server = new McpServer({ name: "bonsai-ts", version: "0.0.1" });

// ── tsfindrefs ─────────────────────────────────────────────────────────────────
server.tool(
  "tsfindrefs",
  `Find all usages of a TypeScript/JavaScript symbol across the project.
Uses the TypeScript compiler API for type-aware resolution — User.save and Product.save
are treated as distinct symbols (no false positives from same-named methods on different classes).

Symbol notation: "path/to/module:Symbol" or "path/to/module:Class.method"
Examples: "src/models/user:User"  "src/services:createUser"  "src/models/user:User.save"

Note: Requires a tsconfig.json in the project root for full type resolution. Without it,
dynamic require() and .d.ts-less third-party packages may be missed.`,
  {
    target: z.string().describe('Symbol ref: "path/to/module:Symbol" or "path/to/module:Class.method"'),
    project_root: z.string().optional().describe("Absolute path to the TypeScript project root (must contain tsconfig.json)"),
  },
  async ({ target, project_root }) => ({
    content: [{ type: "text", text: findRefs(target, project_root) }],
  }),
);

// ── tsrename ───────────────────────────────────────────────────────────────────
server.tool(
  "tsrename",
  `Scope-aware rename of a TypeScript/JavaScript symbol across the entire project.
Uses the TypeScript Language Service to find and rename all references — imports, call sites,
type annotations, re-exports — in one pass. Always run with dry_run=true first.

Symbol notation: "path/to/module:Symbol" or "path/to/module:Class.method"

Note: Dynamic require() strings are not renamed. Symbols in .d.ts-less packages may be missed.`,
  {
    target: z.string().describe('Symbol ref: "path/to/module:Symbol" or "path/to/module:Class.method"'),
    new_name: z.string().describe("The new name for the symbol"),
    project_root: z.string().optional(),
    dry_run: z.boolean().optional().describe("Preview changes without writing files (default: false)"),
  },
  async ({ target, new_name, project_root, dry_run }) => ({
    content: [{ type: "text", text: await doRename(target, new_name, project_root, dry_run ?? false) }],
  }),
);

// ── tsmove ─────────────────────────────────────────────────────────────────────
server.tool(
  "tsmove",
  `Move or rename a TypeScript/JavaScript file (or directory) and rewrite all import paths project-wide.
Uses ts-morph's move() which automatically updates all import declarations that reference the moved file.

Source and destination are relative to the project root.
Examples: "src/utils.ts" → "src/helpers/utils.ts"  or  "src/components" → "src/ui"

Note: Dynamic require() strings and barrel index.ts re-exports may need manual review.
Always run with dry_run=true first.`,
  {
    source: z.string().describe("Relative path of the file or directory to move"),
    destination: z.string().describe("Relative destination path"),
    project_root: z.string().optional(),
    dry_run: z.boolean().optional(),
  },
  async ({ source, destination, project_root, dry_run }) => ({
    content: [{ type: "text", text: await executeMove(source, destination, project_root, dry_run ?? false) }],
  }),
);

// ── tsmovesymbol ───────────────────────────────────────────────────────────────
server.tool(
  "tsmovesymbol",
  `Move a single exported function, class, interface, or type alias to a different module.
Extracts the symbol from the source file, appends it to the destination (creating the file if needed),
and adds a backward-compatible re-export to the source file so existing imports continue to work.

Symbol notation: "path/to/module:Symbol" (top-level symbols only; use tsrename for methods)
Destination: relative module path without extension, e.g. "src/types/user"

Note: Imports across the project that reference the old location continue to work via the re-export.
Run tsfindrefs on the moved symbol to find files you may want to update manually.`,
  {
    target: z.string().describe('Symbol ref: "path/to/module:Symbol"'),
    dest_module: z.string().describe("Destination module path without extension (e.g. src/types/user)"),
    project_root: z.string().optional(),
    dry_run: z.boolean().optional(),
  },
  async ({ target, dest_module, project_root, dry_run }) => ({
    content: [{ type: "text", text: await doMoveSymbol(target, dest_module, project_root, dry_run ?? false) }],
  }),
);

// ── tssignature ────────────────────────────────────────────────────────────────
server.tool(
  "tssignature",
  `Change a function or method's signature and update all call sites.
Supports adding, removing, renaming, and reordering parameters, and changing defaults.
Always run with dry_run=true first to review call-site changes.

Symbol notation: "path/to/module:functionName" or "path/to/module:ClassName.methodName"

Note: TypeScript has no keyword arguments — reorder rewrites positional arguments at call sites.
Added parameters without a default value get "undefined /* TODO: provide <name> */" at call sites.`,
  {
    target: z.string().describe('Function or method ref: "path/to/module:fn" or "path/to/module:Class.method"'),
    add: z
      .array(z.object({ name: z.string(), type: z.string().optional(), default: z.string().optional() }))
      .optional()
      .describe('Parameters to add: [{"name":"timeout","type":"number","default":"30"}]'),
    remove: z.array(z.string()).optional().describe("Parameter names to remove"),
    rename: z
      .array(z.object({ from: z.string(), to: z.string() }))
      .optional()
      .describe('Parameters to rename: [{"from":"userId","to":"uid"}]'),
    reorder: z.array(z.string()).optional().describe("New parameter order (by name)"),
    set_default: z
      .array(z.object({ name: z.string(), value: z.string(), type: z.string().optional() }))
      .optional()
      .describe("Change parameter defaults"),
    project_root: z.string().optional(),
    dry_run: z.boolean().optional(),
  },
  async ({ target, add, remove, rename, reorder, set_default, project_root, dry_run }) => ({
    content: [
      {
        type: "text",
        text: await doSignature(
          target,
          {
            add: add?.map((a) => ({ name: a.name, type: a.type, default: a.default })),
            remove,
            rename,
            reorder,
            setDefault: set_default?.map((s) => ({ name: s.name, value: s.value, type: s.type })),
          },
          project_root,
          dry_run ?? false,
        ),
      },
    ],
  }),
);

// ── Start server ───────────────────────────────────────────────────────────────
const transport = new StdioServerTransport();
await server.connect(transport);
