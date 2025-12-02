import os
import datetime
from typing import Optional

import mysql.connector
from mysql.connector import pooling
from dotenv import load_dotenv

# Load environment variables from .env in this folder
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "payless_user"),
    "password": os.getenv("DB_PASSWORD", "payless_password"),
    "database": os.getenv("DB_NAME", "payless_tax"),
}

_connection_pool: Optional[pooling.MySQLConnectionPool] = None


def get_pool() -> pooling.MySQLConnectionPool:
    global _connection_pool
    if _connection_pool is None:
        _connection_pool = pooling.MySQLConnectionPool(
            pool_name="payless_tax_pool",
            pool_size=5,
            **DB_CONFIG,
        )
    return _connection_pool


def get_connection():
    pool = get_pool()
    return pool.get_connection()


def init_db() -> None:
    """Create minimal tables if they do not exist."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                email VARCHAR(255) NOT NULL UNIQUE,
                full_name VARCHAR(255) NOT NULL,
                persona_inquiry_id VARCHAR(255),
                kyc_status ENUM('NOT_STARTED', 'PENDING', 'VERIFIED', 'FAILED') DEFAULT 'NOT_STARTED',
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
            """
        )
        conn.commit()
    finally:
        conn.close()


def create_user(email: str, full_name: str) -> int:
    conn = get_connection()
    try:
        cur = conn.cursor()
        now = datetime.datetime.utcnow()
        cur.execute(
            """
            INSERT INTO users (email, full_name, kyc_status, created_at, updated_at)
            VALUES (%s, %s, 'NOT_STARTED', %s, %s)
            """,
            (email, full_name, now, now),
        )
        conn.commit()
        return cur.lastrowid
    finally:
        conn.close()


def get_user_by_email(email: str) -> Optional[dict]:
    conn = get_connection()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute("SELECT * FROM users WHERE email = %s", (email,))
        row = cur.fetchone()
        return row
    finally:
        conn.close()


def update_user_inquiry(user_id: int, inquiry_id: str, status: str) -> None:
    conn = get_connection()
    try:
        cur = conn.cursor()
        now = datetime.datetime.utcnow()
        cur.execute(
            """
            UPDATE users
            SET persona_inquiry_id = %s,
                kyc_status = %s,
                updated_at = %s
            WHERE id = %s
            """,
            (inquiry_id, status, now, user_id),
        )
        conn.commit()
    finally:
        conn.close()


def update_user_status_by_inquiry(inquiry_id: str, status: str) -> None:
    conn = get_connection()
    try:
        cur = conn.cursor()
        now = datetime.datetime.utcnow()
        cur.execute(
            """
            UPDATE users
            SET kyc_status = %s,
                updated_at = %s
            WHERE persona_inquiry_id = %s
            """,
            (status, now, inquiry_id),
        )
        conn.commit()
    finally:
        conn.close()
