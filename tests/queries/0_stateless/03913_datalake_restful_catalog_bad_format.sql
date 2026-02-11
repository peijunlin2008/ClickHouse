-- Tags: no-parallel, no-fasttest

SET allow_experimental_database_iceberg = 1;
SET show_data_lake_catalogs_in_system_tables = 1;

DROP DATABASE IF EXISTS 03913_database;
CREATE DATABASE 03913_database 
ENGINE = DataLakeCatalog('http://rest:8181/v1', 'admin', 'password')
SETTINGS 
    catalog_type = 'rest', 
    auth_header = 'wrong.header', -- wrong header will make `select ... from system.tables` fail
    storage_endpoint = 'http://minio:9000/lakehouse', 
    warehouse = 'demo';

select * from system.tables where database = '03913_database' and engine = 'MergeTree';

DROP DATABASE 03913_database;
