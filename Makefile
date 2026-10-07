# Makefile — optional convenience front-end for the EBS lab.
# (Equivalent: ./run.sh <command> ...). Requires GNU make: apt install make
SHELL := /bin/bash
N ?= 8
VM ?=
PO ?=
ARGS ?=

.PHONY: help up down status init provision reset sync-acls class-users export build-golden

help:                ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'
up:                  ## start the whole lab
	scripts/lab-start.sh
down:                ## stop the whole lab (make down PO=--poweroff to power off)
	scripts/lab-stop.sh $(PO)
status:              ## show VM + AppsLogin status
	scripts/lab-status.sh
init:                ## add N students (make init N=3)
	scripts/add-students.sh $(N)
provision:           ## provision one sandbox (make provision VM=9101)
	scripts/provision-sandbox.sh $(VM)
reset:               ## wipe a student's sandbox (make reset S=1 [CLIENT=1])
	scripts/reset-student.sh $(S) $(if $(CLIENT),--client,)
sync-acls:           ## re-assert student Proxmox users + VM ACLs
	scripts/sync-acls.sh
class-users:         ## create class EBS logins for all students
	scripts/create-class-users.sh
export:              ## back up golden + client template (ARGS="--storage local")
	scripts/export-images.sh $(ARGS)
build-golden:        ## rebuild the golden from pristine media (rare)
	scripts/build-golden.sh
