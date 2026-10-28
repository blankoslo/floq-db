-- Deploy floq:add_ledger_expenses to pg
-- requires: employees_table
-- requires: add_employee_user
-- requires: add_read_only_user
-- requires: change_jwt_claim_retrieval
-- requires: add_sales_pipeline
-- add_sales_pipeline only for logged_in_employee_id(); no sales table is used.

BEGIN;

-- For uuid_generate_v4(). Earlier changes already create it, so revert leaves it be.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Utlegg from the ledger app. `expense` and `expense_type` are already taken by the
-- project balance, hence the prefix. Keys match the app's: tech, fagutvikling, sosialt.
CREATE TYPE ledger_expense_type AS ENUM ('tech', 'fagutvikling', 'sosialt');

-- What every type has. Each type's own fields live in a table of its own, joined 1:1.
CREATE TABLE ledger_expense (
    id                   TEXT                CONSTRAINT ledger_expense_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    type                 ledger_expense_type NOT NULL,
    date                 DATE                NOT NULL,
    description          TEXT                NOT NULL,
    -- Who is reimbursed: "Hvem kjøpte det?" on tech, "Hvem betalte?" on the others.
    paid_by              INTEGER             NOT NULL REFERENCES employees (id),
    comment              TEXT,
    charge_to_project    BOOLEAN             NOT NULL DEFAULT FALSE,
    tripletex_expense_id BIGINT              CONSTRAINT ledger_expense_tripletex_expense_id_key UNIQUE,
    created_by           INTEGER             REFERENCES employees (id),
    created_at           TIMESTAMPTZ         NOT NULL DEFAULT now(),

    -- The target of each type table's foreign key, so a row can only hang off an
    -- expense of its own type.
    CONSTRAINT ledger_expense_id_type_key UNIQUE (id, type)
);

CREATE INDEX ledger_expense_paid_by_idx ON ledger_expense (paid_by, date DESC);
CREATE INDEX ledger_expense_type_date_idx ON ledger_expense (type, date DESC);

CREATE TABLE ledger_tech_expense (
    expense_id    TEXT                CONSTRAINT ledger_tech_expense_pkey PRIMARY KEY,
    type          ledger_expense_type NOT NULL DEFAULT 'tech'
                                      CONSTRAINT ledger_tech_expense_is_tech CHECK (type = 'tech'),
    category      TEXT                NOT NULL,
    amount        NUMERIC(12, 2)      NOT NULL CONSTRAINT ledger_tech_expense_amount_positive CHECK (amount > 0),
    -- Null when it was bought for Blank rather than for one person.
    purchased_for INTEGER             REFERENCES employees (id),

    CONSTRAINT ledger_tech_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE
);

CREATE INDEX ledger_tech_expense_purchased_for_idx ON ledger_tech_expense (purchased_for);

CREATE TABLE ledger_social_expense (
    expense_id        TEXT                CONSTRAINT ledger_social_expense_pkey PRIMARY KEY,
    type              ledger_expense_type NOT NULL DEFAULT 'sosialt'
                                          CONSTRAINT ledger_social_expense_is_sosialt CHECK (type = 'sosialt'),
    category          TEXT                NOT NULL,
    amount            NUMERIC(12, 2)      NOT NULL CONSTRAINT ledger_social_expense_amount_positive CHECK (amount > 0),
    participant_count INTEGER             NOT NULL
                                          CONSTRAINT ledger_social_expense_has_participants CHECK (participant_count > 0),

    CONSTRAINT ledger_social_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE
);

CREATE TABLE ledger_fagutvikling_expense (
    expense_id TEXT                CONSTRAINT ledger_fagutvikling_expense_pkey PRIMARY KEY,
    type       ledger_expense_type NOT NULL DEFAULT 'fagutvikling'
                                   CONSTRAINT ledger_fagutvikling_expense_is_fagutvikling CHECK (type = 'fagutvikling'),
    location   TEXT                NOT NULL,
    sharing    TEXT                NOT NULL,

    CONSTRAINT ledger_fagutvikling_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE
);

