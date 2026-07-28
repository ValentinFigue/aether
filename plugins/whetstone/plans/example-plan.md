# Plan: Add JWT Authentication to Express API

> This is an example plan included in the whetstone repo to demonstrate what `/autocritic` output looks like. See `CRITIQUE.md` in this directory for the critique that was generated from it.

## Overview

Add JWT-based authentication to the existing Express.js REST API. Users will log in with email/password and receive a JWT token, which they include in subsequent requests via the `Authorization` header.

## Changes

### 1. Install dependencies
- `jsonwebtoken` for token signing and verification
- `bcrypt` for password hashing at registration

### 2. Database: users table
Add a `password_hash` column to the existing `users` table.

### 3. New endpoints
- `POST /auth/login` — accepts `{ email, password }`, returns `{ token }`
- `POST /auth/register` — creates a user with a hashed password, returns `{ token }`

### 4. Auth middleware
Create `src/middleware/auth.js`. It reads the `Authorization: Bearer <token>` header, verifies the JWT, and attaches `req.user` from the token payload. Returns `401` if the token is missing or invalid.

### 5. Protect existing routes
Mount the auth middleware on all `/api/users/*` and `/api/posts/*` route groups.

## Notes
- JWT secret will be stored in `.env` as `JWT_SECRET`
- Token expiry: 30 days
- No refresh token mechanism for now — simplicity over correctness
- Existing users will need to set a password on first login
