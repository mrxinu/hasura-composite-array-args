CREATE TABLE mountains (
  id              serial PRIMARY KEY,
  name            text    NOT NULL,
  elevation_m     int     NOT NULL,
  first_summited  int     NOT NULL
);

INSERT INTO mountains (name, elevation_m, first_summited) VALUES
  ('K2',         8611, 1954),
  ('Denali',     6190, 1913),
  ('Mont Blanc', 4809, 1786);

-- The interesting bit: argument is a strongly-typed array of the `mountains`
-- row type. Inside the function body, (m).name / (m).elevation_m / etc are
-- real Postgres columns with real types.
CREATE FUNCTION summarize_mountains(mountains_input mountains[])
RETURNS SETOF mountains
LANGUAGE sql STABLE AS $$
  SELECT (m).*
  FROM unnest(mountains_input) AS m
  WHERE (m).elevation_m > 6000;
$$;