-- One expense may cover several people. Each one's costs count toward their own
-- totals, while paid_by on the expense is reimbursed for all of them.
CREATE TABLE ledger_fagutvikling_participant (
    expense_id    TEXT           NOT NULL REFERENCES ledger_fagutvikling_expense (expense_id) ON DELETE CASCADE,
    employee_id   INTEGER        NOT NULL REFERENCES employees (id),
    role          TEXT           NOT NULL,
    days          NUMERIC(5, 2)  NOT NULL CONSTRAINT ledger_fagutvikling_participant_days_positive CHECK (days > 0),
    ticket        NUMERIC(12, 2) NOT NULL CONSTRAINT ledger_fagutvikling_participant_ticket_not_negative CHECK (ticket >= 0),
    travel        NUMERIC(12, 2) NOT NULL CONSTRAINT ledger_fagutvikling_participant_travel_not_negative CHECK (travel >= 0),
    accommodation NUMERIC(12, 2) NOT NULL
                                 CONSTRAINT ledger_fagutvikling_participant_accommodation_not_negative CHECK (accommodation >= 0),

    CONSTRAINT ledger_fagutvikling_participant_pkey PRIMARY KEY (expense_id, employee_id)
);

CREATE INDEX ledger_fagutvikling_participant_employee_idx ON ledger_fagutvikling_participant (employee_id);

-- A form saved before it validates, so it keeps the raw input rather than typed
-- columns. Registering it writes the rows above and deletes this one.
CREATE TABLE ledger_expense_draft (
    id          TEXT                CONSTRAINT ledger_expense_draft_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    type        ledger_expense_type NOT NULL,
    owner_id    INTEGER             NOT NULL REFERENCES employees (id),
    form_values JSONB               NOT NULL DEFAULT '{}'::jsonb,
    saved_at    TIMESTAMPTZ         NOT NULL DEFAULT now()
);

CREATE INDEX ledger_expense_draft_owner_idx ON ledger_expense_draft (owner_id, saved_at DESC);

