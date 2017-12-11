<#
These parameters are hard coded in order to make this script fully automated
param([string]$ConnectionString = $(throw "The ConnectionString parameter is required."),  
      [string]$DatabaseName = $(throw "The DatabaseName parameter is required."),
      [string]$BacpacFileName = $(throw "The OutputFile parameter is required."), 
      [string]$SqlInstallationFolder = "C:\Program Files (x86)\Microsoft SQL Server")
#>

$ConnectionString = "Server=tcp:MyAzureAccount.database.windows.net,1433;Database=MyAzureDatabase;User ID=MyUserName@MyAzureAccount;Password=MyPassword;Trusted_Connection=False;Encrypt=True;Connection Timeout=30;"
$DatabaseName = "MyAzureDatabase" 
#Location to store the current bacpac file
$BacpacFileName = "C:\Git\GetUpdatedAzureDB\today.bacpac"
$SqlInstallationFolder = "C:\Program Files (x86)\Microsoft SQL Server"

# Load DAC assembly.
$DacAssembly = "$SqlInstallationFolder\140\DAC\bin\Microsoft.SqlServer.Dac.dll"
Write-Host "Loading Dac Assembly: $DacAssembly"  
Add-Type -Path $DacAssembly  
Write-Host "Dac Assembly loaded."

# Initialize Dac service.
$now = $(Get-Date).ToString("HH:mm:ss")
$Services = new-object Microsoft.SqlServer.Dac.DacServices $ConnectionString
if ($Services -eq $null)  
{
    exit
}

# Start the actual export.
Write-Host "Starting backup at $DatabaseName at $now"  
$Watch = New-Object System.Diagnostics.StopWatch
$Watch.Start()
$Services.ExportBacpac($BacpacFileName, $DatabaseName)
$Watch.Stop()
Write-Host "Backup completed in" $Watch.Elapsed.ToString()



#Patch the bacpac zip file due to the security key on Azure DB.
if ($PSVersionTable.PSVersion.Major -lt 4) {
    Write-Host "Unsupported powershell version.  This script requires powershell version 4.0 or later"
    return
}

Add-Type -Assembly System.IO.Compression.FileSystem

$targetBacpacPath = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($BacpacFileName),
    [System.IO.Path]::GetFileNameWithoutExtension($BacpacFileName) + "-patched" + [System.IO.Path]::GetExtension($BacpacFileName))
$originXmlFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($targetBacpacPath), "Origin.xml")
$modelXmlFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($targetBacpacPath), "model.xml")

if ([System.IO.File]::Exists($targetBacpacPath)) {
    [System.IO.File]::Delete($targetBacpacPath)
}

#
# Extract the model.xml and Origin.xml from the .bacpac
#
$zip = [System.IO.Compression.ZipFile]::OpenRead($BacpacFileName)
foreach ($entry in $zip.Entries) {
    if ([string]::Compare($entry.Name, "model.xml", $True) -eq 0) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $modelXmlFile, $true)
        break
    }
}   
foreach ($entry in $zip.Entries) {
    if ([string]::Compare($entry.Name, "Origin.xml", $True) -eq 0) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $originXmlFile, $true)
        break
    }
}   
$zip.Dispose()


if(![System.IO.File]::Exists($modelXmlFile)) {
    Write-Host "Could not extract the model.xml from file " + $BacpacFileName
    return
}
if(![System.IO.File]::Exists($originXmlFile)) {
    Write-Host "Could not extract the Origin.xml from file " + $BacpacFileName
    return
}


#
# Modify the model.xml
#
[xml]$modelXml = Get-Content $modelXmlFile
$ns = New-Object System.Xml.XmlNamespaceManager($modelXml.NameTable)
$ns.AddNamespace("x", $modelXml.DocumentElement.NamespaceURI)


$masterKeyNodes = $modelXml.SelectNodes("//x:DataSchemaModel/x:Model/x:Element[@Type='SqlMasterKey']", $ns) 
foreach ($masterKeyNode in $masterKeyNodes) {
    $masterKeyNode.ParentNode.RemoveChild($masterKeyNode)
}

