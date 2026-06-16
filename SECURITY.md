# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a vulnerability involving credential
exposure, prompt injection, unsafe installation behavior, or a gate bypass.

Use GitHub's private vulnerability reporting if it is available for this
repository, or contact the maintainer directly from the GitHub profile.

## Scope

Security-sensitive areas include:

- installation scripts that write into another project,
- hooks that decide whether a task can be marked complete,
- reviewer prompts that include uncommitted diffs,
- handling of untracked files, secrets, and local config.

These skills provide review and workflow guardrails. They are not a security
boundary against a user or process with write access to the repository.
