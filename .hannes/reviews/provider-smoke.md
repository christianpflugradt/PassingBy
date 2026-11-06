This is a provider connectivity smoke test, not a review of the application.
Read only `.hannes/provider.toml`. If line 1 is `provider = "codex-cli"`, return
PASS with reason "Codex provider smoke test completed" and exactly one finding:
message "Codex CLI provider configuration read successfully", path
`.hannes/provider.toml`, line 1. Do not inspect application code, Product.md,
Git history, or unrelated files. Do not perform product or quality assessment.
If the file is missing, unreadable, or has a different provider, return ERROR
with a brief reason. Do not edit files, stage, commit, push, or run build/tests.
