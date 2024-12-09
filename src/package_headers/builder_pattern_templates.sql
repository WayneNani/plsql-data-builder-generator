create or replace package builder_pattern_templates as


  gco_object_source clob := q'{
create or replace type #OWNER#.#TABLE_NAME#_builder_type authid current_user as object (
  #ATTRIBUTES#,
  constructor function #TABLE_NAME#_builder_type return self as result,
  member procedure build(self in #TABLE_NAME#_builder_type),
  #MEMBER_FUNCTIONS#
);
}';

  gco_object_body_source clob := q'{
create or replace type body #OWNER#.#TABLE_NAME#_builder_type as
  constructor function #TABLE_NAME#_builder_type return self as result as
  begin
    return;
  end #TABLE_NAME#_builder_type;

  member procedure build(self in #TABLE_NAME#_builder_type) as
  begin
    insert into #OWNER#.#TABLE_NAME#(#COLUMN_LIST#)
    values (#COLUMN_LIST_WITH_SELF#);
  end build;

  #MEMBER_FUNCTIONS#
end;
}';


  gco_member_function_header_source clob := q'{
  member function with_#COLUMN_NAME#(self in #TABLE_NAME#_builder_type, i_#COLUMN_NAME# #DATA_TYPE#) return #TABLE_NAME#_builder_type
}';

  gco_member_function_body_source clob := q'{
  member function with_#COLUMN_NAME#(self in #TABLE_NAME#_builder_type, i_#COLUMN_NAME# #DATA_TYPE#) return #TABLE_NAME#_builder_type is
    l_self #TABLE_NAME#_builder_type := self;
  begin
    l_self.#COLUMN_NAME# := i_#COLUMN_NAME#;
    return l_self;
  end with_#COLUMN_NAME#;
}';


  function builder_object_header_source(
    i_owner varchar2
    ,i_table_name varchar2
    ,i_attributes clob
    ,i_member_functions clob
  ) return clob;

  function builder_object_body_source(
    i_owner varchar2
    ,i_table_name varchar2
    ,i_column_list clob
    ,i_column_list_with_self clob
    ,i_member_functions clob
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