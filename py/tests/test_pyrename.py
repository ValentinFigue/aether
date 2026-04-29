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
