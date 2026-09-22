BEGIN;

DROP TABLE person_card_event;
DROP TABLE person_card;
DROP TABLE person_track;

DROP FUNCTION set_person_card_event_author();
DROP FUNCTION log_person_card_deleted();
DROP FUNCTION log_person_card_field_change();
DROP FUNCTION log_person_card_track_change();
DROP FUNCTION log_person_card_created();
DROP FUNCTION set_person_card_track_since();
DROP FUNCTION set_person_card_author();

COMMIT;
