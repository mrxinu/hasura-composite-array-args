# Hasura custom function with a table-row-array argument

## TL;DR

**Yes — with one caveat.** Hasura *will* track a custom function whose argument
is an array of a table's row type (`mountains[]`) and the Postgres side is
fully strongly typed. But at the GraphQL boundary, Hasura exposes the
argument as a **custom scalar named after the Postgres array type** (here:
`_mountains`, Postgres's internal name for `mountains[]`). The client passes
the value as a Postgres array literal of composite literals — a single
opaque string — not as a structured GraphQL input object.

In short:

- **Strongly typed in SQL** — inside the function, `mountains_input` is a
  real `mountains[]` and `(m).name`, `(m).elevation_m`, etc. are real columns
  with real types. Pass the wrong number of fields or wrong types and
  Postgres rejects it.
- **Stringly typed at the edge** — at the GraphQL layer it's a single scalar
  with no per-field validation. Clients must hand-build a Postgres array
  literal.

The standing feature request to generate proper GraphQL input objects from
composite types is [hasura/graphql-engine#7078][7078], with related history
in [#3757][3757].

[7078]: https://github.com/hasura/graphql-engine/issues/7078
[3757]: https://github.com/hasura/graphql-engine/issues/3757

## What this repo proves

The setup is real and verified working against `hasura/graphql-engine:v2.40.0`.
End-to-end:

1. `mountains` table created and tracked.
2. `summarize_mountains(mountains_input mountains[]) RETURNS SETOF mountains`
   created and tracked.
3. Hasura exposes `mountains_input` as a custom scalar `_mountains`.
4. A GraphQL query passing three mountain rows as a Postgres array literal
   of composite literals returns the two whose elevation > 6000 m.

```graphql
query TallMountains($m: _mountains!) {
  summarize_mountains(args: { mountains_input: $m }) {
    id
    name
    elevation_m
    first_summited
  }
}
```

With variables:

```json
{
  "m": "{\"(1,K2,8611,1954)\",\"(2,Denali,6190,1913)\",\"(3,\\\"Mont Blanc\\\",4809,1786)\"}"
}
```

Response:

```json
{
  "data": {
    "summarize_mountains": [
      { "id": 1, "name": "K2",     "elevation_m": 8611, "first_summited": 1954 },
      { "id": 2, "name": "Denali", "elevation_m": 6190, "first_summited": 1913 }
    ]
  }
}
```

Mont Blanc (4,809 m) is correctly filtered out — the function got a real
`mountains[]` and the `WHERE (m).elevation_m > 6000` clause did its job.

## Run it yourself

```bash
docker compose up -d
# Wait ~15s for migrations to apply. Then either:
#   - open http://localhost:58080/console (admin secret: `toysecret`)
#   - or hit the GraphQL endpoint with the curl below
```

If a previous metadata reload is needed (the first boot can race the source
init), poke it:

```bash
curl -s -X POST http://localhost:58080/v1/metadata \
  -H 'X-Hasura-Admin-Secret: toysecret' \
  -H 'Content-Type: application/json' \
  -d '{"type":"reload_metadata","args":{"reload_sources":true}}'
```

Then run the query:

```bash
curl -s -X POST http://localhost:58080/v1/graphql \
  -H 'X-Hasura-Admin-Secret: toysecret' \
  -H 'Content-Type: application/json' \
  -d @example-request.json | python3 -m json.tool
```

(See `example-request.json` and `example-query.graphql` for the literal forms.)

Ports are remapped to avoid clashes with anything already bound on 5432/8080:

- Hasura console / GraphQL: <http://localhost:58080>
- Postgres: `localhost:55432` (user `postgres`, password `toypass`)

## The interesting files

- `hasura/migrations/default/1700000000000_init/up.sql` — table, seed data,
  and the `mountains[]`-taking function.
- `hasura/metadata/databases/default/tables/public_mountains.yaml` — tracks
  `mountains`.
- `hasura/metadata/databases/default/functions/public_summarize_mountains.yaml` —
  tracks `summarize_mountains`. Note there is **nothing special** in the
  metadata for the composite-array arg; Hasura figures it out from the
  Postgres signature.

## The composite-array literal, decoded

```
{"(1,K2,8611,1954)","(2,Denali,6190,1913)","(3,\"Mont Blanc\",4809,1786)"}
```

- Outer `{ ... }` — Postgres array literal.
- Each element is a composite (row) literal: `(col1,col2,col3,col4)`.
- Composite literals inside an array literal are double-quoted.
- Text values containing spaces or commas (`Mont Blanc`) need *another*
  layer of double-quoting inside the composite literal.
- All those double quotes then need to be backslash-escaped when the whole
  thing is embedded in a JSON string in the HTTP request.
- Column order must match the table's column order. Hasura/Postgres won't
  let you name columns at this layer — that's exactly the missing strong
  typing.

## When to use `jsonb` instead

If you don't strictly need Postgres-side type enforcement, take a `jsonb`
argument and `jsonb_to_recordset(...)` inside the function. Clients then
pass a normal JSON array of objects — no Postgres-literal escaping, no
positional-column trap. You lose Postgres-side type checking, but for most
GraphQL use cases that's the pragmatic call. Reach for the `table[]` form
when:

- The function is also called from elsewhere in SQL (triggers, other
  functions, `psql`) and you want Postgres to enforce the shape there too.
- You want Postgres to do constraint-style validation (NOT NULL, types)
  before your function body sees the rows.
