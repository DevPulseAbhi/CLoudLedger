-- Cloud Resource Cost Analyzer - package specifications and bodies.
-- Run after 01_tables.sql.

create or replace package pkg_demo_clock as
    function current_simulated_time return timestamp;
    procedure set_speed(p_speed_multiplier number);
    procedure pause_clock;
    procedure resume_clock;
    procedure reset_clock(p_simulated_time timestamp default null);
end pkg_demo_clock;
/

create or replace package body pkg_demo_clock as
    function current_simulated_time return timestamp is
        l_simulated_anchor demo_clock.simulated_anchor%type;
        l_real_anchor      demo_clock.real_anchor%type;
        l_speed             demo_clock.speed_multiplier%type;
        l_is_paused         demo_clock.is_paused%type;
        l_elapsed_seconds   number;
    begin
        select simulated_anchor, real_anchor, speed_multiplier, is_paused
          into l_simulated_anchor, l_real_anchor, l_speed, l_is_paused
          from demo_clock
         where clock_id = 1;

        if l_is_paused = 'Y' then
            return cast(l_simulated_anchor as timestamp);
        end if;

        l_elapsed_seconds :=
              (cast(systimestamp as date) - cast(l_real_anchor as date))
              * 86400
              * l_speed;

        return cast(
            l_simulated_anchor + numtodsinterval(l_elapsed_seconds, 'SECOND')
            as timestamp
        );
    exception
        when no_data_found then
            raise_application_error(
                -20001, 'Demo clock is not initialized. Run 01_tables.sql.'
            );
    end current_simulated_time;

    procedure set_speed(p_speed_multiplier number) is
        l_current_time timestamp;
    begin
        if p_speed_multiplier is null or p_speed_multiplier <= 0 then
            raise_application_error(-20002, 'Clock speed must be greater than zero.');
        end if;

        l_current_time := current_simulated_time;
        update demo_clock
           set simulated_anchor = l_current_time,
               real_anchor = systimestamp,
               speed_multiplier = p_speed_multiplier,
               updated_at = systimestamp
         where clock_id = 1;
        commit;
    end set_speed;

    procedure pause_clock is
        l_is_paused demo_clock.is_paused%type;
        l_current_time timestamp;
    begin
        select is_paused
          into l_is_paused
          from demo_clock
         where clock_id = 1;

        if l_is_paused = 'Y' then
            return;
        end if;

        l_current_time := current_simulated_time;
        update demo_clock
           set simulated_anchor = l_current_time,
               real_anchor = systimestamp,
               is_paused = 'Y',
               updated_at = systimestamp
         where clock_id = 1;
        commit;
    end pause_clock;

    procedure resume_clock is
        l_is_paused demo_clock.is_paused%type;
    begin
        select is_paused into l_is_paused
          from demo_clock
         where clock_id = 1;

        if l_is_paused = 'N' then
            return;
        end if;

        update demo_clock
           set real_anchor = systimestamp,
               is_paused = 'N',
               updated_at = systimestamp
         where clock_id = 1;
        commit;
    end resume_clock;

    procedure reset_clock(p_simulated_time timestamp default null) is
        l_reset_time timestamp := coalesce(p_simulated_time, cast(systimestamp as timestamp));
    begin
        update demo_clock
           set simulated_anchor = l_reset_time,
               real_anchor = systimestamp,
               is_paused = 'N',
               updated_at = systimestamp
         where clock_id = 1;
        commit;
    end reset_clock;
end pkg_demo_clock;
/

create or replace package pkg_cloud_resources as
    procedure create_resource(
        p_resource_name in varchar2,
        p_resource_type in varchar2,
        p_hourly_rate   in number,
        p_description   in varchar2 default null,
        p_resource_id   out number
    );
    procedure update_resource(
        p_resource_id   in number,
        p_resource_name in varchar2,
        p_resource_type in varchar2,
        p_hourly_rate   in number,
        p_description   in varchar2 default null
    );
    procedure delete_resource(p_resource_id in number);
    procedure start_resource(p_resource_id in number);
    procedure stop_resource(p_resource_id in number);
end pkg_cloud_resources;
/

