FROM onjin/alpine-postgres:9.6

ENV PG_SRC_DB=floq
ENV PG_SRC_USER=root
ENV PG_SRC_PASS=password
ENV PG_SRC_HOST=localhost

ENV PG_DST_DB=floq
ENV PG_DST_USER=root
ENV PG_DST_PASS=password
ENV PG_DST_HOST=localhost

ADD db-replicate /db-replicate
ADD db_drop_all.sql /db_drop_all.sql
ADD db_disable_fks.sql /db_disable_fks.sql
ADD db_enable_fks.sql /db_enable_fks.sql

CMD sh db-replicate
