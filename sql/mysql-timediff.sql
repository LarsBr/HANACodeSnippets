-- https://answers.sap.com/questions/13144802/how-to-calculate-difference-between-two-time-in-sa.html?childToView=13143973#comment-13143973

SELECT CURRENT_DATE, * FROM m_database; 
-- CURRENT_DATE|SYSTEM_ID|DATABASE_NAME|HOST   |START_TIME         |VERSION               |USAGE      |
--   ----------|---------|-------------|-------|-------------------|----------------------|-----------|
--   2020-09-22|HXE      |HXE          |hxehost|2020-09-22 14:33:54|2.00.045.00.1575639312|DEVELOPMENT|


-- a HANA version of the mysSQL timeDiff (https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html#function_timediff) function
-- Since HANA's time/timestamp data types don't allow for negative values
-- we need to use the absolute difference and the user needs to know 
-- whether to add/substract with the result
-- Also: the mySQL version works on TIMESTAMP while this implementation works on TIME data types.

CREATE OR REPLACE FUNCTION timediff (time1 time
                                   , time2 time)
RETURNS timediff time
AS
BEGIN
DECLARE secs_diff  Integer; 
DECLARE hours integer;
DECLARE minutes integer;
DECLARE seconds integer;

    secs_diff := abs (seconds_between (time1, time2));
    hours := floor(:secs_diff/3600);
    minutes := floor(:secs_diff - (:hours*3600))/60;
    seconds := :secs_diff - (:hours*3600) - (:minutes*60);
    
    timediff := to_time(:hours || ':'||:minutes || ':' || :seconds);
END;


SELECT timediff ('15:23', '14:30') FROM dummy;
/*
TIMEDIFF('15:23','14:30')|
-------------------------|
                 00:53:00|
*/

SELECT timediff ('12:23', '14:30') FROM dummy;
/*
TIMEDIFF('12:23','14:30')|
-------------------------|
                 02:07:00|
*/

SELECT timediff ('12:23:21.234', CURRENT_TIMESTAMP) FROM dummy;
/*
TIMEDIFF('12:23:21.234',CURRENT_TIMESTAMP)|
------------------------------------------|
                                  03:27:04|
*/

