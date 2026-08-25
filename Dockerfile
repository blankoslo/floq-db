FROM postgres:15-alpine

ENV PG_SRC_URL=postgres://root:password@localhost/floq
ENV PG_DST_URL=postgres://root:password@localhost/floq

ADD db-replicate /db-replicate
ADD db_drop_all.sql /db_drop_all.sql
ADD db_disable_fks.sql /db_disable_fks.sql
ADD db_enable_fks.sql /db_enable_fks.sql

CMD sh db-replicate
