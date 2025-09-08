-- Deploy floq:add_view_available_projects to pg

BEGIN;

CREATE VIEW available_projects AS
SELECT
    p.id,
    p.name,
    p.billable,
    p.active,
    json_build_object(
        'id', c.id,
        'name', c.name
    ) AS customer
FROM projects p
LEFT JOIN customers c ON p.customer = c.id
WHERE p.active = TRUE
AND NOT EXISTS (
    SELECT 1 FROM absence_reasons ar WHERE ar.id = p.id
);

GRANT SELECT ON available_projects TO employee;
GRANT SELECT ON available_projects TO read_only;
GRANT SELECT ON available_projects TO trak_read_only;

COMMIT;
