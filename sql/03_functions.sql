-- Cloud Resource Cost Analyzer - public SQL functions.
-- Run after 02_packages.sql.

create or replace function fn_resource_cost(
    p_resource_id in number
) return number
is
    l_now timestamp := pkg_demo_clock.current_simulated_time;
    l_cycle_start timestamp;
    l_cycle_end timestamp;
begin
    pkg_billing.get_cycle_bounds(l_now, l_cycle_start, l_cycle_end);
    return pkg_billing.resource_cost(
        p_resource_id, l_cycle_start, least(l_now, l_cycle_end)
    );
end fn_resource_cost;
/
