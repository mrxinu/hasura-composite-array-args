ALTER TABLE mountains DROP COLUMN IF EXISTS owner;

CREATE OR REPLACE FUNCTION summarize_mountains_json(mountains_input jsonb)
RETURNS SETOF mountains
LANGUAGE sql STABLE AS $$
  SELECT m.*
  FROM jsonb_to_recordset(mountains_input)
    AS m(id int, name text, elevation_m int, first_summited int)
  WHERE m.elevation_m > 6000;
$$;

DROP FUNCTION IF EXISTS validate_mountains_input(jsonb);
