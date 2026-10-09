-- Deploy floq:allow_emoji_sequences_in_emoji_domain to pg
-- requires: alter_table_employees_add_emoji_column

BEGIN;

-- The old check took a single code point from 2018's blocks, which refused
-- flags, skin tones, ZWJ sequences, keycaps, ❤️ (❤ + U+FE0F) and every emoji
-- added since. Postgres regex has no \p{Emoji}, so this describes one emoji
-- by shape instead: a flag, a keycap, or a pictograph with its modifiers,
-- optionally joined to more by ZWJ. The base range is deliberately broad so
-- future emoji in those planes pass without another migration; it leaves out
-- the regional indicators so half a flag is refused.
ALTER DOMAIN emoji DROP CONSTRAINT emoji_check;

ALTER DOMAIN emoji ADD CONSTRAINT emoji_check CHECK (
  VALUE ~ (
    '^(?:'
    || '[\U0001F1E6-\U0001F1FF]{2}'
    || '|[0-9#*]️?⃣'
    || '|(?:[©®‼-㊙\U0001F000-\U0001F1E5\U0001F200-\U0001FAFF][️\U0001F3FB-\U0001F3FF\U000E0020-\U000E007F]*)'
    || '(?:‍[©®‼-㊙\U0001F000-\U0001F1E5\U0001F200-\U0001FAFF][️\U0001F3FB-\U0001F3FF\U000E0020-\U000E007F]*)*'
    || ')$'
  )
);

COMMIT;
