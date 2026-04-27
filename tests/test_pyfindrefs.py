"""Tests for bonsai.pyfindrefs.find_refs."""

from bonsai.pyfindrefs import find_refs


class TestFindRefs:
    def test_finds_definition(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def my_func():\n    pass\n",
            }
        )
        refs = find_refs("mypkg.utils:my_func", root)
        definitions = [r for r in refs if r.ref_type == "definition"]
        assert len(definitions) == 1
        assert "utils.py" in definitions[0].filepath

    def test_finds_direct_import(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def my_func():\n    pass\n",
                "src/mypkg/caller.py": "from mypkg.utils import my_func\n",
            }
        )
        refs = find_refs("mypkg.utils:my_func", root)
        imports = [r for r in refs if r.ref_type == "import"]
        assert len(imports) == 1
        assert "caller.py" in imports[0].filepath

    def test_finds_call_site(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def my_func():\n    pass\n",
                "src/mypkg/caller.py": "from mypkg.utils import my_func\nmy_func()\n",
            }
        )
        refs = find_refs("mypkg.utils:my_func", root)
        calls = [r for r in refs if r.ref_type == "call"]
        assert len(calls) == 1

    def test_finds_decorator_usage(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/decorators.py": "def my_decorator(f):\n    return f\n",
                "src/mypkg/app.py": ("from mypkg.decorators import my_decorator\n@my_decorator\ndef view(): pass\n"),
            }
        )
        refs = find_refs("mypkg.decorators:my_decorator", root)
        decorators = [r for r in refs if r.ref_type == "decorator"]
        assert len(decorators) == 1

    def test_finds_base_class(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/base.py": "class Base:\n    pass\n",
                "src/mypkg/child.py": "from mypkg.base import Base\nclass Child(Base):\n    pass\n",
            }
        )
        refs = find_refs("mypkg.base:Base", root)
        base_classes = [r for r in refs if r.ref_type == "base_class"]
        assert len(base_classes) == 1

    def test_finds_module_attribute_call(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def my_func():\n    pass\n",
                "src/mypkg/caller.py": "import mypkg.utils as utils\nutils.my_func()\n",
            }
        )
        refs = find_refs("mypkg.utils:my_func", root)
        assert any(r.ref_type in ("call", "attribute") for r in refs)

    def test_src_layout_finds_all_ref_types(self, make_project):
        """Regression: tools previously failed to find anything in src/ layout projects."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/core.py": "def process():\n    pass\n",
                "src/mypkg/runner.py": "from mypkg.core import process\nprocess()\n",
            }
        )
        refs = find_refs("mypkg.core:process", root)
        ref_types = {r.ref_type for r in refs}
        assert "definition" in ref_types
        assert "import" in ref_types
        assert "call" in ref_types

    def test_class_method_target(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/models.py": ("class MyModel:\n    def save(self):\n        pass\n"),
            }
        )
        refs = find_refs("mypkg.models:MyModel.save", root)
        definitions = [r for r in refs if r.ref_type == "definition"]
        assert len(definitions) == 1

    def test_relative_import_tracked(self, make_project):
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": "def helper():\n    pass\n",
                "src/mypkg/app.py": "from .utils import helper\nhelper()\n",
            }
        )
        refs = find_refs("mypkg.utils:helper", root)
        imports = [r for r in refs if r.ref_type == "import"]
        assert len(imports) == 1
