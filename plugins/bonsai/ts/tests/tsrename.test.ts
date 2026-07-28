import { describe, it, expect, afterEach } from "vitest";
import { doRename } from "../src/tsrename.js";
import { makeProject, cleanProject, readFile } from "./_helpers.js";

describe("doRename", () => {
  let root: string;
  afterEach(() => cleanProject(root));

  it("renames a function definition and all call sites", async () => {
    root = makeProject({
      "src/utils.ts": "export function oldName(): void {}",
      "src/caller.ts": 'import { oldName } from "./utils";\noldName();',
    });
    const result = await doRename("src/utils:oldName", "newName", root);
    expect(result).toContain("newName");
    expect(readFile(root, "src/utils.ts")).toContain("newName");
    expect(readFile(root, "src/caller.ts")).toContain("newName");
    expect(readFile(root, "src/caller.ts")).not.toContain("oldName");
  });

  it("renames a class and updates the import specifier", async () => {
    root = makeProject({
      "src/models.ts": "export class OldClass {}",
      "src/app.ts": 'import { OldClass } from "./models";\nconst x = new OldClass();',
    });
    await doRename("src/models:OldClass", "NewClass", root);
    expect(readFile(root, "src/models.ts")).toContain("NewClass");
    expect(readFile(root, "src/app.ts")).toContain("NewClass");
    expect(readFile(root, "src/app.ts")).not.toContain("OldClass");
  });

  it("dry-run does not write files", async () => {
    root = makeProject({
      "src/utils.ts": "export function oldName(): void {}",
    });
    const result = await doRename("src/utils:oldName", "newName", root, true);
    expect(result).toContain("[DRY RUN]");
    expect(readFile(root, "src/utils.ts")).toContain("oldName");
    expect(readFile(root, "src/utils.ts")).not.toContain("newName");
  });

  it("renames a method on a class", async () => {
    root = makeProject({
      "src/models.ts": "export class User { oldMethod(): void {} }",
      "src/app.ts": 'import { User } from "./models";\nconst u = new User();\nu.oldMethod();',
    });
    await doRename("src/models:User.oldMethod", "newMethod", root);
    expect(readFile(root, "src/models.ts")).toContain("newMethod");
    expect(readFile(root, "src/app.ts")).toContain("newMethod");
  });

  it("returns not-found message for unknown symbol", async () => {
    root = makeProject({ "src/utils.ts": "export function foo(): void {}" });
    const result = await doRename("src/utils:missing", "bar", root);
    expect(result).toContain("not found");
  });
});
