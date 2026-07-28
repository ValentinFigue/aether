#!/usr/bin/env bash
set -e

echo "==> Python tests"
cd py && uv run pytest tests/ -v && cd ..

echo "==> TypeScript tests"
cd ts && npm test && cd ..
