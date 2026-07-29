import { User } from "./models";

export function createUser(name: string, email: string): User {
  const user = new User(name, email);
  user.save(); // call on a User instance — tsfindrefs for User.save should find this
  return user;
}

export function processData(data: string, unusedParam: number): string {
  return data.toUpperCase();
}
