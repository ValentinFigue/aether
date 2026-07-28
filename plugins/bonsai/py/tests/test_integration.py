"""Integration tests running each read-only bonsai tool against the sample_project fixture."""

import shutil
from pathlib import Path

import pytest

from bonsai_python.server import pycallers, pyfindrefs, pyfindunused, pygrep, pysignature

FIXTURE_ROOT = Path(__file__).parent / "fixtures" / "sample_project"

pytestmark = pytest.mark.skipif(
    not FIXTURE_ROOT.exists(),
    reason="sample_project fixture not found",
)


class TestPyfindrefs:
    def test_finds_user_definition(self):
        result = pyfindrefs("myapp.models:User", str(FIXTURE_ROOT))
        assert "DEFINITION" in result
        assert "models.py" in result

    def test_finds_user_import_in_services(self):
        result = pyfindrefs("myapp.models:User", str(FIXTURE_ROOT))
        assert "services.py" in result

    def test_finds_create_user_reference_in_utils(self):
        result = pyfindrefs("myapp.services:create_user", str(FIXTURE_ROOT))
        assert "utils.py" in result

    def test_finds_user_save_method_definition(self):
        result = pyfindrefs("myapp.models:User.save", str(FIXTURE_ROOT))
        assert "DEFINITION" in result


class TestPycallers:
    def test_finds_create_user_calls_in_utils(self):
        result = pycallers("myapp.services:create_user", str(FIXTURE_ROOT))
        assert "utils.py" in result

    def test_counts_two_create_user_calls(self):
        result = pycallers("myapp.services:create_user", str(FIXTURE_ROOT))
        # bootstrap() calls create_user twice
        assert result.count("create_user") >= 2

    def test_save_call_found_in_services(self):
        # The call `user.save()` in services.py is matched — AST cannot distinguish
        # User.save vs Product.save without type inference
        result = pycallers("myapp.models:User.save", str(FIXTURE_ROOT))
        assert "services.py" in result

    def test_no_results_for_nonexistent_caller(self):
        result = pycallers("myapp.models:User.delete", str(FIXTURE_ROOT))
        # delete() is never called — the output should not contain a delete() call line
        assert ".delete(" not in result


class TestPyfindunused:
    def test_reports_orphaned_function_as_dead_code(self, tmp_path):
        # Dead code detection skips paths containing "tests/" — copy fixture out
        proj = tmp_path / "sample"
        shutil.copytree(FIXTURE_ROOT, proj)
        result = pyfindunused(project_root=str(proj), dead_code=True, params=False, imports=False)
        # orphan.py is never imported, so orphaned_function must be reported
        assert "orphaned_function" in result

    def test_private_function_not_reported_as_dead_code(self, tmp_path):
        proj = tmp_path / "sample"
        shutil.copytree(FIXTURE_ROOT, proj)
        result = pyfindunused(project_root=str(proj), dead_code=True, params=False, imports=False)
        assert "_internal_helper" not in result

    def test_reports_unused_import_os_in_models(self):
        result = pyfindunused(project_root=str(FIXTURE_ROOT), dead_code=False, params=False, imports=True)
        assert "os" in result

    def test_reports_unused_import_json_in_utils(self):
        result = pyfindunused(project_root=str(FIXTURE_ROOT), dead_code=False, params=False, imports=True)
        assert "json" in result

    def test_reports_unused_param_in_process(self):
        result = pyfindunused(project_root=str(FIXTURE_ROOT), dead_code=False, params=True, imports=False)
        assert "unused_param" in result

    def test_does_not_report_used_param_name(self):
        result = pyfindunused(project_root=str(FIXTURE_ROOT), dead_code=False, params=True, imports=False)
        # `data` is used in process() — must not appear as an UNUSED PARAMETERS entry
        # (it may appear in the function signature preview text, so check entry lines)
        entry_lines = [line for line in result.splitlines() if "data" in line and "unused_param" not in line]
        assert not any("data" in line and "—" in line for line in entry_lines)


class TestPygrep:
    def test_finds_class_keyword(self):
        result = pygrep("class User", project_root=str(FIXTURE_ROOT))
        assert "models.py" in result

    def test_finds_no_todos_in_fixture(self):
        result = pygrep("TODO", project_root=str(FIXTURE_ROOT))
        assert "models.py" not in result
        assert "services.py" not in result
        assert "utils.py" not in result

    def test_case_insensitive_search(self):
        result = pygrep("CLASS USER", project_root=str(FIXTURE_ROOT), case_sensitive=False)
        assert "models.py" in result


class TestPysignatureStructuredArgs:
    """Verify the new dict-form pysignature args are correctly converted."""

    def test_dict_add_dry_run(self):
        result = pysignature(
            "myapp.services:create_user",
            add=[{"name": "timeout", "type": "int", "default": "30"}],
            project_root=str(FIXTURE_ROOT),
            dry_run=True,
        )
        assert "timeout" in result

    def test_legacy_string_add_still_works(self):
        result = pysignature(
            "myapp.services:create_user",
            add=["timeout int 30"],
            project_root=str(FIXTURE_ROOT),
            dry_run=True,
        )
        assert "timeout" in result

    def test_dict_rename_dry_run(self):
        result = pysignature(
            "myapp.services:create_user",
            rename=[{"from": "name", "to": "full_name"}],
            project_root=str(FIXTURE_ROOT),
            dry_run=True,
        )
        assert "full_name" in result

    def test_dict_set_default_dry_run(self):
        result = pysignature(
            "myapp.services:process",
            set_default=[{"name": "unused_param", "value": "0", "type": "int"}],
            project_root=str(FIXTURE_ROOT),
            dry_run=True,
        )
        assert "unused_param" in result
