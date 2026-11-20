1.1.0-SNAPSHOT (WIP)
==================

Bug fixes:
* [OLMIS-8460](https://openlmis.atlassian.net/browse/OLMIS-8460): Requisitions, requisition line items, status changes and stock adjustments deleted in OpenLMIS no longer stay in staging and in the marts built from it. The incremental staging tables are now `<model>_with_deleted` and keep a tombstone for each deleted row; `stg_requisitions`, `stg_requisition_line_items`, `stg_status_changes` and `stg_stock_adjustments` are views that leave the tombstones out. The first `dbt build` after the upgrade rebuilds these four tables from the full event history, which also removes the rows deleted before the upgrade; no `--full-refresh` is needed.

1.0.0 / 2026-09-29
==================

New functionality:
* First packaged release of the analytics-core content: Debezium connector configuration, dbt models and tests, and Superset assets for baseline reporting on the OpenLMIS database.
