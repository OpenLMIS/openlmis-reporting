{{
  config(
    materialized='view'
  )
}}

-- Current state of requisition.requisition_line_items. Rows deleted in the source are
-- tombstones in stg_requisition_line_items_with_deleted and are left out here.

select *
from {{ ref('stg_requisition_line_items_with_deleted') }}
where _cdc_op != 'd'