create or replace package body pkg_cloud_resources as
    procedure create_resource(
        p_resource_name in varchar2,
        p_resource_type in varchar2,
        p_hourly_rate   in number,
        p_description   in varchar2 default null,
        p_resource_id   out number
    ) is
    begin
        if trim(p_resource_name) is null or p_resource_type is null
           or p_hourly_rate is null or p_hourly_rate < 0 then
            raise_application_error(-20010, 'Resource name, type and non-negative rate are required.');
        end if;

        p_resource_id := cloud_resource_seq.nextval;
        insert into cloud_resources (
            resource_id, resource_name, resource_type, hourly_rate, description
        )
        values (
            p_resource_id, trim(p_resource_name), upper(trim(p_resource_type)),
            p_hourly_rate, p_description
        );
        commit;
    end create_resource;

    procedure update_resource(
        p_resource_id   in number,
        p_resource_name in varchar2,
        p_resource_type in varchar2,
        p_hourly_rate   in number,
        p_description   in varchar2 default null
    ) is
        l_status cloud_resources.status%type;
    begin
        if p_resource_id is null or trim(p_resource_name) is null
           or p_resource_type is null or p_hourly_rate is null
           or p_hourly_rate < 0 then
            raise_application_error(-20011, 'Resource fields are invalid.');
        end if;

        select status into l_status
          from cloud_resources
         where resource_id = p_resource_id
         for update;

        update cloud_resources
           set resource_name = trim(p_resource_name),
               resource_type = upper(trim(p_resource_type)),
               hourly_rate = p_hourly_rate,
               description = p_description,
               updated_at = systimestamp
         where resource_id = p_resource_id;
        commit;
    exception
        when no_data_found then
            raise_application_error(-20012, 'Resource does not exist.');
    end update_resource;

    procedure delete_resource(p_resource_id in number) is
    begin
        delete from cloud_resources where resource_id = p_resource_id;
        if sql%rowcount = 0 then
            raise_application_error(-20013, 'Resource does not exist.');
        end if;
        commit;
    end delete_resource;

    procedure start_resource(p_resource_id in number) is
        l_rate cloud_resources.hourly_rate%type;
        l_status cloud_resources.status%type;
    begin
        select hourly_rate, status into l_rate, l_status
          from cloud_resources
         where resource_id = p_resource_id
         for update;

        if l_status = 'RUNNING' then
            raise_application_error(-20014, 'Resource is already running.');
        end if;

        insert into usage_sessions (session_id, resource_id, started_at, hourly_rate)
        values (
            usage_session_seq.nextval, p_resource_id,
            pkg_demo_clock.current_simulated_time, l_rate
        );

        update cloud_resources
           set status = 'RUNNING', updated_at = systimestamp
         where resource_id = p_resource_id;
        commit;
    exception
        when no_data_found then
            raise_application_error(-20015, 'Resource does not exist.');
    end start_resource;

    procedure stop_resource(p_resource_id in number) is
        l_status cloud_resources.status%type;
    begin
        select status into l_status
          from cloud_resources
         where resource_id = p_resource_id
         for update;

        if l_status = 'STOPPED' then
            raise_application_error(-20016, 'Resource is already stopped.');
        end if;

        update usage_sessions
           set ended_at = pkg_demo_clock.current_simulated_time
         where resource_id = p_resource_id
           and ended_at is null;

        update cloud_resources
           set status = 'STOPPED', updated_at = systimestamp
         where resource_id = p_resource_id;
        commit;
    exception
        when no_data_found then
            raise_application_error(-20017, 'Resource does not exist.');
    end stop_resource;
end pkg_cloud_resources;
/

create or replace package pkg_billing as
    procedure get_cycle_bounds(
        p_at          in timestamp,
        p_cycle_start out timestamp,
        p_cycle_end   out timestamp
    );
    function resource_cost(
        p_resource_id in number,
        p_from        in timestamp,
        p_to          in timestamp
    ) return number;
    function current_cycle_cost return number;
end pkg_billing;
/

create or replace package body pkg_billing as
    procedure get_cycle_bounds(
        p_at          in timestamp,
        p_cycle_start out timestamp,
        p_cycle_end   out timestamp
    ) is
        l_cycle_type budget_settings.cycle_type%type;
    begin
        select cycle_type into l_cycle_type from budget_settings where budget_id = 1;

        if l_cycle_type = 'DAILY' then
            p_cycle_start := trunc(p_at);
            p_cycle_end := p_cycle_start + interval '1' day;
        elsif l_cycle_type = 'WEEKLY' then
            p_cycle_start := trunc(p_at, 'IW');
            p_cycle_end := p_cycle_start + interval '7' day;
        else
            p_cycle_start := trunc(p_at, 'MM');
            p_cycle_end := add_months(p_cycle_start, 1);
        end if;
    exception
        when no_data_found then
            raise_application_error(-20020, 'Budget settings are not initialized.');
    end get_cycle_bounds;

    function resource_cost(
        p_resource_id in number,
        p_from        in timestamp,
        p_to          in timestamp
    ) return number is
        l_cost number := 0;
        l_overlap_start timestamp;
        l_overlap_end timestamp;
        l_duration_seconds number;
    begin
        if p_from is null or p_to is null or p_to <= p_from then
            raise_application_error(-20021, 'Billing period must have a positive duration.');
        end if;

        for session_row in (
            select started_at, ended_at, hourly_rate
              from usage_sessions
             where resource_id = p_resource_id
               and started_at < p_to
               and (ended_at is null or ended_at > p_from)
        ) loop
            l_overlap_start := greatest(session_row.started_at, p_from);
            l_overlap_end := least(coalesce(session_row.ended_at, p_to), p_to);
            if l_overlap_end > l_overlap_start then
                l_duration_seconds :=
                      extract(day from (l_overlap_end - l_overlap_start)) * 86400
                    + extract(hour from (l_overlap_end - l_overlap_start)) * 3600
                    + extract(minute from (l_overlap_end - l_overlap_start)) * 60
                    + extract(second from (l_overlap_end - l_overlap_start));
                l_cost := l_cost + session_row.hourly_rate
                    * l_duration_seconds / 3600;
            end if;
        end loop;
        return round(l_cost, 2);
    end resource_cost;

    function current_cycle_cost return number is
        l_now timestamp := pkg_demo_clock.current_simulated_time;
        l_cycle_start timestamp;
        l_cycle_end timestamp;
        l_total number := 0;
    begin
        get_cycle_bounds(l_now, l_cycle_start, l_cycle_end);
        for resource_row in (select resource_id from cloud_resources) loop
            l_total := l_total + resource_cost(
                resource_row.resource_id, l_cycle_start, least(l_now, l_cycle_end)
            );
        end loop;
        return round(l_total, 2);
    end current_cycle_cost;
