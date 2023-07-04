# Floq database replication
Copies the contents from the production database to test every night so that we
have “real” data during development.

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
