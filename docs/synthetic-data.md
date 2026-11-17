# Synthetic data

Made-up data for local development, and later for the CDP `dev` and `test`
environments. Every service that stores data keeps its synthetic data the same
way, so it can be generated, loaded, found and removed the same way everywhere.

Synthetic data is never real APHA or WOAH data, and must never be loaded into
production. The seed scripts refuse to run when `ENVIRONMENT=prod`.

## What exists

All of it covers the same six months, 2026-05-08 to 2026-11-08.

| Service                       | Dataset           | Goes to                          | Contents                                                           |
| ----------------------------- | ----------------- | -------------------------------- | ------------------------------------------------------------------ |
| `apha-risk-insights-backend`  | `disease-risks`   | MongoDB `disease_risks`          | 5 diseases, 93 risk assessments, one every week or two per disease |
| `apha-risk-insights-backend`  | `wahis-outbreaks` | MongoDB `wahis_outbreaks`        | 164 outbreak records, copied from the ingestion service's          |
| `apha-insights-ingestion`     | `wahis-raw`       | S3 `raw/wahis/`                  | 63 events, 113 reports, 164 outbreaks, as a daily poll stores them |
| `apha-insights-ingestion`     | `wahis-outbreaks` | S3 `transformed/wahis-outbreak/` | 164 outbreak records, made by the real transform from `wahis-raw`  |
| `apha-risk-insights-frontend` | none              |                                  | Stores no data of its own. See [Gaps](#gaps)                       |

The counts are for the default seed. Each service writes the exact counts to
`synthetic-data/manifest.json` when it generates.

## Layout

Every service with synthetic data has the same folder at its root:

```
synthetic-data/
├── README.md        what the datasets are and how they are made up
├── generate.js      npm run synthetic:generate
├── seed.sh          npm run synthetic:seed / synthetic:clear
├── lib/             generator code. random.js, output.js and
│                    load-mongo.mongosh.js are the same in every repo
├── manifest.json    generated: datasets, counts, period, markers
└── data/            generated
    ├── mongo/<collection>.json    Extended JSON: { _comment, documents: [] }
    └── s3/<object key>            one file per object, at its S3 key
```

## Nothing generated is committed

Only the generator is in git. `data/` and `manifest.json` are git ignored in
every repo, and `synthetic:seed` generates them before loading. Generation is
seeded, so the same `--anchor`, `--months` and `--seed` always give the same
records, on any machine.

The tests need no committed data either: they build the data in memory and
check that it passes the service's schema, is marked as synthetic, covers six
months, and comes out the same twice. The only committed test data is what
the services had before: the ingestion service's real WAHIS `fixtures/`, and
the backend's small hand-written mocks in `test/mocks/`.

Generating needs Node.js. The ingestion generator runs the service's real
transform, so it also needs that repo's dependencies: with `npm install` run,
it uses node; otherwise it runs in the service's development image, which
`npm run setup` builds. The backend generator needs only node, and falls back
to its development image too.

## Commands

The same in every service:

| Command                                   | What it does                                                      |
| ----------------------------------------- | ----------------------------------------------------------------- |
| `npm run synthetic:generate`              | Writes `data/` and `manifest.json`                                |
| `npm run synthetic:seed`                  | Generates, then loads, replacing any synthetic data already there |
| `npm run synthetic:clear`                 | Removes the synthetic data, and nothing else                      |
| `npm run synthetic:seed -- --only X`      | Loads one dataset, by its name in the manifest                    |
| `npm run synthetic:seed -- --no-generate` | Loads `data/` as it is, without generating                        |

From this repo, with the stack running:

```bash
npm run seed                     # the real WAHIS sample and its transform,
                                 # then every service's synthetic:seed
npm run seed -- --synthetic-only # synthetic data only
npm run seed:clear               # every service's synthetic:clear
```

Use `--synthetic-only` for demos and user research, so nobody mistakes
made-up data for real. The real sample sits inside the synthetic period
(October 2026), so with both loaded a chart can show real and made-up
outbreaks side by side. The real fixtures stay in the ingestion repo as the
reference for what WAHIS returns, and its tests run on them.

`seed` loads the real sample first. The transform reads every raw outbreak in
the bucket, synthetic ones included, so the synthetic step runs after it and
replaces the synthetic records it wrote. It also seeds the ingestion service
before the backend, because the backend copies its outbreak records from the
data ingestion generates. A backend seeded on its own, without that data,
loads disease risks only and says so.

To move the period, pass `--anchor YYYY-MM-DD` (the last day) to
`synthetic:generate`, in `apha-insights-ingestion` first, then in
`apha-risk-insights-backend`.

## How synthetic records are marked

A record must be recognisable on its own, wherever it ends up. The schemas
reject unknown fields, so the markers use fields the schemas already have.

| Where                            | Marker                                                                                     |
| -------------------------------- | ------------------------------------------------------------------------------------------ |
| Every repo                       | Lives under `synthetic-data/`. `manifest.json` has `"synthetic": true`                     |
| Every data file                  | A top-level notice: `_comment` (MongoDB files) or `_synthetic` (raw WAHIS files)           |
| `disease_risks` documents        | `_id` starts with `00000000-0000-4000-a000-`. Every `source` starts with `SYNTHETIC: `     |
| WAHIS events, reports, outbreaks | Every id is `9000000` or above (real ids are far lower)                                    |
| WAHIS outbreak records           | `nationalReference` starts with `SYNTHETIC-`. The description starts with `SYNTHETIC DATA` |
| `wahis_outbreaks` documents      | As above, and `_id` starts with 16 zeros                                                   |
| S3 objects                       | User metadata `synthetic=true`                                                             |

`synthetic:clear` uses the id markers, so it only ever removes synthetic
records. The `source` marker will also show in the frontend, next to each
assessment, once it reads the backend API.

Synthetic WAHIS fetch dates all fall before 2026-11-09, the first real WAHIS
fetch, so a synthetic `raw/wahis/{date}/` folder never shares a date with real
data. Keep that true if you move the period.

## Loading into CDP dev or test

Not decided yet. The seed scripts can point at a real MongoDB or S3 bucket
(see `synthetic-data/seed.sh --help` in each service), but how to run them
against a CDP environment has not been worked out.

## Gaps

- **Frontend.** It reads `src/data/risk-sample-data.json`, a small hand-written
  sample (five diseases, two or three assessments each), not the backend API.
  Its tests fix that file's shape. Once it reads the API it will show the
  backend's synthetic data.
- **Backend `wahis_outbreaks`.** The API does not create or read this
  collection yet. The name follows `disease_risks`; change it in the backend's
  `synthetic-data/generate.js` if the loader settles on another.
- **Backend IDM report PDFs** (`npm run ingest:risk-pdf`) and the
  `ingestion-logs` collection have no synthetic data.
- **Diseases other than HPAI** have no WAHIS data. The transform only covers
  HPAI.

## Adding synthetic data to a service

1. Copy `synthetic-data/lib/random.js` and `output.js` from an existing
   service, and `load-mongo.mongosh.js` if the data goes to MongoDB
2. Write `generate.js` exporting `buildDataset()`, which returns the files and
   a manifest in the same shape as the existing ones
3. Give every record a marker that fits its schema and that `seed.sh --clear`
   can match, and add it to the table above
4. Write a `seed.sh` that generates first, with `--clear`, `--only` and
   `--no-generate`, and add the three `synthetic:*` npm scripts
5. Add a test like `test/integration/synthetic-data/` in the others, building
   the data in memory
6. Git ignore `synthetic-data/data/` and `synthetic-data/manifest.json`, and
   list both in `.prettierignore`
