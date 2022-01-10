# sumo-sqlquery-powershell
A powershell script to run sql queries and return the output in JSON format suitable to run as a Sumologic script check.

This script is designed to execute as a sql script check and the output will be captured as log events in sumologic.

To use:
- ensure your sumo installed collector runs with a user account with db permissions for windows sql server authentication, or alternately you will need to add authentication to the db connection code and securely store user/pwd in the script environment.
- place any queries you want to run in the queries.ps1 file
- ensure you enabled script sources for the collector in user.properties
- create a sumologic script source that executes the powershell script on a schedule

Each query will be executed and the results posted to sumo as a log event. Each result row will be posted in log event as a json formatted array.

## parsing the results in sumo
If there is ONE result row (say with the sql properties query). We could parse it like using a single row per event method.

for example for this query:
```
_source=db_*  _sourcecategory=*db* results "SQL Properties"
// note this next line not required for events > 9:45 am 12 dec AEDT
| parse "RESULTS: name=* db=* server=* results= *" as name,db,server,results nodrop
| where name = "SQL Properties"
```
we could then parse the row several different ways.
a) json auto parse will work and parse out each key using it's nested json name e.g
```
| json auto field=results
| where %"results.database_name" = "master"
```

b) we can json parse each sub key column name we want to use such as:
```
| json field=results "results.database_name" as database_name
```

c) the fastest query to run. we just parse the _raw field like this:
```
| parse "\"db_suspect\":*,\"db_restoring\":*,\"db_online\":*,\"cpu_count\":*,\"hardware_type\":\"*\",\"db_recoveryPending\":*,\"server_memory\":*,\"db_recovering\":0,\"measurement\":\"*\",\"sku\":\"*\",\"database_name\":\"*\",\"engine_edition\":*,\"sql_version\":\"*\",\"uptime\":*,\"sql_instance\":\"*\",\"db_offline\":*}" as db_suspect,db_restoring,db_online,cpu_count,hardware_type,db_recoveryPending,server_memory,sqlserver_server_properties,sku,database_name,engine_edition,sql_version,uptime,sql_instance,db_offline
```

If there are MORE THAN ONE result rows possible we must use parse regex multi to create one new event per result row.

```
(_source=db_*  _sourcecategory=*db* results) "Table size"
| parse "RESULTS: name=* db=* server=* results= *" as name,db,server,results nodrop
// split out each result row into a new event with parse multi
| parse regex field=results "\"TableName\":\"(?<TableName>[^\"]+)\",\"Used_MB\":(?<Used_MB>[^\",]+),\"Total_MB\":(?<Total_MB>[^\",]+),\"Total_GB\":(?<Total_GB>[^\",]+),\"Unused_MB\":(?<Unused_MB>[^\",]+),\"SchemaName\":\"(?<SchemaName>[^\",]+)\",\"RowCounts\":(?<RowCounts>[^\",\}]+)" multi
| timeslice by 1m
| count by _timeslice,tablename,used_mb,total_mb,total_gb,unused_mb,schemaname,rowcounts | fields -_count
| used_mb + unused_mb as total_mb
```