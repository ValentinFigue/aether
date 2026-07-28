# Contributing

## Setup

```bash
git clone https://github.com/valentinfigue/bonsai
cd bonsai
./setup.sh
```

`setup.sh` creates virtualenvs for both `py/` and `ts/`, installs dependencies, and registers the pre-commit hooks.

## Running tests

```bash
# Python
cd py && pytest

# TypeScript
cd ts && npm test
```

## Linting

```bash
# Python (ruff)
cd py && ruff check src/ tests/ && ruff format --check src/ tests/

# TypeScript (eslint)
cd ts && npm run lint
```

Pre-commit runs both automatically on `git commit`.

## Submitting changes

1. Fork the repo and create a branch from `main`.
2. Make your changes and add tests for any new behaviour.
3. Ensure `pytest` and `ruff` pass cleanly.
4. Open a pull request with a short description of what changed and why.

Please open an issue first for large changes so the approach can be agreed on before investing significant time.
