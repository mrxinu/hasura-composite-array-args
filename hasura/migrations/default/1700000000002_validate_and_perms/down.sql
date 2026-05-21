ALTER TABLE parks DROP COLUMN IF EXISTS owner;

CREATE OR REPLACE FUNCTION summarize_parks_json(parks_input jsonb)
RETURNS SETOF parks
LANGUAGE sql STABLE AS $$
  SELECT p.*
  FROM jsonb_to_recordset(parks_input)
    AS p(id int, name text, acreage numeric, founded_in int)
  WHERE p.acreage > 200000;
$$;

DROP FUNCTION IF EXISTS validate_parks_input(jsonb);
