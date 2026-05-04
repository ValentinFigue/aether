"""Tests for bonsai_python.pyfindunused detectors."""

from bonsai_python._common import collect_python_files
from bonsai_python.pyfindunused import find_dead_code, find_unused_imports, find_unused_params

# ── find_dead_code ─────────────────────────────────────────────────────────────


class TestFindDeadCode:
    def test_unreferenced_function_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def never_called():\n    pass\n",
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "never_called" in [r.name for r in results]

    def test_imported_function_not_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def used_func():\n    pass\n",
                "src/mypkg/app.py": "from mypkg.utils import used_func\n",
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "used_func" not in [r.name for r in results]

    def test_private_function_not_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def _private():\n    pass\n",
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "_private" not in [r.name for r in results]

    def test_entry_point_not_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/cli.py": "def main():\n    pass\n",
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "main" not in [r.name for r in results]

    def test_all_export_not_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/api.py": '__all__ = ["exported"]\ndef exported():\n    pass\n',
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "exported" not in [r.name for r in results]

    def test_framework_decorator_exempts_function(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/views.py": "@staticmethod\ndef my_view():\n    pass\n",
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "my_view" not in [r.name for r in results]


# ── find_unused_params ─────────────────────────────────────────────────────────


class TestFindUnusedParams:
    def test_unused_param_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def func(used, unused):\n    return used\n",
            }
        )
        results = find_unused_params(collect_python_files(root), root)
        names = [r.name for r in results]
        assert "unused" in names
        assert "used" not in names

    def test_self_not_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/model.py": "class A:\n    def method(self):\n        pass\n",
            }
        )
        results = find_unused_params(collect_python_files(root), root)
        assert "self" not in [r.name for r in results]

    def test_cls_not_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/model.py": "class A:\n    @classmethod\n    def create(cls):\n        pass\n",
            }
        )
        results = find_unused_params(collect_python_files(root), root)
        assert "cls" not in [r.name for r in results]

    def test_underscore_prefix_not_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def func(_intentionally_unused):\n    pass\n",
            }
        )
        results = find_unused_params(collect_python_files(root), root)
        assert "_intentionally_unused" not in [r.name for r in results]


# ── find_unused_imports ────────────────────────────────────────────────────────


class TestFindUnusedImports:
    def test_unused_import_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "import os\n\ndef func():\n    pass\n",
            }
        )
        results = find_unused_imports(collect_python_files(root), root)
        assert "os" in [r.name for r in results]

    def test_used_import_not_reported(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "import os\n\ndef func():\n    return os.getcwd()\n",
            }
        )
        results = find_unused_imports(collect_python_files(root), root)
        assert "os" not in [r.name for r in results]

    def test_type_checking_import_excluded(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": (
                    "from __future__ import annotations\n"
                    "from typing import TYPE_CHECKING\n"
                    "if TYPE_CHECKING:\n"
                    "    import pathlib\n"
                    "\n"
                    "def func():\n"
                    "    pass\n"
                ),
            }
        )
        results = find_unused_imports(collect_python_files(root), root)
        assert "pathlib" not in [r.name for r in results]

    def test_future_import_excluded(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "from __future__ import annotations\n\ndef func(): pass\n",
            }
        )
        results = find_unused_imports(collect_python_files(root), root)
        assert "annotations" not in [r.name for r in results]

    def test_dotted_import_used_not_reported(self, make_project):
        """import os.path is accessed via `os`, not the dotted string `os.path`."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": (
                    "import os.path\n"
                    "\n"
                    "def func(a, b):\n"
                    "    return os.path.join(a, b)\n"
                ),
            }
        )
        results = find_unused_imports(collect_python_files(root), root)
        names = [r.name for r in results]
        assert "os" not in names

    def test_dotted_import_unused_reported(self, make_project):
        """import os.path with no usage should be reported."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "import os.path\n\ndef func(): pass\n",
            }
        )
        results = find_unused_imports(collect_python_files(root), root)
        names = [r.name for r in results]
        assert "os" in names

    def test_dotted_import_with_alias_unused_reported(self, make_project):
        """import os.path as p with no usage of p should be reported."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "import os.path as osp\n\ndef func(): pass\n",
            }
        )
        results = find_unused_imports(collect_python_files(root), root)
        names = [r.name for r in results]
        assert "osp" in names


class TestFindDeadCodeDecorators:
    def test_property_not_reported(self, make_project):
        """@property on a top-level function should be exempt from dead-code."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": (
                    "@property\n"
                    "def computed():\n"
                    "    return 42\n"
                ),
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "computed" not in [r.name for r in results]

    def test_abstractmethod_not_reported(self, make_project):
        """@abstractmethod on a top-level function should be exempt."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/base.py": (
                    "@abstractmethod\n"
                    "def must_implement():\n"
                    "    ...\n"
                ),
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "must_implement" not in [r.name for r in results]

    def test_cached_property_not_reported(self, make_project):
        """@cached_property on a top-level function should be exempt."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": (
                    "@cached_property\n"
                    "def expensive():\n"
                    "    return list(range(1000))\n"
                ),
            }
        )
        results = find_dead_code(collect_python_files(root), root)
        assert "expensive" not in [r.name for r in results]