end pkg_billing;
/

create or replace package pkg_budgets as
    procedure configure(
        p_budget_amount         in number,
        p_cycle_type            in varchar2,
        p_warning_threshold_pct in number default 80,
        p_currency_code         in varchar2 default 'INR'
    );
    procedure evaluate_alerts;
    procedure enforce_budget;
end pkg_budgets;
/

create or replace package body pkg_budgets as
    procedure configure(
        p_budget_amount         in number,
        p_cycle_type            in varchar2,
        p_warning_threshold_pct in number default 80,
        p_currency_code         in varchar2 default 'INR'
    ) is
    begin
        update budget_settings
           set budget_amount = p_budget_amount,
               cycle_type = upper(trim(p_cycle_type)),
               warning_threshold_pct = p_warning_threshold_pct,
               currency_code = upper(trim(p_currency_code)),
               updated_at = systimestamp
         where budget_id = 1;
        if sql%rowcount = 0 then
            raise_application_error(-20030, 'Budget settings are not initialized.');
        end if;
        commit;
    end configure;

    procedure evaluate_alerts is
        l_now timestamp := pkg_demo_clock.current_simulated_time;
        l_start timestamp;
        l_end timestamp;
        l_budget budget_settings.budget_amount%type;
        l_warning_pct budget_settings.warning_threshold_pct%type;
        l_cost number;
        l_alert_type budget_alerts.alert_type%type;
        l_threshold budget_alerts.threshold_pct%type;
    begin
        select budget_amount, warning_threshold_pct
          into l_budget, l_warning_pct
          from budget_settings
         where budget_id = 1;

        pkg_billing.get_cycle_bounds(l_now, l_start, l_end);
        l_cost := pkg_billing.current_cycle_cost;

        if l_cost >= l_budget then
            l_alert_type := 'EXCEEDED';
            l_threshold := 100;
        elsif l_cost >= l_budget * l_warning_pct / 100 then
            l_alert_type := 'WARNING';
            l_threshold := l_warning_pct;
        else
            return;
        end if;

        begin
            insert into budget_alerts (
                alert_id, cycle_type, cycle_start, threshold_pct, alert_type,
                amount, budget_amount
            )
            select budget_alert_seq.nextval, cycle_type, l_start, l_threshold,
                   l_alert_type, l_cost, l_budget
              from budget_settings
             where budget_id = 1;
        exception
            when dup_val_on_index then
                null;
        end;
        commit;
    exception
        when no_data_found then
            raise_application_error(-20031, 'Budget settings are not initialized.');
    end evaluate_alerts;

    procedure enforce_budget is
        l_now timestamp := pkg_demo_clock.current_simulated_time;
        l_cycle_start timestamp;
        l_cycle_end timestamp;
        l_budget budget_settings.budget_amount%type;
        l_cost number;
        l_alert_exists number;
    begin
        select budget_amount
          into l_budget
          from budget_settings
         where budget_id = 1;

        pkg_billing.get_cycle_bounds(l_now, l_cycle_start, l_cycle_end);
        l_cost := pkg_billing.current_cycle_cost;

        if l_cost < l_budget then
            evaluate_alerts;
            return;
        end if;

        select count(*)
          into l_alert_exists
          from budget_alerts
         where cycle_type = (
                   select cycle_type from budget_settings where budget_id = 1
               )
           and cycle_start = l_cycle_start
           and alert_type = 'EXCEEDED'
           and threshold_pct = 100;

        if l_alert_exists = 0 then
            insert into budget_alerts (
                alert_id, cycle_type, cycle_start, threshold_pct, alert_type,
                amount, budget_amount
            )
            select budget_alert_seq.nextval, cycle_type, l_cycle_start, 100,
                   'EXCEEDED', l_cost, l_budget
              from budget_settings
             where budget_id = 1;
        end if;

        for resource_row in (
            select resource_id
              from cloud_resources
             where status = 'RUNNING'
        ) loop
            if pkg_billing.resource_cost(
                   resource_row.resource_id, l_cycle_start, least(l_now, l_cycle_end)
               ) >= l_budget then
                pkg_cloud_resources.stop_resource(resource_row.resource_id);
            end if;
        end loop;
        commit;
    exception
        when no_data_found then
            raise_application_error(-20032, 'Budget settings are not initialized.');
    end enforce_budget;
end pkg_budgets;
/
