param (
    [Parameter(Mandatory = $false)] $query_file = './queries.ps1',
    [Parameter(Mandatory = $false)] $output_line_per = 'query'

)

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

function sql {
    param (
        [Parameter(Mandatory = $true)] $sqlText,
        [Parameter(Mandatory = $false)] $database = "master",
        [Parameter(Mandatory = $false)] $server = "localhost"
    )
    $connection = new-object System.Data.SqlClient.SQLConnection("Data Source=$server; Integrated Security=SSPI; Initial Catalog=$database");
    try {
        $cmd = new-object System.Data.SqlClient.SqlCommand($sqlText, $connection);
    }
    catch {
        Write-Error "SQL client error"
        Write-Error $_
        break
    }
    tolog -level 'debug' -event $sqlText

    ## Write-Host "connecting to $server, database: $database"
    ## write-host $sqlText
    $connection.Open();
    $reader = $cmd.ExecuteReader()

    $results = @()
    while ($reader.Read()) {
        $row = @{}
        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $row[$reader.GetName($i)] = $reader.GetValue($i)
        }
        $results += new-object psobject -property $row            
    }
    $connection.Close();

    , $results

}

function tolog {
    param (
        [Parameter(Mandatory = $false)] $level = 'info',
        [Parameter(Mandatory = $true)] $event
    )

    if ($level -match 'info|warn|err|fatal') {
        write-host "$(Get-Date -format 'yyyy-MM-dd HH:mm:ss K') [$level] $($event | out-string)"

    }
    else {
        Write-Verbose "$(Get-Date -format 'yyyy-MM-dd HH:mm:ss K') [$level] $($event | out-string)"
    }
    #"$(Get-Date -format 'yyyy-MM-dd hh:mm:ss K') [$level] $($event | out-string)`n" | out-file -FilePath some_file.txt -Encoding ascii

}

$queries = @()

#  dot source the queries file
. "$scriptDir\$query_file"

tolog -level "info" -event "starting script: $($queries.count) to run from $query_file"
$n = 0

foreach ( $query in $queries) {
    $n +=1
    tolog -level "debug" -event "executing query job: $($query.name) on $query.server"
    # remove line breaks from query
    $q = ($query.query -replace "--.+"," ") -replace "`n"," "

    try {
        $data = sql -sqlText $q -database $query.database -server $query.server
        tolog -level "info" -event "query $($n): $($query.name) on $($query.server) $($data.count) rows."
        if ($output_line_per -eq 'query') {
            tolog -level 'info' -event "RESULTS: name=$($query.name) db=$($query.database) server=$($query.server) results= { `"results`": $($data | convertto-json -Compress ) }"
        } else {
            $i = 0
            foreach ($row in $data) {
                $i +=1
                tolog -level 'info' -event "RESULTS: name=$($query.name) db=$($query.database) server=$($query.server) row=$i/$($data.count) { `"row`": $($row | convertto-json -Compress ) }"
            }
        }
     
    }
    catch {
        tolog -level 'error' -event "FAILED: name=$($query.name) db=$($query.database) server=$($query.server) error=$($_)"
    }
}
 
