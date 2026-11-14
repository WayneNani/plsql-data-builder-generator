create or replace package body builder_pattern_generator as

  gc_newline constant varchar2(1) := chr(10);
  gc_whitespace constant varchar2(4) := ' ' || chr(9) || chr(10) || chr(13);

  subtype identifier_type is varchar2(130 char);
  subtype expression_type is varchar2(32767);

  type t_identifiers_type is table of identifier_type index by pls_integer;
  type t_expressions_type is table of expression_type index by pls_integer;

  type r_table_type is record(
    owner identifier_type
    ,table_name identifier_type
    ,package_name identifier_type
    -- columns that get a parameter and are part of the insert
    ,insert_columns t_identifiers_type
    ,insert_defaults t_expressions_type
    -- columns of the table's %rowtype, in column order
    ,row_columns t_identifiers_type
  );


  -- 'my_table' -> 'MY_TABLE', '"MyTable"' -> 'MyTable'
  function normalize_name(
    i_name varchar2
  ) return varchar2 as
  begin

    if i_name like '"%"' then
      return substr(i_name, 2, length(i_name) - 2);
    end if;

    return upper(trim(i_name));

  end normalize_name;


  -- 'MY_TABLE' -> 'my_table', 'MyTable' -> '"MyTable"'
  function format_identifier(
    i_name varchar2
  ) return varchar2 as
  begin

    if regexp_like(i_name, '^[A-Z][A-Z0-9_$#]*$') then
      return lower(i_name);
    end if;

    return '"' || i_name || '"';

  end format_identifier;


  function format_default(
    i_data_default varchar2
  ) return varchar2 as

    l_default expression_type := rtrim(ltrim(i_data_default, gc_whitespace), gc_whitespace);

  begin

    if l_default is null or upper(l_default) = 'NULL' then
      return 'null';
    end if;

    return l_default;

  end format_default;


  function read_table(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2
  ) return r_table_type as

    l_owner identifier_type := normalize_name(i_table_owner);
    l_table_name identifier_type := normalize_name(i_table_name);
    l_table r_table_type;

  begin

    l_table.owner := format_identifier(l_owner);
    l_table.table_name := format_identifier(l_table_name);
    l_table.package_name := format_identifier(
      case
        when i_package_name is not null
          then normalize_name(i_package_name)
        else
          substr(l_table_name, 1, 120) || '_BUILDER'
      end
    );

    -- data_default is a LONG, hence the cursor loop instead of bulk collect
    -- with SQL string functions.
    for r_column in (
      select
        c.column_name
        ,c.data_default
      from
        all_tab_cols c
      where
        c.owner = l_owner
        and c.table_name = l_table_name
        and c.virtual_column = 'NO'
        -- excludes system generated hidden columns (e.g. unused columns),
        -- but keeps invisible columns
        and c.user_generated = 'YES'
        and not exists (
          select null
          from all_tab_identity_cols i
          where
            i.owner = c.owner
            and i.table_name = c.table_name
            and i.column_name = c.column_name
            and i.generation_type = 'ALWAYS'
        )
      order by
        c.column_id nulls last
        ,c.internal_column_id
    ) loop
      l_table.insert_columns(l_table.insert_columns.count + 1) := format_identifier(r_column.column_name);
      l_table.insert_defaults(l_table.insert_defaults.count + 1) := format_default(r_column.data_default);
    end loop;

    if l_table.insert_columns.count = 0 then
      raise_application_error(
        -20001
        ,'No insertable columns found for ' || l_owner || '.' || l_table_name
         || '. Does the table exist and is it accessible?'
      );
    end if;

    for r_column in (
      select
        c.column_name
      from
        all_tab_cols c
      where
        c.owner = l_owner
        and c.table_name = l_table_name
        and c.hidden_column = 'NO'
      order by
        c.column_id
    ) loop
      l_table.row_columns(l_table.row_columns.count + 1) := format_identifier(r_column.column_name);
    end loop;

    return l_table;

  end read_table;


  function get_parameters(
    i_table r_table_type
  ) return clob as

    l_parameters clob;

  begin

    for i in 1 .. i_table.insert_columns.count loop
      l_parameters := l_parameters
        || case when i > 1 then gc_newline || '    ,' end
        || i_table.insert_columns(i)
        || ' in ' || i_table.owner || '.' || i_table.table_name || '.' || i_table.insert_columns(i) || '%type'
        || ' default ' || i_table.insert_defaults(i);
    end loop;

    return l_parameters;

  end get_parameters;


  function get_list(
    i_identifiers t_identifiers_type
    ,i_prefix varchar2 default null
  ) return clob as

    l_list clob;

  begin

    for i in 1 .. i_identifiers.count loop
      l_list := l_list
        || case when i > 1 then gc_newline || '      ,' end
        || i_prefix || i_identifiers(i);
    end loop;

    return l_list;

  end get_list;


  function get_package_spec_sql(
    i_table r_table_type
  ) return clob as
  begin

    return builder_pattern_templates.package_spec_source(
      i_owner => i_table.owner
      ,i_table_name => i_table.table_name
      ,i_package_name => i_table.package_name
      ,i_parameters => get_parameters(i_table)
    );

  end get_package_spec_sql;


  function get_package_body_sql(
    i_table r_table_type
  ) return clob as
  begin

    return builder_pattern_templates.package_body_source(
      i_owner => i_table.owner
      ,i_table_name => i_table.table_name
      ,i_package_name => i_table.package_name
      ,i_parameters => get_parameters(i_table)
      ,i_column_list => get_list(i_table.insert_columns)
      ,i_build_values => get_list(i_table.insert_columns, 'build.')
      ,i_build_row_values => get_list(i_table.insert_columns, 'build_row.')
      ,i_returning_list => get_list(i_table.row_columns)
    );

  end get_package_body_sql;


  function generate_builder_package_sql(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2 default null
  ) return clob as

    l_table r_table_type;

  begin

    l_table := read_table(
      i_table_owner => i_table_owner
      ,i_table_name => i_table_name
      ,i_package_name => i_package_name
    );

    -- Runnable as a script (SQL*Plus, SQLcl, SQL Developer)
    return get_package_spec_sql(l_table)
      || gc_newline || '/' || gc_newline || gc_newline
      || get_package_body_sql(l_table)
      || gc_newline || '/' || gc_newline;

  end generate_builder_package_sql;


  procedure generate_builder_package(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2 default null
  ) as

    l_table r_table_type;

  begin

    l_table := read_table(
      i_table_owner => i_table_owner
      ,i_table_name => i_table_name
      ,i_package_name => i_package_name
    );

    execute immediate get_package_spec_sql(l_table);
    execute immediate get_package_body_sql(l_table);

  end generate_builder_package;

end builder_pattern_generator;
/
