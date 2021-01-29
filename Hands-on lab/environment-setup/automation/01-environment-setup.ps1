Import-Module ".\environment-automation"

$InformationPreference = "Continue"

$subs = Get-AzSubscription | Select-Object -ExpandProperty Name
if($subs.GetType().IsArray -and $subs.length -gt 1){
        $subOptions = [System.Collections.ArrayList]::new()
        for($subIdx=0; $subIdx -lt $subs.length; $subIdx++){
                $opt = New-Object System.Management.Automation.Host.ChoiceDescription "$($subs[$subIdx])", "Selects the $($subs[$subIdx]) subscription."   
                $subOptions.Add($opt)
        }
        $selectedSubIdx = $host.ui.PromptForChoice('Enter the desired Azure Subscription for this lab','Copy and paste the name of the subscription to make your choice.', $subOptions.ToArray(),0)
        $selectedSubName = $subs[$selectedSubIdx]
        Write-Information "Selecting the $selectedSubName subscription"
        Select-AzSubscription -SubscriptionName $selectedSubName
}

$userName = ((az ad signed-in-user show) | ConvertFrom-JSON).UserPrincipalName
$resourceGroupName = Read-Host -Prompt "Enter the name of the resource group containing the Azure Synapse Analytics Workspace"
$sqlPassword = Read-Host -Prompt "Enter the SQL Administrator password you used in the deployment" -AsSecureString
$sqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($sqlPassword))
$uniqueId = Read-Host -Prompt "Enter the unique suffix you used in the deployment"

$subscriptionId = (Get-AzContext).Subscription.Id
$global:logindomain = (Get-AzContext).Tenant.Id

$templatesPath = ".\templates"
$sqlScriptsPath = ".\sql"
$workspaceName = "asaworkspace$($uniqueId)"
$dataLakeAccountName = "asadatalake$($uniqueId)"
$blobStorageAccountName = "asastore$($uniqueId)"
$keyVaultName = "asakeyvault$($uniqueId)"
$keyVaultSQLUserSecretName = "SQL-USER-ASA"
$sqlPoolName = "SQLPool01"
$sqlUserName = "asa.sql.admin"
$integrationRuntimeName = "AzureIntegrationRuntime01"
$sparkPoolName = "SparkPool01"
$amlWorkspaceName = "amlworkspace$($uniqueId)"

$global:synapseToken = ""
$global:synapseSQLToken = ""
$global:managementToken = ""

$global:tokenTimes = [ordered]@{
        Synapse = (Get-Date -Year 1)
        SynapseSQL = (Get-Date -Year 1)
        Management = (Get-Date -Year 1)
}

Get-AzResourceGroup -Name $resourceGroupName -ErrorVariable rgNotPresent -ErrorAction SilentlyContinue

if ($rgNotPresent)
{
    throw "The $($resourceGroupName) resource group does not exist in this subscription."
}

Write-Information "Assign Ownership on Synapse Workspace"
Assign-SynapseRole -WorkspaceName $workspaceName -RoleId "6e4bf58a-b8e1-4cc3-bbf9-d73143322b78" -PrincipalId "37548b2e-e5ab-4d2b-b0da-4d812f56c30e"  # Workspace Admin
Assign-SynapseRole -WorkspaceName $workspaceName -RoleId "7af0c69a-a548-47d6-aea3-d00e69bd83aa" -PrincipalId "37548b2e-e5ab-4d2b-b0da-4d812f56c30e"  # SQL Admin
Assign-SynapseRole -WorkspaceName $workspaceName -RoleId "c3a6d2f1-a26f-4810-9b0f-591308d5cbf1" -PrincipalId "37548b2e-e5ab-4d2b-b0da-4d812f56c30e"  # Apache Spark Admin

#add the permission to the datalake to workspace
$id = (Get-AzADServicePrincipal -DisplayName $workspacename).id
New-AzRoleAssignment -Objectid $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue;
New-AzRoleAssignment -SignInName $username -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue;

