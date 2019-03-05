#!/usr/bin/bash

terraform destroy -force
terraform plan
terraform apply -auto-approve > ./terraform.log 2>&1
ansible-playbook -vv run_robot.yml -i inventory 

