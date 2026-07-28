# Critique — example-plan.md — 2026-05-06

> This is the `/autocritic` output for `example-plan.md`. It demonstrates the kind of findings whetstone surfaces and the severity ratings system.

### Critique report

| # | Critic | Severity | Finding | Recommendation |
|---|--------|----------|---------|----------------|
| 1 | Impl | 🔴 | No migration strategy for existing users — adding `password_hash` column leaves all current rows NULL; login will silently fail for anyone who existed before the migration | Add a nullable column initially; build a "set password on first login" flow or a backfill script, and document the migration steps |
| 2 | Impl | 🔴 | `bcrypt` work factor not specified — the default (`10`) may be too low for production and too slow for test suites without a dedicated config | Set work factor explicitly (e.g. `12` for prod, `1` for test via `NODE_ENV` check) |
| 3 | Impl | 🟡 | No rate limiting on `POST /auth/login` — an attacker can brute-force passwords without throttling | Add `express-rate-limit` on auth routes; lock accounts after N failures |
| 4 | Arch | 🔴 | 30-day non-expiring JWT with no refresh token and no revocation mechanism — a leaked token is valid for a month with no way to invalidate it | Use short-lived access tokens (15 min) + refresh tokens stored server-side; or add a token blocklist for logout/revocation |
| 5 | Arch | 🟡 | Auth middleware mounted at route-group level (`/api/users/*`) rather than per-route — future routes added under that prefix inherit auth silently, which will surprise contributors | Mount per-route or use an explicit allowlist; make the protection boundary visible |
| 6 | Risk | 🔴 | JWT secret in `.env` with no rotation mechanism or environment separation — if `JWT_SECRET` leaks, all tokens ever signed are compromised | Document secret rotation, use different secrets per environment, consider key IDs (`kid`) to support rotation without immediate invalidation |
| 7 | Risk | 🟡 | `req.user` is set from the JWT payload without validating that the user still exists in the database — a deleted or suspended user can still make requests with a valid token | Optionally verify user existence on sensitive operations, or keep token TTL short enough that this is acceptable |
| 8 | Risk | 🟢 | No logging of failed authentication attempts — makes post-incident analysis and anomaly detection impossible | Log `{ event: 'auth.failure', reason, ip, timestamp }` on every 401 |

**Blockers:** 4
**Significant:** 2
**Minor:** 1

---

*4 blockers found. The plan should not be implemented as written. The most critical issues are the missing token revocation strategy (#4), the JWT secret rotation gap (#6), and the lack of a migration plan for existing users (#1).*