Write-Information "Setting Key Vault Access Policy"
Set-AzKeyVaultAccessPolicy -ResourceGroupName $resourceGroupName -VaultName $keyVaultName -UserPrincipalName $userName -PermissionsToSecrets set,delete,get,list

$ws = Get-Workspace $SubscriptionId $ResourceGroupName $WorkspaceName;
$upid = $ws.identity.principalid
Set-AzKeyVaultAccessPolicy -ResourceGroupName $resourceGroupName -VaultName $keyVaultName -ObjectId $upid -PermissionsToSecrets set,delete,get,list

Write-Information "Create SQL-USER-ASA Key Vault Secret"
$secretValue = ConvertTo-SecureString $sqlPassword -AsPlainText -Force
$secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $keyVaultSQLUserSecretName -SecretValue $secretValue

Write-Information "Create KeyVault linked service $($keyVaultName)"

$result = Create-KeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $keyVaultName
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create Integration Runtime $($integrationRuntimeName)"

$result = Create-IntegrationRuntime -TemplatesPath $templatesPath -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -Name $integrationRuntimeName -CoreCount 16 -TimeToLive 60
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create Data Lake linked service $($dataLakeAccountName)"

$dataLakeAccountKey = List-StorageAccountKeys -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName
$result = Create-DataLakeLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $dataLakeAccountName  -Key $dataLakeAccountKey
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create Blob Storage linked service $($blobStorageAccountName)"

$blobStorageAccountKey = List-StorageAccountKeys -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -Name $blobStorageAccountName
$result = Create-BlobStorageLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $blobStorageAccountName  -Key $blobStorageAccountKey
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Start the $($sqlPoolName) SQL pool if needed."

$result = Get-SQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName
if ($result.properties.status -ne "Online") {
    Control-SQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -Action resume
    Wait-ForSQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -TargetStatus Online
}

Write-Information "Setup $($sqlPoolName)"

$params = @{
        "PASSWORD" = $sqlPassword
        "DATALAKESTORAGEKEY" = $dataLakeAccountKey
        "DATALAKESTORAGEACCOUNTNAME" = $dataLakeAccountName
}

try
{
   $result = Execute-SQLScriptFile-SqlCmd -SQLScriptsPath $sqlScriptsPath -WorkspaceName $workspaceName -SQLPoolName "master" -SQLUserName $sqlUserName -SQLPassword $sqlPassword -FileName "00_master_setup" -Parameters $params
}
catch 
{
    write-host $_.exception
}

try
{
    $result = Execute-SQLScriptFile-SqlCmd -SQLScriptsPath $sqlScriptsPath -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -SQLUserName $sqlUserName -SQLPassword $sqlPassword -FileName "01_sqlpool01_mcw" -Parameters $params
}
catch 
{
    write-host $_.exception
}


$result

Write-Information "Create linked service for SQL pool $($sqlPoolName) with user asa.sql.admin"

$linkedServiceName = $sqlPoolName.ToLower()
$result = Create-SQLPoolKeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $linkedServiceName -DatabaseName $sqlPoolName `
                 -UserName "asa.sql.admin" -KeyVaultLinkedServiceName $keyVaultName -SecretName $keyVaultSQLUserSecretName
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create linked service for SQL pool $($sqlPoolName) with user asa.sql.workload01"

$linkedServiceName = "$($sqlPoolName.ToLower())_workload01"
$result = Create-SQLPoolKeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $linkedServiceName -DatabaseName $sqlPoolName `
                 -UserName "asa.sql.workload01" -KeyVaultLinkedServiceName $keyVaultName -SecretName $keyVaultSQLUserSecretName
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create linked service for SQL pool $($sqlPoolName) with user asa.sql.workload02"

