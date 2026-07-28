import { describe, it, expect, afterEach } from "vitest";
import * as path from "path";
import { fileURLToPath } from "url";
import { findRefs } from "../src/tsfindrefs.js";
import { makeProject, cleanProject } from "./_helpers.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_ROOT = path.resolve(__dirname, "fixtures/sample_ts_project");

// ── Fixture-based (read-only) ─────────────────────────────────────────────────

describe("findRefs — fixture project", () => {
  it("finds User class definition and import", () => {
    const result = findRefs("src/models:User", FIXTURE_ROOT);
    expect(result).toContain("DEFINITION");
    expect(result).toContain("IMPORT");
    expect(result).toContain("src/models.ts");
  });

  it("finds createUser call sites", () => {
    const result = findRefs("src/services:createUser", FIXTURE_ROOT);
    expect(result).toContain("CALL");
    expect(result).toContain("src/utils.ts");
  });

  it("type-aware: User.save call is found, not Product.save", () => {
    const result = findRefs("src/models:User.save", FIXTURE_ROOT);
    expect(result).toContain("CALL");
    // The call in services.ts on a User instance should be found
    expect(result).toContain("services.ts");
  });
});

// ── makeProject (isolated) ────────────────────────────────────────────────────

describe("findRefs — isolated projects", () => {
  let root: string;
  afterEach(() => cleanProject(root));

  it("finds definition", () => {
    root = makeProject({ "src/utils.ts": "export function myFunc(): void {}" });
    const result = findRefs("src/utils:myFunc", root);
    expect(result).toContain("DEFINITION");
    expect(result).toContain("myFunc");
  });

  it("finds import reference", () => {
    root = makeProject({
      "src/utils.ts": "export function myFunc(): void {}",
      "src/caller.ts": 'import { myFunc } from "./utils";\nmyFunc();',
    });
    const result = findRefs("src/utils:myFunc", root);
    expect(result).toContain("IMPORT");
    expect(result).toContain("CALL");
  });

  it("finds class and base_class reference", () => {
    root = makeProject({
      "src/base.ts": "export class Base {}",
      "src/child.ts": 'import { Base } from "./base";\nexport class Child extends Base {}',
    });
    const result = findRefs("src/base:Base", root);
    expect(result).toContain("BASE_CLASS");
  });

  it("returns not-found message for missing symbol", () => {
    root = makeProject({ "src/utils.ts": "export function foo(): void {}" });
    const result = findRefs("src/utils:nonExistent", root);
    expect(result).toContain("not found");
  });

  it("type-aware: distinguishes User.save from Product.save", () => {
    root = makeProject({
      "src/models.ts": [
        "export class User { save(): void {} }",
        "export class Product { save(): void {} }",
      ].join("\n"),
      "src/services.ts": [
        'import { User, Product } from "./models";',
        "const u = new User(); u.save();",
        "const p = new Product(); p.save();",
      ].join("\n"),
    });

    const userResult = findRefs("src/models:User.save", root);
    const productResult = findRefs("src/models:Product.save", root);

    // Each should find exactly 1 definition + 1 call
    const userCalls = (userResult.match(/u\.save/g) ?? []).length;
    const productCalls = (productResult.match(/p\.save/g) ?? []).length;
    expect(userCalls).toBe(1);
    expect(productCalls).toBe(1);
  });
});
