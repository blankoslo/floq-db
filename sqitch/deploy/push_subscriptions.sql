-- Deploy floq:add_push_subscriptions_table to pg

BEGIN;

CREATE TABLE push_subscriptions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  endpoint      TEXT NOT NULL,
  p256dh        TEXT NOT NULL,
  auth          TEXT NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
);

COMMIT;