$linkedServiceName = "$($sqlPoolName.ToLower())_workload02"
$result = Create-SQLPoolKeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $linkedServiceName -DatabaseName $sqlPoolName `
                 -UserName "asa.sql.workload02" -KeyVaultLinkedServiceName $keyVaultName -SecretName $keyVaultSQLUserSecretName
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create data sets"

$datasets = @{
        SQLDestinationPoC = $sqlPoolName.ToLower()
        hrdatapoc = $blobStorageAccountName
}

foreach ($dataset in $datasets.Keys) 
{
        Write-Information "Creating dataset $($dataset)"
        $result = Create-Dataset -DatasetsPath $datasetsPath -WorkspaceName $workspaceName -Name $dataset -LinkedServiceName $datasets[$dataset]
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId
}
Write-Information "Setup machine learning tables in SQL Pool"
$params = @{
    "PASSWORD" = $sqlPassword
    "DATALAKESTORAGEKEY" = $dataLakeStorageAccountKey
    "DATALAKESTORAGEACCOUNTNAME" = $dataLakeAccountName
}

try
{
    Execute-SQLScriptFile-SqlCmd -SQLScriptsPath $sqlScriptsPath -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -SQLUserName $sqlUserName -SQLPassword $sqlPassword -FileName "02_sqlpool01_ml" -Parameters $params
}
catch 
{
    write-host $_.exception
}

Write-Information "Validating the environment..."

$sqlConnectionString = "Server=tcp:$($workspaceName).sql.azuresynapse.net,1433;Initial Catalog=$($sqlPoolName);Persist Security Info=False;User ID=$($sqlUserName);Password=$($sqlPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$validEnvironment = $true

Write-Information "Verifying the existence of the SQL Pool users..."
$sqlPoolUsers = 'asa.sql.workload01', 'asa.sql.workload02','CEO','DataAnalystMiami','DataAnalystSanDiego'
foreach($sqlUser in $sqlPoolUsers)
{
        $usrQuery = "select count(name) as Count from sys.database_principals where name = '$($sqlUser)'"
        $result = (Invoke-SqlCmd -Query $usrQuery -ConnectionString $sqlConnectionString) | Select-Object -ExpandProperty Count
        if ($result -eq 1){       
        	Write-Host "User $($sqlUser) verified" 
        }
        else {
        	Write-Host "User $($sqlUser) not found" -ForegroundColor Red
        	$validEnvironment = $false
        }
}

Write-Information "Verifying roles for the SQL Pool Users..."
$sqlUserRoles = @{
	"CEO" = 'db_datareader'
	"asa.sql.workload01" = 'db_datareader'
	"asa.sql.workload02" = 'db_datareader'
}
foreach($usrRole in $sqlUserRoles.Keys){
	$roleQuery = "select IS_ROLEMEMBER('$($sqlUserRoles[$usrRole])', '$($usrRole)') as INROLE"
	$result = (Invoke-SqlCmd -Query $roleQuery -ConnectionString $sqlConnectionString) | Select-Object -ExpandProperty INROLE
	if ($result -eq 1){       
        Write-Host "User $($usrRole) verified in role $($sqlUserRoles[$usrRole])"
    }
    else {
    	Write-Host "User $($usrRole) is not in role $($sqlUserRoles[$usrRole])" -ForegroundColor Red
    	$validEnvironment = $false
    }
}

Write-Information "Verifying the existence of the wwi_mcw schema..."
$schemaQuery = "select count(name) as Count from sys.schemas where name='wwi_mcw'"
$result = (Invoke-SqlCmd -Query $schemaQuery -ConnectionString $sqlConnectionString) | Select-Object -ExpandProperty Count
if ($result -eq 1){Write-Host 'Schema wwi_mcw verified'}else{Write-Host 'Schema wwi_mcw not found' -ForegroundColor Red;$validEnvironment = $false}

Write-Information "Verifying the existence of the SQL Pool Tables..."
$sqlTables = 'Product', 'ASAMCWMLModelExt','ASAMCWMLModel'
foreach($table in $sqlTables)
{
        $tblQuery = "select count(name) as Count from sys.tables where name = '$($table)' and SCHEMA_NAME(schema_id) = 'wwi_mcw'"
        $result = (Invoke-SqlCmd -Query $tblQuery -ConnectionString $sqlConnectionString) | Select-Object -ExpandProperty Count
        if ($result -eq 1){       
        	Write-Host "Table $($table) verified"
        }
        else {
        	Write-Host "Table $($table) not found" -ForegroundColor Red
        	$validEnvironment = $false
        }
}

$scopedCredentialQuery = "select count(name) as Count from sys.database_scoped_credentials where name='StorageCredential'"
$result = (Invoke-SqlCmd -Query $scopedCredentialQuery -ConnectionString $sqlConnectionString) | Select-Object -ExpandProperty Count
if ($result -eq 1){Write-Host 'Database Scoped Credential StorageCredential verified'}else{Write-Host 'Database Scoped Credential StorageCredential not found' -ForegroundColor Red;$validEnvironment = $false}

Write-Information "Verifying the existence of the SQL External Data Source (Storage)..."
$extDataSourceQuery = "select count(name) as Count from sys.external_data_sources where name='ASAMCWModelStorage'"
$result = (Invoke-SqlCmd -Query $extDataSourceQuery -ConnectionString $sqlConnectionString) | Select-Object -ExpandProperty Count
if ($result -eq 1){Write-Host 'External data source ASAMCWModelStorage verified'}else{Write-Host 'External data source ASAMCWModelStorage not found' -ForegroundColor Red;$validEnvironment = $false}

Write-Information "Verifying the existence of the SQL Pool Model External Table..."
$extTableQuery = "select count(name) as Count from sys.external_tables where name='ASAMCWMLModelExt' and SCHEMA_NAME(schema_id)='wwi_mcw'"
$result = (Invoke-SqlCmd -Query $extTableQuery -ConnectionString $sqlConnectionString) | Select-Object -ExpandProperty Count
if ($result -eq 1){Write-Host 'External table ASAMCWMLModelExt verified'}else{Write-Host 'External table ASAMCWMLModelExt not found' -ForegroundColor Red;$validEnvironment = $false}

Write-Information "Verifying the existence of the SQL CSV external file format..."
$fileFormatQuery = "select count(name) as Count from sys.external_file_formats where name='csv'"
$result = (Invoke-SqlCmd -Query $fileFormatQuery -ConnectionString $sqlConnectionString) | Select-Object -ExpandProperty Count
if ($result -eq 1){Write-Host 'File Format csv verified'}else{Write-Host 'File format csv not found' -ForegroundColor Red;$validEnvironment = $false}

Write-Information "Verifying the data lake storage account..."
$dataLakeAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName

if ($dataLakeAccount -eq $null) {
        Write-Host "The datalake account $($dataLakeAccountName) was not found" -ForegroundColor Red
        $validEnvironment = $false
} else {
	foreach($storageFileOrFolder in $storageFilesAndFolders.Keys){	
		$dataLakeItem = Get-AzDataLakeGen2Item -Context $dataLakeAccount.Context -FileSystem $storageFilesAndFolders[$storageFileOrFolder].Split("/")[0] -Path $storageFilesAndFolders[$storageFileOrFolder].Replace($storageFilesAndFolders[$storageFileOrFolder].Split("/")[0] +"/","")
		if(!($dataLakeItem -eq $null)){
			Write-Host "Data Lake $($storageFilesAndFolders[$storageFileOrFolder]) has been verified"
		} else {
			Write-Host "Data Lake $($storageFilesAndFolders[$storageFileOrFolder]) not found" -ForegroundColor Red
        	        $validEnvironment = $false
		}
	}
}

if($validEnvironment = $true){
        Write-Host "Environment validation has succeeded." -ForegroundColor Green
} else {
        Write-Host "Environment validation has failed. Please check the above output for Red messages." -ForegroundColor Red
}
