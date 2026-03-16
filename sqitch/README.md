# Floq DB Migrations

## Prerequisites

You need either:
- [Sqitch](https://sqitch.org/download/) installed locally (e.g. `brew install sqitch`), or
- Docker, and use the `./sqitch` wrapper script in this directory which runs Sqitch in a container

## Running Sqitch

### Via Docker (recommended)

All commands use the `./sqitch` wrapper script from inside this `sqitch/` directory.
The script runs the official `sqitch/sqitch` Docker image and mounts the current directory into the container.

**Deploy all pending changes:**
```sh
SQITCH_PASSWORD=password ./sqitch deploy --target floq-local-docker
```

**Revert the last change:**
```sh
SQITCH_PASSWORD=password ./sqitch revert --to '@HEAD^' --target floq-local-docker
```

**Check deployment status:**
```sh
SQITCH_PASSWORD=password ./sqitch status --target floq-local-docker
```

Available targets are defined in `sqitch.conf`: `floq-local-docker`, `floq-dev`, `floq-test`, `floq-prod`.
For non-local targets, the `SQITCH_PASSWORD` is the `root` database password, which can be found in 1Password.

#### Author config

Since the script runs as `root` inside the container, your name will show as `root` in `sqitch.plan` unless you configure it. Create a `.sqitch/sqitch.conf` file in this directory:

```sh
mkdir -p .sqitch
cat > .sqitch/sqitch.conf << EOF
[user]
    name = Your Name
    email = your.email@blank.no
EOF
```

### Locally (native install)

If you have Sqitch installed locally, use `sqitch` directly instead of `./sqitch`.
Use the `floq-local` target which points to `localhost`:

```sh
SQITCH_PASSWORD=password sqitch deploy --target floq-local
```

## Adding a new migration

From inside the `sqitch/` directory:

1. Register the change (creates the three SQL files and updates `sqitch.plan`):
```sh
./sqitch add add_foo_table -n 'Add foo table'
```

2. Edit the generated files:
   - `deploy/add_foo_table.sql` — the change (e.g. `CREATE TABLE`)
   - `revert/add_foo_table.sql` — how to undo it (e.g. `DROP TABLE`)
   - `verify/add_foo_table.sql` — a check that it was applied (e.g. `SELECT * FROM foo`)

3. If your change depends on another, add it in `sqitch.plan`:
```
add_foo_table [employees_table] 2026-... # Add foo table
```

4. Deploy:
```sh
SQITCH_PASSWORD=password ./sqitch deploy --target floq-local-docker
```
