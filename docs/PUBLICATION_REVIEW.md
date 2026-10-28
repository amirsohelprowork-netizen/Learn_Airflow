# Public GitHub publication review

Reviewed on 29 October 2026 (IST), before committing the hardened local platform.

The current publishable files contain no secret findings from Gitleaks 8.30.1. A separate exact-value comparison found none of the 24 generated local credential values (including Vault bootstrap secrets) in the publishable files or reachable Git objects. No private-key markers were found in those files or Git history. All 14 tracked evidence screenshots were visually reviewed; no unmasked credentials were observed.

Git history is not free of historical credential literals: Gitleaks reported 22 matches across old commits. These were classified as 10 occurrences of default local administrator credentials and 12 occurrences of the retired static local API/webserver signing keys. They occur in previous versions of `agent-command.md`, `PROJECT_CONTEXT.md`, `values.yaml`, and `repo_bundle.txt`. None are the credentials used by the hardened installation. Any other installation still using those old defaults or keys must replace them before relying on them as secrets. Deleting an old file does not remove its contents from Git history.

The generated `.local/` directory, `.env` files, private key files, AWS credential directory, Terraform state, and local repository exports are ignored. Example environment files remain eligible for publication. Ignore rules do not remove a file that was already tracked; the tracked-file review found no generated local credential or state files.

This was a publication-safety check, not a guarantee that automated scanning detects every possible secret. No history was rewritten, no commit was created, and nothing was pushed. The existing backup branch remains local; publish the intended `main` branch rather than all local branches.
