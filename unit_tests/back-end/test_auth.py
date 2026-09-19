import pytest
from jose import jwt
from datetime import timedelta
import os
import sys

# Add the server directory to the path so we can import from main
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../server")))

# Mock environment variables before importing main
os.environ["SECRET_KEY"] = "test-secret-key"
os.environ["DATABASE_URL"] = "postgresql://user:pass@localhost:5432/db" # Fake DB URL

# We might need to mock psycopg2 to avoid connection errors on import
import unittest.mock as mock
mock.patch("psycopg2.connect").start()

from main import verify_password, get_password_hash, create_access_token, SECRET_KEY, ALGORITHM

def test_password_hashing_happy():
    password = "secure_password123"
    hashed = get_password_hash(password)
    assert hashed != password
    assert verify_password(password, hashed) is True

def test_password_hashing_negative():
    password = "secure_password123"
    hashed = get_password_hash(password)
    assert verify_password("wrong_password", hashed) is False

def test_password_hashing_edge_empty():
    password = ""
    hashed = get_password_hash(password)
    assert verify_password(password, hashed) is True

def test_password_hashing_edge_long():
    password = "a" * 100
    hashed = get_password_hash(password)
    assert verify_password(password, hashed) is True

def test_jwt_token_happy():
    data = {"sub": "user_123", "role": "admin"}
    token = create_access_token(data)
    decoded = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    assert decoded["sub"] == "user_123"
    assert decoded["role"] == "admin"
    assert "exp" in decoded

def test_jwt_token_negative_invalid():
    with pytest.raises(Exception): # jose.exceptions.JWTError
        jwt.decode("invalid-token", SECRET_KEY, algorithms=[ALGORITHM])

def test_jwt_token_edge_expired():
    data = {"sub": "user_123"}
    # Create a token that expires in the past
    token = create_access_token(data, expires_delta=timedelta(seconds=-1))
    with pytest.raises(Exception):
        jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
