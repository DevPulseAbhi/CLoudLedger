-- Cloud Resource Cost Analyzer - Stage 2
-- Run this script first as the application schema user.
-- The statements are rerunnable in a clean schema; existing objects are not
-- dropped so historical data cannot be destroyed accidentally.

create sequence cloud_resource_seq start with 1 increment by 1 nocache;
create sequence usage_session_seq start with 1 increment by 1 nocache;
create sequence budget_alert_seq start with 1 increment by 1 nocache;
create sequence billing_cycle_seq start with 1 increment by 1 nocache;

create table cloud_resources (
    resource_id       number(12)    not null,
    resource_name     varchar2(100) not null,
    resource_type     varchar2(20)  not null,
    hourly_rate       number(12,4)  not null,
    status            varchar2(10)  default 'STOPPED' not null,
    description       varchar2(500),
    created_at        timestamp(6)  default systimestamp not null,
    updated_at        timestamp(6)  default systimestamp not null,
    constraint pk_cloud_resources primary key (resource_id),
    constraint uq_cloud_resources_name unique (resource_name),
    constraint ck_cloud_resources_type
        check (resource_type in ('VM', 'STORAGE', 'COMPUTE')),
    constraint ck_cloud_resources_rate check (hourly_rate >= 0),
    constraint ck_cloud_resources_status
        check (status in ('RUNNING', 'STOPPED'))
);

create table demo_clock (
    clock_id             number(1) not null,
    simulated_anchor     timestamp(6) with time zone not null,
    real_anchor          timestamp(6) with time zone not null,
    speed_multiplier      number(12,4) default 1 not null,
    is_paused             char(1) default 'N' not null,
    updated_at            timestamp(6) default systimestamp not null,
    constraint pk_demo_clock primary key (clock_id),
    constraint ck_demo_clock_id check (clock_id = 1),
    constraint ck_demo_clock_speed check (speed_multiplier > 0),
    constraint ck_demo_clock_paused check (is_paused in ('Y', 'N'))
);

create table budget_settings (
    budget_id             number(1) not null,
    budget_amount         number(14,2) not null,
    cycle_type            varchar2(10) not null,
    warning_threshold_pct number(5,2) default 80 not null,
    currency_code         varchar2(3) default 'INR' not null,
    updated_at            timestamp(6) default systimestamp not null,
    constraint pk_budget_settings primary key (budget_id),
    constraint ck_budget_settings_id check (budget_id = 1),
    constraint ck_budget_settings_amount check (budget_amount > 0),
    constraint ck_budget_settings_cycle
        check (cycle_type in ('DAILY', 'WEEKLY', 'MONTHLY')),
    constraint ck_budget_settings_threshold
        check (warning_threshold_pct > 0 and warning_threshold_pct < 100),
    constraint ck_budget_settings_currency
        check (regexp_like(currency_code, '^[A-Z]{3}$'))
);

create table usage_sessions (
    session_id      number(12) not null,
    resource_id     number(12) not null,
    started_at      timestamp(6) not null,
    ended_at        timestamp(6),
    hourly_rate     number(12,4) not null,
    created_at      timestamp(6) default systimestamp not null,
    constraint pk_usage_sessions primary key (session_id),
    constraint fk_usage_sessions_resource
        foreign key (resource_id) references cloud_resources (resource_id),
    constraint ck_usage_sessions_rate check (hourly_rate >= 0),
    constraint ck_usage_sessions_dates
        check (ended_at is null or ended_at >= started_at)
);

create unique index uq_usage_sessions_open_resource
    on usage_sessions (
        case when ended_at is null then resource_id else null end
    );

create table billing_cycles (
    cycle_id       number(12) not null,
    cycle_type     varchar2(10) not null,
    cycle_start    timestamp(6) not null,
    cycle_end      timestamp(6) not null,
    finalized_at   timestamp(6),
    total_cost     number(14,2) default 0 not null,
    constraint pk_billing_cycles primary key (cycle_id),
    constraint uq_billing_cycles_range unique (cycle_type, cycle_start),
    constraint ck_billing_cycles_type
        check (cycle_type in ('DAILY', 'WEEKLY', 'MONTHLY')),
    constraint ck_billing_cycles_dates check (cycle_end > cycle_start),
    constraint ck_billing_cycles_cost check (total_cost >= 0)
);

create table budget_alerts (
    alert_id       number(12) not null,
    cycle_type     varchar2(10) not null,
    cycle_start    timestamp(6) not null,
    threshold_pct  number(5,2) not null,
    alert_type     varchar2(10) not null,
    amount         number(14,2) not null,
    budget_amount  number(14,2) not null,
    created_at     timestamp(6) default systimestamp not null,
    constraint pk_budget_alerts primary key (alert_id),
    constraint uq_budget_alerts_threshold
        unique (cycle_type, cycle_start, threshold_pct, alert_type),
    constraint ck_budget_alerts_type
        check (cycle_type in ('DAILY', 'WEEKLY', 'MONTHLY')),
    constraint ck_budget_alerts_threshold
        check (threshold_pct > 0 and threshold_pct <= 100),
    constraint ck_budget_alerts_alert_type
        check (alert_type in ('WARNING', 'EXCEEDED')),
    constraint ck_budget_alerts_amounts
        check (amount >= 0 and budget_amount > 0)
);

merge into demo_clock target
using (select 1 clock_id from dual) source
on (target.clock_id = source.clock_id)
when not matched then
    insert (
        clock_id, simulated_anchor, real_anchor, speed_multiplier, is_paused
    )
    values (1, systimestamp, systimestamp, 1, 'N');

merge into budget_settings target
using (select 1 budget_id from dual) source
on (target.budget_id = source.budget_id)
when not matched then
    insert (
        budget_id, budget_amount, cycle_type, warning_threshold_pct, currency_code
    )
    values (1, 10000, 'MONTHLY', 80, 'INR');

commit;
