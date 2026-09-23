BEGIN;

UPDATE person_track t
SET sort_order = o.sort_order
FROM (VALUES
    ('nyutdannede',        10),
    ('onsker_utrullering', 20),
    ('blir_ledig',         30),
    ('ledig_na',           40),
    ('tilbud_sendt',       50),
    ('intervju',           60),
    ('signert_avtale',     70),
    ('i_arbeid',           80)
) AS o (slug, sort_order)
WHERE t.slug = o.slug;

COMMIT;
