# Auto-Azure-BACPAC-Download
Automatically extract Azure DB and restore it to a local SQL server with one step

The purpose for this is to reduce the number of steps needed to extract a data tier database from Microsoft Azure SQL database and upload the database into a local SQL Server database.

WARNING: The attached ps1 file will store your SQL sa password in clear text.  
If you don't want to do this, don't use this file.


This code currently runs successfully on the following setup:

Local PC OS:  Windows 10 Pro

Installed locally on PC
Microsoft SQL Server Developer (64-bit) v12.0.5207.0

You will need to put the ps1 script file somewhere and make reference to it in the T-SQL script.

Running the SQL script will do the whole process in one step.
