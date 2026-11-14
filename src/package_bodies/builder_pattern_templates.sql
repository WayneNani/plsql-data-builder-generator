create or replace package body builder_pattern_templates as

  -- Fixed names are replaced first, so that generated content (e.g. column
  -- default expressions) is never touched by a later replacement.
  function fill_names(
    i_template clob
    ,i_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2
  ) return clob as

    l_source clob := i_template;

  begin

    l_source := replace(l_source, '#OWNER#', i_owner);
    l_source := replace(l_source, '#TABLE_NAME#', i_table_name);
    l_source := replace(l_source, '#PACKAGE_NAME#', i_package_name);

    return l_source;

  end fill_names;


  function package_spec_source(
    i_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2
    ,i_parameters clob
  ) return clob as

    l_source clob;

  begin

    l_source := fill_names(
      i_template => gco_package_spec_source
      ,i_owner => i_owner
      ,i_table_name => i_table_name
      ,i_package_name => i_package_name
    );
    l_source := replace(l_source, '#PARAMETERS#', i_parameters);

    return l_source;

  end package_spec_source;


  function package_body_source(
    i_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2
    ,i_parameters clob
    ,i_column_list clob
    ,i_build_values clob
    ,i_build_row_values clob
    ,i_returning_list clob
  ) return clob as

    l_source clob;

  begin

    l_source := fill_names(
      i_template => gco_package_body_source
      ,i_owner => i_owner
      ,i_table_name => i_table_name
      ,i_package_name => i_package_name
    );
    l_source := replace(l_source, '#COLUMN_LIST#', i_column_list);
    l_source := replace(l_source, '#BUILD_VALUES#', i_build_values);
    l_source := replace(l_source, '#BUILD_ROW_VALUES#', i_build_row_values);
    l_source := replace(l_source, '#RETURNING_LIST#', i_returning_list);
    l_source := replace(l_source, '#PARAMETERS#', i_parameters);

    return l_source;

  end package_body_source;

end builder_pattern_templates;
/
