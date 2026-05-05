# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.0.1] - 2026-05-05

### Added

**bonsai-py** — AST-based Python refactoring MCP server:
- `pyrename` — rename a symbol across an entire project
- `pymove` — move a module file and update all imports
- `pymovesymbol` — move a symbol between modules
- `pysignature` — add, remove, rename, reorder, or set defaults on function parameters, with automatic call-site rewriting
- `pyfindrefs` — find all references to a symbol
- `pycallers` — find all callers of a function
- `pyfindunused` — detect dead code, unused parameters, and unused imports
- `pygrep` — regex search across Python files

**bonsai-ts** — TypeScript/TSX refactoring MCP server:
- `tsrename` — rename a symbol across a TypeScript project
- `tsmove` — move a file and update all imports
- `tsmovesymbol` — move a symbol between modules
- `tssignature` — modify function signatures with call-site rewriting
- `tsfindrefs` — find all references to a symbol

All mutating tools default to `dry_run=True`.
