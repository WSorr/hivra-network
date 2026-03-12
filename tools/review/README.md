# Review Checks

This directory contains deterministic repository checks for architecture and security hygiene.

Scripts:

- `topology_check.sh` validates high-level repository placement rules.
- `dependency_check.sh` validates downward dependency direction between Rust crates.
- `security_check.sh` validates that common local artifacts and obvious secret-like content are not tracked.
- `review_all.sh` runs every check and returns non-zero on any failure.

Run from the repository root:

```bash
tools/review/review_all.sh
```

These checks are intentionally mechanical. They should stay simple, deterministic, and easy to audit.
