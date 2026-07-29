"""Tests for pysignature behaviour on decorated functions."""

from bonsai_python.pysignature import SignatureChange, do_signature


class TestDecoratedFunctions:
    def test_fastapi_decorator_preserved_on_rename(self, make_project):
        """Renaming a param on a FastAPI-style route must leave the decorator unchanged."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/routes.py": (
                    "app = None\n\n"
                    '@app.get("/users/{user_id}")\n'
                    "def get_user(user_id: int, db=None):\n"
                    "    return db.get(user_id)\n"
                ),
                "src/mypkg/caller.py": ("from mypkg.routes import get_user\n\nget_user(user_id=1, db=session)\n"),
            }
        )
        changes = [SignatureChange(action="rename", param_name="user_id", new_name="uid")]
        do_signature("mypkg.routes:get_user", changes, root, dry_run=False)

        routes_text = (root / "src/mypkg/routes.py").read_text()
        # Decorator must be untouched
        assert '@app.get("/users/{user_id}")' in routes_text
        # Parameter must be renamed
        assert "def get_user(uid: int" in routes_text

    def test_stacked_decorators_all_preserved_on_reorder(self, make_project):
        """Reordering params must leave all stacked decorators intact."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/service.py": ("@decorator_a\n@decorator_b\ndef create(name: str, value: int):\n    pass\n"),
            }
        )
        changes = [SignatureChange(action="reorder", param_name="", new_order=["value", "name"])]
        do_signature("mypkg.service:create", changes, root, dry_run=False)

        text = (root / "src/mypkg/service.py").read_text()
        assert "@decorator_a" in text
        assert "@decorator_b" in text
        assert "def create(value: int, name: str)" in text

    def test_kwargs_forwarding_preserved_on_rename(self, make_project):
        """Renaming a positional param must not break **kwargs forwarding."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/utils.py": ("def process(data, **kwargs):\n    return _inner(data, **kwargs)\n"),
                "src/mypkg/caller.py": ("from mypkg.utils import process\n\nprocess(data=payload, timeout=30)\n"),
            }
        )
        changes = [SignatureChange(action="rename", param_name="data", new_name="payload")]
        do_signature("mypkg.utils:process", changes, root, dry_run=False)

        utils_text = (root / "src/mypkg/utils.py").read_text()
        # **kwargs must still be present
        assert "**kwargs" in utils_text
        # Renamed param
        assert "def process(payload" in utils_text

        caller_text = (root / "src/mypkg/caller.py").read_text()
        # Call site updated
        assert "payload=payload" in caller_text

    def test_pydantic_validator_decorator_preserved_on_add(self, make_project):
        """Adding a param with a default to a Pydantic-style validator must leave the decorator."""
        root = make_project(
            {
                "src/mypkg/__init__.py": "",
                "src/mypkg/model.py": (
                    '@field_validator("email")\ndef validate_email(cls, v):\n    return v.lower()\n'
                ),
            }
        )
        changes = [SignatureChange(action="add", param_name="info", new_default="None")]
        do_signature("mypkg.model:validate_email", changes, root, dry_run=False)

        text = (root / "src/mypkg/model.py").read_text()
        assert '@field_validator("email")' in text
        assert "def validate_email(cls, v" in text
        assert "info" in text
