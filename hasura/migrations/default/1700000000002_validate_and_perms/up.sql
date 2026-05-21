-- Validation helper: enforce that the jsonb input is shaped like mountains[].
-- This is what the composite-array variant gets "for free" from Postgres's
-- composite-type parsing — here we hand-roll it on top of jsonb.
CREATE FUNCTION validate_mountains_input(mountains_input jsonb)
RETURNS void
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  bad jsonb;
BEGIN
  IF jsonb_typeof(mountains_input) <> 'array' THEN
    RAISE EXCEPTION 'mountains_input must be a JSON array, got %', jsonb_typeof(mountains_input);
  END IF;

  -- Find any element that's missing a required field or has a wrong type.
  -- jsonb_typeof returns text labels ('string','number','null',etc).
  SELECT elem INTO bad
  FROM jsonb_array_elements(mountains_input) AS elem
  WHERE jsonb_typeof(elem) <> 'object'
     OR NOT (elem ? 'id' AND elem ? 'name' AND elem ? 'elevation_m' AND elem ? 'first_summited')
     OR jsonb_typeof(elem->'id')             NOT IN ('number')
     OR jsonb_typeof(elem->'name')           NOT IN ('string')
     OR jsonb_typeof(elem->'elevation_m')    NOT IN ('number')
     OR jsonb_typeof(elem->'first_summited') NOT IN ('number')
  LIMIT 1;

  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'mountains_input element fails schema check: %', bad
      USING HINT = 'each element must be {id:int, name:string, elevation_m:int, first_summited:int}';
  END IF;
END;
$$;

-- Wrap the existing jsonb variant with validation. Postgres allows two
-- functions with the same name as long as the signatures differ, but in
-- this case we want to replace summarize_mountains_json's behavior, so
-- CREATE OR REPLACE the existing definition.
CREATE OR REPLACE FUNCTION summarize_mountains_json(mountains_input jsonb)
RETURNS SETOF mountains
LANGUAGE plpgsql STABLE AS $$
BEGIN
  PERFORM validate_mountains_input(mountains_input);

  RETURN QUERY
    SELECT m.*
    FROM jsonb_to_recordset(mountains_input)
      AS m(id int, name text, elevation_m int, first_summited int)
    WHERE m.elevation_m > 6000;
END;
$$;

-- For the permissions demo: an `owner` column on the table, so a
-- non-admin role can see only its own rows. Backfill existing seed data
-- so the role we'll add (`alice`) sees K2 and the role `bob`
-- sees Denali and Mont Blanc.
ALTER TABLE mountains ADD COLUMN owner text NOT NULL DEFAULT 'alice';
UPDATE mountains SET owner = 'bob' WHERE name IN ('Denali', 'Mont Blanc');
