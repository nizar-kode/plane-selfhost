#!/usr/bin/env python3
"""
Plane Secret & Environment Generator
Generates cryptographically secure secrets for Plane self-hosted deployments.
"""

import os
import re
import secrets
import string
import sys
from pathlib import Path


def generate_django_secret_key() -> str:
    # Avoid '$' to prevent docker-compose variable interpolation issues
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%&*(-_=+)"
    return "".join(secrets.choice(chars) for _ in range(50))


def generate_alphanumeric(length: int = 32) -> str:
    chars = string.ascii_letters + string.digits
    return "".join(secrets.choice(chars) for _ in range(length))


def generate_hex(length: int = 32) -> str:
    return secrets.token_hex(length)


def main():
    base_dir = Path(__file__).resolve().parent.parent
    env_example_path = base_dir / ".env.example"
    env_target_path = base_dir / ".env"

    if not env_example_path.exists():
        print(f"Error: {env_example_path} does not exist.", file=sys.stderr)
        sys.exit(1)

    force = "--force" in sys.argv or "-f" in sys.argv
    if env_target_path.exists() and not force:
        print(f"Warning: {env_target_path} already exists.")
        print("Use '--force' or '-f' to overwrite existing configuration.")
        return

    content = env_example_path.read_text(encoding="utf-8")

    # Generate unique credentials
    secret_key = generate_django_secret_key()
    live_secret_key = generate_hex(32)
    pg_password = generate_alphanumeric(32)
    mq_password = generate_alphanumeric(32)
    s3_access_key = "plane_" + generate_alphanumeric(16)
    s3_secret_key = generate_alphanumeric(40)

    # Perform substitutions
    content = re.sub(
        r"^SECRET_KEY=.*$",
        f"SECRET_KEY={secret_key}",
        content,
        flags=re.MULTILINE,
    )
    content = re.sub(
        r"^LIVE_SERVER_SECRET_KEY=.*$",
        f"LIVE_SERVER_SECRET_KEY={live_secret_key}",
        content,
        flags=re.MULTILINE,
    )
    content = re.sub(
        r"^POSTGRES_PASSWORD=.*$",
        f"POSTGRES_PASSWORD={pg_password}",
        content,
        flags=re.MULTILINE,
    )
    content = re.sub(
        r"^DATABASE_URL=.*$",
        f"DATABASE_URL=postgresql://plane:{pg_password}@plane-db:5432/plane",
        content,
        flags=re.MULTILINE,
    )
    content = re.sub(
        r"^RABBITMQ_PASSWORD=.*$",
        f"RABBITMQ_PASSWORD={mq_password}",
        content,
        flags=re.MULTILINE,
    )
    content = re.sub(
        r"^AMQP_URL=.*$",
        f"AMQP_URL=amqp://plane:{mq_password}@plane-mq:5672/plane",
        content,
        flags=re.MULTILINE,
    )
    content = re.sub(
        r"^AWS_ACCESS_KEY_ID=.*$",
        f"AWS_ACCESS_KEY_ID={s3_access_key}",
        content,
        flags=re.MULTILINE,
    )
    content = re.sub(
        r"^AWS_SECRET_ACCESS_KEY=.*$",
        f"AWS_SECRET_ACCESS_KEY={s3_secret_key}",
        content,
        flags=re.MULTILINE,
    )

    env_target_path.write_text(content, encoding="utf-8")
    print(f"[OK] Generated secure .env configuration at: {env_target_path}")
    print("  - Generated django SECRET_KEY (50 chars)")
    print("  - Generated LIVE_SERVER_SECRET_KEY (64-char hex)")
    print("  - Generated POSTGRES_PASSWORD & synced DATABASE_URL")
    print("  - Generated RABBITMQ_PASSWORD & synced AMQP_URL")
    print("  - Generated MinIO S3 ACCESS_KEY & SECRET_ACCESS_KEY")
    print("\nNext step: Verify APP_DOMAIN and WEB_URL in .env if using a custom domain.")


if __name__ == "__main__":
    main()
