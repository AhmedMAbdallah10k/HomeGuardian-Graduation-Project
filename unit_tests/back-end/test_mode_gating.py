import pytest
import sys
import os

# Add the server directory to the path so we can import from main
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../server")))

# Mock environment variables before importing main
os.environ["SECRET_KEY"] = "test-secret-key"
os.environ["DATABASE_URL"] = "postgresql://user:pass@localhost:5432/db"

import unittest.mock as mock
mock.patch("psycopg2.connect").start()

from main import get_mode_gating_config

def test_mode_gating_happy_nanny_silver():
    room_modes = {"nanny", "silver"}
    config = get_mode_gating_config(room_modes)
    
    assert config["is_nanny_mode"] is True
    assert config["is_silver_mode"] is True
    assert config["is_home_alone"] is False
    
    assert "fire" in config["parallel_services"]
    assert "exit" in config["parallel_services"]
    assert "stillness" in config["parallel_services"]
    
    assert config["choking_active"] is True
    assert config["sharp_active"] is True
    assert config["door_window_active"] is False

def test_mode_gating_negative_empty():
    room_modes = set()
    config = get_mode_gating_config(room_modes)
    
    assert config["is_nanny_mode"] is False
    assert config["is_silver_mode"] is False
    
    # Fire, fridge, face are always on
    assert set(config["parallel_services"]) == {"fire", "fridge", "face"}
    
    assert config["choking_active"] is False
    assert config["sharp_active"] is False
    assert config["door_window_active"] is False

def test_mode_gating_edge_typo():
    # Typo in mode name should be ignored
    room_modes = {"nany"} 
    config = get_mode_gating_config(room_modes)
    
    assert config["is_nanny_mode"] is False
    assert config["choking_active"] is False
    assert config["sharp_active"] is False

def test_mode_gating_edge_duplicate():
    # Set handles duplicates naturally, but let's test the logic
    room_modes = {"nanny", "nanny"}
    config = get_mode_gating_config(room_modes)
    
    assert config["is_nanny_mode"] is True
    assert config["choking_active"] is True
    assert config["sharp_active"] is True

def test_mode_gating_home_alone():
    room_modes = {"home_alone"}
    config = get_mode_gating_config(room_modes)
    
    assert config["is_home_alone"] is True
    assert config["door_window_active"] is True
    assert "stillness" not in config["parallel_services"]
