{%- macro exasol__stage(include_source_columns,
                ldts,
                rsrc,
                source_model,
                hashed_columns,
                derived_columns,
                sequence,
                prejoined_columns,
                missing_columns) -%}

{% if (source_model is none) and execute %}

    {%- set error_message -%}
    Staging error: Missing source_model configuration. A source model name must be provided.
    e.g.
    [REF STYLE]
    source_model: model_name
    OR
    [SOURCES STYLE]
    source_model:
        source_name: source_table_name
    {%- endset -%}

    {{- exceptions.raise_compiler_error(error_message) -}}
{%- endif -%}

{#- Check for source format or ref format and create relation object from source_model -#}
{% if source_model is mapping and source_model is not none -%}

    {%- set source_name = source_model | first -%}
    {%- set source_table_name = source_model[source_name] -%}

    {%- set source_relation = source(source_name, source_table_name) -%}
    {%- set all_source_columns = datavault4dbt.source_columns(source_relation=source_relation) -%}
{%- elif source_model is not mapping and source_model is not none -%}

    {%- set source_relation = ref(source_model) -%}
    {%- set all_source_columns = datavault4dbt.source_columns(source_relation=source_relation) -%}
{%- else -%}

    {%- set all_source_columns = [] -%}
{%- endif -%}

{%- set ldts_rsrc_input_column_names = [] -%}

{# Setting the column name for load date timestamp and record source to the alias coming from the attributes #}
{%- set ldts_alias = var('datavault4dbt.ldts_alias', 'ldts') -%}
{%- set rsrc_alias = var('datavault4dbt.rsrc_alias', 'rsrc') -%}
{%- set load_datetime_col_name = ldts_alias -%}
{%- set record_source_col_name = rsrc_alias -%}

{%- if datavault4dbt.is_attribute(ldts) and ldts == ldts_alias -%}
  {%- set ldts_rsrc_input_column_names = ldts_rsrc_input_column_names + [ldts]  -%}
{%- endif %}

{%- if datavault4dbt.is_attribute(rsrc) and rsrc == rsrc_alias -%}
  {%- set ldts_rsrc_input_column_names = ldts_rsrc_input_column_names + [rsrc] -%}
{%- endif %}

{%- if sequence is not none -%}
  {%- set ldts_rsrc_input_column_names = ldts_rsrc_input_column_names + [sequence] -%}
{%- endif -%}

{%- set ldts = datavault4dbt.as_constant(ldts) -%}
{%- set rsrc = datavault4dbt.as_constant(rsrc) -%}

{%- set derived_column_names = datavault4dbt.extract_column_names(derived_columns) -%}
{%- set hashed_column_names = datavault4dbt.extract_column_names(hashed_columns) -%}
{%- set ranked_column_names = datavault4dbt.extract_column_names(ranked_columns) -%}
{%- set prejoined_column_names = datavault4dbt.extract_column_names(prejoined_columns) -%}
{%- set missing_column_names = datavault4dbt.extract_column_names(missing_columns) -%}
{%- set exclude_column_names = derived_column_names + hashed_column_names + prejoined_column_names + missing_column_names + ldts_rsrc_column_names %}
{%- set source_and_derived_column_names = (all_source_columns + derived_column_names) | unique | list -%}


{%- set source_columns_to_select = datavault4dbt.process_columns_to_select(all_source_columns, exclude_column_names) | list -%}
{%- set derived_columns_to_select = datavault4dbt.process_columns_to_select(source_and_derived_column_names, hashed_column_names) | unique | list -%}
{%- set final_columns_to_select = [] -%}

{%- set final_columns_to_select = final_columns_to_select + source_columns_to_select -%}

{#- Getting Data types for derived columns with detection from source relation -#}
{%- set derived_columns_with_datatypes = datavault4dbt.derived_columns_datatypes(derived_columns, source_relation) -%}
{%- set derived_columns_with_datatypes_DICT = fromjson(derived_columns_with_datatypes) -%}

{%- set all_columns = adapter.get_columns_in_relation( source_relation ) -%}
{%- set columns_without_excluded_columns = [] -%}
{%- for column in all_columns -%}
  {%- if column.name not in exclude_column_names %}
    {%- do columns_without_excluded_columns.append(column) -%}
  {%- endif -%}
{%- endfor -%}

{#- Select hashing algorithm -#}

{#- Setting unknown and error keys with default values for the selected hash algorithm -#}
{%- set hash = var('datavault4dbt.hash', 'MD5') -%}
{%- set hash_alg, unknown_key, error_key = datavault4dbt.hash_default_values(hash_function=hash) -%}

{# Select timestamp and format variables #}

{%- set beginning_of_all_times = var('datavault4dbt.beginning_of_all_times', '0001-01-01T00-00-01') -%}
{%- set end_of_all_times = var('datavault4dbt.end_of_all_times', '8888-12-31T23-59-59') -%}
{%- set timestamp_format = var('datavault4dbt.timestamp_format', 'YYYY-mm-ddTHH-MI-SS') -%}

{# Setting the error/unknown value for the record source  for the ghost records#}
{% set error_value_rsrc = var('datavault4dbt.default_error_rsrc', 'ERROR') %}
{% set unknown_value_rsrc = var('datavault4dbt.default_unknown_rsrc', 'SYSTEM') %}

{# Setting the rsrc default datatype and length #}
{% set rsrc_default_dtype = var('datavault4dbt.rsrc_default_dtype', 'VARCHAR (2000000) UTF8') %}

WITH

source_data AS (
    SELECT DISTINCT

    {{- "\n\n    " ~ datavault4dbt.print_list(datavault4dbt.escape_column_names(all_source_columns)) if all_source_columns else " *" }}

  FROM {{ source_relation }}

  {% set last_cte = "source_data" -%}
),


{% set alias_columns = [load_datetime_col_name, record_source_col_name] %}

{#  Selecting all columns from the source data, renaming load date and record source to Scalefree naming conventions #}

ldts_rsrc_data AS (
  SELECT

  {{ ldts }} AS {{ load_datetime_col_name}},
  CAST( {{ rsrc }} as {{ rsrc_default_dtype }} ) AS {{ record_source_col_name }},
  {% if sequence is not none -%}
    {{ sequence }} AS edwSequence,
    {%- set alias_columns = alias_columns + ['edwSequence'] -%}
  {% endif -%}

  {{ datavault4dbt.print_list(datavault4dbt.escape_column_names(source_columns_to_select)) }}

  FROM {{ last_cte }}

  {% set last_cte = "ldts_rsrc_data" %}
  {%- set final_columns_to_select = alias_columns + final_columns_to_select  %}
),

{% if datavault4dbt.is_something(missing_columns) %}


{# Filling missing columns with NULL values for schema changes #}
missing_columns AS (

  SELECT

    {{ datavault4dbt.print_list(datavault4dbt.escape_column_names(final_columns_to_select)) }},

  {%- for col, dtype in missing_columns.items() %}
    CAST(NULL as {{ dtype }}) as "{{ col }}",

  {% endfor %}

  FROM {{ last_cte }}
  {%- set last_cte = "missing_columns" -%}
  {%- set final_columns_to_select = final_columns_to_select + missing_column_names %}
),
{%- endif -%}

{% if datavault4dbt.is_something(prejoined_columns) %}
{#  Prejoining Business Keys of other source objects for Link purposes #}
prejoined_columns AS (

  SELECT

  {{ datavault4dbt.print_list(datavault4dbt.prefix(columns=datavault4dbt.escape_column_names(final_columns_to_select), prefix_str='lcte').split(',')) }}

  {%- for col, vals in prejoined_columns.items() -%}
    ,pj_{{loop.index}}.{{ vals['bk'] }} AS "{{ col }}"
  {% endfor -%}

  FROM {{ last_cte }} lcte

  {%- for col, vals in prejoined_columns.items() %}
    left join {{ source(vals['src_name']|string, vals['src_table']) }} as pj_{{loop.index}} on lcte.{{ vals['this_column_name'] }} = pj_{{loop.index}}.{{ vals['ref_column_name'] }}
  {% endfor %}

  {% set last_cte = "prejoined_columns" -%}
  {%- set final_columns_to_select = final_columns_to_select + prejoined_column_names %}
),
{%- endif -%}


{%- if datavault4dbt.is_something(derived_columns) %}
{# Adding derived columns to the selection #}
derived_columns AS (

    SELECT

    {{ datavault4dbt.print_list(datavault4dbt.escape_column_names(final_columns_to_select)) }},

    {{ datavault4dbt.derive_columns(columns=derived_columns) | indent(4) }}

    FROM {{ last_cte }}
    {%- set last_cte = "derived_columns" -%}
    {%- set final_columns_to_select = final_columns_to_select + derived_column_names %}
),
{%- endif -%}

{% if datavault4dbt.is_something(hashed_columns) and hashed_columns is mapping -%}
{# Generating Hashed Columns (hashkeys and hashdiffs for Hubs/Links/Satellites) #}
hashed_columns AS (

    SELECT

    {{ datavault4dbt.print_list(datavault4dbt.escape_column_names(final_columns_to_select)) }},

    {% set processed_hash_columns = datavault4dbt.process_hash_column_excludes(hashed_columns) -%}

    {{ datavault4dbt.hash_columns(columns=processed_hash_columns) | indent(4) }}

    FROM {{ last_cte }}
    {%- set last_cte = "hashed_columns" -%}
    {%- set final_columns_to_select = final_columns_to_select + hashed_column_names %}
),
{%- endif -%}

{# Adding Ranked Columns to the selection #}
{% if datavault4dbt.is_something(ranked_columns) -%}

ranked_columns AS (

    SELECT *,

    {{ datavault4dbt.rank_columns(columns=ranked_columns) | indent(4) if datavault4dbt.is_something(ranked_columns) }}

    FROM {{ last_cte }}
    {%- set last_cte = "ranked_columns" -%}
    {%- set final_columns_to_select = final_columns_to_select + ranked_column_names %}
),
{%- endif -%}

{# Creating Ghost Record for unknown case, based on datatype #}
unknown_values AS (
    SELECT

    {{ datavault4dbt.string_to_timestamp( timestamp_format , beginning_of_all_times) }} as {{ load_datetime_col_name }},
    '{{ unknown_value_rsrc }}' as {{ record_source_col_name }},
    {# Generating Ghost Records for all source columns, except the ldts, rsrc & edwSequence column #}
    {% for column in columns_without_excluded_columns -%}
          {{ datavault4dbt.ghost_record_per_datatype(column_name=column.name, datatype=column.dtype, ghost_record_type='unknown') }}
          {%- if not loop.last %},{% endif %}
    {% endfor %}

    {%- if  datavault4dbt.is_something(missing_columns) -%},
      {# Additionally generating ghost record for Missing columns #}
      {% for col, dtype in missing_columns.items() %}
        {{ datavault4dbt.ghost_record_per_datatype(column_name=col, datatype=dtype, ghost_record_type='unknown') }}
        {%- if not loop.last %},{% endif %}
      {% endfor %}
    {%- endif -%}



    {% if datavault4dbt.is_something(prejoined_columns) -%}
      {# Additionally generating ghost records for Prejoined columns #}
      {% for col, vals in prejoined_columns.items() %}
        {%- set pj_relation_columns = adapter.get_columns_in_relation( source(vals['src_name']|string, vals['src_table']) ) -%}

          {% for column in pj_relation_columns -%}
            {% if column.name|lower == vals['bk']|lower -%},
              {{ datavault4dbt.ghost_record_per_datatype(column_name=column.name, datatype=column.dtype, ghost_record_type='unknown') }}
            {% endif %}
          {% endfor -%}

        {% endfor -%}

    {%- endif -%}

    {%- if derived_columns is not none -%}
    --Additionally generating Ghost Records for Derived Columns
      ,{% for column_name, properties in derived_columns.items() -%}
        {{ datavault4dbt.ghost_record_per_datatype(column_name=column_name, datatype=properties.datatype, ghost_record_type='unknown') }}
        {%- if not loop.last %},{% endif -%}
      {% endfor %}
    {% endif %}

      ,{%- for hash_column in processed_hash_columns %}
        CAST('{{ unknown_key }}' as HASHTYPE) as "{{ hash_column }}"
        {%- if not loop.last %},{% endif %}

      {%- endfor %}
    {%- endif -%}

    ),

{# Creating Ghost Record for error case, based on datatype #}
error_values AS (
    SELECT

    {{ datavault4dbt.string_to_timestamp( timestamp_format , end_of_all_times) }} as {{ load_datetime_col_name }},
    '{{ error_value_rsrc }}' as {{ record_source_col_name }},

    {# Generating Ghost Records for Source Columns #}
    {% for column in columns_without_excluded_columns -%}
          {{ datavault4dbt.ghost_record_per_datatype(column_name=column.name, datatype=column.dtype, ghost_record_type='error') }}
          {%- if not loop.last %},{% endif %}
    {% endfor %}

    {% if datavault4dbt.is_something(missing_columns) -%},
      {# Additionally generating ghost record for Missing columns #}
      {% for col, dtype in missing_columns.items() %}
        {{ datavault4dbt.ghost_record_per_datatype(column_name=col, datatype=dtype, ghost_record_type='error') }}
        {%- if not loop.last %},{% endif -%}
      {% endfor %}
    {%- endif -%}

    {% if datavault4dbt.is_something(prejoined_columns) -%}
      {# Additionally generating ghost records for the Prejoined columns #}
      {% for col, vals in prejoined_columns.items() %}
        {% set pj_relation_columns = adapter.get_columns_in_relation( source(vals['src_name']|string, vals['src_table']) ) -%}

        ,{% for column in pj_relation_columns -%}
          {%- if column.name|lower == vals['bk']|lower -%}
            {{ datavault4dbt.ghost_record_per_datatype(column_name=column.name, datatype=column.dtype, ghost_record_type='error') }}
          {%- endif -%}
        {% endfor -%}

      {% endfor -%}

    {%- endif %}

    {% if datavault4dbt.is_something(derived_columns) -%},
      {# Additionally generating Ghost Records for Derived Columns #}
      {% for column_name, properties in derived_columns_with_datatypes_DICT.items() -%}
        {{ datavault4dbt.ghost_record_per_datatype(column_name=column_name, datatype=properties.datatype, ghost_record_type='error') }}
        {%- if not loop.last %},{% endif %}
      {% endfor %}
    {% endif %}

    {%- if datavault4dbt.is_something(processed_hash_columns)-%},
      {%- for hash_column in processed_hash_columns %}
        CAST('{{ error_key }}' as HASHTYPE) as "{{ hash_column }}"
        {%- if not loop.last %},{% endif %}

      {%- endfor %}
    {%- endif -%}
    ),

{# Combining all previous ghost record calculations to two rows with the same width as regular entries #}
ghost_records AS (
    SELECT * FROM unknown_values
    UNION ALL
    SELECT * FROM error_values
),

{# Combining the two ghost records with the regular data #}
columns_to_select AS (

    SELECT

     {{ datavault4dbt.print_list(datavault4dbt.escape_column_names(final_columns_to_select)) }}

    FROM {{ last_cte }}
    UNION ALL
    SELECT

    {{ datavault4dbt.print_list(datavault4dbt.escape_column_names(final_columns_to_select)) }}

     FROM ghost_records
)

SELECT * FROM columns_to_select

{%- endmacro -%}