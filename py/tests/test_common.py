"""Unit tests for bonsai_python._common utilities."""

from pathlib import Path

from bonsai_python._common import (
    FileChanges,
    FileEdit,
    apply_changes,
    find_module_path,
    module_aliases_for_file,
    module_to_path,
    path_to_module,
    python_roots,
    resolve_relative_import,
)

# ── path_to_module ─────────────────────────────────────────────────────────────


class TestPathToModule:
    def test_flat_module(self, tmp_path):
        f = tmp_path / "mymod.py"
        f.write_text("")
        assert path_to_module(f, tmp_path) == "mymod"

    def test_nested_module(self, tmp_path):
        pkg = tmp_path / "pkg"
        pkg.mkdir()
        (pkg / "__init__.py").write_text("")
        f = pkg / "sub.py"
        f.write_text("")
        assert path_to_module(f, tmp_path) == "pkg.sub"

    def test_package_init_returns_package_name(self, tmp_path):
        pkg = tmp_path / "pkg"
        pkg.mkdir()
        init = pkg / "__init__.py"
        init.write_text("")
        assert path_to_module(init, tmp_path) == "pkg"

    def test_file_outside_root_returns_none(self, tmp_path):
        outside = tmp_path.parent / "outside.py"
        assert path_to_module(outside, tmp_path) is None


# ── module_to_path ─────────────────────────────────────────────────────────────


class TestModuleToPath:
    def test_module_file(self, tmp_path):
        f = tmp_path / "mod.py"
        f.write_text("")
        assert module_to_path("mod", tmp_path) == f

    def test_package_resolves_to_init(self, tmp_path):
        pkg = tmp_path / "pkg"
        pkg.mkdir()
        init = pkg / "__init__.py"
        init.write_text("")
        assert module_to_path("pkg", tmp_path) == init

    def test_nonexistent_module_returns_none(self, tmp_path):
        assert module_to_path("nonexistent", tmp_path) is None

    def test_round_trip(self, tmp_path):
        pkg = tmp_path / "mypkg"
        pkg.mkdir()
        f = pkg / "utils.py"
        f.write_text("")
        module = path_to_module(f, tmp_path)
        assert module is not None
        assert module_to_path(module, tmp_path) == f


# ── python_roots ───────────────────────────────────────────────────────────────


class TestPythonRoots:
    def test_always_includes_root(self, tmp_path):
        assert tmp_path in python_roots(tmp_path)

    def test_src_layout_detected(self, tmp_path):
        src = tmp_path / "src"
        pkg = src / "mypkg"
        pkg.mkdir(parents=True)
        (pkg / "__init__.py").write_text("")
        assert src in python_roots(tmp_path)

    def test_src_without_packages_not_added(self, tmp_path):
        src = tmp_path / "src"
        src.mkdir()
        # No package inside — should NOT be added as a root
        (src / "readme.txt").write_text("not a package")
        assert src not in python_roots(tmp_path)

    def test_nested_project_detected(self, tmp_path):
        sub = tmp_path / "subproject"
        sub.mkdir()
        (sub / "pyproject.toml").write_text("[project]\nname='sub'\n")
        assert sub in python_roots(tmp_path)


# ── find_module_path ───────────────────────────────────────────────────────────


class TestFindModulePath:
    def test_flat_layout(self, tmp_path):
        f = tmp_path / "utils.py"
        f.write_text("")
        assert find_module_path("utils", tmp_path) == f

    def test_src_layout(self, tmp_path):
        pkg = tmp_path / "src" / "mypkg"
        pkg.mkdir(parents=True)
        (pkg / "__init__.py").write_text("")
        f = pkg / "utils.py"
        f.write_text("")
        assert find_module_path("mypkg.utils", tmp_path) == f

    def test_not_found_returns_none(self, tmp_path):
        assert find_module_path("nonexistent.module", tmp_path) is None


# ── resolve_relative_import ────────────────────────────────────────────────────


