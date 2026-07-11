"""Unit tests for error classifier — P1-10 testing methodology."""
import subprocess
import unittest

from app.errors import classify_exception
from app.schemas import ErrorCode


class TestClassifyException(unittest.TestCase):
    """Test classify_exception() maps raw exceptions to structured errors."""

    # ── Original tests (P0: preserved exactly) ──────────────────

    def test_permission_denied(self):
        result = classify_exception(PermissionError("Access is denied"))
        self.assertEqual(result["code"], ErrorCode.PERMISSION_DENIED)

    def test_file_not_found_is_env_error_for_scripts(self):
        result = classify_exception(FileNotFoundError("No such file: setup.ps1"))
        self.assertEqual(result["code"], ErrorCode.ENV_ERROR)

    def test_module_not_found(self):
        result = classify_exception(ModuleNotFoundError("No module named 'pyautogui'"))
        self.assertEqual(result["code"], ErrorCode.ENV_ERROR)

    def test_timeout(self):
        result = classify_exception(TimeoutError("Connection timed out"))
        self.assertEqual(result["code"], ErrorCode.TIMEOUT)

    def test_port_in_use(self):
        result = classify_exception(RuntimeError("Address already in use: port 9000"))
        self.assertEqual(result["code"], ErrorCode.RUNTIME_ERROR)

    def test_window_not_found(self):
        result = classify_exception(Exception("No visible window found for process Doubao"))
        self.assertEqual(result["code"], ErrorCode.WINDOW_NOT_FOUND)

    def test_uia_failed(self):
        result = classify_exception(Exception("UIA InvokePattern failed"))
        self.assertEqual(result["code"], ErrorCode.UIA_FAILED)

    def test_json_parse_error(self):
        result = classify_exception(ValueError("JSON decode error at line 5"))
        self.assertEqual(result["code"], ErrorCode.INVALID_INPUT)

    def test_all_have_next_action(self):
        """Every error type must return a next_action."""
        cases = [
            PermissionError("denied"),
            FileNotFoundError("setup.ps1"),
            ModuleNotFoundError("pyautogui"),
            TimeoutError("timeout"),
            RuntimeError("port 9000"),
            Exception("No visible window"),
        ]
        for e in cases:
            with self.subTest(exc_type=type(e).__name__):
                result = classify_exception(e)
                self.assertIsNotNone(
                    result["next_action"],
                    f"{type(e).__name__} missing next_action",
                )
                self.assertGreater(
                    len(result["next_action"]), 5,
                    f"{type(e).__name__} next_action too short",
                )

    # ── Expanded coverage (P1: uncovered ErrorCode branches) ────

    def test_permission_denied_variant_access_denied(self):
        """'Access denied' keyword also maps to PERMISSION_DENIED."""
        result = classify_exception(Exception("Access denied"))
        self.assertEqual(result["code"], ErrorCode.PERMISSION_DENIED)

    def test_permission_denied_variant_elevation(self):
        """'requires elevation' keyword maps to PERMISSION_DENIED."""
        result = classify_exception(Exception("Operation requires elevation"))
        self.assertEqual(result["code"], ErrorCode.PERMISSION_DENIED)

    def test_not_found_non_script_file(self):
        """FileNotFoundError without script extension → NOT_FOUND."""
        result = classify_exception(FileNotFoundError("No such file: data.csv"))
        self.assertEqual(result["code"], ErrorCode.NOT_FOUND)

    def test_not_found_cannot_find(self):
        """'cannot find' keyword maps to NOT_FOUND."""
        result = classify_exception(FileNotFoundError("Cannot find the path specified"))
        self.assertEqual(result["code"], ErrorCode.NOT_FOUND)

    def test_state_conflict_locked(self):
        """'locked' keyword maps to STATE_CONFLICT."""
        result = classify_exception(RuntimeError("Resource is locked"))
        self.assertEqual(result["code"], ErrorCode.STATE_CONFLICT)

    def test_state_conflict_already_running(self):
        """'already running' keyword maps to STATE_CONFLICT."""
        result = classify_exception(RuntimeError("Instance already running"))
        self.assertEqual(result["code"], ErrorCode.STATE_CONFLICT)

    def test_state_conflict_duplicate(self):
        """'duplicate' keyword maps to STATE_CONFLICT."""
        result = classify_exception(RuntimeError("Duplicate entry"))
        self.assertEqual(result["code"], ErrorCode.STATE_CONFLICT)

    def test_called_process_error(self):
        """subprocess.CalledProcessError maps to RUNTIME_ERROR."""
        err = subprocess.CalledProcessError(1, "cmd")
        err.stderr = "command failed"
        result = classify_exception(err)
        self.assertEqual(result["code"], ErrorCode.RUNTIME_ERROR)

    def test_internal_error_fallback(self):
        """Unknown exception types map to INTERNAL_ERROR."""
        result = classify_exception(KeyError("unknown_key"))
        self.assertEqual(result["code"], ErrorCode.INTERNAL_ERROR)

    def test_context_prefix_in_message(self):
        """When context is provided, it prefixes the message."""
        msg = "something went wrong"
        result = classify_exception(KeyError(msg), context="Deploy")
        self.assertIn("Deploy", result["message"])
        self.assertIn(msg, result["message"])

    def test_empty_message_no_crash(self):
        """Exception with empty message still classifies without crash."""
        result = classify_exception(Exception(""))
        self.assertIn("code", result)
        self.assertIn("message", result)

    def test_result_is_dict_with_expected_keys(self):
        """Return type is a plain dict with code, message, next_action."""
        result = classify_exception(PermissionError("denied"))
        self.assertIsInstance(result, dict)
        for key in ("code", "message", "next_action"):
            self.assertIn(key, result)


if __name__ == "__main__":
    unittest.main()
