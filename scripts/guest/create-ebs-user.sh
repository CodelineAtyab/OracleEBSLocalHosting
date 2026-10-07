#!/bin/bash
# Runs INSIDE the shared class instance (EBS 12.1.3) as root.
# Create an EBS application user (if absent) and give it System Administrator.
#   usage: ssh root@<class> 'bash -s -- <USER> <PASSWORD>' < create-ebs-user.sh
set -u
USER_NAME="${1:?usage: create-ebs-user.sh <user> <password>}"
PW="${2:?usage: create-ebs-user.sh <user> <password>}"
. /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env

sqlplus -s apps/apps@EBSDB <<SQL
set serveroutput on feed off
DECLARE
  v_user   VARCHAR2(30) := UPPER('$USER_NAME');
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM fnd_user WHERE user_name = v_user;
  IF v_exists = 0 THEN
    fnd_user_pkg.CreateUser(x_user_name => v_user,
                            x_owner     => NULL,
                            x_unencrypted_password => '$PW',
                            x_start_date => SYSDATE);
    COMMIT;
    dbms_output.put_line('created user '||v_user);
  ELSE
    dbms_output.put_line('user exists '||v_user);
  END IF;

  SELECT COUNT(*) INTO v_exists
    FROM fnd_user_resp_groups_direct g, fnd_responsibility r, fnd_user u
   WHERE u.user_name = v_user
     AND g.user_id = u.user_id
     AND g.responsibility_id = r.responsibility_id
     AND g.end_date IS NULL
     AND r.responsibility_key = 'SYSTEM_ADMINISTRATOR';
  IF v_exists = 0 THEN
    fnd_user_pkg.AddResp(username        => v_user,
                         resp_app         => 'SYSADMIN',
                         resp_key         => 'SYSTEM_ADMINISTRATOR',
                         security_group   => 'STANDARD',
                         description      => 'auto',
                         start_date       => SYSDATE,
                         end_date         => NULL);
    COMMIT;
    dbms_output.put_line('added System Administrator to '||v_user);
  ELSE
    dbms_output.put_line('responsibility present for '||v_user);
  END IF;
END;
/
SQL
