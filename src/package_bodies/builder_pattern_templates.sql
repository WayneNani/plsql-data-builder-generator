create or replace package body builder_pattern_templates as

  function builder_object_header_source(
    i_table_name varchar2
    ,i_member_functions clob
  ) return clob as

    l_source clob := gco_object_source;

  begin

    l_source := replace(l_source, '#TABLE_NAME#', i_table_name);
    l_source := replace(l_source, '#MEMBER_FUNCTIONS#', i_member_functions);

    return l_source;

  end builder_object_header_source;


  function builder_object_body_source(
    i_table_name varchar2
    ,i_member_functions clob
  ) return clob as

    l_source clob := gco_object_body_source;

  begin

    l_source := replace(l_source, '#TABLE_NAME#', i_table_name);
    l_source := replace(l_source, '#MEMBER_FUNCTIONS#', i_member_functions);

    return l_source;

  end builder_object_body_source;


  function parameter_object_header_source(
    i_table_name varchar2
    ,i_attributes clob
  ) return clob as

    l_source clob := gco_parameter_object_header_source;

  begin

    l_source := replace(l_source, '#TABLE_NAME#', i_table_name);
    l_source := replace(l_source, '#ATTRIBUTES#', i_attributes);

    return l_source;

  end parameter_object_header_source;


  function parameter_object_body_source(
    i_table_name varchar2
    ,i_attributes clob
  ) return clob as

    l_source clob := gco_parameter_object_body_source;

  begin

    l_source := replace(l_source, '#TABLE_NAME#', i_table_name);
    l_source := replace(l_source, '#ATTRIBUTES#', i_attributes);

    return l_source;

  end parameter_object_body_source;


  function member_function_header_source(
    i_table_name varchar2
    ,i_column_name varchar2
    ,i_column_data_type varchar2
  ) return clob as

    l_source clob := gco_member_function_header_source;

  begin

    l_source := replace(l_source, '#TABLE_NAME#', i_table_name);
    l_source := replace(l_source, '#COLUMN_NAME#', i_column_name);
    l_source := replace(l_source, '#DATA_TYPE#', i_column_data_type);

    return l_source;

  end member_function_header_source;

  function member_function_body_source(
    i_table_name varchar2
    ,i_column_name varchar2
    ,i_column_data_type varchar2
  ) return clob as

    l_source clob := gco_member_function_body_source;

  begin

    l_source := replace(l_source, '#TABLE_NAME#', i_table_name);
    l_source := replace(l_source, '#COLUMN_NAME#', i_column_name);
    l_source := replace(l_source, '#DATA_TYPE#', i_column_data_type);

    return l_source;

  end member_function_body_source;

end builder_pattern_templates;