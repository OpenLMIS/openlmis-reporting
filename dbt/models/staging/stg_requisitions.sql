{{
  config(
    materialized='view'
  )
}}

-- Current state of requisition.requisitions. Rows deleted in the source are
-- tombstones in stg_requisitions_with_deleted and are left out here.

select *
from {{ ref('stg_requisitions_with_deleted') }}
where _cdc_op != 'd'
