-- Cloud Resource Cost Analyzer - narrow automatic timestamp triggers.
-- Run after 03_functions.sql.

create or replace trigger trg_cloud_resources_updated
before update on cloud_resources
for each row
begin
    :new.updated_at := systimestamp;
end;
/

create or replace trigger trg_demo_clock_updated
before update on demo_clock
for each row
begin
    :new.updated_at := systimestamp;
end;
/

create or replace trigger trg_budget_settings_updated
before update on budget_settings
for each row
begin
    :new.updated_at := systimestamp;
end;
/
