export class User {
  constructor(public name: string, public email: string) {}

  save(): void {
    // persist user
  }

  delete(): void {
    // remove user
  }
}

/** Deliberately has a same-named .save() method — for type-aware false-positive tests. */
export class Product {
  constructor(public title: string) {}

  save(): void {
    // persist product — different symbol from User.save
  }
}

export type UserId = string;
