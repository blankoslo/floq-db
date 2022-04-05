-- Deploy floq:add_trak to pg

BEGIN;

CREATE TYPE responsible_type AS ENUM (
    'HR_MANAGER',
    'PROJECT_MANAGER',
    'OTHER'
);

CREATE TABLE employee_settings (
    employee_id integer NOT NULL,
    slack boolean DEFAULT true NOT NULL,
    delegate boolean DEFAULT true NOT NULL,
    deadline boolean DEFAULT true NOT NULL,
    week_before_deadline boolean DEFAULT true NOT NULL,
    termination boolean DEFAULT true NOT NULL,
    hired boolean DEFAULT true NOT NULL
);

CREATE TABLE employee_task (
    id text NOT NULL,
    task_id text NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    employee_id integer NOT NULL,
    responsible_id integer NOT NULL,
    due_date timestamp(3) without time zone NOT NULL,
    completed_date timestamp(3) without time zone,
    completed_by_id integer
);

CREATE TABLE employee_task_comments (
    id text NOT NULL,
    text text NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by_id integer NOT NULL,
    employee_task_id text NOT NULL
);

CREATE TABLE notification (
    id text NOT NULL,
    employee_id integer NOT NULL,
    created_by integer,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    read boolean DEFAULT false NOT NULL,
    description text NOT NULL
);

CREATE TABLE phase (
    id text NOT NULL,
    title text NOT NULL,
    process_template_id text NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    due_date_day_offset integer,
    due_date timestamp(3) without time zone,
    active boolean DEFAULT true NOT NULL
);

CREATE TABLE process_template (
    title text NOT NULL,
    slug text NOT NULL
);

CREATE TABLE profession (
    id integer NOT NULL,
    title text NOT NULL
);

CREATE TABLE profession_task (
    profession_id integer NOT NULL,
    task_id text NOT NULL
);

CREATE TABLE task (
    id text NOT NULL,
    title text NOT NULL,
    description text,
    link text,
    global boolean DEFAULT true NOT NULL,
    phase_id text,
    responsible_id integer,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    active boolean DEFAULT true NOT NULL,
    due_date_day_offset integer,
    due_date timestamp(3) without time zone,
    responsible_type responsible_type DEFAULT 'HR_MANAGER'::responsible_type NOT NULL
);

ALTER TABLE employees
    ADD profession_id integer;

ALTER TABLE employee_settings
    ADD CONSTRAINT employee_settings_pkey PRIMARY KEY (employee_id);

ALTER TABLE employee_task_comments
    ADD CONSTRAINT employee_task_comments_pkey PRIMARY KEY (id);

ALTER TABLE employee_task
    ADD CONSTRAINT employee_task_pkey PRIMARY KEY (id);

ALTER TABLE notification
    ADD CONSTRAINT notification_pkey PRIMARY KEY (id);

ALTER TABLE phase
    ADD CONSTRAINT phase_pkey PRIMARY KEY (id);

ALTER TABLE process_template
    ADD CONSTRAINT process_template_pkey PRIMARY KEY (slug);

ALTER TABLE profession
    ADD CONSTRAINT profession_pkey PRIMARY KEY (id);

ALTER TABLE profession_task
    ADD CONSTRAINT profession_task_pkey PRIMARY KEY (profession_id, task_id);

ALTER TABLE task
    ADD CONSTRAINT task_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX employee_email_key ON employees USING btree (email);
CREATE UNIQUE INDEX profession_title_key ON profession USING btree (title);


ALTER TABLE employees
    ADD CONSTRAINT employee_hr_manager_fkey FOREIGN KEY (hr_manager) REFERENCES employees(id) ON DELETE SET NULL,
    ADD CONSTRAINT employee_profession_id_fkey FOREIGN KEY (profession_id) REFERENCES profession(id) ON DELETE RESTRICT;

ALTER TABLE employee_settings
    ADD CONSTRAINT employee_settings_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

ALTER TABLE employee_task_comments
    ADD CONSTRAINT employee_task_comments_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES employees(id) ON DELETE CASCADE,
    ADD CONSTRAINT employee_task_comments_employee_task_id_fkey FOREIGN KEY (employee_task_id) REFERENCES employee_task(id) ON DELETE CASCADE;

ALTER TABLE employee_task
    ADD CONSTRAINT employee_task_completed_by_id_fkey FOREIGN KEY (completed_by_id) REFERENCES employees(id) ON DELETE SET NULL,
    ADD CONSTRAINT employee_task_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
    ADD CONSTRAINT employee_task_responsible_id_fkey FOREIGN KEY (responsible_id) REFERENCES employees(id) ON DELETE CASCADE,
    ADD CONSTRAINT employee_task_task_id_fkey FOREIGN KEY (task_id) REFERENCES task(id) ON DELETE CASCADE;

ALTER TABLE notification
    ADD CONSTRAINT notification_created_by_fkey FOREIGN KEY (created_by) REFERENCES employees(id) ON DELETE SET NULL,
    ADD CONSTRAINT notification_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

ALTER TABLE phase
    ADD CONSTRAINT phase_process_template_id_fkey FOREIGN KEY (process_template_id) REFERENCES process_template(slug) ON DELETE CASCADE;

ALTER TABLE profession_task
    ADD CONSTRAINT profession_task_profession_id_fkey FOREIGN KEY (profession_id) REFERENCES profession(id) ON DELETE CASCADE,
    ADD CONSTRAINT profession_task_task_id_fkey FOREIGN KEY (task_id) REFERENCES task(id) ON DELETE CASCADE;

ALTER TABLE task
    ADD CONSTRAINT task_phase_id_fkey FOREIGN KEY (phase_id) REFERENCES phase(id) ON DELETE SET NULL,
    ADD CONSTRAINT task_responsible_id_fkey FOREIGN KEY (responsible_id) REFERENCES employees(id) ON DELETE SET NULL;



COMMIT;
