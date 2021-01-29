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