-- The bytes live in Cloudinary, as for sales_case_attachment. A receipt belongs to a
-- draft or to an expense; registering a draft moves its receipts over before the
-- draft is deleted, which would otherwise take them with it.
CREATE TABLE ledger_receipt (
    id            TEXT        CONSTRAINT ledger_receipt_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    expense_id    TEXT        REFERENCES ledger_expense (id) ON DELETE CASCADE,
    draft_id      TEXT        REFERENCES ledger_expense_draft (id) ON DELETE CASCADE,
    filename      TEXT        NOT NULL,
    content_type  TEXT,
    byte_size     BIGINT      CONSTRAINT ledger_receipt_has_bytes CHECK (byte_size IS NULL OR byte_size > 0),

    public_id     TEXT        NOT NULL CONSTRAINT ledger_receipt_public_id_key UNIQUE,
    resource_type TEXT        NOT NULL,
    format        TEXT,

    created_by    INTEGER     REFERENCES employees (id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT ledger_receipt_has_one_owner CHECK (num_nonnulls(expense_id, draft_id) = 1)
);

CREATE INDEX ledger_receipt_expense_idx ON ledger_receipt (expense_id);
CREATE INDEX ledger_receipt_draft_idx ON ledger_receipt (draft_id);

CREATE FUNCTION set_ledger_created_by()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.created_by = logged_in_employee_id();
    RETURN NEW;
END;
$$;

CREATE TRIGGER ledger_expense_created_by
    BEFORE INSERT ON ledger_expense
    FOR EACH ROW
    EXECUTE FUNCTION set_ledger_created_by();

CREATE TRIGGER ledger_receipt_created_by
    BEFORE INSERT ON ledger_receipt
    FOR EACH ROW
    EXECUTE FUNCTION set_ledger_created_by();

-- An expense is seen by whoever paid or registered it, whoever it was bought for or
-- took part, and an admin. SECURITY DEFINER because the type tables' policies ask
-- this too, and reading them back under their own policies would recurse.
CREATE FUNCTION ledger_expense_visible(expense TEXT)
    RETURNS BOOLEAN
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public
AS
$$
SELECT check_admin_write_access()
    OR EXISTS (SELECT 1 FROM ledger_expense e
               WHERE e.id = expense AND logged_in_employee_id() IN (e.paid_by, e.created_by))
    OR EXISTS (SELECT 1 FROM ledger_tech_expense t
               WHERE t.expense_id = expense AND t.purchased_for = logged_in_employee_id())
    OR EXISTS (SELECT 1 FROM ledger_fagutvikling_participant p
               WHERE p.expense_id = expense AND p.employee_id = logged_in_employee_id());
$$;

-- Whoever paid or registered it may change it until it has gone to Tripletex, after
-- which only an admin may.
CREATE FUNCTION ledger_expense_editable(expense TEXT)
    RETURNS BOOLEAN
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public
AS
$$
SELECT check_admin_write_access()
    OR EXISTS (SELECT 1 FROM ledger_expense e
               WHERE e.id = expense
                 AND e.tripletex_expense_id IS NULL
                 AND logged_in_employee_id() IN (e.paid_by, e.created_by));
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_expense TO employee;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_tech_expense TO employee;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_social_expense TO employee;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_fagutvikling_expense TO employee;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_fagutvikling_participant TO employee;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_expense_draft TO employee;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_receipt TO employee;

-- Drafts are left out: they are someone's unfinished form, not the books.
GRANT SELECT ON TABLE ledger_expense TO read_only;
GRANT SELECT ON TABLE ledger_tech_expense TO read_only;
GRANT SELECT ON TABLE ledger_social_expense TO read_only;
GRANT SELECT ON TABLE ledger_fagutvikling_expense TO read_only;
GRANT SELECT ON TABLE ledger_fagutvikling_participant TO read_only;
GRANT SELECT ON TABLE ledger_receipt TO read_only;

-- The policies on ledger_expense read its own columns rather than call the functions
-- above: those see the table as it was when the statement began, so they would miss
-- the row an INSERT ... RETURNING is handing back, and check an UPDATE's old values
-- rather than its new ones.
ALTER TABLE ledger_expense ENABLE ROW LEVEL SECURITY;
CREATE POLICY ledger_expense_select_policy ON ledger_expense FOR SELECT TO employee
    USING (check_admin_write_access()
           OR logged_in_employee_id() IN (paid_by, created_by)
           OR ledger_expense_visible(id));
-- Anyone may register an expense, including one somebody else paid for.
CREATE POLICY ledger_expense_insert_policy ON ledger_expense FOR INSERT TO employee
    WITH CHECK (true);
CREATE POLICY ledger_expense_update_policy ON ledger_expense FOR UPDATE TO employee
    USING (check_admin_write_access()
           OR (tripletex_expense_id IS NULL AND logged_in_employee_id() IN (paid_by, created_by)))
    WITH CHECK (check_admin_write_access() OR logged_in_employee_id() IN (paid_by, created_by));
CREATE POLICY ledger_expense_delete_policy ON ledger_expense FOR DELETE TO employee
    USING (check_admin_write_access()
           OR (tripletex_expense_id IS NULL AND logged_in_employee_id() IN (paid_by, created_by)));
CREATE POLICY ledger_expense_read_only_policy ON ledger_expense FOR SELECT TO read_only USING (true);

ALTER TABLE ledger_tech_expense ENABLE ROW LEVEL SECURITY;
CREATE POLICY ledger_tech_expense_select_policy ON ledger_tech_expense FOR SELECT TO employee
    USING (ledger_expense_visible(expense_id));
CREATE POLICY ledger_tech_expense_write_policy ON ledger_tech_expense FOR ALL TO employee
    USING (ledger_expense_editable(expense_id)) WITH CHECK (ledger_expense_editable(expense_id));
CREATE POLICY ledger_tech_expense_read_only_policy ON ledger_tech_expense FOR SELECT TO read_only USING (true);

ALTER TABLE ledger_social_expense ENABLE ROW LEVEL SECURITY;
CREATE POLICY ledger_social_expense_select_policy ON ledger_social_expense FOR SELECT TO employee
    USING (ledger_expense_visible(expense_id));
CREATE POLICY ledger_social_expense_write_policy ON ledger_social_expense FOR ALL TO employee
    USING (ledger_expense_editable(expense_id)) WITH CHECK (ledger_expense_editable(expense_id));
CREATE POLICY ledger_social_expense_read_only_policy ON ledger_social_expense FOR SELECT TO read_only USING (true);

ALTER TABLE ledger_fagutvikling_expense ENABLE ROW LEVEL SECURITY;
CREATE POLICY ledger_fagutvikling_expense_select_policy ON ledger_fagutvikling_expense FOR SELECT TO employee
    USING (ledger_expense_visible(expense_id));
CREATE POLICY ledger_fagutvikling_expense_write_policy ON ledger_fagutvikling_expense FOR ALL TO employee
    USING (ledger_expense_editable(expense_id)) WITH CHECK (ledger_expense_editable(expense_id));
CREATE POLICY ledger_fagutvikling_expense_read_only_policy ON ledger_fagutvikling_expense
    FOR SELECT TO read_only USING (true);

ALTER TABLE ledger_fagutvikling_participant ENABLE ROW LEVEL SECURITY;
CREATE POLICY ledger_fagutvikling_participant_select_policy ON ledger_fagutvikling_participant
    FOR SELECT TO employee USING (ledger_expense_visible(expense_id));
CREATE POLICY ledger_fagutvikling_participant_write_policy ON ledger_fagutvikling_participant
    FOR ALL TO employee
    USING (ledger_expense_editable(expense_id)) WITH CHECK (ledger_expense_editable(expense_id));
CREATE POLICY ledger_fagutvikling_participant_read_only_policy ON ledger_fagutvikling_participant
    FOR SELECT TO read_only USING (true);

-- Only the owner, admins included: a draft is not anybody else's business yet.
ALTER TABLE ledger_expense_draft ENABLE ROW LEVEL SECURITY;
CREATE POLICY ledger_expense_draft_owner_policy ON ledger_expense_draft FOR ALL TO employee
    USING (owner_id = logged_in_employee_id()) WITH CHECK (owner_id = logged_in_employee_id());

-- A draft's receipts follow the draft's own policy, through the subquery.
ALTER TABLE ledger_receipt ENABLE ROW LEVEL SECURITY;
CREATE POLICY ledger_receipt_select_policy ON ledger_receipt FOR SELECT TO employee
    USING (CASE
               WHEN expense_id IS NOT NULL THEN ledger_expense_visible(expense_id)
               ELSE EXISTS (SELECT 1 FROM ledger_expense_draft d WHERE d.id = draft_id)
           END);
CREATE POLICY ledger_receipt_write_policy ON ledger_receipt FOR ALL TO employee
    USING (CASE
               WHEN expense_id IS NOT NULL THEN ledger_expense_editable(expense_id)
               ELSE EXISTS (SELECT 1 FROM ledger_expense_draft d WHERE d.id = draft_id)
           END)
    WITH CHECK (CASE
                    WHEN expense_id IS NOT NULL THEN ledger_expense_editable(expense_id)
                    ELSE EXISTS (SELECT 1 FROM ledger_expense_draft d WHERE d.id = draft_id)
                END);
CREATE POLICY ledger_receipt_read_only_policy ON ledger_receipt FOR SELECT TO read_only USING (true);

COMMIT;
