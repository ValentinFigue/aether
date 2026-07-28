import { describe, it, expect, afterEach } from "vitest";
import * as fs from "fs";
import * as path from "path";
import { doMoveSymbol } from "../src/tsmovesymbol.js";
import { makeProject, cleanProject, readFile } from "./_helpers.js";

describe("doMoveSymbol", () => {
  let root: string;
  afterEach(() => cleanProject(root));

  it("moves a function to a new file", async () => {
    root = makeProject({ "src/utils.ts": "export function myHelper(): void {}" });
    await doMoveSymbol("src/utils:myHelper", "src/helpers", root);
    expect(fs.existsSync(path.join(root, "src/helpers.ts"))).toBe(true);
    expect(readFile(root, "src/helpers.ts")).toContain("myHelper");
  });

  it("adds backward-compat re-export to source file", async () => {
    root = makeProject({ "src/utils.ts": "export function myHelper(): void {}" });
    await doMoveSymbol("src/utils:myHelper", "src/helpers", root);
    const src = readFile(root, "src/utils.ts");
    expect(src).toContain("export {");
    expect(src).toContain("myHelper");
    expect(src).toContain("helpers");
  });

  it("moves a class and preserves the body", async () => {
    root = makeProject({
      "src/models.ts": [
        "export class User {",
        "  constructor(public name: string) {}",
        "  save(): void {}",
        "}",
      ].join("\n"),
    });
    await doMoveSymbol("src/models:User", "src/types/user", root);
    const dest = readFile(root, "src/types/user.ts");
    expect(dest).toContain("class User");
    expect(dest).toContain("save()");
  });

  it("dry-run does not write files", async () => {
    root = makeProject({ "src/utils.ts": "export function myHelper(): void {}" });
    const result = await doMoveSymbol("src/utils:myHelper", "src/helpers", root, true);
    expect(result).toContain("[DRY RUN]");
    expect(fs.existsSync(path.join(root, "src/helpers.ts"))).toBe(false);
    expect(readFile(root, "src/utils.ts")).not.toContain("backward-compat");
  });

  it("returns not-found message for missing symbol", async () => {
    root = makeProject({ "src/utils.ts": "export function foo(): void {}" });
    const result = await doMoveSymbol("src/utils:missing", "src/other", root);
    expect(result).toContain("not found");
  });
});
