"""Oracle connection helpers for the Cloud Resource Cost Analyzer."""

from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Iterator

import oracledb
from dotenv import load_dotenv


load_dotenv()


class DatabaseConfigurationError(RuntimeError):
    """Raised when the Oracle connection configuration is incomplete."""


def _required_setting(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise DatabaseConfigurationError(
            f"Missing required setting: {name}. Copy .env.example to .env "
            "or set the environment variable before starting the app."
        )
    return value


def configure_oracle_client() -> None:
    """Enable Thick mode only when explicitly requested by configuration."""

    use_thick_mode = os.getenv("ORACLE_THICK_MODE", "false").strip().lower()
    if use_thick_mode not in {"true", "1", "yes"}:
        return

    lib_dir = os.getenv("ORACLE_CLIENT_LIB_DIR", "").strip() or None
    try:
        oracledb.init_oracle_client(lib_dir=lib_dir)
    except oracledb.ProgrammingError as exc:
        if "already been initialized" not in str(exc).lower():
            raise DatabaseConfigurationError(
                "Oracle Thick mode could not be initialized. Check "
                "ORACLE_CLIENT_LIB_DIR and the Oracle Client installation."
            ) from exc


def get_connection() -> oracledb.Connection:
    """Open a new Oracle connection using environment-based credentials."""

    configure_oracle_client()
    user = _required_setting("ORACLE_USER")
    password = _required_setting("ORACLE_PASSWORD")
    dsn = _required_setting("ORACLE_DSN")
    try:
        return oracledb.connect(user=user, password=password, dsn=dsn)
    except oracledb.Error as exc:
        raise ConnectionError(
            "Unable to connect to Oracle. Verify ORACLE_USER, ORACLE_PASSWORD, "
            "ORACLE_DSN, and that the database listener is running."
        ) from exc


@contextmanager
def connection() -> Iterator[oracledb.Connection]:
    """Yield a connection and always close it after use."""

    conn = get_connection()
    try:
        yield conn
    finally:
        conn.close()
