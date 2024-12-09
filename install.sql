set define on
set serveroutput on
set verify off
set feedback off
set linesize 240
set trimout on
set trimspool on

@@src/package_headers/builder_pattern_generator.sql
@@src/package_headers/builder_pattern_templates.sql

@@src/package_bodies/builder_pattern_generator.sql
@@src/package_bodies/builder_pattern_templates.sql

prompt ***************************
prompt You can start building now!
prompt ***************************