# pglifecycle-action

GitHub Actions for [pglifecycle](https://github.com/gmr/pglifecycle), a
PostgreSQL schema management tool.

Two actions live here:

| Action | What it does |
| --- | --- |
| `gmr/pglifecycle-action@v1` | Installs pglifecycle and puts it on `PATH` |
| `gmr/pglifecycle-action/deploy@v1` | Runs `pglifecycle deploy`, publishes the plan, and can fail on drift |

## Setup

```yaml
- uses: gmr/pglifecycle-action@v1
  with:
    version: 2.0.0-alpha.1
- run: pglifecycle build ./schema schema.dump
```

| Input | Default | Description |
| --- | --- | --- |
| `version` | `latest` | Release tag to install |
| `repository` | `gmr/pglifecycle` | Repository to install from |
| `github-token` | `${{ github.token }}` | Token for the release lookup |

Outputs: `version` (the tag installed) and `path` (the binary).

`latest` resolves to the newest release. pglifecycle has published only
prereleases so far, so `latest` picks the newest prerelease and logs a
warning; pin `version` to keep a workflow stable.

Linux and macOS runners on x86-64 and arm64 are supported — the release
publishes no Windows binary. `pull`, `build`, and `deploy` shell out to
`pg_dump`, `pg_dumpall`, `pg_restore`, and `psql`, which the
GitHub-hosted Linux and macOS images already carry.

## Deploy

`deploy` compares a project against a database and produces the DDL that
would make the database match. It never applies anything: the script is
the output.

```yaml
permissions:
  contents: read
  pull-requests: write

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: gmr/pglifecycle-action/deploy@v1
        with:
          project: ./schema
          host: db.example.net
          database: production
          username: schema_ci
          password: ${{ secrets.PGPASSWORD }}
          comment-on-pr: true
          fail-on-drift: true
```

| Input | Default | Description |
| --- | --- | --- |
| `project` | *(required)* | Path to the pglifecycle project |
| `version` | `latest` | pglifecycle release tag to install |
| `dump` | | Compare against this `pg_dump` file instead of a live database |
| `output` | `pglifecycle-plan.sql` | Path to write the DDL script to |
| `allow-drop` | `false` | Include destructive statements in the plan |
| `no-privileges` | `false` | Leave grants and revokes out of the plan |
| `role` | | Role to assume when connecting |
| `args` | | Extra flags appended to the invocation |
| `host` `port` `database` `username` `password` | | Connection settings (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`) |
| `comment-on-pr` | `false` | Post the plan as a sticky pull request comment |
| `fail-on-drift` | `false` | Fail the step when the plan holds any change |
| `github-token` | `${{ github.token }}` | Token for the release lookup and the comment |

| Output | Description |
| --- | --- |
| `drift` | `true` when the database does not match the project |
| `plan` | Path of the generated DDL script |
| `excluded` | Count of destructive statements withheld from the plan |

The plan always goes to the job summary. `comment-on-pr` also posts it to
the pull request, replacing the previous comment for the same project on
each run, and needs `pull-requests: write`.

Destructive changes are excluded from the plan unless `allow-drop` is
set, but they still count as drift: a plan that withheld statements
reports `drift: true` and `excluded` above zero.

### Applying a plan

The action deliberately has no apply mode. Take the script from the
`plan` output and run it in the step or job that owns that decision:

```yaml
- id: plan
  uses: gmr/pglifecycle-action/deploy@v1
  with:
    project: ./schema
    host: db.example.net
    database: production
    username: schema_ci
    password: ${{ secrets.PGPASSWORD }}
- if: steps.plan.outputs.drift == 'true'
  env:
    PGPASSWORD: ${{ secrets.PGPASSWORD }}
  run: psql -h db.example.net -U schema_ci -d production -1 -f "${{ steps.plan.outputs.plan }}"
```

## Versioning

Releases are tagged `vMAJOR.MINOR.PATCH`, and the `v1` tag moves to the
newest release of that major version. Pin to `v1` for fixes, or to a
full tag to freeze. These tags track the actions, not pglifecycle —
the tool version is the `version` input.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
