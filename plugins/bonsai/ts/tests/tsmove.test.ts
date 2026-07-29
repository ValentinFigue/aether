import { describe, it, expect, afterEach } from "vitest";
import * as fs from "fs";
import * as path from "path";
import { executeMove } from "../src/tsmove.js";
import { makeProject, cleanProject, readFile } from "./_helpers.js";

describe("executeMove", () => {
  let root: string;
  afterEach(() => cleanProject(root));

  it("moves a file and rewrites imports in other files", async () => {
    root = makeProject({
      "src/utils.ts": "export function helper(): void {}",
      "src/app.ts": 'import { helper } from "./utils";\nhelper();',
    });
    await executeMove("src/utils.ts", "src/helpers/utils.ts", root);
    expect(fs.existsSync(path.join(root, "src/helpers/utils.ts"))).toBe(true);
    expect(fs.existsSync(path.join(root, "src/utils.ts"))).toBe(false);
    const app = readFile(root, "src/app.ts");
    expect(app).toContain("helpers/utils");
    expect(app).not.toContain('"./utils"');
  });

  it("dry-run does not write files", async () => {
    root = makeProject({
      "src/utils.ts": "export function helper(): void {}",
      "src/app.ts": 'import { helper } from "./utils";\nhelper();',
    });
    const result = await executeMove("src/utils.ts", "src/moved.ts", root, true);
    expect(result).toContain("[DRY RUN]");
    expect(fs.existsSync(path.join(root, "src/utils.ts"))).toBe(true);
    expect(fs.existsSync(path.join(root, "src/moved.ts"))).toBe(false);
  });

  it("returns not-found for missing source", async () => {
    root = makeProject({ "src/app.ts": "export const x = 1;" });
    const result = await executeMove("src/missing.ts", "src/other.ts", root);
    expect(result).toContain("not found");
  });
});
