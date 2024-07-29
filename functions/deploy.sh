#!/bin/bash

case "$1" in
     -d|--dev)
         HOST=floq-dev.caawuzisqucy.eu-central-1.rds.amazonaws.com
         shift
         ;;
     -t|--test)
         HOST=floq-test.caawuzisqucy.eu-central-1.rds.amazonaws.com
         shift
         ;;
     -p|--prod)
         HOST=floq.caawuzisqucy.eu-central-1.rds.amazonaws.com
         shift
         ;;
     -p|--prod-folq)
         HOST=floq-folq-prod.caawuzisqucy.eu-central-1.rds.amazonaws.com
         shift
         ;;
     -l|--local)
         HOST=localhost
         shift
         ;;
     *)
         echo "No environment specified"
         exit 3
         ;;
esac

for f in *.sql
do
 echo "deploying $f to $HOST"
 psql -f "$f" -h $HOST -d floq -U root
done
