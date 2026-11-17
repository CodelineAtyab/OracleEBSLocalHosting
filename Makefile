# Makefile — optional convenience front-end for the EBS lab.
# (Equivalent: ./run.sh <command> ...). Requires GNU make: apt install make
SHELL := /bin/bash
N ?= 8
VM ?=
PO ?=
ARGS ?=

.PHONY: help up down autostart status init rebuild provision reset sync-acls class-users access-files vnc portal portal-add backup base-backup export build-golden

help:                ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'
up:                  ## start the whole lab
	scripts/lab-start.sh
down:                ## stop the whole lab (make down PO=--poweroff to power off)
	scripts/lab-stop.sh $(PO)
autostart:           ## make the lab come up after a host boot (ARGS=--remove to disable)
	scripts/install-lab-autostart.sh $(ARGS)
status:              ## show VM + AppsLogin status
	scripts/lab-status.sh
init:                ## add N students (make init N=3)
	scripts/add-students.sh $(N)
rebuild:             ## build class + N students from templates (make rebuild N=9)
	scripts/lab-rebuild.sh $(N)
provision:           ## provision one sandbox (make provision VM=9101)
	scripts/provision-sandbox.sh $(VM)
reset:               ## wipe a student's sandbox (make reset S=1 [CLIENT=1])
	scripts/reset-student.sh $(S) $(if $(CLIENT),--client,)
sync-acls:           ## re-assert student Proxmox users + VM ACLs
	scripts/sync-acls.sh
backup:              ## full DR backup to USB (make backup M=/mnt/ebs-usb)
	scripts/backup-to-usb.sh $(M) $(ARGS)
base-backup:         ## base DR backup: templates + pristine media (make base-backup M=/mnt/ebs-usb)
	scripts/backup-to-usb.sh $(M) --with-media
class-users:         ## create class EBS logins for all students
	scripts/create-class-users.sh
access-files:        ## write/refresh each client's your_access.txt + hostname
	scripts/client/write-access-file.sh $(VM)
vnc:                 ## show each client's live VNC address + PIN
	scripts/client/vnc-credentials.sh
portal:              ## build/refresh the live status page (LXC 9300)
	scripts/portal/portal-install.sh $(ARGS)
portal-add:          ## add another Proxmox host (make portal-add L=site-b U=https://ip:8006 F=/root/tok)
	scripts/portal/portal-add-host.sh $(L) $(U) $(F)
export:              ## back up golden + client template (ARGS="--storage local")
	scripts/export-images.sh $(ARGS)
build-golden:        ## rebuild the golden from pristine media (rare)
	scripts/build-golden.sh
