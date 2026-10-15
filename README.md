# Cloud Resource Cost Analyzer

An MCA Semester 1 minor project using Oracle Database and PL/SQL for persistence
and billing logic, with a Python/Streamlit dashboard.

## Stage 1 and Stage 2 status

Stage 1 provides:

- A separate Python entry point in `app.py`.
- A small Oracle connection layer in `db.py`.
- Environment-based credentials and DSN configuration.
- Dependency declarations in `requirements.txt`.
- A connection test screen that runs `select sysdate from dual`.
- Ordered Oracle schema and PL/SQL foundation scripts under `sql\`.

Stage 2 currently includes the core tables, constraints, sequences, demo-clock
package, resource-management package, billing package, budget package, public
resource-cost function, timestamp-maintenance triggers, and a database-backed
Streamlit dashboard. The dashboard includes current-cycle metrics, resource
create/edit/delete/start/stop actions, clock controls, budget configuration,
and alert evaluation. It does not use hardcoded dashboard metrics.

## Prerequisites

- Python 3.12 or newer.
- An Oracle Database with a reachable service name, such as `FREEPDB1`.
- An Oracle schema/user for this project.
- Network access to the Oracle listener.

The application uses `python-oracledb` Thin mode by default, so an Oracle
Instant Client is not required for the initial setup.

## Local setup

From `e:\SQL Mini Project` in PowerShell:

```powershell
$python = "C:\Users\MY ASUS\AppData\Local\Python\pythoncore-3.14-64\python.exe"
& $python -m venv .venv
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Edit `.env` with the Oracle username, password, and DSN. Do not commit `.env`.
The DSN accepts an Easy Connect string such as
`localhost:1521/FREEPDB1`, or an Oracle Net service name resolvable by the
local Oracle configuration.

## Run the application

```powershell
& .\.venv\Scripts\streamlit.exe run app.py
```

Open the displayed local URL. The application first checks Oracle using
`SYSDATE`, then displays Dashboard, Resources, and Settings tabs. The database
scripts must be installed before the tabs can load their records.

## Troubleshooting

- **Missing required setting**: copy `.env.example` to `.env` and fill in all
  three `ORACLE_*` values. The application loads this file automatically.
  Environment variables already set in the process take precedence.

- **Unable to connect**: check that the Oracle listener and database are
  running, confirm the service name, and test the same DSN with SQL*Plus.
- **Thick mode errors**: keep `ORACLE_THICK_MODE=false` unless Thick mode is
  needed. If enabled, set `ORACLE_CLIENT_LIB_DIR` to the Oracle Client library
  directory.

## Run Stage 2 in SQL Developer

Connect in SQL Developer using the same Oracle user, password, and DSN values
configured by `ORACLE_USER`, `ORACLE_PASSWORD`, and `ORACLE_DSN`. The first
script to run is:

```sql
@e:\SQL Mini Project\sql\01_tables.sql
```

Run it with **Run Script (F5)**, not only **Run Statement (Ctrl+Enter)**,
because the scripts contain SQL*Plus/SQL Developer `/` delimiters for PL/SQL.
Then run these scripts in order:

```sql
@e:\SQL Mini Project\sql\02_packages.sql
@e:\SQL Mini Project\sql\03_functions.sql
@e:\SQL Mini Project\sql\04_triggers.sql
@e:\SQL Mini Project\sql\05_verify.sql
```

Run every script through the existing `LocalOracle` connection in VS Code SQL
Developer, using the same schema and service as the `.env` values. In the
current setup this connection is `SYSTEM` on `localhost:1521/FREEPDB1`.
Do not run the scripts under a different schema: the Python queries use
unqualified names such as `CLOUD_RESOURCES`, so Oracle resolves them in the
connected application schema.

Run each file with **Run Script (F5)**, not only **Run Statement (Ctrl+Enter)**.
The scripts do not drop existing tables or historical records. `01_tables.sql`
initializes the singleton clock and budget configuration rows, but does not
insert demo resources.

### Verify table creation and compilation

After running the scripts, execute this as the same connection:

```sql
select table_name
from user_tables
where table_name in (
    'CLOUD_RESOURCES', 'USAGE_SESSIONS', 'BUDGET_SETTINGS',
    'DEMO_CLOCK', 'BUDGET_ALERTS', 'BILLING_CYCLES'
)
order by table_name;

select object_name, object_type, status
from user_objects
where object_name in (
    'PKG_DEMO_CLOCK', 'PKG_CLOUD_RESOURCES', 'PKG_BILLING',
    'PKG_BUDGETS', 'FN_RESOURCE_COST',
    'TRG_CLOUD_RESOURCES_UPDATED', 'TRG_DEMO_CLOCK_UPDATED',
    'TRG_BUDGET_SETTINGS_UPDATED'
)
order by object_type, object_name;

select object_name, object_type, line, position, text
from user_errors
where name in (
    'PKG_DEMO_CLOCK', 'PKG_CLOUD_RESOURCES', 'PKG_BILLING',
    'PKG_BUDGETS', 'FN_RESOURCE_COST',
    'TRG_CLOUD_RESOURCES_UPDATED', 'TRG_DEMO_CLOCK_UPDATED',
    'TRG_BUDGET_SETTINGS_UPDATED'
)
order by name, sequence;
```

All listed objects should be `VALID`, and the `USER_ERRORS` query should return
no rows. The same checks are automated by
`sql\05_verify.sql`, which also prints the connected schema, reports missing
objects explicitly, and executes read-only package smoke checks. The
`DEMO_CLOCK` and `BUDGET_SETTINGS` checks should each return one row:

```sql
select * from demo_clock;
select * from budget_settings;
```

If `05_verify.sql` reports missing tables, rerun `01_tables.sql` in the same
`LocalOracle` connection. If it reports invalid packages, inspect the
`USER_ERRORS` output and rerun `02_packages.sql`, then `03_functions.sql` and
`04_triggers.sql` in that order. Start Streamlit only after every required
table is `PRESENT`, every required object is `VALID`, and
`PACKAGE_RUNTIME_CHECK=PASS` is displayed.

## Next stage

After Stage 2 is verified, the next stage will add focused billing and
accelerated-clock tests, analytics, and additional UI refinement. Sample/demo
resource data is intentionally deferred so the database foundation does not
create fake usage.
