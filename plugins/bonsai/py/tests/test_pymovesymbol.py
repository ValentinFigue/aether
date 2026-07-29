"""Tests for bonsai_python.pymovesymbol.do_move_symbol."""

from bonsai_python.pymovesymbol import do_move_symbol


class TestDoMoveSymbol:
    def test_moves_function_to_new_file(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def format_date(d):\n    return str(d)\n",
            }
        )
        result = do_move_symbol("mypkg.utils:format_date", "mypkg.dates", root, dry_run=False)
        assert result is True
        assert (root / "src/mypkg/dates.py").exists()
        assert "def format_date" in (root / "src/mypkg/dates.py").read_text()

    def test_compat_comment_left_in_source(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def format_date(d):\n    return str(d)\n",
            }
        )
        do_move_symbol("mypkg.utils:format_date", "mypkg.dates", root, dry_run=False)
        src_text = (root / "src/mypkg/utils.py").read_text()
        assert "was moved" in src_text
        assert "def format_date" not in src_text

    def test_rewrites_import_in_caller(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def format_date(d):\n    return str(d)\n",
                "src/mypkg/app.py": "from mypkg.utils import format_date\nformat_date(None)\n",
            }
        )
        do_move_symbol("mypkg.utils:format_date", "mypkg.dates", root, dry_run=False)
        app_text = (root / "src/mypkg/app.py").read_text()
        assert "from mypkg.dates import format_date" in app_text
        assert "from mypkg.utils import format_date" not in app_text

    def test_removes_symbol_from_all_in_source(self, make_project):
        """Moving a symbol should remove it from __all__ in the source module."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": (
                    '__all__ = ["format_date", "parse_date"]\n'
                    "\n"
                    "def format_date(d):\n"
                    "    return str(d)\n"
                    "\n"
                    "def parse_date(s):\n"
                    "    return s\n"
                ),
            }
        )
        do_move_symbol("mypkg.utils:format_date", "mypkg.dates", root, dry_run=False)
        src_text = (root / "src/mypkg/utils.py").read_text()
        assert "format_date" not in src_text or "was moved" in src_text
        # __all__ should no longer list format_date
        assert '"format_date"' not in src_text and "'format_date'" not in src_text
        # parse_date must remain
        assert "parse_date" in src_text

    def test_all_updated_when_only_symbol_present(self, make_project):
        """If __all__ only had the moved symbol, it should become empty."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": (
                    '__all__ = ["format_date"]\n'
                    "\n"
                    "def format_date(d):\n"
                    "    return str(d)\n"
                ),
            }
        )
        do_move_symbol("mypkg.utils:format_date", "mypkg.dates", root, dry_run=False)
        src_text = (root / "src/mypkg/utils.py").read_text()
        assert '"format_date"' not in src_text and "'format_date'" not in src_text
        assert "__all__ = []" in src_text

    def test_creates_init_py_for_new_parent_package(self, make_project):
        """Moving to a new subpackage that does not yet exist should create __init__.py."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def format_date(d):\n    return str(d)\n",
            }
        )
        do_move_symbol("mypkg.utils:format_date", "mypkg.dates.helpers", root, dry_run=False)
        # The new module file should exist
        assert (root / "src/mypkg/dates/helpers.py").exists()
        # The new intermediate package must have an __init__.py
        assert (root / "src/mypkg/dates/__init__.py").exists()

    def test_dry_run_makes_no_changes(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": (
                    '__all__ = ["format_date"]\n'
                    "\n"
                    "def format_date(d):\n"
                    "    return str(d)\n"
                ),
            }
        )
        result = do_move_symbol("mypkg.utils:format_date", "mypkg.dates", root, dry_run=True)
        assert result is True
        src_text = (root / "src/mypkg/utils.py").read_text()
        assert "def format_date" in src_text
        assert '"format_date"' in src_text
        assert not (root / "src/mypkg/dates.py").exists()

    def test_unknown_symbol_returns_false(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def something_else(): pass\n",
            }
        )
        result = do_move_symbol("mypkg.utils:nonexistent", "mypkg.dates", root, dry_run=False)
        assert result is False
