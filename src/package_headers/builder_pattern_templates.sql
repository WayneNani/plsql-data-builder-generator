create or replace package builder_pattern_templates as

  gco_parameter_object_header_source clob := q'{
create or replace type #TABLE_NAME#_columns_type as object (
  #ATTRIBUTES#,
  constructor function #TABLE_NAME#_columns_type return self as result
);
}';

  gco_parameter_object_body_source clob := q'{
create or replace type body #TABLE_NAME#_columns_type as
  constructor function #TABLE_NAME#_columns_type return self as result as
  begin
    return;
  end #TABLE_NAME#_columns_type;
end;
}';

  gco_object_source clob := q'{
create or replace type #TABLE_NAME#_builder_type authid current_user as object (
  l_columns #TABLE_NAME#_columns_type,
  constructor function #TABLE_NAME#_builder_type return self as result,
  member procedure build(self in #TABLE_NAME#_builder_type),
  #MEMBER_FUNCTIONS#
);
}';

  gco_object_body_source clob := q'{
create or replace type body #TABLE_NAME#_builder_type as
  constructor function #TABLE_NAME#_builder_type return self as result as
  begin
    self.l_columns := #TABLE_NAME#_columns_type();

    return;
  end #TABLE_NAME#_builder_type;

  member procedure build(self in #TABLE_NAME#_builder_type) as
  begin
    insert into #TABLE_NAME#
    values self.l_columns;
  end build;

  #MEMBER_FUNCTIONS#
end;
}';


  gco_member_function_header_source clob := q'{
member function with_#COLUMN_NAME#(self in out #TABLE_NAME#_builder_type, i_#COLUMN_NAME# #DATA_TYPE#) return #TABLE_NAME#_builder_type
}';

  gco_member_function_body_source clob := q'{
member function with_#COLUMN_NAME#(self in out #TABLE_NAME#_builder_type, i_#COLUMN_NAME# #DATA_TYPE#) return #TABLE_NAME#_builder_type is
begin
  self.l_columns.#COLUMN_NAME# := i_#COLUMN_NAME#;
  return self;
end with_#COLUMN_NAME#;
}';


  function builder_object_header_source(
    i_table_name varchar2
    ,i_member_functions clob
  ) return clob;

  function builder_object_body_source(
    i_table_name varchar2
    ,i_member_functions clob
  ) return clob;


  function parameter_object_header_source(
    i_table_name varchar2
    ,i_attributes clob
  ) return clob;


  function parameter_object_body_source(
    i_table_name varchar2
    ,i_attributes clob
  ) return clob;


  function member_function_header_source(
    i_table_name varchar2
    ,i_column_name varchar2
    ,i_column_data_type varchar2
  ) return clob;

  function member_function_body_source(
    i_table_name varchar2
    ,i_column_name varchar2
    ,i_column_data_type varchar2
  ) return clob;

end builder_pattern_templates;