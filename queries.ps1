#$queries = @()

<#
$queries += @{
    'name' = 'query name';
    'query' = @"
        YOUR
        QUERY
        "@;
    'database' = 'master';
    'server' = 'localhost';
}
#>

$queries += @{
    'name' = 'database free space';
    'query' = @"
SELECT DB_NAME(database_id) AS database_name, 
type_desc, 
name AS FileName, 
size/128.0 AS CurrentSizeMB
FROM sys.master_files
WHERE database_id > 6 AND type IN (0,1)
"@;
    'database' = 'master';
    'server' = 'localhost';
}



$queries += @{
    'name' = 'SQL Properties';
    'query' = @"
    SET DEADLOCK_PRIORITY -10;
    DECLARE
           @SqlStatement AS nvarchar(max) = ''
           ,@EngineEdition AS tinyint = CAST(SERVERPROPERTY('EngineEdition') AS int)
            
    IF @EngineEdition = 8  /*Managed Instance*/
          SET @SqlStatement =  'SELECT TOP 1 ''sqlserver_server_properties'' AS [measurement],
                REPLACE(@@SERVERNAME,''\'','':'') AS [sql_instance],
                DB_NAME() as [database_name],
                    virtual_core_count AS cpu_count,
                            (SELECT process_memory_limit_mb FROM sys.dm_os_job_object) AS server_memory,
                            sku,
                            @EngineEdition AS engine_edition,
                            hardware_generation AS hardware_type,
                            reserved_storage_mb AS total_storage_mb,
                            (reserved_storage_mb - storage_space_used_mb) AS available_storage_mb,
                            (select DATEDIFF(MINUTE,sqlserver_start_time,GETDATE()) from sys.dm_os_sys_info) as uptime,
                SERVERPROPERTY(''ProductVersion'') AS sql_version,
                db_online,
                db_restoring,
                db_recovering,
                db_recoveryPending,
                db_suspect
                FROM    sys.server_resource_stats
                CROSS APPLY
                (SELECT  SUM( CASE WHEN state = 0 THEN 1 ELSE 0 END ) AS db_online,
                                     SUM( CASE WHEN state = 1 THEN 1 ELSE 0 END ) AS db_restoring,
                                     SUM( CASE WHEN state = 2 THEN 1 ELSE 0 END ) AS db_recovering,
                                     SUM( CASE WHEN state = 3 THEN 1 ELSE 0 END ) AS db_recoveryPending,
                                     SUM( CASE WHEN state = 4 THEN 1 ELSE 0 END ) AS db_suspect,
                                     SUM( CASE WHEN state = 6 or state = 10 THEN 1 ELSE 0 END ) AS db_offline
                            FROM    sys.databases
                ) AS dbs	
                ORDER BY start_time DESC';
    IF @EngineEdition = 5  /*Azure SQL DB*/
       SET @SqlStatement =  'SELECT	''sqlserver_server_properties'' AS [measurement],
                REPLACE(@@SERVERNAME,''\'','':'') AS [sql_instance],
                DB_NAME() as [database_name],
                            (SELECT count(*) FROM sys.dm_os_schedulers WHERE status = ''VISIBLE ONLINE'') AS cpu_count,
                            (SELECT process_memory_limit_mb FROM sys.dm_os_job_object) AS server_memory,
                            slo.edition as sku,
                            @EngineEdition  AS engine_edition,
                            slo.service_objective AS hardware_type,
                CASE 
                     WHEN slo.edition = ''Hyperscale'' then NULL 
                     ELSE  cast(DATABASEPROPERTYEX(DB_NAME(),''MaxSizeInBytes'') as bigint)/(1024*1024)  
                END AS total_storage_mb,
                CASE
                     WHEN slo.edition = ''Hyperscale'' then NULL
                     ELSE
                    (cast(DATABASEPROPERTYEX(DB_NAME(),''MaxSizeInBytes'') as bigint)/(1024*1024)-
                        (select  SUM(size/128 - CAST(FILEPROPERTY(name, ''SpaceUsed'') AS int)/128)	FROM sys.database_files )
                    )	
                END AS available_storage_mb,   
                            (select DATEDIFF(MINUTE,sqlserver_start_time,GETDATE()) from sys.dm_os_sys_info)  as uptime
                FROM     sys.databases d
                -- sys.databases.database_id may not match current DB_ID on Azure SQL DB
                CROSS JOIN sys.database_service_objectives slo
                WHERE d.name = DB_NAME() AND slo.database_id = DB_ID()';
    ELSE IF @EngineEdition IN (2,3,4) /*Standard,Enterprise,Express*/
    BEGIN
            DECLARE @MajorMinorVersion AS int = CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') as nvarchar),4) AS int)*100 + CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') as nvarchar),3) AS int)
            DECLARE @Columns AS nvarchar(MAX) = ''
            IF @MajorMinorVersion >= 1050
                    SET @Columns = N',CASE [virtual_machine_type_desc]
                            WHEN ''NONE'' THEN ''PHYSICAL Machine''
                            ELSE [virtual_machine_type_desc]
                    END AS [hardware_type]';
            ELSE /*data not available*/
                    SET @Columns = N',''<n/a>'' AS [hardware_type]';
      
            SET @SqlStatement =  'SELECT	''sqlserver_server_properties'' AS [measurement],
                REPLACE(@@SERVERNAME,''\'','':'') AS [sql_instance],
                DB_NAME() as [database_name],
                    [cpu_count]
                        ,(SELECT [total_physical_memory_kb] FROM sys.[dm_os_sys_memory]) AS [server_memory]
                        ,CAST(SERVERPROPERTY(''Edition'') AS NVARCHAR) AS [sku]
                        ,@EngineEdition AS [engine_edition]
                        ,DATEDIFF(MINUTE,[sqlserver_start_time],GETDATE()) AS [uptime]
                        ' + @Columns + ',
                SERVERPROPERTY(''ProductVersion'') AS sql_version,
                        db_online,
                        db_restoring,
                        db_recovering,
                        db_recoveryPending,
                        db_suspect,
                        db_offline
                   FROM sys.[dm_os_sys_info]
                CROSS APPLY
                        (        SELECT  SUM( CASE WHEN state = 0 THEN 1 ELSE 0 END ) AS db_online,
                                            SUM( CASE WHEN state = 1 THEN 1 ELSE 0 END ) AS db_restoring,
                                            SUM( CASE WHEN state = 2 THEN 1 ELSE 0 END ) AS db_recovering,
                                            SUM( CASE WHEN state = 3 THEN 1 ELSE 0 END ) AS db_recoveryPending,
                                            SUM( CASE WHEN state = 4 THEN 1 ELSE 0 END ) AS db_suspect,
                                            SUM( CASE WHEN state = 6 or state = 10 THEN 1 ELSE 0 END ) AS db_offline
                                FROM    sys.databases
                        ) AS dbs';
           
     END
     EXEC sp_executesql @SqlStatement , N'@EngineEdition smallint', @EngineEdition = @EngineEdition;
    
