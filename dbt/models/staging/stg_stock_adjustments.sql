{{
  config(
    materialized='view'
  )
}}

-- Current state of requisition.stock_adjustments. Rows deleted in the source are
-- tombstones in stg_stock_adjustments_with_deleted and are left out here.

select *
from {{ ref('stg_stock_adjustments_with_deleted') }}
where _cdc_op != 'd'
