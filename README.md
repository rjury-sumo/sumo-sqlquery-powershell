# sumo-sqlquery-powershell
A powershell script to run sql queries and return the output in JSON format suitable to run as a Sumologic script check.

This script is designed to execute as a sql script check and the output will be captured as log events in sumologic.

To use:
- ensure your sumo installed collector runs with a user account with db permissions for windows sql server authentication, or alternately you will need to add authentication to the db connection code and securely store user/pwd in the script environment.
- place any queries you want to run in the queries.ps1 file
- ensure you enabled script sources for the collector in user.properties
- create a sumologic script source that executes the powershell script on a schedule

Each query will be executed and the results posted to sumo as a log event. 

# Example of a script source JSON
```
{  "name":"db_standard_info", "category":"aws/prod/db/sqlserver", "description":"mssql queries script source", "charsetName":"UTF-8", "timestampParsing":true, "timestampFormats":[], "multiLineProcessing":true, "forceTimeZone":false, "filters":[], "cutoffTimestamp":0, "fields":{ }, "dryRunMode":false, "script":null, "cronExpression":"0 0 0 * * ?", "timeout":0, "workingDir":"", "commands":["powershell","-NoLogo","-NonInteractive","-ExecutionPolicy","RemoteSigned","-WindowStyle","Hidden","-File"], "scriptFile":"C:\\Program Files\\Sumo Logic Collector\\sql_query_sumo_logic.ps1", "extension":"ps1", "sourceType":"Script" }
```

# per query or per row result logging
there are TWO options for results logging output.

## 1. one log event per resut row
```
  .\sql_query.demo.ps1 -output_line_per 'row' 
```

Each result row will be posted in log event with some header info and a 'row' json object.
This is a useful if you have queries with large numbers of rows or results totalling > 64k the max sumo log size.

```
2022-01-26 03:43:36 +00:00 [info] RESULTS: name=SQL Properties db=master server=localhost row=1/1 { "row": {"db_suspect":0,"db_restoring":0,"db_onli
ne":4,"cpu_count":2,"hardware_type":"HYPERVISOR","db_recoveryPending":0,"server_memory":4193904,"db_recovering":0,"measurement":"sqlserver_server_pr
operties","sku":"Express Edition (64-bit)","database_name":"master","engine_edition":4,"sql_version":"15.0.2000.5","uptime":32,"sql_instance":"EC2AM
AZ-Q1OOJPP:SQLEXPRESS","db_offline":0} } 
```

Parsing this output is quite straightforward since we can parse each event row in sumo easily. 
```
parse "RESULTS: name=* db=* server=* row=* {*}" as name,db,server,results,rowcount,row nodrop
```

## 2. one log event per query (default)
This is more compact in terms of ingest size but requires more complex parsing potentially.
``` 
.\sql_query.demo.ps1 

 2022-01-26 03:48:39 +00:00 [info] RESULTS: name=SQL Properties db=master server=localhost results= { "results": {"db_suspect":0,"db_restoring":0,"db
_online":4,"cpu_count":2,"hardware_type":"HYPERVISOR","db_recoveryPending":0,"server_memory":4193904,"db_recovering":0,"measurement":"sqlserver_serv
er_properties","sku":"Express Edition (64-bit)","database_name":"master","engine_edition":4,"sql_version":"15.0.2000.5","uptime":37,"sql_instance":"
EC2AMAZ-Q1OOJPP:SQLEXPRESS","db_offline":0} } 
```

### parsing the results in sumo
**recommended**
- create a field extraction rule in sumologic to parse the basic event fields from your database qury results with this parse logic:
```
parse "RESULTS: name=* db=* server=* results= *" as name,db,server,results nodrop
```
The results element is a json formatted array of results.

### queries with one result row
If there is ONE result row (say with the sql properties query). We could parse it like using a single row per event method.

for example for this query:
```
_source=db_*  _sourcecategory=*db* results "SQL Properties"
// you might have this line as an FER in which case not required
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
### queries with 1..many result rows
If there are MORE THAN ONE result rows possible we must use parse regex multi to create one new event per result row.

### one approach - parse into row json objects
We can parse multi to get one row event for each result row like this:
```
| parse regex field=results "[\[,](?<row>\{\".*?[\d\"]\})[,$]" multi
| json auto field=row
```

### another approach - parse regex multi each row directly
We can also do it this way this is trickier to write the expression as text columns have "" and numeric ones do not.
```
(_source=db_*  _sourcecategory=*db* results) "Table size"
| parse "RESULTS: name=* db=* server=* results= *" as name,db,server,results nodrop
// split out each result row into a new event with parse multi
| parse regex field=results "\"TableName\":\"(?<TableName>[^\"]+)\",\"Used_MB\":(?<Used_MB>[^\",]+),\"Total_MB\":(?<Total_MB>[^\",]+),\"Total_GB\":(?<Total_GB>[^\",]+),\"Unused_MB\":(?<Unused_MB>[^\",]+),\"SchemaName\":\"(?<SchemaName>[^\",]+)\",\"RowCounts\":(?<RowCounts>[^\",\}]+)" multi
| timeslice by 1m
| count by _timeslice,tablename,used_mb,total_mb,total_gb,unused_mb,schemaname,rowcounts | fields -_count
| used_mb + unused_mb as total_mb
```

