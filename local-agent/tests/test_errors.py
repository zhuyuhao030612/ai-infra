"""Unit tests for error classifier — P1-10 testing methodology."""
from app.errors import classify_exception
from app.schemas import ErrorCode


def test_permission_denied():
    result = classify_exception(PermissionError("Access is denied"))
    assert result.code == ErrorCode.PERMISSION_DENIED


def test_file_not_found_is_env_error_for_scripts():
    result = classify_exception(FileNotFoundError("No such file: setup.ps1"))
    assert result.code == ErrorCode.ENV_ERROR


def test_module_not_found():
    result = classify_exception(ModuleNotFoundError("No module named 'pyautogui'"))
    assert result.code == ErrorCode.ENV_ERROR


def test_timeout():
    result = classify_exception(TimeoutError("Connection timed out"))
    assert result.code == ErrorCode.TIMEOUT


def test_port_in_use():
    result = classify_exception(RuntimeError("Address already in use: port 9000"))
    assert result.code == ErrorCode.RUNTIME_ERROR


def test_window_not_found():
    result = classify_exception(Exception("No visible window found for process Doubao"))
    assert result.code == ErrorCode.WINDOW_NOT_FOUND


def test_uia_failed():
    result = classify_exception(Exception("UIA InvokePattern failed"))
    assert result.code == ErrorCode.UIA_FAILED


def test_json_parse_error():
    result = classify_exception(ValueError("JSON decode error at line 5"))
    assert result.code == ErrorCode.INVALID_INPUT


def test_all_have_next_action():
    """Every error must have a suggested next action."""
    cases = [
        PermissionError("denied"),
        FileNotFoundError("setup.ps1"),
        ModuleNotFoundError("pyautogui"),
        TimeoutError("timeout"),
        RuntimeError("port 9000"),
        Exception("No visible window"),
    ]
    for e in cases:
        result = classify_exception(e)
        assert result.next_action is not None, f"{type(e).__name__} missing next_action"
        assert len(result.next_action) > 5, f"{type(e).__name__} next_action too short"
