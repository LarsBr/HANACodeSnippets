-- This .sql contains the code to setup the SUDO_GRANT functionality in a HANA database.
-- Please see the blog post that explains the use case for this functionality and how it 
-- is implemented here.
--
-- Note that I don't recommend using this functionality in your system. It's presented here
-- for education purposes only.
-- If you do use it, it's at your own risk. If you aren't 100% sure about how using this function
-- will affect your landscape, then don't use it.
--
-- Make sure to read the blog post about the procedure: https://www.lbreddemann.org/sudo-grant/

-- 1) create the SYSTEM.SUDO_GRANT procedure
create or replace procedure "SUDO_GRANT"
                        ( IN PRIVILEGE NVARCHAR(256)
                        , IN OBJECT    NVARCHAR(800) 
                        , IN GRANTEE   NVARCHAR(256)
                        , IN ADMIN_GRANT_OPTION NVARCHAR(17) DEFAULT '')
    LANGUAGE SQLSCRIPT
    SQL SECURITY DEFINER                -- this setting enables to grant as SYSTEM
    DEFAULT SCHEMA SYSTEM
AS
BEGIN
DECLARE IS_DB_AUDIT_ACTIVE NVARCHAR(5) := 'FALSE';
DECLARE IS_AUDIT_POLICY_ACTIVE NVARCHAR(5) := 'FALSE';

DECLARE PROCEDURE_OWNER_NAME NVARCHAR(256);

DECLARE SUDO_GRANT_IN_WRONG_SCHEMA CONDITION FOR SQL_ERROR_CODE 10000;
DECLARE SUDO_GRANT_NOT_OWNED_BY_SYSTEM CONDITION FOR SQL_ERROR_CODE 10003;
DECLARE DB_AUDIT_INACTIVE CONDITION FOR SQL_ERROR_CODE 10001;
DECLARE SUDO_GRANT_AUDIT_INACTIVE CONDITION FOR SQL_ERROR_CODE 10002; 

DECLARE EXIT HANDLER FOR SQLEXCEPTION RESIGNAL;

-- check that the sudo_grant procedure is, in fact, in the SYSTEM schema
-- and has the name SUDO_GRANT. We need this for the auditing to work.
    if    (::CURRENT_OBJECT_NAME != 'SUDO_GRANT'
        or ::CURRENT_OBJECT_SCHEMA != 'SYSTEM') then
            SIGNAL SUDO_GRANT_IN_WRONG_SCHEMA
            SET MESSAGE_TEXT = 'SUDO_GRANT procedure is not in SYSTEM schema or is not called SUDO_GRANT. Re-install the procedure as SUDO_GRANT into the SYSTEM schema.';
    end if;

-- also check that the sudo_grant procedure is OWNED by SYSTEM in case 
-- someone installs it with into the SYSTEM schema but is not doing that 
-- as the SYSTEM user.   
    SELECT 
        MAX(owner_name) 
        INTO procedure_owner_name
    FROM 
        (SELECT owner_name 
            FROM ownership
            WHERE 
                object_name = 'SUDO_GRANT'
                AND schema_name = 'SYSTEM'
        UNION ALL
            SELECT '' AS owner_name
            FROM DUMMY
        );

    IF  (:procedure_owner_name != 'SYSTEM') THEN 
        SIGNAL SUDO_GRANT_NOT_OWNED_BY_SYSTEM
        SET MESSAGE_TEXT = 'SUDO_GRANT procedure is not owned by the SYSTEM user. Re-install the procedure logged in as SYSTEM.';
    END IF;

-- ensure that auditing is active before doing anything.
    SELECT 
            max(IS_DB_AUDIT_ACTIVE)  
       into IS_DB_AUDIT_ACTIVE
    FROM 
        (   select 
            'FALSE' as IS_DB_AUDIT_ACTIVE
            from dummy
        union all
            select 
                upper(value) as IS_DB_AUDIT_ACTIVE
            from 
                m_inifile_contents 
            where 
                file_name = 'global.ini' 
            and section = 'auditing configuration'
            and key = 'global_auditing_state'
        );
    
    if :IS_DB_AUDIT_ACTIVE != 'TRUE' then
        SIGNAL DB_AUDIT_INACTIVE 
        SET MESSAGE_TEXT = 'Database Auditing is currently not active. Activate Auditing before using SUDO_GRANT procedure.';
    end if;

-- check that "our" audit policy is present and active    
    select 
        max(IS_AUDIT_POLICY_ACTIVE) 
        into IS_AUDIT_POLICY_ACTIVE
    from
        (   select
                'FALSE' as IS_AUDIT_POLICY_ACTIVE
            from
                dummy
        union all
            select
                    IS_AUDIT_POLICY_ACTIVE
            from
                audit_policies
            where
                audit_policy_name = 'SUDO_GRANT'
            or (    event_action = 'EXECUTE' 
                and OBJECT_TYPE  = 'PROCEDURE' 
                and object_name  = 'SUDO_GRANT')
        );

    if :IS_AUDIT_POLICY_ACTIVE != 'TRUE' then
        SIGNAL SUDO_GRANT_AUDIT_INACTIVE 
        SET MESSAGE_TEXT = 'SUDO_GRANT auditing policy not active or not set up. Create and/or activate the audit policy for the SUDO_GRANT procedure before using it.';
    end if;

-- OK, if we reached this point, we know the auditing is active and we proceed with the next steps
    EXEC 'GRANT ' || :PRIVILEGE || ' ON ' || :OBJECT || ' TO ' || :GRANTEE || ' ' || :ADMIN_GRANT_OPTION;
end;


-- 2) create and enable the audit policies
CREATE AUDIT POLICY "SUDO_GRANT" AUDITING ALL EXECUTE ON "SYSTEM"."SUDO_GRANT" LEVEL INFO;
ALTER AUDIT POLICY "SUDO_GRANT" ENABLE;

-- 3) setup the SUDO_GRANTERS role
CREATE role SUDO_GRANTERS;
GRANT EXECUTE ON "SYSTEM"."SUDO_GRANT" TO SUDO_GRANTERS;

-- assign SUDO_GRANTERS to users or other roles.
-- GRANT "SUDO_GRANTERS" to "USER_ADMINS" with admin option;

-- example call for "SYS"."GET_INSUFFICIENT_PRIVILEGE_ERROR_DETAILS"
-- the parameters follow the GRANT syntax:
--
-- GRANT <privilege>[{, <privilege>}...] TO <grantee> [ WITH ADMIN OPTION | WITH GRANT OPTION ]
--
-- See 'GRANT' documentation:
-- https://help.sap.com/viewer/4fe29514fd584807ac9f2a04f6754767/2.0.04/en-US/20f674e1751910148a8b990d33efbdc5.html
/*
call SYSTEM.sudo_grant 
     (privilege => 'EXECUTE'
    , object    => '"SYS"."GET_INSUFFICIENT_PRIVILEGE_ERROR_DETAILS"'
    , grantee   => '_SYS_REPO'
    , admin_grant_option => 'WITH GRANT OPTION');
*/

-- check audit log entries
/*
select 
    * 
from 
    audit_log 
where 
    upper(statement_string) like '%SUDO_GRANT%'
order by timestamp desc;
*/

-- license
-- MIT License

-- Copyright (c) 2020 Lars Breddemann

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARßTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.