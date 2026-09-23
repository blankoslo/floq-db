BEGIN;

DO
$$
BEGIN
    IF (
        SELECT array_agg(slug ORDER BY sort_order)
        FROM person_track
        WHERE slug IN ('nyutdannede', 'onsker_utrullering', 'blir_ledig', 'ledig_na',
                       'tilbud_sendt', 'intervju', 'signert_avtale', 'i_arbeid')
    ) <> ARRAY['nyutdannede', 'onsker_utrullering', 'blir_ledig', 'ledig_na',
               'tilbud_sendt', 'intervju', 'signert_avtale', 'i_arbeid'] THEN
        RAISE EXCEPTION 'the person tracks are not in the new order';
    END IF;

    IF (SELECT array_agg(slug) FROM person_track WHERE is_default) <> ARRAY['i_arbeid'] THEN
        RAISE EXCEPTION 'i_arbeid is no longer the default track';
    END IF;
END;
$$;

ROLLBACK;