"@;
    'database' = 'master';
    'server' = 'localhost';
}

$queries += @{
    'name'     = 'DB Size';
    'query'    = @"
SELECT d.NAME
, ROUND(SUM(CAST(mf.size AS bigint)) * 8 / 1024, 0) Size_MBs
, (SUM(CAST(mf.size AS bigint)) * 8 / 1024) / 1024 AS Size_GBs
FROM sys.master_files mf
INNER JOIN sys.databases d ON d.database_id = mf.database_id
WHERE d.database_id > 4 -- Skip system databases
GROUP BY d.NAME
ORDER BY d.NAME
"@;
    'database' = 'master';
    'server'   = 'localhost';
}

$queries += @{
    'name'     = 'Current Running Jobs';
    'query'    = @"
SELECT
--   ja.job_id,
-- jh.instance_id,
j.name AS job_name,
ja.start_execution_date AS job_start_execution_date,
-- Previous_executed_step_id ,  
ISNULL(last_executed_step_id, 0) + 1 AS current_executed_step_id,
datediff(mi, ja.last_executed_step_date, getdate()) as Current_Step_running_in_Minutes,
datediff(mi, ja.start_execution_date, getdate()) as Job_running_in_Minutes,
Js.step_name
FROM
msdb.dbo.sysjobactivity ja
LEFT JOIN
msdb.dbo.sysjobhistory jh
ON ja.job_history_id = jh.instance_id
JOIN
msdb.dbo.sysjobs j
ON ja.job_id = j.job_id
JOIN
msdb.dbo.sysjobsteps js
ON ja.job_id = js.job_id
AND ISNULL(ja.last_executed_step_id, 0) + 1 = js.step_id
WHERE
ja.session_id =
(
    SELECT
    TOP 1 session_id
    FROM
    msdb.dbo.syssessions
    ORDER BY
    agent_start_date DESC
)
AND start_execution_date is not null
AND stop_execution_date is null;
"@;
    'database' = 'master';
    'server'   = 'localhost';
}

<#
$queries += @{
    'name' = 'query name';
    'query' = @"
YOUR
QUERY
"@;
    'database' = 'master';
    'server' = 'no-existent-server';
}
#>