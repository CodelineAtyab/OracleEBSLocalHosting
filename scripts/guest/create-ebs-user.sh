#!/bin/bash
# Runs INSIDE the shared class instance (EBS 12.1.3) as root.
# Ensure an EBS application user exists AND (re)set its password to the given
# value EVERY time (so it can never drift from the documented default), then
# give it the System Administrator responsibility.
#   usage: ssh root@<class> 'bash -s -- <USER> <PASSWORD>' < create-ebs-user.sh
set -u
USER_NAME="${1:?usage: create-ebs-user.sh <user> <password>}"
PW="${2:?usage: create-ebs-user.sh <user> <password>}"
. /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env

sqlplus -s apps/apps@EBSDB <<SQL
set serveroutput on size 100000 feed off
DECLARE
  v_user VARCHAR2(30) := UPPER('$USER_NAME');
  v_n    NUMBER;
  v_ok   BOOLEAN;
BEGIN
  -- 1) create if absent
  SELECT COUNT(*) INTO v_n FROM fnd_user WHERE user_name = v_user;
  IF v_n = 0 THEN
    fnd_user_pkg.CreateUser(x_user_name => v_user,
                            x_owner     => NULL,
                            x_unencrypted_password => '$PW',
                            x_start_date => SYSDATE);
    dbms_output.put_line('created '||v_user);
  END IF;

  -- 2) ALWAYS (re)set the password so it can never drift
  fnd_user_pkg.UpdateUser(x_user_name => v_user,
                          x_owner     => 'CUST',
                          x_unencrypted_password => '$PW',
                          x_password_date => SYSDATE,
                          x_start_date    => SYSDATE);
  dbms_output.put_line('password (re)set for '||v_user);

  -- 3) ensure the System Administrator responsibility
  SELECT COUNT(*) INTO v_n
    FROM fnd_user_resp_groups_direct g, fnd_responsibility r, fnd_user u
   WHERE u.user_name = v_user
     AND g.user_id = u.user_id
     AND g.responsibility_id = r.responsibility_id
     AND g.end_date IS NULL
     AND r.responsibility_key = 'SYSTEM_ADMINISTRATOR';
  IF v_n = 0 THEN
    fnd_user_pkg.AddResp(username        => v_user,
                         resp_app         => 'SYSADMIN',
                         resp_key         => 'SYSTEM_ADMINISTRATOR',
                         security_group   => 'STANDARD',
                         description      => 'auto',
                         start_date       => SYSDATE,
                         end_date         => NULL);
    dbms_output.put_line('added System Administrator to '||v_user);
  END IF;

  COMMIT;

  -- 4) verify
  v_ok := fnd_user_pkg.validatelogin(v_user, '$PW');
  dbms_output.put_line('verify '||v_user||' => '||CASE WHEN v_ok THEN 'VALID' ELSE 'INVALID' END);
EXCEPTION WHEN OTHERS THEN
  dbms_output.put_line('ERROR '||v_user||': '||SQLERRM);
END;
/
SQL
