##################
### Pre block  ###
##################
Import-Module -Name Az.Accounts
Import-Module -Name Az.Sql

#Change these to suit your own Azure environment
$AzureCred = Get-AutomationPSCredential -Name "PRD_DWH_Auto"
$Source_ResourceGroupName="RG-SQLDWH" 
$Source_ServerName = "sql-datawarehouse-server"
$Source_DatabaseName = "sql-datawarehouse"
$Source_Subscription = "Production"
$RestorePointLabel = $Source_DatabaseName+"_"+(Get-Date -Format o)
$NewDatabaseName = $RestorePointLabel
Connect-AzAccount -SubscriptionID "a1234a6a-a123-1a23-ab1c-12ab3456c7" -Credential $AzureCred
Select-AzSubscription $Source_Subscription

##################
### Main block ###
##################
# Get DB
$DB = Get-AzSqlDatabase -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName -DatabaseName $Source_DatabaseName | Select-Object * | Where-Object {$_.DatabaseName -eq $Source_DatabaseName}
Write-Output $DB

# Bring online if currently paused
IF ($DB.status -eq "Paused")
{
	Write-Output "Bringing DWH Online"
    Resume-AzSqlDatabase -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName -DatabaseName $Source_DatabaseName  
	} ELSE {
    Write-Output "DWH is already Online"
}

# Create a new restore point
Write-Output "Creating new restore point: "$RestorePointLabel
New-AzSqlDatabaseRestorePoint -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName -DatabaseName $Source_DatabaseName -RestorePointLabel $NewDatabaseName
Write-Output "New restore point has been created: "$RestorePointLabel

# Verify the backup database name and backup date 
Get-AzSqlDatabaseRestorePoints -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName -DatabaseName $Source_DatabaseName | Select-Object RestorePointLabel | Where-Object {$_.RestorePointLabel -eq $RestorePointLabel}
$RestorePoint = Get-AzSqlDatabaseRestorePoints -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName -DatabaseName $Source_DatabaseName | Select-Object RestorePointLabel,RestorePointCreationDate | Where-object {$_.RestorePointLabel -eq $RestorePointLabel}
$PointInTime = $RestorePoint.RestorePointCreationDate
Write-Output "Restore point label:  "$RestorePoint.RestorePointLabel
Write-Output "Point in time used for restore: "$PointInTime

# Restore the database  
Write-Output "Restoring DWH"
Write-Output "Starting DWH restore of "$NewDatabaseName
Restore-AzSqlDatabase -FromPointInTimeBackup -PointInTime $PointInTime -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName -TargetDatabaseName $NewDatabaseName -ResourceId $DB.ResourceID
Write-Output "Completed DWH restore: "$NewDatabaseName

# Pause the new database
Write-Output "Pausing restored DWH: "$NewDatabaseName
Suspend-AzSqlDatabase -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName -DatabaseName $NewDatabaseName
Write-Output "Paused restored DWH: "$NewDatabaseName

# Remove old DWH, not prod or master
$excluded = "master",""
$excluded += $Source_DatabaseName
$excluded += $NewDatabaseName
$RemoveDatabase = Get-AzSqlDatabase -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName | Select-Object DatabaseName | Where-Object {$_.DatabaseName -notin $excluded}
Write-Output "Removing old DWH: "$RemoveDatabase.DatabaseName
Remove-AzSqlDatabase -ResourceGroupName $Source_ResourceGroupName -ServerName $Source_ServerName -DatabaseName $RemoveDatabase.DatabaseName
Write-Output "Removed old DWH: "$RemoveDatabase.DatabaseName

Write-Output "End of Refresh"