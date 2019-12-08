---- Predicting Mortality of patient admissions diagnosed with Pneumonia 

--- All different diagnosis count from admissions table 
SELECT DIAGNOSIS, COUNT(DIAGNOSIS) as Count_Diagnosis
FROM [mimic].[dbo].[ADMISSIONS]
GROUP BY DIAGNOSIS
ORDER BY Count_Diagnosis desc;
---PNEUMONIA - 1613

--- Getting all the ICD 9 code associated with diagnosis pneumonia  --- Duplicate ICD9CODE present
Select ICD9_CODE, DIAGNOSIS
FROM [mimic].[dbo].[ADMISSIONS] a 
INNER JOIN
[mimic].[dbo].[DIAGNOSES_ICD] d 
ON a.HADM_ID = d.HADM_ID
WHERE a.DIAGNOSIS = 'PNEUMONIA';
--- 24084 rows

--- Getting unique ICD 9 code associated with diagnosis pneumonia
Select DISTINCT(ICD9_CODE), DIAGNOSIS
FROM [mimic].[dbo].[ADMISSIONS] a 
INNER JOIN
[mimic].[dbo].[DIAGNOSES_ICD] d 
ON a.HADM_ID = d.HADM_ID
WHERE a.DIAGNOSIS = 'PNEUMONIA';
--- 1876 rows

--- Getting a sorted list of most common ICD9_Code associated with diagnosis pneumonia
Select ICD9_CODE, COUNT(ICD9_CODE) AS Count_ICD9CODE
FROM [mimic].[dbo].[ADMISSIONS] a 
INNER JOIN
[mimic].[dbo].[DIAGNOSES_ICD] d 
ON a.HADM_ID = d.HADM_ID
WHERE a.DIAGNOSIS = 'PNEUMONIA'
GROUP BY ICD9_CODE
ORDER BY Count_ICD9CODE DESC;
--- 1876 rows

--- ICD 9 CODE + Description for diagnosis - PNEUMONIA
Select d.ICD9_CODE, SHORT_TITLE, diagnosis
FROM [mimic].[dbo].[ADMISSIONS] a 
INNER JOIN
[mimic].[dbo].[DIAGNOSES_ICD] d 
ON a.HADM_ID = d.HADM_ID
INNER JOIN 
[mimic].[dbo].[D_ICD_DIAGNOSES] dd
ON dd.ICD9_CODE = d.ICD9_CODE
WHERE a.DIAGNOSIS = 'PNEUMONIA';
--- 23688 rows

---1. Preprocessing the Admissions table 
--- so as to have only one random HADM_ID for one SUBJECT_ID.
--- Creating random number based on HADM_ID. Since HADM_ID is unique which will create unique random numbers.
SELECT [SUBJECT_ID], [HADM_ID], [ADMITTIME], [ETHNICITY], [DIAGNOSIS], [HOSPITAL_EXPIRE_FLAG], RAND([HADM_ID]) AS RANDOM_NO 
INTO [mimic].[dbo].ADMISSIONS_TEMP1
FROM [mimic].[dbo].[ADMISSIONS];
--- 58976 rows affected

--- Assigning Min random number to each subject_id
SELECT [SUBJECT_ID], MIN(RANDOM_NO) AS MIN_RANDOM_NO
INTO [mimic].[dbo].ADMISSIONS_TEMP2
FROM [mimic].[dbo].ADMISSIONS_TEMP1
GROUP BY [SUBJECT_ID];
--- 46520 rows affected

--- Combining the two tables based on Min Random Number and performing cleaning of [HOSPITAL_EXPIRE_FLAG] and [DIAGNOSIS] 
SELECT T1.[SUBJECT_ID], [HADM_ID], [ADMITTIME], [ETHNICITY], [DIAGNOSIS], [HOSPITAL_EXPIRE_FLAG]
INTO [mimic].[dbo].ADMISSIONS_PROCESSED
FROM [mimic].[dbo].ADMISSIONS_TEMP1 T1 
INNER JOIN 
[mimic].[dbo].ADMISSIONS_TEMP2 T2
ON RANDOM_NO=MIN_RANDOM_NO
WHERE [HOSPITAL_EXPIRE_FLAG] = '0' OR [HOSPITAL_EXPIRE_FLAG] = '1'  AND [DIAGNOSIS] <> ''; --- 45472 rows
---

--- Getting count of Mortality / Mortality due to Pneumonia from Admissions Table
SELECT COUNT(*)
FROM [mimic].[dbo].ADMISSIONS_PROCESSED
WHERE [HOSPITAL_EXPIRE_FLAG] = 1 --- 4815
AND [DIAGNOSIS] = 'Pneumonia'; --- 211

---2. Patients table 
SELECT [SUBJECT_ID], [GENDER], [DOB], [EXPIRE_FLAG] 
FROM [mimic].[dbo].PATIENTS;

---3. Joining Processed Admissions Table with the Patients Table
SELECT ap.[SUBJECT_ID], [HADM_ID], [ADMITTIME], [ETHNICITY], [DIAGNOSIS], [HOSPITAL_EXPIRE_FLAG], [GENDER], [DOB], [EXPIRE_FLAG]
INTO [mimic].[dbo].COMB_ADM_PAT_RAW1
FROM [mimic].[dbo].[ADMISSIONS_PROCESSED] ap
LEFT JOIN 
[mimic].[dbo].PATIENTS p
ON ap.SUBJECT_ID = p.SUBJECT_ID; --- 45472 rows

