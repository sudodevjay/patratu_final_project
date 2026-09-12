#!/usr/bin/env python3
"""
Export device-wise user snapshot from BIO_USERMAST into a local JSON file.

Default behavior:
- Reads DB connection from demo/src/main/resources/jdbc.properties
- Connects to SQL Server using pyodbc
- Fetches latest record per (device, user) from BIO_USERMAST
- Stores status (0/1), deleted flag, and basic metadata in a snapshot file
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Optional, Tuple

try:
    import pyodbc  # type: ignore
except ImportError as exc:
    raise SystemExit(
        "pyodbc is required. Install it with: pip install pyodbc"
    ) from exc


DEFAULT_JDBC_PROPS = Path("demo/src/main/resources/jdbc.properties")
DEFAULT_SQL_DRIVER = "ODBC Driver 17 for SQL Server"
DEFAULT_TABLE = "BIO_USERMAST"
NO_DEVICE_KEY = "_NO_DEVICE_"


@dataclass
class ConnectionConfig:
    server: str
    port: int
    database: str
    username: Optional[str]
    password: Optional[str]
    trusted: bool
    encrypt: bool
    trust_server_certificate: bool
    driver: str


def parse_properties_file(path: Path) -> Dict[str, str]:
    props: Dict[str, str] = {}
    if not path.exists():
        return props
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        props[key.strip()] = value.strip()
    return props


def parse_bool(value: Optional[str], default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"true", "1", "yes", "y", "on"}


def parse_sqlserver_jdbc_url(url: str) -> Dict[str, Any]:
    """
    Parse JDBC URL format like:
    jdbc:sqlserver://localhost:1433;databaseName=IDSL_NTPC_CLIMS;integratedSecurity=true;encrypt=true;trustServerCertificate=true
    """
    prefix = "jdbc:sqlserver://"
    if not url or not url.lower().startswith(prefix):
        raise ValueError("Only jdbc:sqlserver:// URLs are supported.")

    body = url[len(prefix):]
    parts = body.split(";")
    host_part = parts[0].strip()
    params: Dict[str, str] = {}
    for item in parts[1:]:
        item = item.strip()
        if not item or "=" not in item:
            continue
        k, v = item.split("=", 1)
        params[k.strip().lower()] = v.strip()

    if ":" in host_part:
        server, port_text = host_part.rsplit(":", 1)
        try:
            port = int(port_text)
        except ValueError:
            port = 1433
    else:
        server, port = host_part, 1433

    return {
        "server": server.strip(),
        "port": port,
        "database": params.get("databasename") or params.get("database"),
        "trusted": parse_bool(params.get("integratedsecurity"), default=False),
        "encrypt": parse_bool(params.get("encrypt"), default=True),
        "trust_server_certificate": parse_bool(
            params.get("trustservercertificate"), default=True
        ),
    }


def build_connection_config(args: argparse.Namespace) -> ConnectionConfig:
    props_path = Path(args.jdbc_props)
    props = parse_properties_file(props_path)

    jdbc_info: Dict[str, Any] = {}
    url = props.get("url")
    if url:
        jdbc_info = parse_sqlserver_jdbc_url(url)

    server = args.server or jdbc_info.get("server") or "localhost"
    port = args.port or jdbc_info.get("port") or 1433
    database = args.database or jdbc_info.get("database")
    username = args.username if args.username is not None else props.get("username")
    password = args.password if args.password is not None else props.get("password")

    trusted = args.trusted
    if not trusted:
        trusted = bool(jdbc_info.get("trusted", False))
        if args.no_trusted:
            trusted = False

    encrypt = (
        args.encrypt
        if args.encrypt is not None
        else bool(jdbc_info.get("encrypt", True))
    )
    trust_server_certificate = (
        args.trust_server_certificate
        if args.trust_server_certificate is not None
        else bool(jdbc_info.get("trust_server_certificate", True))
    )
    driver = args.driver or DEFAULT_SQL_DRIVER

    if not database:
        raise ValueError(
            "Database name missing. Pass --database or set url=...databaseName=... in jdbc.properties"
        )

    if not trusted and (not username or not password):
        raise ValueError(
            "SQL authentication selected but username/password missing. "
            "Pass --trusted, or provide --username and --password."
        )

    return ConnectionConfig(
        server=server,
        port=int(port),
        database=database,
        username=username if username else None,
        password=password if password else None,
        trusted=trusted,
        encrypt=encrypt,
        trust_server_certificate=trust_server_certificate,
        driver=driver,
    )


def build_pyodbc_connection_string(cfg: ConnectionConfig) -> str:
    parts = [
        f"DRIVER={{{cfg.driver}}}",
        f"SERVER={cfg.server},{cfg.port}",
        f"DATABASE={cfg.database}",
        f"Encrypt={'yes' if cfg.encrypt else 'no'}",
        f"TrustServerCertificate={'yes' if cfg.trust_server_certificate else 'no'}",
    ]
    if cfg.trusted:
        parts.append("Trusted_Connection=yes")
    else:
        parts.append(f"UID={cfg.username}")
        parts.append(f"PWD={cfg.password}")
    return ";".join(parts)


def validate_table_identifier(table: str) -> str:
    table = table.strip()
    if not table:
        raise ValueError("Table name cannot be empty.")
    if not re.fullmatch(r"[A-Za-z0-9_.]+", table):
        raise ValueError(
            "Invalid table name. Use only letters, numbers, underscore and dot."
        )
    return table


def fetch_latest_rows(conn: "pyodbc.Connection", table_name: str) -> Iterable[Tuple[Any, ...]]:
    sql = f"""
    WITH latest AS (
        SELECT
            BU_ID,
            LTRIM(RTRIM(ISNULL(SLNO, ''))) AS device_sn,
            CASE WHEN ISNUMERIC(ID) = 1 THEN CONVERT(BIGINT, ID) ELSE NULL END AS user_id,
            ISNULL(NAME, '') AS user_name,
            CASE
                WHEN ISNUMERIC(Verify) = 1 AND CONVERT(INT, Verify) IN (0, 1) THEN CONVERT(INT, Verify)
                ELSE 1
            END AS status,
            ISNULL(ISDELETED, 0) AS is_deleted,
            ROW_NUMBER() OVER (
                PARTITION BY LTRIM(RTRIM(ISNULL(SLNO, ''))), ID
                ORDER BY BU_ID DESC
            ) AS rn
        FROM {table_name}
        WHERE ISNUMERIC(ID) = 1
    )
    SELECT
        device_sn,
        user_id,
        user_name,
        status,
        is_deleted,
        BU_ID
    FROM latest
    WHERE rn = 1
    ORDER BY device_sn, user_id;
    """
    cursor = conn.cursor()
    cursor.execute(sql)
    return cursor.fetchall()


def normalize_status(value: Any) -> int:
    try:
        return 0 if int(value) == 0 else 1
    except Exception:
        return 1


def normalize_deleted(value: Any) -> int:
    try:
        return 1 if int(value) == 1 else 0
    except Exception:
        return 0


def build_snapshot(rows: Iterable[Tuple[Any, ...]], table_name: str) -> Dict[str, Any]:
    devices: Dict[str, Dict[str, Any]] = {}
    total_rows = 0

    for row in rows:
        total_rows += 1
        device_sn_raw, user_id_raw, user_name_raw, status_raw, deleted_raw, bu_id_raw = row

        if user_id_raw is None:
            continue
        try:
            user_id = int(user_id_raw)
        except Exception:
            continue

        device_sn = str(device_sn_raw).strip() if device_sn_raw is not None else ""
        device_key = device_sn if device_sn else NO_DEVICE_KEY

        status = normalize_status(status_raw)
        is_deleted = normalize_deleted(deleted_raw)

        bucket = devices.setdefault(
            device_key,
            {
                "total_users": 0,
                "active_users": 0,
                "deleted_users": 0,
                "disabled_users": 0,
                "users": {},
            },
        )

        user_key = str(user_id)
        if user_key not in bucket["users"]:
            bucket["total_users"] += 1

        bucket["users"][user_key] = {
            "name": "" if user_name_raw is None else str(user_name_raw),
            "status": status,
            "is_deleted": is_deleted,
            "bu_id": int(bu_id_raw) if bu_id_raw is not None else None,
        }

    # Recompute counts from final user state in each device bucket.
    for device_data in devices.values():
        active_users = 0
        deleted_users = 0
        disabled_users = 0
        for user_data in device_data["users"].values():
            if user_data["is_deleted"] == 1:
                deleted_users += 1
            else:
                active_users += 1
                if user_data["status"] == 0:
                    disabled_users += 1
        device_data["active_users"] = active_users
        device_data["deleted_users"] = deleted_users
        device_data["disabled_users"] = disabled_users
        device_data["total_users"] = len(device_data["users"])

    generated_at = datetime.now(timezone.utc).isoformat()
    total_users_all_devices = sum(len(x["users"]) for x in devices.values())

    return {
        "meta": {
            "generated_at_utc": generated_at,
            "source_table": table_name,
            "devices_count": len(devices),
            "rows_read": total_rows,
            "users_snapshot_count": total_users_all_devices,
            "note": "status: 0=disabled, 1=enabled; is_deleted: 1=deleted in DB",
        },
        "devices": devices,
    }


def atomic_json_write(path: Path, data: Dict[str, Any], pretty: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_file = path.with_suffix(path.suffix + ".tmp")
    with tmp_file.open("w", encoding="utf-8", newline="\n") as fh:
        if pretty:
            json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=True)
        else:
            json.dump(data, fh, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        fh.write("\n")
    os.replace(tmp_file, path)


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    default_output = (
        Path(tempfile.gettempdir()) / "idsl-sync" / "usermast_device_snapshot.json"
    )
    parser = argparse.ArgumentParser(
        description="Export device-wise user snapshot from BIO_USERMAST."
    )
    parser.add_argument(
        "--jdbc-props",
        default=str(DEFAULT_JDBC_PROPS),
        help="Path to jdbc.properties (default: demo/src/main/resources/jdbc.properties)",
    )
    parser.add_argument("--driver", default=DEFAULT_SQL_DRIVER, help="ODBC SQL Server driver name")
    parser.add_argument("--server", help="DB server host")
    parser.add_argument("--port", type=int, help="DB server port")
    parser.add_argument("--database", help="DB name")
    parser.add_argument("--username", help="SQL auth username")
    parser.add_argument("--password", help="SQL auth password")
    parser.add_argument(
        "--trusted",
        action="store_true",
        help="Force Windows integrated auth (Trusted_Connection=yes)",
    )
    parser.add_argument(
        "--no-trusted",
        action="store_true",
        help="Disable integrated auth and use SQL auth",
    )
    parser.add_argument(
        "--encrypt",
        action="store_true",
        default=None,
        help="Enable encryption for SQL Server connection",
    )
    parser.add_argument(
        "--no-encrypt",
        dest="encrypt",
        action="store_false",
        help="Disable encryption for SQL Server connection",
    )
    parser.add_argument(
        "--trust-server-certificate",
        action="store_true",
        default=None,
        help="Trust SQL Server certificate",
    )
    parser.add_argument(
        "--no-trust-server-certificate",
        dest="trust_server_certificate",
        action="store_false",
        help="Do not trust SQL Server certificate",
    )
    parser.add_argument(
        "--table",
        default=DEFAULT_TABLE,
        help="Source table/view name (default: BIO_USERMAST)",
    )
    parser.add_argument(
        "--output",
        default=str(default_output),
        help=f"Output JSON file path (default: {default_output})",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Write human-readable JSON",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)

    try:
        table_name = validate_table_identifier(args.table)
        cfg = build_connection_config(args)
        conn_str = build_pyodbc_connection_string(cfg)

        with pyodbc.connect(conn_str, timeout=30) as conn:
            rows = fetch_latest_rows(conn, table_name)
            snapshot = build_snapshot(rows, table_name)

        output_path = Path(args.output).expanduser().resolve()
        atomic_json_write(output_path, snapshot, pretty=args.pretty)

        meta = snapshot["meta"]
        print(f"Snapshot written: {output_path}")
        print(f"Devices: {meta['devices_count']}")
        print(f"Rows read: {meta['rows_read']}")
        print(f"Users in snapshot: {meta['users_snapshot_count']}")
        return 0
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
