"""Streamlit dashboard for the Oracle-backed cloud cost analyzer."""

from __future__ import annotations

from datetime import datetime
from html import escape
from typing import Any

import streamlit as st

from db import DatabaseConfigurationError, connection


st.set_page_config(
    page_title="CloudLedger",
    page_icon="☁️",
    layout="wide",
)


def query_records(
    sql: str, parameters: dict[str, Any] | None = None
) -> list[dict[str, Any]]:
    with connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute(sql, parameters or {})
            columns = [column[0].lower() for column in cursor.description]
            return [
                dict(zip(columns, row, strict=True))
                for row in cursor.fetchall()
            ]


def query_value(sql: str, parameters: dict[str, Any] | None = None) -> Any:
    with connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute(sql, parameters or {})
            row = cursor.fetchone()
            return None if row is None else row[0]


def render_records(records: list[dict[str, Any]]) -> None:
    """Render database records without Streamlit's Pandas-backed table widgets."""

    if not records:
        st.info("No records found.")
        return
    columns = list(records[0])
    header = "| " + " | ".join(columns) + " |"
    separator = "| " + " | ".join("---" for _ in columns) + " |"
    rows = [
        "| " + " | ".join(escape(str(record.get(column, ""))) for column in columns) + " |"
        for record in records
    ]
    st.markdown("\n".join([header, separator, *rows]))


def run_procedure(
    package: str,
    procedure: str,
    parameters: list[Any] | None = None,
) -> Any:
    with connection() as conn:
        with conn.cursor() as cursor:
            arguments = list(parameters or [])
            if procedure == "create_resource":
                resource_id = cursor.var(int)
                arguments.append(resource_id)
                cursor.callproc(f"{package}.{procedure}", arguments)
                return resource_id.getvalue()
            cursor.callproc(f"{package}.{procedure}", arguments)
    return None


def render_connection_error(exc: Exception) -> None:
    if isinstance(exc, DatabaseConfigurationError):
        st.error(str(exc))
    else:
        st.error(
            "Database operation failed. Confirm the SQL scripts were run in "
            f"order and Oracle is available. Details: {exc}"
        )


def render_dashboard() -> None:
    st.subheader("Dashboard")
    try:
        current_time = query_value(
            "select pkg_demo_clock.current_simulated_time from dual"
        )
        local_time = query_value("select current_timestamp from dual")
        cycle_cost = query_value(
            "select pkg_billing.current_cycle_cost from dual"
        ) or 0
        resources = query_records(
            """
            select resource_name, resource_type, status, hourly_rate,
                   fn_resource_cost(resource_id) as current_cost
            from cloud_resources
            order by resource_name
            """
        )
        budget = query_records(
            """
            select budget_amount, cycle_type, warning_threshold_pct, currency_code
            from budget_settings
            where budget_id = 1
            """
        )
        clock = query_records(
            """
            select speed_multiplier, is_paused
            from demo_clock
            where clock_id = 1
            """
        )
        alerts = query_records(
            """
            select alert_type, amount, threshold_pct, created_at
            from budget_alerts
            order by created_at desc
            fetch first 5 rows only
            """
        )
    except Exception as exc:
        render_connection_error(exc)
        return

    budget_amount = float(budget[0]["budget_amount"]) if budget else 0
    consumed_pct = (float(cycle_cost) / budget_amount * 100) if budget_amount else 0
    running_count = sum(1 for row in resources if row["status"] == "RUNNING")

    if isinstance(current_time, datetime):
        formatted_time = current_time.strftime("%d %b %Y, %H:%M:%S")
    else:
        formatted_time = str(current_time)
    if isinstance(local_time, datetime):
        formatted_local_time = local_time.strftime("%d %b %Y, %H:%M:%S")
    else:
        formatted_local_time = str(local_time)

    metrics = st.columns(3)
    metrics[0].metric("Current-cycle cost", f"₹{float(cycle_cost):,.2f}")
    metrics[1].metric("Budget consumed", f"{consumed_pct:.2f}%")
    metrics[2].metric("Running resources", running_count)
    st.info(
        f"Local time: **{formatted_local_time}**  \n"
        f"Simulated time: **{formatted_time}** "
        f"({clock[0]['speed_multiplier'] if clock else 1}× clock)"
    )

    if budget:
        st.caption(
            f"Budget: ₹{budget_amount:,.2f} · {budget[0]['cycle_type']} cycle · "
            f"Consumed: ₹{float(cycle_cost):,.2f} · "
            f"Remaining: ₹{max(budget_amount - float(cycle_cost), 0):,.2f} · "
            f"Warning at {budget[0]['warning_threshold_pct']}%"
        )
    if clock:
        state = "Paused" if clock[0]["is_paused"] == "Y" else "Running"
        st.caption(f"Clock: {state} at {clock[0]['speed_multiplier']}×")

    st.subheader("Resources")
    render_records(resources)
    st.subheader("Recent alerts")
    if not alerts:
        st.info("No budget alerts have been recorded.")
    else:
        render_records(alerts)


