{{
  config(
    materialized='view'
  )
}}

-- Current state of requisition.status_changes. Rows deleted in the source are
-- tombstones in stg_status_changes_with_deleted and are left out here.

select *
from {{ ref('stg_status_changes_with_deleted') }}
where _cdc_op != 'd'
