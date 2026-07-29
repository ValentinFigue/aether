import { describe, it, expect, afterEach } from "vitest";
import { doSignature } from "../src/tssignature.js";
import { makeProject, cleanProject, readFile } from "./_helpers.js";

describe("doSignature", () => {
  let root: string;
  afterEach(() => cleanProject(root));

  it("adds a parameter with a default to the declaration", async () => {
    root = makeProject({
      "src/api.ts": "export function createUser(name: string): void {}",
      "src/app.ts": 'import { createUser } from "./api";\ncreateUser("Alice");',
    });
    await doSignature("src/api:createUser", { add: [{ name: "timeout", type: "number", default: "30" }] }, root);
    expect(readFile(root, "src/api.ts")).toContain("timeout");
    expect(readFile(root, "src/api.ts")).toContain("30");
  });

  it("adds a required parameter and inserts TODO at call sites", async () => {
    root = makeProject({
      "src/api.ts": "export function createUser(name: string): void {}",
      "src/app.ts": 'import { createUser } from "./api";\ncreateUser("Alice");',
    });
    await doSignature("src/api:createUser", { add: [{ name: "role", type: "string" }] }, root);
    const app = readFile(root, "src/app.ts");
    expect(app).toContain("TODO: provide role");
  });

  it("removes a parameter and its argument at call sites", async () => {
    root = makeProject({
      "src/api.ts": "export function fn(x: number, y: string): void {}",
      "src/app.ts": 'import { fn } from "./api";\nfn(1, "hello");',
    });
    await doSignature("src/api:fn", { remove: ["y"] }, root);
    expect(readFile(root, "src/api.ts")).not.toContain("y: string");
    expect(readFile(root, "src/app.ts")).not.toContain('"hello"');
  });

  it("renames a parameter in the declaration", async () => {
    root = makeProject({
      "src/api.ts": "export function fn(userId: string): string { return userId; }",
    });
    await doSignature("src/api:fn", { rename: [{ from: "userId", to: "uid" }] }, root);
    expect(readFile(root, "src/api.ts")).toContain("uid");
    expect(readFile(root, "src/api.ts")).not.toContain("userId");
  });

  it("reorders parameters in the declaration", async () => {
    root = makeProject({
      "src/api.ts": "export function fn(a: number, b: string, c: boolean): void {}",
      "src/app.ts": 'import { fn } from "./api";\nfn(1, "hello", true);',
    });
    await doSignature("src/api:fn", { reorder: ["b", "a", "c"] }, root);
    const decl = readFile(root, "src/api.ts");
    const paramOrder = ["b", "a", "c"].every((name) => decl.includes(name));
    expect(paramOrder).toBe(true);
    // Check declaration has b before a
    const bIdx = decl.indexOf("b: string");
    const aIdx = decl.indexOf("a: number");
    expect(bIdx).toBeLessThan(aIdx);
  });

  it("sets a default value", async () => {
    root = makeProject({
      "src/api.ts": "export function fn(retries: number): void {}",
    });
    await doSignature("src/api:fn", { setDefault: [{ name: "retries", value: "3" }] }, root);
    expect(readFile(root, "src/api.ts")).toContain("= 3");
  });

  it("dry-run does not write files", async () => {
    root = makeProject({ "src/api.ts": "export function fn(x: number): void {}" });
    const result = await doSignature("src/api:fn", { add: [{ name: "y", type: "string" }] }, root, true);
    expect(result).toContain("[DRY RUN]");
    expect(readFile(root, "src/api.ts")).not.toContain("y: string");
  });

  it("returns not-found for missing function", async () => {
    root = makeProject({ "src/api.ts": "export function foo(): void {}" });
    const result = await doSignature("src/api:missing", { add: [{ name: "x" }] }, root);
    expect(result).toContain("not found");
  });

  it("rejects non-function targets", async () => {
    root = makeProject({ "src/models.ts": "export class User {}" });
    const result = await doSignature("src/models:User", { add: [{ name: "x" }] }, root);
    expect(result).toContain("not a function or method");
  });
});
