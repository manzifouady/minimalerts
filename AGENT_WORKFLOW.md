# Agent Workflow Guide

This document explains exactly how to contribute to this repository as an agent (or human) with consistent quality.

## Goal

Make safe, reviewable changes that:
- solve the requested problem,
- do not leak secrets,
- are tested before push,
- keep docs aligned with behavior.

## Repository Rules

- Do not commit `config.json` or `state.json`.
- Treat credentials (SMTP, SMS API, app passwords) as secrets.
- Prefer small, focused commits.
- Update docs whenever runtime behavior changes.

## Standard Change Flow

### 1) Understand the request

- Restate the user request in concrete terms.
- Identify affected files before editing.
- Check if change impacts:
  - normal install path (`install.sh`)
  - Docker path (`Dockerfile`, `docker-entrypoint.sh`, `docker-compose.yml`)
  - monitoring logic (`monitor.py`)
  - docs (`README.md`, `ARCHITECTURE.md`)

### 2) Inspect current implementation

Use quick targeted searches:
- `rg` for symbols/flags/threshold names
- read only relevant files
- avoid broad/unnecessary edits

### 3) Implement

General rules:
- Keep changes minimal and explicit.
- Preserve backwards compatibility when possible.
- If adding a feature, ensure both systemd and Docker paths are considered.

Typical examples:
- **Feature add**: update runtime code + config template + installer/docker prompts + docs.
- **Feature remove**: remove from logic + remove from config template/prompts + docs cleanup.
- **Behavior change**: add diagnostic command or guardrails where ambiguity can break deployments.

### 4) Test before commit

Run only relevant checks for your change. Minimum baseline:

```bash
python3 -m py_compile monitor.py
bash -n install.sh
bash -n docker-entrypoint.sh
docker compose config >/tmp/minimalerts-compose.yml
```

If runtime behavior changed, run one of:

```bash
source .venv/bin/activate && python3 monitor.py --self-test
docker compose run --rm minimalerts self-test
docker compose run --rm minimalerts verify-host
```

If image/runtime changed, also:

```bash
docker build -t minimalerts:local .
```

### 5) Validate docs

Before commit, ensure `README.md` reflects:
- new commands,
- changed defaults,
- changed setup flow,
- any new environment variables.

If docs and code disagree, fix docs before commit.

### 6) Commit style

Commit message format in this repo:
- short title line (why-oriented),
- optional body with intent and impact.

Recommended structure:

```text
<Action> <scope> <outcome>.

<Why this change was needed and what behavior is improved.>
```

Examples:
- `Add Docker host-metrics verification and host-scope collection settings.`
- `Remove MB-based memory alert threshold and keep RAM alerts percent-based.`

### 7) Push and verify state

After commit:

```bash
git push
git status
```

Working tree should be clean after push.

## Feature Add Checklist

- [ ] Runtime logic implemented (`monitor.py`)
- [ ] Config template updated (`config.sample.json`) if needed
- [ ] Install flow updated (`install.sh`) if needed
- [ ] Docker flow updated (`docker-entrypoint.sh`, `docker-compose.yml`) if needed
- [ ] Tests/validation commands executed
- [ ] Docs updated (`README.md`)
- [ ] Commit + push completed

## Feature Remove Checklist

- [ ] Remove logic from runtime code
- [ ] Remove dead config keys/prompts
- [ ] Remove docs references and examples
- [ ] Re-run tests to ensure no regressions
- [ ] Commit + push completed

## Safety Checklist

- [ ] No secret files staged
- [ ] No credentials printed in docs/examples as real values
- [ ] No destructive git operations used
- [ ] No long-lived local process left running

## If something fails

- Read exact error text.
- Fix root cause, not symptoms.
- Re-run the smallest meaningful test.
- Re-run full relevant checks before commit.

## Definition of Done

A change is done when:
1. behavior works,
2. tests pass,
3. docs are accurate,
4. commit is pushed,
5. another agent can understand and continue work from repo state alone.
