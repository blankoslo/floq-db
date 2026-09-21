-- Verify floq:add_sales_case_attachments on pg

BEGIN;

DO
$$
BEGIN
    IF (SELECT COUNT(*) FROM sales_event_kind WHERE slug IN ('attachment_added', 'attachment_removed')) <> 2 THEN
        RAISE EXCEPTION 'the attachment event kinds are missing';
    END IF;

    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'sales_case_attachment'
    ) <> ARRAY['byte_size', 'case_id', 'content_type', 'filename', 'format', 'id', 'public_id',
               'resource_type', 'uploaded_at', 'uploaded_by'] THEN
        RAISE EXCEPTION 'sales_case_attachment columns do not match the expected contract';
    END IF;

    -- One row per Cloudinary object, so the same upload recorded twice is refused
    -- rather than delivered twice.
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_case_attachment'::regclass
          AND conname = 'sales_case_attachment_public_id_key'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION 'public_id is not unique';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_case_attachment'::regclass
          AND contype = 'f'
          AND confrelid = 'sales_case'::regclass
          AND confdeltype = 'c'
    ) THEN
        RAISE EXCEPTION 'attachments do not follow their case';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_trigger
        WHERE NOT tgisinternal
          AND tgrelid = 'sales_case_attachment'::regclass
    ) <> 3 THEN
        RAISE EXCEPTION 'the attachment triggers are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class
        WHERE oid = 'sales_case_attachment'::regclass AND relrowsecurity
    ) THEN
        RAISE EXCEPTION 'row-level security is not enabled on sales_case_attachment';
    END IF;

    -- The uploader or an admin, and nobody else — stricter than the card, which
    -- any employee may edit.
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'sales_case_attachment'
          AND policyname = 'sales_case_attachment_delete_policy'
          AND cmd = 'DELETE'
          AND roles = ARRAY['employee']::name[]
          AND qual LIKE '%logged_in_employee_id()%'
          AND qual LIKE '%check_admin_write_access()%'
    ) THEN
        RAISE EXCEPTION 'the attachment delete policy does not match the expected contract';
    END IF;

    IF NOT has_table_privilege('employee', 'sales_case_attachment', 'SELECT')
       OR NOT has_table_privilege('employee', 'sales_case_attachment', 'INSERT')
       OR NOT has_table_privilege('employee', 'sales_case_attachment', 'DELETE')
       OR has_table_privilege('employee', 'sales_case_attachment', 'UPDATE')
       OR NOT has_table_privilege('read_only', 'sales_case_attachment', 'SELECT') THEN
        RAISE EXCEPTION 'attachment grants do not match the expected contract';
    END IF;
END;
$$;

ROLLBACK;
