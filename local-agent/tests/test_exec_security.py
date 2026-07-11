"""Security tests for exec router — P2A destructive-command blocking."""
import unittest

from app.routers.exec import _DESTRUCTIVE


class TestExecSecurity(unittest.TestCase):
    def test_destructive_rm_rf(self):
        self.assertTrue(_DESTRUCTIVE.search("rm -rf /"), "rm -rf / should be blocked")

    def test_destructive_del_c_drive(self):
        self.assertTrue(
            _DESTRUCTIVE.search("del /s /q C:\\"), "del /s /q C:\\ should be blocked"
        )

    def test_destructive_remove_item(self):
        self.assertTrue(
            _DESTRUCTIVE.search("Remove-Item -Recurse -Force"),
            "Remove-Item should be blocked",
        )

    def test_destructive_git_reset_hard(self):
        self.assertTrue(
            _DESTRUCTIVE.search("git reset --hard"),
            "git reset --hard should be blocked",
        )

    def test_safe_git_status(self):
        self.assertFalse(
            _DESTRUCTIVE.search("git status"), "git status should be allowed"
        )

    def test_safe_echo(self):
        self.assertFalse(_DESTRUCTIVE.search("echo hello"), "echo hello should be allowed")


if __name__ == "__main__":
    unittest.main()
