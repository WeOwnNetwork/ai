#!/usr/bin/env python3
"""
Test file for Copilot auto-review verification.
This file contains intentional patterns to trigger Copilot analysis.
"""

import os
import subprocess

# Intentional security issue: hardcoded secret (Copilot should flag this)
API_KEY = "sk-live-1234567890abcdef1234567890"

# Intentional bug: unused variable
def unused_var_function():
    unused_variable = "this is never used"
    return True

# Intentional issue: shell=True with user input (security risk)
def run_command(user_input):
    result = subprocess.run(f"echo {user_input}", shell=True, capture_output=True)
    return result.stdout.decode()

# Intentional issue: no input validation
def process_data(data):
    # No validation on data parameter
    return eval(data)  # Dangerous - Copilot should flag eval usage

# Intentional style issue: bare except
def risky_exception_handling():
    try:
        with open("/etc/passwd", "r") as f:
            return f.read()
    except:
        pass  # Bare except - bad practice

if __name__ == "__main__":
    print("Test script for Copilot auto-review")
    run_command("hello")
