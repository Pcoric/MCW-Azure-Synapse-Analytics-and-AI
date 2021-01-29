if not exists(select * from sys.database_principals where name = 'asa.sql.workload01') create user [asa.sql.workload01] from login [asa.sql.workload01]
if not exists(select * from sys.database_principals where name = 'asa.sql.workload02') create user [asa.sql.workload02] from login [asa.sql.workload02]
if not exists(select * from sys.database_principals where name = 'ceo') create user [CEO] without login;
execute sp_addrolemember 'db_datareader', 'asa.sql.workload01' 
execute sp_addrolemember 'db_datareader', 'asa.sql.workload02' 
execute sp_addrolemember 'db_datareader', 'CEO' 
if not exists(select * from sys.database_principals where name = 'DataAnalystMiami') create user [DataAnalystMiami] without login
if not exists(select * from sys.database_principals where name = 'DataAnalystSanDiego')create user [DataAnalystSanDiego] without login
if not exists(select * from sys.schemas where name='wwi_mcw') EXEC('create schema [wwi_mcw] authorization [dbo]')
create master key
CREATE TABLE [wwi_mcw].[HRData]
 (
    [ID] [nvarchar](150) NOT  NULL,
    [Function] [nvarchar](150)  NULL,
    [CostCenter] [nvarchar](150)  NULL,
    [JobTitle] [nvarchar](150)  NULL,
    [ServiceLine] [nvarchar](150)  NULL,
    [PrimaryLOB] [nvarchar](150)  NULL,
    [PrimarySectorSegment] [nvarchar](150)  NULL,
    [ServiceNetwork] [nvarchar](150)  NULL,
    [ServiceGroup] [nvarchar](150)  NULL,
    [EmployeeType] [nvarchar](150)  NULL,
    [EmployeeClass] [nvarchar](150)  NULL,
    [SecondaryLOB] [nvarchar](150)  NULL,
    [IsClientFacing] [nvarchar](150)  NULL,
    [SecondarySectorSegment] [nvarchar](150)  NULL,
    [Sublevel] [int]  NULL,
    [FormTemplateID] [int] NULL,
    [FormTemplateName] [nvarchar](150)  NULL,
    [FormTitle] [nvarchar](150)  NULL,
    [DocumentID] [int]  NULL,
    [PromotionStatus] [nvarchar](150)  NULL,
    [OverallPerformanceRating] [int]  NULL,
    [OverallPerformanceRatingDescription] [nvarchar](150) NULL,
    [OverallPerformanceRatingDescriptionLocaleSpecific] [nvarchar](150)  NULL,
    [UnadjustedOverallPerformanceRatingDescriptionLocaleSpecific] [nvarchar](150)  NULL,
    [CalculatedOverallPerformanceRating] [int]  NULL,
    [CalculatedOverallPerformanceRatingDescription] [nvarchar](150)  NULL
 )
 WITH
 (
   DISTRIBUTION = HASH(ID),
   CLUSTERED COLUMNSTORE INDEX
 )
 GO

