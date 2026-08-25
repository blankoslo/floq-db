# Floq database replication

Copies the contents from the production database to test every night so that we
have “real” data during development.

## Setup

### Prerequisites

- [floq-db](https://github.com/blankoslo/floq-db) set up and running in Docker
- Postgres@15 (or latest major version)
- 1password access

### Running the script

- Prepend to `db-replicate` script:

  ```sh
   PG_SRC_URL=postgres://root:password@floq-test.caawuzisqucy.eu-central-1.rds.amazonaws.com/floq
   PG_DST_URL=postgres://root:password@localhost/floq
  ```

- In `PG_SRC_URL`, add password from 1password under "Floq: Blank – test – root"
- In the Dockerfile, edit:
  - `ENV PG_SRC_URL=postgres://root:password@floq-test.caawuzisqucy.eu-central-1.rds.amazonaws.com/floq`
  - `ENV PG_DST_URL=postgres://root:password@host.docker.internal/floq`
- In `db-replicate`, remove `/` from where it says `db_*.sql`
- Run `./db-replicate`

## Empty test database?

You should be able to see an error log on the Google Cloud Run Job (link below).

Check if the Postgres version this docker image is based on is older than the running test database. If so, update the Postgres image (latest major should be fine).

## Build & deploy

A build trigger on Google Cloud Build is connected to this repo and will build a new version whenever a new commit is created on master. The image is then stored on Google Container Reistry.

[Google Cloud Build triggers](https://console.cloud.google.com/cloud-build/triggers?project=marine-cycle-97212) (look for `floq-db-replicate-docker-container`)

[Google Container Registry](https://console.cloud.google.com/gcr/images/marine-cycle-97212/eu/floq-db-replicate?project=marine-cycle-97212)

## Runtime

A Google Cloud Run Job runs every morning (at 7) duplicating the prod database in test, using the latest image on Google Container Registry.

[Google Cloud Run Job](https://console.cloud.google.com/run/jobs/details/europe-north1/floq-db-replicate-prod-to-test/executions?project=marine-cycle-97212)
