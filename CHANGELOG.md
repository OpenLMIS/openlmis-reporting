1.1.0-SNAPSHOT (WIP)
==================

Bug fixes:
* [OLMIS-8460](https://openlmis.atlassian.net/browse/OLMIS-8460): Requisitions, requisition line items, status changes and stock adjustments deleted in OpenLMIS no longer stay in staging and in the marts built from it. The incremental staging tables are now `<model>_with_deleted` and keep a tombstone for each deleted row; `stg_requisitions`, `stg_requisition_line_items`, `stg_status_changes` and `stg_stock_adjustments` are views that leave the tombstones out. No `--full-refresh` is needed: the first `dbt build` after the upgrade builds the four new tables from the raw events, which also removes the rows deleted before the upgrade as long as their delete events are still in raw, and keeps the rows of the old tables whose events have already expired from raw (`RAW_TTL_DAYS`); rows deleted longer ago than that need a manual cleanup. If raw was truncated since the last build (as in the platform's source-upgrade runbook), drop the old `stg_requisitions`, `stg_requisition_line_items`, `stg_status_changes` and `stg_stock_adjustments` tables before the first build, or the rows deleted while the stack was detached come back. That first build takes about as long as a `--full-refresh` of these four models.
* [OLMIS-8460](https://openlmis.atlassian.net/browse/OLMIS-8460): `mart_stock_status` and `mart_adjustments`, which are incremental, delete the rows of deleted line items and adjustments after each run, and no longer skip a row that shares its timestamp with the previous run's last row; the new `no_deleted_source_rows` test checks these two marts and `mart_requisition_summary`.

1.0.0 / 2026-09-29
==================

New functionality:
* First packaged release of the analytics-core content: Debezium connector configuration, dbt models and tests, and Superset assets for baseline reporting on the OpenLMIS database.
