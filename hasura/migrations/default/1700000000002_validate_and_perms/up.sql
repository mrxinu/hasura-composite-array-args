-- Validation helper: enforce that the jsonb input is shaped like parks[].
-- This is what the composite-array variant gets "for free" from Postgres's
-- composite-type parsing — here we hand-roll it on top of jsonb.
CREATE FUNCTION validate_parks_input(parks_input jsonb)
RETURNS void
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  bad jsonb;
BEGIN
  IF jsonb_typeof(parks_input) <> 'array' THEN
    RAISE EXCEPTION 'parks_input must be a JSON array, got %', jsonb_typeof(parks_input);
  END IF;

  -- Find any element that's missing a required field or has a wrong type.
  -- jsonb_typeof returns text labels ('string','number','null',etc).
  SELECT elem INTO bad
  FROM jsonb_array_elements(parks_input) AS elem
  WHERE jsonb_typeof(elem) <> 'object'
     OR NOT (elem ? 'id' AND elem ? 'name' AND elem ? 'acreage' AND elem ? 'founded_in')
     OR jsonb_typeof(elem->'id')         NOT IN ('number')
     OR jsonb_typeof(elem->'name')       NOT IN ('string')
     OR jsonb_typeof(elem->'acreage')    NOT IN ('number')
     OR jsonb_typeof(elem->'founded_in') NOT IN ('number')
  LIMIT 1;

  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'parks_input element fails schema check: %', bad
      USING HINT = 'each element must be {id:int, name:string, acreage:number, founded_in:int}';
  END IF;
END;
$$;

-- Wrap the existing jsonb variant with validation. Postgres allows two
-- functions with the same name as long as the signatures differ, but in
-- this case we want to replace summarize_parks_json's behavior, so
-- CREATE OR REPLACE the existing definition.
CREATE OR REPLACE FUNCTION summarize_parks_json(parks_input jsonb)
RETURNS SETOF parks
LANGUAGE plpgsql STABLE AS $$
BEGIN
  PERFORM validate_parks_input(parks_input);

  RETURN QUERY
    SELECT p.*
    FROM jsonb_to_recordset(parks_input)
      AS p(id int, name text, acreage numeric, founded_in int)
    WHERE p.acreage > 200000;
END;
$$;

-- For the permissions demo: a `parks_owner` column on the table, so a
-- non-admin role can see only its own rows. Backfill existing seed data
-- so the role we'll add (`alice`) sees Yellowstone and the role `bob`
-- sees Yosemite and Crater Lake.
ALTER TABLE parks ADD COLUMN owner text NOT NULL DEFAULT 'alice';
UPDATE parks SET owner = 'bob' WHERE name IN ('Yosemite', 'Crater Lake');
