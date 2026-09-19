import subprocess
import sys
import time
import re

def run_command(command):
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def print_header(text):
    print("\n" + "="*65)
    print(f" {text}")
    print("="*65)

def parse_backend_tests(output):
    tests = []
    # Match lines like: unit_tests/back-end/test_auth.py::test_password_hashing_happy PASSED
    pattern = r"unit_tests/back-end/(.*?\.py)::(.*?) (PASSED|FAILED)"
    matches = re.findall(pattern, output)
    for file, name, status in matches:
        tests.append({"file": file, "name": name, "status": status})
    return tests

def parse_frontend_tests(output):
    tests = []
    # Match lines like: 00:00 +0: UserOptions.fromJson Happy Scenario: parses valid JSON correctly
    # Note: Flutter test output can vary, this is a best-effort parse for the current setup
    lines = output.splitlines()
    for line in lines:
        if " +0: " in line or " +1: " in line or " +2: " in line or " +3: " in line:
            if "loading" not in line and "All tests passed" not in line:
                # Extract the test name after the +N:
                parts = line.split(":", 2)
                if len(parts) > 2:
                    name = parts[2].strip()
                    tests.append({"name": name, "status": "PASSED"})
    return tests

def generate_markdown_report(be_tests, fe_tests, be_duration, fe_duration, be_success, fe_success):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    be_passed = len([t for t in be_tests if t['status'] == "PASSED"])
    fe_passed = len(fe_tests)
    total_passed = be_passed + fe_passed
    
    md = f"# Home Guardian — Unit Test Report\n"
    md += f"*Generated on: {timestamp}*\n\n"
    
    md += "## 📊 Summary\n"
    md += "| Category | Status | Passed | Time |\n"
    md += "| :--- | :--- | :--- | :--- |\n"
    md += f"| Back-end | {'✅ PASSED' if be_success else '❌ FAILED'} | {be_passed}/18 | {be_duration:.2f}s |\n"
    md += f"| Front-end | {'✅ PASSED' if fe_success else '❌ FAILED'} | {fe_passed}/3 | {fe_duration:.2f}s |\n"
    md += f"| **TOTAL** | | **{total_passed}/21** | **{be_duration + fe_duration:.2f}s** |\n\n"
    
    md += "## 🛡️ Back-end Details (Python)\n"
    md += "| File | Test Name | Result |\n"
    md += "| :--- | :--- | :--- |\n"
    for test in be_tests:
        md += f"| {test['file']} | `{test['name']}` | {'✅ PASSED' if test['status'] == 'PASSED' else '❌ FAILED'} |\n"
    
    md += "\n## 📱 Front-end Details (Flutter)\n"
    md += "| Test Name | Result |\n"
    md += "| :--- | :--- |\n"
    for test in fe_tests:
        md += f"| {test['name']} | ✅ PASSED |\n"
    
    if not be_success or not fe_success:
        md += "\n## ⚠️ Errors\n"
        if not be_success:
            md += "### Back-end Errors\n```\nCheck terminal output for full traceback.\n```\n"
        if not fe_success:
            md += "### Front-end Errors\n```\nCheck terminal output for full traceback.\n```\n"

    with open("UNIT_TEST_REPORT.md", "w", encoding="utf-8") as f:
        f.write(md)
    return "UNIT_TEST_REPORT.md"

def main():
    print_header("HOME GUARDIAN — DETAILED TEST RUNNER")
    
    # 1. Run Backend Tests
    print("\n[1/2] Running Backend Tests (pytest)...")
    start_time = time.time()
    be_success, be_out, be_err = run_command("python -m pytest unit_tests/back-end -v")
    be_duration = time.time() - start_time
    be_tests = parse_backend_tests(be_out)
    
    # 2. Run Frontend Tests
    print("[2/2] Running Frontend Tests (flutter test)...")
    start_time = time.time()
    fe_success, fe_out, fe_err = run_command("flutter test unit_tests/front-end/user_options_test.dart")
    fe_duration = time.time() - start_time
    fe_tests = parse_frontend_tests(fe_out)
    
    # 3. Generate Markdown File
    report_file = generate_markdown_report(be_tests, fe_tests, be_duration, fe_duration, be_success, fe_success)
    print(f"\n[+] Markdown report generated: {report_file}")

    # 4. Detailed Report (Terminal)
    print_header("DETAILED TEST RESULTS")
    
    print(f"\n--- BACK-END (Python) ---")
    print(f"{'FILE':<20} | {'TEST NAME':<40} | {'RESULT':<10}")
    print("-" * 75)
    for test in be_tests:
        print(f"{test['file']:<20} | {test['name']:<40} | {test['status']:<10}")
    
    print(f"\n--- FRONT-END (Flutter) ---")
    print(f"{'TEST NAME':<63} | {'RESULT':<10}")
    print("-" * 75)
    for test in fe_tests:
        print(f"{test['name']:<63} | {test['status']:<10}")

    # 4. Summary Table
    print_header("SUMMARY REPORT")
    
    be_passed = len([t for t in be_tests if t['status'] == "PASSED"])
    fe_passed = len(fe_tests)
    
    print(f"{'CATEGORY':<15} | {'STATUS':<10} | {'PASSED':<8} | {'TIME':<8}")
    print("-" * 50)
    
    be_status = "PASSED" if be_success else "FAILED"
    print(f"{'Back-end':<15} | {be_status:<10} | {be_passed:<8} | {be_duration:.2f}s")
    
    fe_status = "PASSED" if fe_success else "FAILED"
    print(f"{'Front-end':<15} | {fe_status:<10} | {fe_passed:<8} | {fe_duration:.2f}s")
    
    print("-" * 50)
    total_passed = be_passed + fe_passed
    print(f"{'TOTAL':<15} | {'':<10} | {total_passed:<8} | {be_duration + fe_duration:.2f}s")

    if not be_success and not be_tests:
        print("\n[!] Backend Execution Error:")
        print(be_err if be_err else be_out)
        
    if not fe_success and not fe_tests:
        print("\n[!] Frontend Execution Error:")
        print(fe_err if fe_err else fe_out)

    print("\n" + "="*65)
    if be_success and fe_success:
        print(" SUCCESS: ALL SYSTEMS GO! ALL TESTS PASSED.")
    else:
        print(" WARNING: SOME TESTS FAILED. CHECK LOGS ABOVE.")
    print("="*65 + "\n")

if __name__ == "__main__":
    main()
