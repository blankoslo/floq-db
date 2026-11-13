FROM postgres:18-alpine

# PG_SRC_URL and PG_DST_URL must be supplied at runtime (e.g. from Secret Manager),
# not baked into the image.

ADD db-replicate /db-replicate
ADD db_drop_all.sql /db_drop_all.sql

CMD sh db-replicate
