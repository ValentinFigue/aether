import textwrap
from pathlib import Path

import pytest


@pytest.fixture
def make_project(tmp_path):
    """Create a temporary Python project with the given source files.

    Usage::

        root = make_project({
            "src/mypkg/__init__.py": "",
            "src/mypkg/utils.py": "def foo(): pass",
            "src/mypkg/main.py": "from .utils import foo\\nfoo()",
        })
        # root == tmp_path, with pyproject.toml already written
    """

    def _make(files: dict[str, str]) -> Path:
        (tmp_path / "pyproject.toml").write_text("[project]\nname = 'testpkg'\n")
        for rel, content in files.items():
            fpath = tmp_path / rel
            fpath.parent.mkdir(parents=True, exist_ok=True)
            fpath.write_text(textwrap.dedent(content))
        return tmp_path

    return _make
