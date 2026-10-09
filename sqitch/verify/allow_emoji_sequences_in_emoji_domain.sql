-- Verify floq:allow_emoji_sequences_in_emoji_domain on pg

BEGIN;

SELECT '🇳🇴'::emoji, '👍🏽'::emoji, '❤️'::emoji, '🏳️‍🌈'::emoji, '1️⃣'::emoji, '🫠'::emoji;

ROLLBACK;
