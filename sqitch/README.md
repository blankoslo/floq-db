# Floq DB Migrations

## Prerequisites

You need to install [Sqitch](http://sqitch.org), or use the `sqitch.sh` which
runs Sqitch in a Docker container.

## Initialization

Edit `sqitch.conf` if you want to change the database target(s) and set the DB
password using SQITCH_PASSWORD, then run:

```
sqitch deploy --verify --target <TARGET>
```

## Hacking

To add a new migration to the database schema:

- `sqitch add add_foo_table -n 'Add a new foo table'`
- `$EDITOR {deploy,revert,verify}/add_foo_table.sql`
- `sqitch deploy --verify --target floq-dev`

To revert the last change:

- `sqitch revert --to '@HEAD^' --target floq-dev`

## New DB instructions
TODO