"""Security tests for auth module — P2A default-token rejection."""
import unittest

from fastapi import HTTPException

from app.security import _DEFAULTS, _configured


class TestSecurity(unittest.TestCase):
    def test_defaults_contains_empty(self):
        self.assertIn("", _DEFAULTS, "empty string must be in defaults")

    def test_defaults_contains_agent_default(self):
        self.assertIn(
            "local-agent-mvp-token-change-me",
            _DEFAULTS,
            "default agent token must be in defaults",
        )

    def test_defaults_contains_high_risk_default(self):
        self.assertIn(
            "high-risk-confirm-token-change-me",
            _DEFAULTS,
            "default high-risk token must be in defaults",
        )

    def test_custom_token_not_in_defaults(self):
        self.assertNotIn(
            "test_token_abc123", _DEFAULTS, "custom token should not be in defaults"
        )

    def test_configured_rejects_defaults(self):
        for token in _DEFAULTS:
            with self.assertRaises(HTTPException) as exc:
                _configured(token, "TEST_TOKEN")
            self.assertEqual(
                exc.exception.status_code,
                503,
                f"should reject default token {token!r}",
            )
            self.assertIn("default tokens are rejected", exc.exception.detail.lower())

    def test_configured_allows_custom(self):
        # Should not raise for a non-default token
        _configured("custom-secure-token-xyz", "TEST_TOKEN")


if __name__ == "__main__":
    unittest.main()
