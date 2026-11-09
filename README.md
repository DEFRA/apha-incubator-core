# apha-incubator-core

Developer toolkit for running the APHA Risk Insights microservices together locally.

It clones the service repos, keeps them up to date, and runs them all together.
Services share one docker network (`apha-risk`) and one AWS emulator (floci).
Every other piece of infrastructure, like a database or cache, belongs to a
single service.

| Service                                                                              | URL                                     |
| ------------------------------------------------------------------------------------ | --------------------------------------- |
| [apha-risk-insights-frontend](https://github.com/DEFRA/apha-risk-insights-frontend) | http://localhost:3000                   |
| [apha-risk-insights-backend](https://github.com/DEFRA/apha-risk-insights-backend)   | http://localhost:3001 (docs at `/documentation`) |

| Infrastructure                       | Address from your machine | Owned by |
| ------------------------------------ | ------------------------- | -------- |
| `apha-risk-insights-backend-mongodb` | mongodb://localhost:27017 | backend  |
| `apha-risk-insights-frontend-redis`  | localhost:6379            | frontend |
| `floci` (AWS emulator)               | http://localhost:4566     | shared   |

## Prerequisites

- [Docker Desktop](https://docs.docker.com/get-docker/) with compose v2
- git, with SSH access to GitHub (or set `GIT_PROTOCOL=https` in `.env`)
- Node and npm, version in `.nvmrc` (run `nvm use`). npm only runs the toolkit
  scripts: service dependencies are installed inside the docker images

## Getting started

```bash
git clone git@github.com:DEFRA/apha-incubator-core.git
cd apha-incubator-core
npm run setup
npm start
```

Services are cloned next to this repo by default:

```
repos/
├── apha-incubator-core/
├── apha-risk-insights-backend/
└── apha-risk-insights-frontend/
```

Change this with `SERVICES_DIR` in `.env` (see `.env.example`).

## Commands

Run `npm run` to list commands. Each one runs a script in `./scripts`. Pass extra
arguments after `--`, e.g. `npm run logs -- apha-risk-insights-backend`. Every
script supports `--help`, e.g. `npm start -- --help`.

| Command                    | What it does                                                                   |
| -------------------------- | ------------------------------------------------------------------------------ |
| `npm run setup`            | Checks prerequisites, clones every service, builds images                      |
| `npm run update`           | Pulls `main` for every service, then rebuilds images                           |
| `npm run update:no-build`  | Pulls `main` for every service without rebuilding                              |
| `npm start`                | Starts everything and waits for each `/health` to respond                      |
| `npm run start:build`      | Rebuilds images, then starts everything                                        |
| `npm run start:logs`       | Starts everything, then follows logs                                           |
| `npm run start:debug`      | Starts node with `--inspect-brk`. Attach to 9229 (backend) or 9230 (frontend)  |
| `npm run stop`             | Stops everything                                                               |
| `npm run stop:clean`       | Stops everything and deletes volumes (wipes local MongoDB data)                |
| `npm run restart`          | Stops then starts everything                                                   |
| `npm run status`           | Branch, uncommitted changes and ahead/behind for each repo, plus running containers |
| `npm run logs [-- service...]` | Follows logs for every service, or the ones named                          |
| `npm test [-- service...]` | Runs each service's dockerised tests (same as its `npm run docker:test`)       |

`update` only pulls repos that are on `main` with no uncommitted changes. Other
repos are fetched and left alone, so it never touches work in progress.

Source code is mounted into the containers, so edits to `src/` reload
automatically. After changing a service's `package.json`, rebuild with
`npm run start:build`.

## How it works

`compose.yaml` extends each service from its own repo's `compose.yaml`, so each
service keeps owning its image, mounts and environment.

### Networks

```
                 apha-risk (shared)
   ┌──────────────────┬──────────────────┬──────────┐
   │                  │                  │          │
 backend           frontend           (next)      floci
   │                  │
   │ backend-internal │ frontend-internal
   │                  │
 backend-mongodb   frontend-redis
 (alias: mongodb)  (alias: redis)
```

- **`apha-risk` is shared.** Only the services and floci join it, so services
  can call each other by name, e.g. `http://apha-risk-insights-backend:3001`.
- **Each service has a private network** (`<service>-internal`) for the
  infrastructure it owns. Infra containers are named `<service>-<infra>`, and on
  that private network only they also answer to the hostname the service
  already uses (`mongodb`, `redis`). Service code and config don't change, two
  services can each own a `mongodb` without clashing, and no service can reach
  another's database.
- **Volumes are named after their owner** too, e.g.
  `apha-risk-insights-backend-mongodb-data`.

### floci

Each service repo defines its own floci, so running two service stacks side by
side gives two containers answering to `floci` on the same network. Here there
is one, and `compose/floci/start.d/00-run-service-scripts.sh` runs every
service's floci init scripts against it. `AWS_ENDPOINT_URL` points at
`http://floci:4566`, which containers can reach, rather than `localhost`.

`start.sh` refuses to start if a service is already running from its own repo
(for example via `npm run docker:up`), because its containers would clash on
the shared network. Stop that stack first with `npm run docker:stop` in the
service repo.

## Adding a service

1. Add it to `SERVICES` in `scripts/lib.sh`
2. Add it and its infrastructure to `compose.yaml`, following the existing
   services. For a new backend with its own MongoDB:

   ```yaml
   apha-risk-insights-reports:
     extends:
       file: ${SERVICES_DIR:-..}/apha-risk-insights-reports/compose.yaml
       service: apha-risk-insights-reports
     links: !reset []
     depends_on: !override
       floci:
         condition: service_healthy
       apha-risk-insights-reports-mongodb:
         condition: service_healthy
     environment:
       <<: *aws-local
     networks:
       - apha-risk
       - apha-risk-insights-reports
     ports:
       - '3002:3002'
       - '9231:9229'

   apha-risk-insights-reports-mongodb:
     extends:
       file: ${SERVICES_DIR:-..}/apha-risk-insights-reports/compose.yaml
       service: mongodb
     volumes:
       - apha-risk-insights-reports-mongodb-data:/data
     networks: !override
       apha-risk-insights-reports:
         aliases: [mongodb]
     ports:
       - '27018:27017'
   ```

   Then add the volume and network:

   ```yaml
   volumes:
     apha-risk-insights-reports-mongodb-data:

   networks:
     apha-risk-insights-reports:
       name: apha-risk-insights-reports-internal
   ```

   Every host port must be unique: the next MongoDB gets `27018`, the next Redis
   `6380`, and so on.
3. If it has floci init scripts, mount its `compose/floci/start.d` into floci
   under `/etc/floci/init/services/<service>`
4. Add a health check to `start.sh` and rows to the tables above
