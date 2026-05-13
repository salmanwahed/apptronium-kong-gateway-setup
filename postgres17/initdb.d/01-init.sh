#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER kong WITH PASSWORD '${KONG_PG_PASSWORD}';
    CREATE DATABASE kong OWNER kong;

    CREATE USER app_ratesageai WITH PASSWORD '${APP_RATESAGEAI_PASSWORD}';
    CREATE DATABASE app_ratesageai OWNER app_ratesageai;
EOSQL