def render_resources() -> None:
    st.subheader("Resource management")
    try:
        resources = query_records(
            """
            select resource_id, resource_name, resource_type, hourly_rate,
                   status, description, fn_resource_cost(resource_id) as current_cost
            from cloud_resources
            order by resource_name
            """
        )
    except Exception as exc:
        render_connection_error(exc)
        return

    render_records(resources)
    resource_map = {
        f"{row['resource_name']} ({row['resource_id']})": int(row["resource_id"])
        for row in resources
    }

    with st.expander("Create resource", expanded=not resources):
        with st.form("create_resource"):
            name = st.text_input("Name")
            resource_type = st.selectbox("Type", ["VM", "STORAGE", "COMPUTE"])
            rate = st.number_input("Hourly rate", min_value=0.0, step=1.0)
            description = st.text_input("Description")
            submitted = st.form_submit_button("Create")
        if submitted:
            if not name.strip():
                st.warning("Resource name is required.")
            else:
                try:
                    resource_id = run_procedure(
                        "pkg_cloud_resources",
                        "create_resource",
                        [name, resource_type, rate, description or None],
                    )
                    st.success(f"Created resource {resource_id}.")
                    st.rerun()
                except Exception as exc:
                    render_connection_error(exc)

    if not resource_map:
        return

    selected_label = st.selectbox("Select resource", list(resource_map))
    selected_id = resource_map[selected_label]
    selected = next(row for row in resources if row["resource_id"] == selected_id)
    action_columns = st.columns(3)
    if selected["status"] == "STOPPED":
        if action_columns[0].button("Start resource", key=f"start_{selected_id}"):
            try:
                run_procedure("pkg_cloud_resources", "start_resource", [selected_id])
                st.success("Resource started.")
                st.rerun()
            except Exception as exc:
                render_connection_error(exc)
    elif action_columns[0].button("Stop resource", key=f"stop_{selected_id}"):
        try:
            run_procedure("pkg_cloud_resources", "stop_resource", [selected_id])
            st.success("Resource stopped.")
            st.rerun()
        except Exception as exc:
            render_connection_error(exc)

    if action_columns[1].button("Delete resource", key=f"delete_{selected_id}"):
        try:
            run_procedure("pkg_cloud_resources", "delete_resource", [selected_id])
            st.success("Resource deleted.")
            st.rerun()
        except Exception as exc:
            render_connection_error(exc)

    with st.expander("Edit selected resource"):
        with st.form(f"edit_resource_{selected_id}"):
            edit_name = st.text_input("Name", value=str(selected["resource_name"]))
            type_options = ["VM", "STORAGE", "COMPUTE"]
            edit_type = st.selectbox(
                "Type",
                type_options,
                index=type_options.index(selected["resource_type"]),
            )
            edit_rate = st.number_input(
                "Hourly rate",
                min_value=0.0,
                value=float(selected["hourly_rate"]),
                step=1.0,
            )
            edit_description = st.text_input(
                "Description",
                value=str(selected["description"] or ""),
            )
            edit_submitted = st.form_submit_button("Save changes")
        if edit_submitted:
            try:
                run_procedure(
                    "pkg_cloud_resources",
                    "update_resource",
                    [selected_id, edit_name, edit_type, edit_rate, edit_description or None],
                )
                st.success("Resource updated.")
                st.rerun()
            except Exception as exc:
                render_connection_error(exc)


