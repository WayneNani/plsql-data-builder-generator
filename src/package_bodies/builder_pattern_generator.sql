create or replace package body builder_pattern_generator as

  function get_table_columns(
    i_table_owner varchar2
    ,i_table_name varchar2
  ) return t_table_columns_type as

    l_table_columns t_table_columns_type;

  begin

    select
      column_id
      ,lower(column_name) as column_name
      ,lower(data_type) as data_type
      ,case
         when (data_type not like '%VARCHAR%' and data_length = 4000)
              or data_type like '%TIMESTAMP%'
           then null
         else
           '(' ||
           case
             when data_precision is not null
               then to_char(data_precision) || ', ' || to_char(data_scale)
             else
               to_char(data_length)
           end
          || ')'
      end as data_type_scale
    bulk collect into
      l_table_columns
    from
      all_tab_cols
    where
      table_name = upper(i_table_name)
      and owner = upper(i_table_owner)
      and virtual_column = 'NO'
    order by
      column_id;

    return l_table_columns;

  end get_table_columns;


  function get_attributes(
    i_table_columns t_table_columns_type
  ) return clob as

    l_attributes clob;

  begin

    select listagg(column_name || ' ' || data_type || data_type_scale, ',' || chr(13)) within group (order by column_id)
    into l_attributes
    from table(i_table_columns);

    return l_attributes;

  end get_attributes;


  function get_member_functions_body(
    i_table_name varchar2
    ,i_table_columns t_table_columns_type
  ) return clob as

    l_member_functions clob;

  begin

    select
      listagg(
        builder_pattern_templates.member_function_body_source(
            i_table_name => i_table_name
            ,i_column_name => column_name
            ,i_column_data_type => data_type
        )
        ,chr(13)
      ) within group (order by column_id)
    into l_member_functions
    from table(i_table_columns);

    return l_member_functions;

  end get_member_functions_body;

  function get_member_functions_header(
    i_table_name varchar2
    ,i_table_columns t_table_columns_type
  ) return clob as

    l_member_functions clob;

  begin

    select
      listagg(
        builder_pattern_templates.member_function_header_source(
            i_table_name => i_table_name
            ,i_column_name => column_name
            ,i_column_data_type => data_type
        )
        ,',' || chr(13)
      ) within group (order by column_id)
    into l_member_functions
    from table(i_table_columns);

    return l_member_functions;

  end get_member_functions_header;


  function get_column_list(
    i_table_columns t_table_columns_type
  ) return clob as

    l_column_list clob;

  begin

    select listagg(column_name, ', ') within group (order by column_id)
    into l_column_list
    from table(i_table_columns);

    return l_column_list;

  end get_column_list;


  function get_column_list_with_self(
    i_table_columns t_table_columns_type
  ) return clob as

    l_column_list clob;

  begin

    select listagg('self.' || column_name, ', ') within group (order by column_id)
    into l_column_list
    from table(i_table_columns);

    return l_column_list;

  end get_column_list_with_self;


  function generate_builder_object_sql(
    i_table_owner varchar2
    ,i_table_name varchar2
  ) return clob as

    l_table_columns t_table_columns_type;
    l_attributes clob;
    l_member_functions_body clob;
    l_member_functions_header clob;
    l_source clob;
    l_column_list clob;
    l_column_list_with_self clob;

  begin

    l_table_columns := get_table_columns(
      i_table_owner => i_table_owner
      ,i_table_name => i_table_name
    );

    l_attributes := get_attributes(
      i_table_columns => l_table_columns
    );
    l_member_functions_body := get_member_functions_body(
      i_table_name => i_table_name
      ,i_table_columns => l_table_columns
    );
    l_member_functions_header := get_member_functions_header(
      i_table_name => i_table_name
      ,i_table_columns => l_table_columns
    );

    l_column_list := get_column_list(
      i_table_columns => l_table_columns
    );

    l_column_list_with_self := get_column_list_with_self(
      i_table_columns => l_table_columns
    );

    l_source := l_source
                  || chr(13)
                  || chr(13)
                  || builder_pattern_templates.BUILDER_OBJECT_HEADER_SOURCE(
                    I_TABLE_NAME => i_table_name
                    ,I_ATTRIBUTES => l_attributes
                    ,I_MEMBER_FUNCTIONS => l_member_functions_header
                  )
                  || chr(13)
                  || chr(13)
                  || builder_pattern_templates.BUILDER_OBJECT_body_SOURCE(
                    I_TABLE_NAME => i_table_name
                    ,I_COLUMN_LIST => l_column_list
                    ,i_column_list_with_self => l_column_list_with_self
                    ,I_MEMBER_FUNCTIONS => l_member_functions_body
                  );

    return l_source;

  end generate_builder_object_sql;

end builder_pattern_generator;
/
