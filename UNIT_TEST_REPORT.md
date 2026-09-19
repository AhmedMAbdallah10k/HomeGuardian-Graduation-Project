# Home Guardian — Unit Test Report
*Generated on: 2026-05-30 15:43:04*

## 📊 Summary
| Category | Status | Passed | Time |
| :--- | :--- | :--- | :--- |
| Back-end | ✅ PASSED | 18/18 | 16.53s |
| Front-end | ✅ PASSED | 3/3 | 4.72s |
| **TOTAL** | | **21/21** | **21.24s** |

## 🛡️ Back-end Details (Python)
| File | Test Name | Result |
| :--- | :--- | :--- |
| test_auth.py | `test_password_hashing_happy` | ✅ PASSED |
| test_auth.py | `test_password_hashing_negative` | ✅ PASSED |
| test_auth.py | `test_password_hashing_edge_empty` | ✅ PASSED |
| test_auth.py | `test_password_hashing_edge_long` | ✅ PASSED |
| test_auth.py | `test_jwt_token_happy` | ✅ PASSED |
| test_auth.py | `test_jwt_token_negative_invalid` | ✅ PASSED |
| test_auth.py | `test_jwt_token_edge_expired` | ✅ PASSED |
| test_mode_gating.py | `test_mode_gating_happy_nanny_silver` | ✅ PASSED |
| test_mode_gating.py | `test_mode_gating_negative_empty` | ✅ PASSED |
| test_mode_gating.py | `test_mode_gating_edge_typo` | ✅ PASSED |
| test_mode_gating.py | `test_mode_gating_edge_duplicate` | ✅ PASSED |
| test_mode_gating.py | `test_mode_gating_home_alone` | ✅ PASSED |
| test_options.py | `test_validate_options_happy` | ✅ PASSED |
| test_options.py | `test_validate_options_negative_route` | ✅ PASSED |
| test_options.py | `test_validate_options_negative_retention` | ✅ PASSED |
| test_options.py | `test_validate_options_edge_identical_urls` | ✅ PASSED |
| test_options.py | `test_validate_options_edge_malformed_url` | ✅ PASSED |
| test_options.py | `test_validate_options_ignore_unknown_cols` | ✅ PASSED |

## 📱 Front-end Details (Flutter)
| Test Name | Result |
| :--- | :--- |
| UserOptions.fromJson Happy Scenario: parses valid JSON correctly | ✅ PASSED |
| UserOptions.fromJson Negative Scenario: handles missing keys with safe defaults | ✅ PASSED |
| UserOptions.fromJson Edge Case: handles type mismatches gracefully | ✅ PASSED |