$sqlDatabaseCredentialNodes = $modelXml.SelectNodes("//x:DataSchemaModel/x:Model/x:Element[@Type='SqlDatabaseCredential']", $ns) 
foreach ($sqlDatabaseCredentialNode in $sqlDatabaseCredentialNodes) {
    if ($sqlDatabaseCredentialNode.Property.Name -eq "Identity" -and $sqlDatabaseCredentialNode.Property.Value -eq "SHARED ACCESS SIGNATURE")
    {
        $sqlDatabaseCredentialNode.ParentNode.RemoveChild($sqlDatabaseCredentialNode)    
    }
}

$modelXml.Save($modelXmlFile)

#
# Modify the Origin.xml
#
[xml]$originXml = Get-Content $originXmlFile
$ns = New-Object System.Xml.XmlNamespaceManager($originXml.NameTable)
$ns.AddNamespace("x", $originXml.DocumentElement.NamespaceURI)

$databaseCredentialNode = $originXml.SelectSingleNode("//x:DacOrigin/x:Server/x:ObjectCounts/x:DatabaseCredential", $ns) 
if ($databaseCredentialNode) {
    if ($databaseCredentialNode.InnerText -eq "1") {
        $databaseCredentialNode.ParentNode.RemoveChild($databaseCredentialNode)
    } else {
        $databaseCredentialNode.InnerText = $databaseCredentialNode.Value - 1
    }
}

$masterKeyNode = $originXml.SelectSingleNode("//x:DacOrigin/x:Server/x:ObjectCounts/x:MasterKey", $ns) 
if ($masterKeyNode) {
    $masterKeyNode.ParentNode.RemoveChild($masterKeyNode)
}

$modelXmlHash = (Get-FileHash $modelXmlFile -Algorithm SHA256).Hash
$checksumNode = $originXml.SelectSingleNode("//x:DacOrigin/x:Checksums/x:Checksum", $ns) 
if ($checksumNode) {
    $checksumNode.InnerText = $modelXmlHash
}

$originXml.Save($originXmlFile)

#
# Create the new .bacpac using the patched model.xml and Origin.xml
#
$zipSource = [System.IO.Compression.ZipFile]::OpenRead($BacpacFileName)
$zipTarget = [System.IO.Compression.ZipFile]::Open($targetBacpacPath, "Create")
foreach ($entry in $zipSource.Entries) {
    if ([string]::Compare($entry.Name, "Origin.xml", $True) -eq 0) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipTarget, $originXmlFile, $entry.FullName)
    } elseif ([string]::Compare($entry.Name, "model.xml", $True) -eq 0) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipTarget, $modelXmlFile, $entry.FullName)
    } else {
        $targetEntry = $zipTarget.CreateEntry($entry.FullName)
        $sourceStream = $null
        $targetStream = $null        
        try {
            $sourceStream = [System.IO.Stream]$entry.Open()
            $targetStream = [System.IO.Stream]$targetEntry.Open()        
            $sourceStream.CopyTo($targetStream)
        }
        finally {
            if ($targetStream -ne $null) {
                $targetStream.Dispose()
            }
            if ($sourceStream -ne $null) {
                $sourceStream.Dispose()
            }
        }
    }
}
$zipSource.Dispose()
$zipTarget.Dispose()

[System.IO.File]::Delete($modelXmlFile)
[System.IO.File]::Delete($originXmlFile)

Write-Host "Completed update to the model.xml and Origin.xml in file"([System.IO.Path]::GetFullPath($targetBacpacPath))

& "C:\Program Files (x86)\Microsoft SQL Server\140\DAC\bin\SqlPackage.exe" /Action:Import /SourceFile:"C:\Git\GetUpdatedAzureDB\today-patched.bacpac" /TargetConnectionString:"Data Source=MyLocalSQLServer;User ID=sa; Password=MySAPassword; Initial Catalog=MyLocalDB; Integrated Security=false;"
