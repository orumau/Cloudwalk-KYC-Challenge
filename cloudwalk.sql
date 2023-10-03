/*Created Cloudwalk Database.*/
create database cloudwalk;

use cloudwalk;

/*Created tables to import the CSVs content.*/
create table clients (
	ID Int primary key not null,
    CNPJ int
);

create table representatives (
	ID Int primary key not null,
    CPF int,
    foreign KEY (ID) REFERENCES clients(ID)
);

create table kyc (
	document text not null,
    analysis JSON
);

/*Imported the CSVs content to its respective tables using MySQL Workbench's Table Data Import Wizard.*/
/*Once fulfilled, the three main tables were used for solving the challenge, as follows.*/

/*Created Rejected table*/
create table rejected (
	document varchar(20) primary key not null,
	reason text
);

/*Rejected Tax Status*/
insert into rejected (select
	document,
	concat ("Irregular Tax Status: ", json_value(analysis, "$.RESULT[0].BASICDATA.TAXIDSTATUS")) as reason
from kyc
where
	json_value(analysis, "$.RESULT[0].BASICDATA.TAXIDSTATUS") != "ATIVA"
    AND json_value(analysis, "$.RESULT[0].BASICDATA.TAXIDSTATUS") != "REGULAR"
);

/*Rejected Currently Sanctioned Status*/
insert into rejected (select
	document,
	concat ("Currently Sanctioned: ", json_value(analysis, "$.RESULT[0].KYCDATA.ISCURRENTLYSANCTIONED")) as reason
from kyc
where
	json_value(analysis, "$.RESULT[0].KYCDATA.ISCURRENTLYSANCTIONED") = "true"
);

/*Rejected Criminal Lawsuits Identified*/
insert into rejected (select
	document,
	"Has Criminal Lawsuits" as reason
from kyc
where
	length (document) = 11 and
    json_value(analysis, "$.RESULT[0].PROCESSES.TOTALLAWSUITS") > 0 and 
    json_search(analysis, "one", "CRIMINAL", null, "$.RESULT[0].PROCESSES.LAWSUITS[*].COURTTYPE") IS NOT NULL
);

/*Relating rejected owners/representatives and companies*/
insert into rejected (select c.cnpj as document, rj.reason as reason
from clients c
	join representatives rs on c.id = rs.id
    right outer join rejected rj on rs.cpf = rj.document
where length (rj.document) = 11 and rs.cpf is not null
);
    
insert into rejected (select kyc.document as document, rj.reason as reason
from clients c
	join representatives rs on c.id = rs.id
    right outer join rejected rj on rs.cpf = rj.document
    join kyc
where length (rj.document) = 11
and rs.cpf is null
and json_search(analysis, "one", rj.document, null, "$.RESULT[0].RELATIONSHIPS.RELATIONSHIPS[*].RELATEDENTITYTAXIDNUMBER") IS NOT NULL
);

/*Deleting individuals (CPF) from the table. Companies only*/
delete from rejected
where length (document) = 11;

/*Created Approved table*/
create table approved (
	document varchar(20) primary key,
    PEP varchar(10),
    age int,
    risklevel varchar(20)
);

/*Identified approved companies for not being present on the rejected table, and their risk level by their PEP status and age*/
insert into approved (select
	document,
    json_value(analysis, "$.RESULT[0].KYCDATA.ISCURRENTLYPEP") as PEP,
    json_value(analysis, "$.RESULT[0].BASICDATA.AGE") as age,
    case
		when json_value(analysis, "$.RESULT[0].KYCDATA.ISCURRENTLYPEP") = "true" then "C - High"
        when json_value(analysis, "$.RESULT[0].BASICDATA.AGE") < 10 then "B - Medium"
        else "A - Low"
	end as risklevel
FROM kyc
where length (document) = 14
and document not in (select document from rejected)
);   
    