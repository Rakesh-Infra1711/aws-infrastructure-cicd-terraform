"""Demo web application for the AWS infrastructure assessment.

Endpoints
  /health  - liveness check used by the ALB target group (no DB dependency)
  /db      - JSON database connectivity check (200 OK / 503 on failure)
  /        - HTML page: instance, AZ, app version and a visit counter stored in RDS

Database credentials are read at runtime from AWS Secrets Manager using the
EC2 instance role. Nothing secret is stored in code, environment or disk.
"""

import json
import os
import threading
import time
import urllib.request
from html import escape

import boto3
import pymysql
from flask import Flask, jsonify

app = Flask(__name__)

AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")
DB_HOST = os.environ.get("DB_HOST", "")
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_SECRET_ARN = os.environ.get("DB_SECRET_ARN", "")
DB_CA_PATH = os.environ.get("DB_CA_PATH", "")
APP_VERSION = os.environ.get("APP_VERSION", "local")

_SECRET_TTL_SECONDS = 300
_secret_cache = {"value": None, "fetched_at": 0.0}
_secret_lock = threading.Lock()


def get_db_credentials():
    """Return {'username', 'password'} from Secrets Manager, cached for 5 minutes.

    The cache is short so a rotated password is picked up automatically.
    """
    with _secret_lock:
        fresh = time.time() - _secret_cache["fetched_at"] < _SECRET_TTL_SECONDS
        if _secret_cache["value"] and fresh:
            return _secret_cache["value"]
        client = boto3.client("secretsmanager", region_name=AWS_REGION)
        secret = json.loads(client.get_secret_value(SecretId=DB_SECRET_ARN)["SecretString"])
        _secret_cache["value"] = secret
        _secret_cache["fetched_at"] = time.time()
        return secret


def get_connection():
    creds = get_db_credentials()
    ssl = {"ca": DB_CA_PATH} if DB_CA_PATH else None
    return pymysql.connect(
        host=DB_HOST,
        user=creds["username"],
        password=creds["password"],
        database=DB_NAME,
        ssl=ssl,
        connect_timeout=5,
        autocommit=True,
    )


def record_visit():
    """Insert a visit row and return (total_visits, mysql_version)."""
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CREATE TABLE IF NOT EXISTS visits ("
                " id BIGINT AUTO_INCREMENT PRIMARY KEY,"
                " instance_id VARCHAR(64) NOT NULL,"
                " visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
            )
            cur.execute("INSERT INTO visits (instance_id) VALUES (%s)", (instance_metadata("instance-id"),))
            cur.execute("SELECT COUNT(*) FROM visits")
            total = cur.fetchone()[0]
            cur.execute("SELECT VERSION()")
            version = cur.fetchone()[0]
        return total, version
    finally:
        conn.close()


def instance_metadata(path):
    """Read EC2 instance metadata using IMDSv2 (token required)."""
    try:
        token_req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        req = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
        )
        return urllib.request.urlopen(req, timeout=1).read().decode()
    except Exception:
        return "unknown"


@app.route("/health")
def health():
    return jsonify(status="ok", version=APP_VERSION), 200


@app.route("/db")
def db_check():
    try:
        total, version = record_visit()
        return jsonify(database="connected", mysql_version=version, total_visits=total), 200
    except Exception as exc:  # report, never leak credentials
        app.logger.error("Database check failed: %s", exc)
        return jsonify(database="unavailable", error=type(exc).__name__), 503


@app.route("/")
def index():
    instance_id = instance_metadata("instance-id")
    az = instance_metadata("placement/availability-zone")
    try:
        total, version = record_visit()
        db_status = f"Connected to MySQL {escape(version)} over TLS &mdash; total visits: {total}"
        db_class = "ok"
    except Exception as exc:
        app.logger.error("Database check failed: %s", exc)
        db_status = f"Database unavailable ({escape(type(exc).__name__)})"
        db_class = "err"

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>AWS DevOps Task</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 body{{font-family:system-ui,Arial,sans-serif;max-width:760px;margin:40px auto;padding:0 16px;color:#1d1d1f}}
 h1{{color:#1F4E79}} table{{border-collapse:collapse;width:100%}}
 td{{border:1px solid #ccd;padding:8px}} td:first-child{{font-weight:600;width:35%}}
 .ok{{color:#137333;font-weight:600}} .err{{color:#b3261e;font-weight:600}}
</style></head><body>
<h1>AWS Infrastructure &amp; CI/CD &mdash; Demo App v2</h1>
<p>Served over HTTPS by an Application Load Balancer to an EC2 Auto Scaling Group.
Refresh the page to see requests balanced across instances and Availability Zones.</p>
<table>
 <tr><td>Instance ID</td><td>{escape(instance_id)}</td></tr>
 <tr><td>Availability Zone</td><td>{escape(az)}</td></tr>
 <tr><td>App version</td><td>{escape(APP_VERSION)}</td></tr>
 <tr><td>Database</td><td class="{db_class}">{db_status}</td></tr>
</table>
</body></html>"""


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
