{{
  config(
    materialized='table',
    engine='MergeTree()',
    order_by='(product_code, period_end_date, facility_name)',
    settings={'allow_nullable_key': 1}
  )
}}

-- Logistics summary: rows of mart_stock_status filtered to the top 5
-- products by total consumption in the latest reporting month, PER
-- PROGRAM. The original global top-5 all came from the highest-volume
-- program, so filtering the dashboard to any other program showed an
-- empty report ("Logistics Summary is always blank" in the client
-- review). Replicates the legacy "Logistics Summary Report" chart's
-- subquery filter (Superset blocks subqueries in adhoc_filters, so we
-- materialize the selection as its own mart). Refreshed on every build.

with latest_month as (
  -- Anchor the "current month" on the latest COMPLETE reporting month.
  -- The newest month present in the data is structurally partial (real
  -- data: 7% of facilities vs 96% the month before), so anchoring on
  -- max(period_end_date) would rank products from a sliver of the network.
  select month as month_start
  from {{ ref('mart_month_completeness') }}
  where family = 'stock'
    and is_latest_complete = 1
),

top_products as (
  select program_name, product_name
  from (
    select
      program_name,
      product_name,
      row_number() over (
        partition by program_name
        order by sum(total_consumed_quantity) desc
      ) as consumption_rank
    from {{ ref('mart_stock_status') }}
    cross join latest_month
    where period_end_date >= latest_month.month_start
      and total_consumed_quantity is not null
    group by program_name, product_name
  )
  where consumption_rank <= 5
)

select s.*
from {{ ref('mart_stock_status') }} s
inner join top_products tp
  on s.program_name = tp.program_name
 and s.product_name = tp.product_name
