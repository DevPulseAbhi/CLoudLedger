-- Cloud Resource Cost Analyzer - non-destructive verification
-- Run after 01_tables.sql through 04_triggers.sql in the same schema used by
-- the Streamlit application. This script does not insert, update, or delete.

set serveroutput on

prompt === Current schema and required tables ===
select user as connected_user, sys_context('USERENV', 'CURRENT_SCHEMA') as current_schema
from dual;

with required_tables (object_name) as (
    select 'CLOUD_RESOURCES' from dual union all
    select 'USAGE_SESSIONS' from dual union all
    select 'BUDGET_SETTINGS' from dual union all
    select 'DEMO_CLOCK' from dual union all
    select 'BUDGET_ALERTS' from dual union all
    select 'BILLING_CYCLES' from dual
)
select required_tables.object_name,
       case when user_tables.table_name is null then 'MISSING' else 'PRESENT' end as status
from required_tables
left join user_tables
  on user_tables.table_name = required_tables.object_name
order by required_tables.object_name;

prompt === Required PL/SQL objects ===
with required_objects (object_name, object_type) as (
    select 'PKG_DEMO_CLOCK', 'PACKAGE' from dual union all
    select 'PKG_CLOUD_RESOURCES', 'PACKAGE' from dual union all
    select 'PKG_BILLING', 'PACKAGE' from dual union all
    select 'PKG_BUDGETS', 'PACKAGE' from dual union all
    select 'FN_RESOURCE_COST', 'FUNCTION' from dual union all
    select 'TRG_CLOUD_RESOURCES_UPDATED', 'TRIGGER' from dual union all
    select 'TRG_DEMO_CLOCK_UPDATED', 'TRIGGER' from dual union all
    select 'TRG_BUDGET_SETTINGS_UPDATED', 'TRIGGER' from dual
)
select required_objects.object_name,
       required_objects.object_type,
       coalesce(user_objects.status, 'MISSING') as status
from required_objects
left join user_objects
  on user_objects.object_name = required_objects.object_name
 and user_objects.object_type = required_objects.object_type
order by required_objects.object_type, required_objects.object_name;

prompt === Compilation errors (no rows means no errors) ===
select name, type, line, position, text
from user_errors
where name in (
    'PKG_DEMO_CLOCK',
    'PKG_CLOUD_RESOURCES',
    'PKG_BILLING',
    'PKG_BUDGETS',
    'FN_RESOURCE_COST',
    'TRG_CLOUD_RESOURCES_UPDATED',
    'TRG_DEMO_CLOCK_UPDATED',
    'TRG_BUDGET_SETTINGS_UPDATED'
)
order by name, sequence;

prompt === Runtime smoke checks ===
begin
    dbms_output.put_line(
        'CURRENT_SIMULATED_TIME=' ||
        to_char(pkg_demo_clock.current_simulated_time, 'YYYY-MM-DD HH24:MI:SS')
    );
    dbms_output.put_line(
        'CURRENT_CYCLE_COST=' ||
        to_char(pkg_billing.current_cycle_cost, 'FM9999999990D00')
    );
    dbms_output.put_line('PACKAGE_RUNTIME_CHECK=PASS');
exception
    when others then
        dbms_output.put_line(
            'PACKAGE_RUNTIME_CHECK=FAIL ORA-' ||
            abs(sqlcode) || ': ' || sqlerrm
        );
end;
/