def render_settings() -> None:
    st.subheader("Clock and budget settings")
    try:
        settings = query_records(
            """
            select budget_amount, cycle_type, warning_threshold_pct, currency_code
            from budget_settings
            where budget_id = 1
            """
        )
        clock = query_records(
            "select speed_multiplier, is_paused from demo_clock where clock_id = 1"
        )
    except Exception as exc:
        render_connection_error(exc)
        return

    if not settings or not clock:
        st.error("Stage 2 settings are missing. Run sql\\01_tables.sql first.")
        return

    st.markdown("#### Accelerated demo clock")
    speed = st.number_input(
        "Speed multiplier",
        min_value=0.01,
        value=float(clock[0]["speed_multiplier"]),
        step=1.0,
    )
    clock_columns = st.columns(4)
    if clock_columns[0].button("Apply speed"):
        try:
            run_procedure("pkg_demo_clock", "set_speed", [speed])
            st.success("Clock speed updated without changing simulated time.")
            st.rerun()
        except Exception as exc:
            render_connection_error(exc)
    if clock[0]["is_paused"] == "Y":
        if clock_columns[1].button("Resume clock"):
            try:
                run_procedure("pkg_demo_clock", "resume_clock")
                st.rerun()
            except Exception as exc:
                render_connection_error(exc)
    elif clock_columns[1].button("Pause clock"):
        try:
            run_procedure("pkg_demo_clock", "pause_clock")
            st.rerun()
        except Exception as exc:
            render_connection_error(exc)
    if clock_columns[2].button("Reset clock"):
        try:
            run_procedure("pkg_demo_clock", "reset_clock", [datetime.now()])
            st.success("Clock reset.")
            st.rerun()
        except Exception as exc:
            render_connection_error(exc)

    st.markdown("#### Budget")
    current = settings[0]
    with st.form("budget_settings"):
        amount = st.number_input(
            "Budget amount", min_value=0.01, value=float(current["budget_amount"])
        )
        cycle_options = ["DAILY", "WEEKLY", "MONTHLY"]
        cycle = st.selectbox(
            "Cycle",
            cycle_options,
            index=cycle_options.index(current["cycle_type"]),
        )
        threshold = st.number_input(
            "Warning threshold (%)",
            min_value=0.01,
            max_value=99.99,
            value=float(current["warning_threshold_pct"]),
        )
        currency = st.text_input("Currency code", value=str(current["currency_code"]))
        if st.form_submit_button("Save budget"):
            try:
                run_procedure(
                    "pkg_budgets",
                    "configure",
                    [amount, cycle, threshold, currency],
                )
                st.success("Budget settings saved.")
                st.rerun()
            except Exception as exc:
                render_connection_error(exc)

    if st.button("Evaluate budget alerts"):
        try:
            run_procedure("pkg_budgets", "evaluate_alerts")
            st.success("Budget alerts evaluated from current Oracle records.")
        except Exception as exc:
            render_connection_error(exc)


st.title("CloudLedger")
st.caption("Cloud Resource Cost Analyzer · Oracle-backed billing simulator for cloud resources.")

try:
    with connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute("select sysdate from dual")
            database_time = cursor.fetchone()[0]
    st.caption(f"Connected to Oracle · database time: {database_time}")
except Exception as exc:
    render_connection_error(exc)
    st.stop()

dashboard_tab, resources_tab, settings_tab = st.tabs(
    ["Dashboard", "Resources", "Settings"]
)
with dashboard_tab:
    render_dashboard()
with resources_tab:
    render_resources()
with settings_tab:
    render_settings()
