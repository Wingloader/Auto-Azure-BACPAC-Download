USE [master]
GO

--MyLocalDB is the local copy of the database I use for development purposes.
--Substitute the DB name with the name you use.

--This process is assuming you are pulling a database down from Azure to use on 
--  a local PC.  If you are putting the DB copy from Azure anywhere else you 
--  may have to modify this.

--You will need to have permissions turned on to allow the xp_cmdshell procedure.   

--Steps
--1. Back up the current DB as MyLocalDB.bak
--2. Restore that backup from step 1 to a new DB with the previous day stamped at the end of the DB name (MyLocalDB20171231)
--3. Delete the original MyLocalDB database
--4. Pull down the production database from Azure and create a new database with the name MyLocalDB
--First, back up the existing 

--Step 1
BACKUP DATABASE [MyLocalDB] TO  DISK = N'C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Backup\MyLocalDB.bak'
	WITH NOFORMAT, INIT,  NAME = N'MyLocalDB-Full Database Backup', SKIP, NOREWIND, NOUNLOAD,  STATS = 10
GO

SELECT 'Current database has been backed up'
GO

--Step 2
DECLARE @vcrDBName VARCHAR(Max)
DECLARE @datYesterday SMALLDATETIME
SET @datYesterday = DATEADD(d, -1, GETDATE())
SET @vcrDBName = 'MyLocalDB' + 
	RIGHT('0' + CAST(MONTH(@datYesterday) AS CHAR(2)),2) +
	RIGHT('0' + RTRIM(CAST(DAY(@datYesterday) AS CHAR(2))),2) +
	CAST(YEAR(@datYesterday) AS CHAR(4))
DECLARE @chrDestinationFileLDF AS NVARCHAR(max)
DECLARE @chrDestinationFileMDF AS NVARCHAR(max)
SET @chrDestinationFileMDF = 'C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Backup\' + @vcrDBName + '_Primary.mdf'
SET @chrDestinationFileLDF = 'C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Backup\' + @vcrDBName + '_Primary.ldf'
RESTORE DATABASE @vcrDBName FROM  DISK = N'C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Backup\MyLocalDB.bak' 
	WITH  FILE = 1, MOVE N'MyLocalDB' TO @chrDestinationFileMDF, MOVE N'MyLocalDB_Log' TO @chrDestinationFileLDF,  NOUNLOAD,  REPLACE,  STATS = 5
GO

SELECT 'Database has been restored with a new name'
GO

--Set the DB to single user so it will kill any current connections
--This may leave the database in single user mode but since it is local
--  but if you are the only user of the DB on a local machine, it is 
--  highly unlikely to occur.
ALTER DATABASE [MyLocalDB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
GO

--Step 3
DROP DATABASE [MyLocalDB]
GO

SELECT 'Existing MyLocalDB database deleted'
GO

--Step 4 -- Pull down the bacpac from Azure and import the data into MyLocalDB

SELECT 'Processing bacpac'
GO

--Place the GetAzureDB.ps1 script somewhere convenient for you
EXEC MASTER..xp_cmdshell '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -File C:\Git\GetUpdatedAzureDB\GetAzureDB.ps1"'
GO

ALTER DATABASE [MyLocalDB] SET MULTI_USER
GO

--FINISHED