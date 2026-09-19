import pytest
import sys
import os
from fastapi import HTTPException

# Add the server directory to the path so we can import from main
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../server")))

# Mock environment variables before importing main
os.environ["SECRET_KEY"] = "test-secret-key"
os.environ["DATABASE_URL"] = "postgresql://user:pass@localhost:5432/db"

import unittest.mock as mock
mock.patch("psycopg2.connect").start()

from main import validate_user_options

def test_validate_options_happy():
    data = {
        "network_route_mode": "home",
        "api_base_home_url": "http://192.168.1.10",
        "api_base_tunnel_url": "http://100.81.199.36",
        "recording_retention_days": 30
    }
    validated = validate_user_options(data)
    
    assert validated["network_route_mode"] == "home"
    assert validated["api_base_home_url"] == "http://192.168.1.10"
    assert validated["api_base_tunnel_url"] == "http://100.81.199.36"
    assert validated["recording_retention_days"] == 30

def test_validate_options_negative_route():
    data = {"network_route_mode": "invalid"}
    with pytest.raises(HTTPException) as excinfo:
        validate_user_options(data)
    assert excinfo.value.status_code == 400
    assert "network_route_mode must be 'home' or 'tunnel'" in str(excinfo.value.detail)

def test_validate_options_negative_retention():
    data = {"recording_retention_days": -5}
    with pytest.raises(HTTPException) as excinfo:
        validate_user_options(data)
    assert excinfo.value.status_code == 400
    assert "recording_retention_days must be a non-negative integer" in str(excinfo.value.detail)

def test_validate_options_edge_identical_urls():
    # Should be valid according to current logic
    data = {
        "api_base_home_url": "http://same.com",
        "api_base_tunnel_url": "http://same.com"
    }
    validated = validate_user_options(data)
    assert validated["api_base_home_url"] == "http://same.com"
    assert validated["api_base_tunnel_url"] == "http://same.com"

def test_validate_options_edge_malformed_url():
    # Current logic just strips whitespace, doesn't validate URL format strictly
    data = {"api_base_home_url": "  not-really-a-url  "}
    validated = validate_user_options(data)
    assert validated["api_base_home_url"] == "not-really-a-url"

def test_validate_options_ignore_unknown_cols():
    data = {"unknown_col": "value", "theme": "dark"}
    validated = validate_user_options(data)
    assert "unknown_col" not in validated
    assert validated["theme"] == "dark"
