# Project Rules: Coder-Validator Loop

Whenever implementing code updates, fixing bugs, or addressing user requests in this repository:

1. **Iterative Development Loop**:
   - Spawning subagents or writing code directly is acceptable, but you **MUST** run the validation test suite immediately after any code changes.
   - Run the E2E verification script: `bash validate.sh` from the workspace.

2. **Self-Correction & Repeat**:
   - If `validate.sh` exits with a non-zero code or outputs any failure details (`[FAIL]` or stderr errors):
     - Identify the root cause of the failure.
     - Delegate the fixes to the `coder` subagent (or apply them directly).
     - Run `bash validate.sh` again to test the new code.
   - You **MUST** repeat this loop (Fix → Validate → Fix) continuously until `validate.sh` completes with a perfect success status (exiting with code 0 and showing "ALL TESTS PASSED SUCCESSFULLY!").

3. **No Unverified Deliveries**:
   - Never report a task as complete or present the final changes to the user unless the validation loop has completed perfectly.
