"""Tests for bonsai_python.pyrename.do_rename."""

from bonsai_python.pyrename import do_rename


class TestDoRename:
    def test_dry_run_returns_true_without_writing(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def old_name():\n    pass\n",
            }
        )
        result = do_rename("mypkg.utils:old_name", "new_name", root, dry_run=True)
        assert result is True
        # File must be unchanged
        assert "old_name" in (root / "src/mypkg/utils.py").read_text()

    def test_renames_definition(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def old_name():\n    pass\n",
            }
        )
        do_rename("mypkg.utils:old_name", "new_name", root, dry_run=False)
        text = (root / "src/mypkg/utils.py").read_text()
        assert "def new_name" in text
        assert "def old_name" not in text

    def test_renames_import_and_call_in_other_file(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def old_name():\n    pass\n",
                "src/mypkg/caller.py": "from mypkg.utils import old_name\nold_name()\n",
            }
        )
        do_rename("mypkg.utils:old_name", "new_name", root, dry_run=False)
        text = (root / "src/mypkg/caller.py").read_text()
        assert "new_name" in text
        assert "old_name" not in text

    def test_unknown_module_returns_false(self, make_project):
        root = make_project({"src/mypkg/__init__.py": ""})
        result = do_rename("mypkg.nonexistent:func", "new_name", root, dry_run=True)
        assert result is False

    def test_renames_symbol_in_all_on_definition_file(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": (
                    '__all__ = ["old_name", "other"]\n'
                    "\n"
                    "def old_name():\n"
                    "    pass\n"
                ),
            }
        )
        do_rename("mypkg.utils:old_name", "new_name", root, dry_run=False)
        text = (root / "src/mypkg/utils.py").read_text()
        assert '"new_name"' in text or "'new_name'" in text
        assert '"old_name"' not in text and "'old_name'" not in text
        assert "def new_name" in text

    def test_renames_symbol_in_all_on_reexporting_module(self, make_project):
        """__all__ in an __init__.py that re-exports the symbol should be updated."""
        root = make_project(
            {
                "src/mypkg/__init__.py": (
                    "from .utils import old_name\n"
                    '\n__all__ = ["old_name"]\n'
                ),
                "src/mypkg/utils.py": "def old_name():\n    pass\n",
            }
        )
        do_rename("mypkg.utils:old_name", "new_name", root, dry_run=False)
        init_text = (root / "src/mypkg/__init__.py").read_text()
        assert '"new_name"' in init_text or "'new_name'" in init_text
        assert '"old_name"' not in init_text and "'old_name'" not in init_text

    def test_local_shadow_not_renamed(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def target():\n    pass\n",
                "src/mypkg/other.py": (
                    "from mypkg.utils import target\n"
                    "\n"
                    "def foo():\n"
                    "    target = 42  # local shadow — must not be renamed\n"
                    "    return target\n"
                ),
            }
        )
        do_rename("mypkg.utils:target", "renamed", root, dry_run=False)
        text = (root / "src/mypkg/other.py").read_text()
        # The local variable assignment should be untouched
        assert "    target = 42" in text