class TestResolveRelativeImport:
    def _setup_pkg(self, tmp_path):
        pkg = tmp_path / "pkg"
        pkg.mkdir()
        (pkg / "__init__.py").write_text("")
        f = pkg / "sub.py"
        f.write_text("")
        return f

    def test_single_dot_with_module(self, tmp_path):
        f = self._setup_pkg(tmp_path)
        assert resolve_relative_import(f, tmp_path, 1, "utils") == "pkg.utils"

    def test_single_dot_bare(self, tmp_path):
        f = self._setup_pkg(tmp_path)
        assert resolve_relative_import(f, tmp_path, 1, None) == "pkg"

    def test_double_dot(self, tmp_path):
        sub = tmp_path / "pkg" / "sub"
        sub.mkdir(parents=True)
        (tmp_path / "pkg" / "__init__.py").write_text("")
        (sub / "__init__.py").write_text("")
        f = sub / "mod.py"
        f.write_text("")
        assert resolve_relative_import(f, tmp_path, 2, "utils") == "pkg.utils"


# ── FileChanges.apply ──────────────────────────────────────────────────────────


class TestFileChangesApply:
    def test_single_line_replacement(self):
        lines = ["hello world\n", "second line\n"]
        fc = FileChanges(
            filepath=Path("x.py"),
            edits=[FileEdit(0, 0, 6, 11, "there")],
        )
        result = fc.apply(lines)
        assert result[0] == "hello there\n"
        assert result[1] == "second line\n"

    def test_multi_line_replacement_collapses_lines(self):
        lines = ["line1\n", "line2\n", "line3\n"]
        fc = FileChanges(
            filepath=Path("x.py"),
            edits=[FileEdit(0, 1, 0, 5, "replaced")],
        )
        result = fc.apply(lines)
        assert len(result) == 2
        assert result[0] == "replaced\n"
        assert result[1] == "line3\n"

    def test_multiple_edits_applied_independently(self):
        lines = ["aaa\n", "bbb\n"]
        fc = FileChanges(
            filepath=Path("x.py"),
            edits=[
                FileEdit(0, 0, 0, 3, "AAA"),
                FileEdit(1, 1, 0, 3, "BBB"),
            ],
        )
        result = fc.apply(lines)
        assert result == ["AAA\n", "BBB\n"]


# ── apply_changes ──────────────────────────────────────────────────────────────


class TestApplyChanges:
    def test_dry_run_does_not_write(self, tmp_path):
        f = tmp_path / "mod.py"
        f.write_text("original = 1\n")
        fc = FileChanges(filepath=f, edits=[FileEdit(0, 0, 0, 8, "modified")])
        apply_changes([fc], dry_run=True)
        assert f.read_text() == "original = 1\n"

    def test_normal_write_modifies_file(self, tmp_path):
        f = tmp_path / "mod.py"
        f.write_text("old = 1\n")
        # "old = 1\n" — the "1" is at columns 6:7
        fc = FileChanges(filepath=f, edits=[FileEdit(0, 0, 6, 7, "2")])
        count = apply_changes([fc], dry_run=False)
        assert count == 1
        assert f.read_text() == "old = 2\n"

    def test_returns_number_of_files_changed(self, tmp_path):
        f1 = tmp_path / "a.py"
        f2 = tmp_path / "b.py"
        f1.write_text("x = 1\n")
        f2.write_text("y = 1\n")
        changes = [
            FileChanges(filepath=f1, edits=[FileEdit(0, 0, 4, 5, "2")]),
            FileChanges(filepath=f2, edits=[FileEdit(0, 0, 4, 5, "2")]),
        ]
        assert apply_changes(changes, dry_run=False) == 2


# ── module_aliases_for_file ────────────────────────────────────────────────────


class TestModuleAliasesForFile:
    def test_returns_all_aliases_across_roots(self, tmp_path):
        src = tmp_path / "src"
        pkg = src / "mypkg"
        pkg.mkdir(parents=True)
        (pkg / "__init__.py").write_text("")
        f = pkg / "utils.py"
        f.write_text("")
        roots = python_roots(tmp_path)
        aliases = module_aliases_for_file(f, roots)
        # Should have at least the src-root alias
        assert "mypkg.utils" in aliases
