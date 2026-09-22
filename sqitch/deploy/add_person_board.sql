BEGIN;

CREATE TABLE person_track (
    slug       TEXT    CONSTRAINT person_track_pkey PRIMARY KEY,
    label      TEXT    NOT NULL,
    sort_order INTEGER NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    active     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE UNIQUE INDEX person_track_one_default_idx ON person_track (is_default) WHERE is_default;

INSERT INTO person_track (slug, label, sort_order, is_default) VALUES
    ('nyutdannede',        'Nyutdannede',        10, FALSE),
    ('onsker_utrullering', 'Ønsker utrullering', 20, FALSE),
    ('blir_ledig',         'Blir ledig',         30, FALSE),
    ('ledig_na',           'Ledig nå',           40, FALSE),
    ('i_arbeid',           'I arbeid',           50, TRUE),
    ('tilbud_sendt',       'Tilbud sendt',       60, FALSE),
    ('intervju',           'Intervju',           70, FALSE),
    ('signert_avtale',     'Signert avtale',     80, FALSE);

CREATE TABLE person_card (
    id          TEXT        CONSTRAINT person_card_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id INTEGER     CONSTRAINT person_card_employee_id_key UNIQUE REFERENCES employees (id),
    name_text   TEXT,
    track_slug  TEXT        NOT NULL REFERENCES person_track (slug),
    track_since TIMESTAMPTZ NOT NULL DEFAULT now(),
    note        TEXT,
    created_by  INTEGER     REFERENCES employees (id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT person_card_names_one_person CHECK ((employee_id IS NULL) <> (name_text IS NULL)),
    CONSTRAINT person_card_employee_id_is_stable CHECK (employee_id IS NULL OR id = 'ansatt-' || employee_id)
);

CREATE TABLE person_card_event (
    id          TEXT        CONSTRAINT person_card_event_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id     TEXT        REFERENCES person_card (id) ON DELETE SET NULL,
    kind_slug   TEXT        NOT NULL REFERENCES sales_event_kind (slug),
    from_track  TEXT        REFERENCES person_track (slug),
    to_track    TEXT        REFERENCES person_track (slug),
    author_id   INTEGER     REFERENCES employees (id),
    payload     JSONB       NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX person_card_event_card_idx ON person_card_event (card_id, occurred_at DESC);

CREATE FUNCTION set_person_card_author()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.created_by = logged_in_employee_id();
    RETURN NEW;
END;
$$;

CREATE TRIGGER person_card_author
    BEFORE INSERT ON person_card
    FOR EACH ROW
    EXECUTE FUNCTION set_person_card_author();

CREATE FUNCTION set_person_card_track_since()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NEW.track_slug IS DISTINCT FROM OLD.track_slug THEN
        NEW.track_since = clock_timestamp();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER person_card_track_since
    BEFORE UPDATE ON person_card
    FOR EACH ROW
    EXECUTE FUNCTION set_person_card_track_since();

CREATE FUNCTION log_person_card_created()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO person_card_event (card_id, kind_slug, to_track, author_id)
    VALUES (NEW.id, 'created', NEW.track_slug, NEW.created_by);

    RETURN NULL;
END;
$$;

CREATE TRIGGER person_card_created
    AFTER INSERT ON person_card
    FOR EACH ROW
    WHEN (NEW.employee_id IS NULL)
    EXECUTE FUNCTION log_person_card_created();

CREATE FUNCTION log_person_card_track_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO person_card_event (card_id, kind_slug, from_track, to_track, author_id)
    VALUES (NEW.id, 'stage_change', OLD.track_slug, NEW.track_slug, logged_in_employee_id());

    RETURN NULL;
END;
$$;

CREATE TRIGGER person_card_track_change
    AFTER UPDATE OF track_slug ON person_card
    FOR EACH ROW
    WHEN (NEW.track_slug IS DISTINCT FROM OLD.track_slug)
    EXECUTE FUNCTION log_person_card_track_change();

CREATE FUNCTION log_person_card_field_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    changes JSONB;
BEGIN
    SELECT jsonb_agg(jsonb_build_object('field', key, 'from', to_jsonb(OLD) -> key, 'to', value)
                     ORDER BY key)
    INTO changes
    FROM jsonb_each(to_jsonb(NEW))
    WHERE to_jsonb(OLD) -> key IS DISTINCT FROM value
      AND key NOT IN ('id', 'track_slug', 'track_since', 'created_at', 'created_by', 'employee_id');

    IF changes IS NOT NULL THEN
        INSERT INTO person_card_event (card_id, kind_slug, author_id, payload)
        VALUES (NEW.id, 'field_change', logged_in_employee_id(), jsonb_build_object('changes', changes));
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER person_card_field_change
    AFTER UPDATE ON person_card
    FOR EACH ROW
    EXECUTE FUNCTION log_person_card_field_change();

CREATE FUNCTION log_person_card_deleted()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO person_card_event (card_id, kind_slug, from_track, author_id, payload)
    VALUES (OLD.id, 'deleted', OLD.track_slug, logged_in_employee_id(),
            jsonb_build_object('card', to_jsonb(OLD)));

    RETURN OLD;
END;
$$;

CREATE TRIGGER person_card_deleted
    BEFORE DELETE ON person_card
    FOR EACH ROW
    EXECUTE FUNCTION log_person_card_deleted();

CREATE FUNCTION set_person_card_event_author()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.author_id = logged_in_employee_id();
    RETURN NEW;
END;
$$;

CREATE TRIGGER person_card_event_author
    BEFORE INSERT ON person_card_event
    FOR EACH ROW
    EXECUTE FUNCTION set_person_card_event_author();

GRANT SELECT, INSERT, UPDATE ON TABLE person_track TO employee;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE person_card TO employee;
GRANT SELECT, INSERT ON TABLE person_card_event TO employee;

GRANT SELECT ON TABLE person_track TO read_only;
GRANT SELECT ON TABLE person_card TO read_only;
GRANT SELECT ON TABLE person_card_event TO read_only;

ALTER TABLE person_track ENABLE ROW LEVEL SECURITY;
CREATE POLICY person_track_select_policy ON person_track FOR SELECT USING (true);
CREATE POLICY person_track_write_policy ON person_track FOR ALL TO employee
    USING (check_admin_write_access()) WITH CHECK (check_admin_write_access());

ALTER TABLE person_card ENABLE ROW LEVEL SECURITY;
CREATE POLICY person_card_select_policy ON person_card FOR SELECT USING (true);
CREATE POLICY person_card_insert_policy ON person_card FOR INSERT TO employee WITH CHECK (true);
CREATE POLICY person_card_update_policy ON person_card FOR UPDATE TO employee
    USING (true) WITH CHECK (true);
CREATE POLICY person_card_delete_policy ON person_card FOR DELETE TO employee
    USING (employee_id IS NULL);

ALTER TABLE person_card_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY person_card_event_select_policy ON person_card_event FOR SELECT USING (true);
CREATE POLICY person_card_event_insert_policy ON person_card_event FOR INSERT TO employee
    WITH CHECK (true);

COMMIT;
