{#
  no_deleted_source_rows — fails when a mart still holds rows whose source
  row was deleted.

  Incremental marts upsert only the rows that changed, so a row deleted in
  the source has to be removed explicitly (see the post_hook of
  mart_stock_status). This test returns the mart rows whose key is a
  tombstone (_cdc_op = 'd') in the given <model>_with_deleted staging table.

  Args:
    source_model   ref() of the staging table that keeps the tombstones.

  Example:

    - name: line_item_id
      tests:
        - no_deleted_source_rows:
            arguments:
              source_model: ref('stg_requisition_line_items_with_deleted')
#}

{% test no_deleted_source_rows(model, column_name, source_model) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }} in (
  select id
  from {{ source_model }}
  where _cdc_op = 'd'
)

{% endtest %}
