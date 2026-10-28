-- Revert floq:drop_unused_tables from pg

BEGIN;

-- The tables come back empty: take a pg_dump of them before deploying.
CREATE TABLE talks (
    employee integer REFERENCES employees(id),
    talk_date date NOT NULL,
    title text NOT NULL,
    description text,
    location text NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT now(),
    id SERIAL PRIMARY KEY
);

CREATE TABLE project_sdg_events (
  event_id SERIAL PRIMARY KEY,
  event_type TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  caused_by INTEGER NOT NULL REFERENCES employees(id),
  project TEXT NOT NULL REFERENCES projects(id),
  goal INTEGER NOT NULL
);

CREATE TABLE ranked_games (
  id    text NOT NULL DEFAULT (uuid_generate_v4()),
  title text NOT NULL DEFAULT '',
  PRIMARY KEY (id)
);

CREATE TYPE ranked_matchup_result as ENUM ('WIN', 'LOSS', 'TIE');

CREATE TABLE ranked_matchups (
  id       text NOT NULL DEFAULT (uuid_generate_v4()),
  game_id  text NOT NULL REFERENCES ranked_games(id),

  user1_id integer NOT NULL REFERENCES employees(id),
  user2_id integer NOT NULL REFERENCES employees(id),
    CHECK (user1_id != user2_id),

  matchup_result ranked_matchup_result NOT NULL DEFAULT ('TIE'),
  created_at     timestamp             NOT NULL DEFAULT now(),

  PRIMARY KEY (id)
);

CREATE TABLE profession_task (
    profession_id text NOT NULL,
    task_id uuid NOT NULL,
    CONSTRAINT profession_task_pkey PRIMARY KEY (profession_id, task_id),
    CONSTRAINT profession_task_profession_id_fkey FOREIGN KEY (profession_id) REFERENCES profession(slug) ON DELETE CASCADE,
    CONSTRAINT profession_task_task_id_fkey FOREIGN KEY (task_id) REFERENCES task(id) ON DELETE CASCADE
);

CREATE TABLE employee_task_comments (
    id uuid DEFAULT gen_random_uuid(),
    text text NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by_id integer NOT NULL,
    employee_task_id uuid NOT NULL,
    CONSTRAINT employee_task_comments_pkey PRIMARY KEY (id),
    CONSTRAINT employee_task_comments_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES employees(id) ON DELETE CASCADE,
    CONSTRAINT employee_task_comments_employee_task_id_fkey FOREIGN KEY (employee_task_id) REFERENCES employee_task(id) ON DELETE CASCADE
);

COMMIT;