---4. Since we have DOB and ADMITTIME, we calculate the Age
--- Converting String to Datetime type for dates
SELECT [SUBJECT_ID], [HADM_ID], ADMITTIME, CAST(ADMITTIME AS datetime)  AS ADMITTIME_DATE, [ETHNICITY], [DIAGNOSIS], 
[HOSPITAL_EXPIRE_FLAG], [GENDER], DOB, CAST(DOB AS datetime) AS DOB_DATE, [EXPIRE_FLAG] 
INTO [mimic].[dbo].COMB_ADM_PAT_RAW2
FROM [mimic].[dbo].COMB_ADM_PAT_RAW1; --- 45472 rows

--- Taking difference for calculating age --- Here I am avoiding mm and dd complexity for age and just using year
SELECT [SUBJECT_ID], [HADM_ID], ADMITTIME, [ETHNICITY], [DIAGNOSIS], 
[HOSPITAL_EXPIRE_FLAG], [GENDER], DOB, [EXPIRE_FLAG], (DATEPART(year, ADMITTIME_DATE) - DATEPART(year, DOB_DATE)) as AGE
INTO [mimic].[dbo].COMB_ADM_PAT
FROM [mimic].[dbo].COMB_ADM_PAT_RAW2;  --- 45472 rows
 
--- Now since we have Age we go forward to assign classes to Age (Age category)
--- 0-1 --> Neonate  15-59 --> Adult   60-89 --> Senior Adult    89+ -->  >89
SELECT [SUBJECT_ID], [HADM_ID], ADMITTIME, [ETHNICITY], [DIAGNOSIS], [HOSPITAL_EXPIRE_FLAG], [GENDER], DOB, [EXPIRE_FLAG], [AGE]
    , CASE
        -- all ages > 89 in the database were replaced with 300
        WHEN [AGE] <= 1
            THEN 'NEONATE' --- 7874 rows
		WHEN [AGE] > 14 AND [AGE] <=59
            THEN 'ADULT' --- 14017 rows 
		WHEN [AGE] > 59 AND [AGE] <=89
            THEN 'SENIOR ADULT' --- 21645 rows
        ELSE '>89' --- 1936 rows
        END AS AGE_CATEGORY
INTO [mimic].[dbo].COMB_ADM_PAT_AGECAT
FROM [mimic].[dbo].COMB_ADM_PAT
ORDER BY [SUBJECT_ID];  --- 45472 rows


Select ethnicity, count(ethnicity) AS CT FROM [mimic].[dbo].COMB_ADM_PAT_AGECAT GROUP BY ETHNICITY ORDER BY CT DESC;

--- Reducing 41 Ethnicity classes to top 4 classes 
SELECT *, 
CASE WHEN lower(ethnicity) like '%white%' 
		THEN 'WHITE'  
	WHEN lower(ethnicity) like '%black%' 
		THEN 'BLACK'  
	WHEN lower(ethnicity) like '%asian%' 
		THEN 'ASIAN'
	WHEN lower(ethnicity) like '%hispanic%' 
		THEN 'HISPANIC/LATINO'	
	ELSE 'OTHERS' 
	END AS ETHNICITY_CATEGORY 
---INTO [mimic].[dbo].COMB_ADM_PAT_ETHCAT 
FROM [mimic].[dbo].COMB_ADM_PAT_AGECAT; 

--- Taking Lab events of patients 
SELECT * FROM [mimic].[dbo].[LABEVENTS]
--- 1% of the Lab events data
select * from [mimic].[dbo].[LABEVENTS] tablesample(1 percent) --- Not as random as newid() but will give fast results --- 275701 rows
--- select top 1 percent * from [mimic].[dbo].[LABEVENTS] order by newid() 

--- Creating LABEVENTS_SAMPLE_RAW(1%) file
select * INTO [mimic].[dbo].LABEVENTS_SAMPLE_RAW from [mimic].[dbo].[LABEVENTS] tablesample(1 percent) --- 277591 rows affected
--- select top 1 percent * INTO LABEVENTS_SAMPLE_RAW from [mimic].[dbo].[LABEVENTS] order by newid()

select * FROM [mimic].[dbo].LABEVENTS_SAMPLE_RAW;


--- Taking chartevents of patients
SELECT * FROM [mimic].[dbo].[CHARTEVENTS]
--- 1% of the chart events data
select * from [mimic].[dbo].[CHARTEVENTS] tablesample(1 percent)--- Not as random as newid() but will give fast results --- 3324858 rows
--- select top 1 percent * from [mimic].[dbo].[CHARTEVENTS] order by newid() 

--- Creating CHARTEVENTS_SAMPLE_RAW(1%) file
select * INTO [mimic].[dbo].CHARTEVENTS_SAMPLE_RAW from [mimic].[dbo].[CHARTEVENTS] tablesample(1 percent)
--- select top 1 percent * INTO LABEVENTS_SAMPLE_RAW from [mimic].[dbo].[CHARTEVENTS] order by newid()