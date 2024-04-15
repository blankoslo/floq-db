For now we have to different ways to alter the database:

### Sqitch

Should be used for all tables, and everything we need for the tables to work: custom types, extensions ++. Can also be used for functions needed in migrations.

### SQL-files deployed manually

For all functions and views, that are created and updated mainly to develop our API exposed through postgrest.

### Why?

Because the Sqitch migrations don't make much sense when we iterate over functions often. It is hard following their changes in git when we end up with v1, v2, v3... of every function.

Hopefully we can use some other tool (pgRebase?) to maintain the functions in a nicer way. In the future.

### Hooks

Please make sure to read [hooks/README.md](hooks/README.md) to ensure that no passwords are committed.

## How to run

### Prerequisites

- [floq](https://github.com/blankoslo/floq) set up
- Docker

### Docker setup

In the following files in `./sqitch/deploy`, change the `PASSWORD` from `NULL` to `'password'`: - `add_employee_user.sql` - `add_read_only_user.sql` - `add_trak_read_only_user.sql`

- Make .env file (`cp .env.example .env`) and put values:
  - `POSTGRES_VOLUME_MOUNT`: `~/path/to/floq/dev:/var/lib/postgresql/data` (edit path here, and note that it points to `floq`, not `floq-db`!)
  - `PGRST_JWT_SECRET`: Same as `API_TOKEN_SECRET` in `floq`'s `.env`. Found in 1password under "Floq test JWT secret", or in the Google Cloud security page under [floq-test-api-token](https://console.cloud.google.com/security/secret-manager/secret/floq-test-api-token/versions?authuser=1&project=marine-cycle-97212)
- Run `docker compose up` (If you have the Docker desktop app it should appear there now)
- Create database entries:
  - If using the Docker desktop app:
    - Go into the `floq-db-1` container
    - Select the Exec tab
  - If **not** using the Docker desktop app:
    - In the terminal, type `docker exec -it floq-floq-db-1 /bin/sh`
  - Type `psql -d floq`, then:
    - `CREATE USER employee WITH PASSWORD 'password';`
    - `CREATE USER read_only WITH PASSWORD 'password';`
    - `CREATE USER trak WITH PASSWORD 'password';`
    - `CREATE USER trak_read_only WITH PASSWORD 'password';`
