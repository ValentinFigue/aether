import { createUser } from "./services";

export function bootstrap(): void {
  createUser("Alice", "alice@example.com");
  createUser("Bob", "bob@example.com");
}

export function orphanedHelper(): void {
  // never called — demonstrates a dead symbol
}
