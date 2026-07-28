import * as fs from "fs";
import * as os from "os";
import * as path from "path";

const DEFAULT_TSCONFIG = {
  compilerOptions: {
    target: "ES2020",
    module: "CommonJS",
    moduleResolution: "node",
    strict: true,
  },
  include: ["src"],
};

/**
 * Create a temporary project directory with given files.
 * Returns the project root path. Caller is responsible for cleanup.
 */
export function makeProject(
  files: Record<string, string>,
  tsconfig: object = DEFAULT_TSCONFIG,
): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "bonsai-ts-test-"));
  fs.writeFileSync(path.join(root, "tsconfig.json"), JSON.stringify(tsconfig, null, 2));
  for (const [rel, content] of Object.entries(files)) {
    const abs = path.join(root, rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, content);
  }
  return root;
}

export function cleanProject(root: string): void {
  fs.rmSync(root, { recursive: true, force: true });
}

export function readFile(root: string, rel: string): string {
  return fs.readFileSync(path.join(root, rel), "utf8");
}
