#!/bin/bash
# Runs INSIDE the class instance (EBS 12.1.3) as root.
# Admin-reset an EBS application user's password (no old password needed).
#   usage: ssh root@class 'bash -s -- <USER> <PASSWORD>' < set-ebs-password.sh
set -u
U="${1:?usage: set-ebs-password.sh <user> <password>}"
P="${2:?usage: set-ebs-password.sh <user> <password>}"
. /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env
sqlplus -s apps/apps@EBSDB <<SQL
set serveroutput on size 100000 feed off
declare
  b boolean;
begin
  fnd_user_pkg.updateuser(x_user_name        => UPPER('$U'),
                          x_owner            => 'CUST',
                          x_unencrypted_password => '$P',
                          x_start_date       => SYSDATE);
  commit;
  b := fnd_user_pkg.validatelogin(UPPER('$U'), '$P');
  dbms_output.put_line('set '||UPPER('$U')||' / $P  => '||case when b then 'VALID' else 'INVALID' end);
exception when others then
  dbms_output.put_line('ERROR '||UPPER('$U')||': '||sqlerrm);
end;
/
exit
SQL
