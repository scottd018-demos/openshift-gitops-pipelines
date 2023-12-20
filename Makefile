#
# NOTE: these may all be overridden by export VAR_NAME=var_value.  we are assuming deployment is done through
#       the terraform deploy-infra target, but this allows us not to rely on it entirely.
#
ROSA_CLUSTER_NAME ?= poc-dscott
ROSA_SUBNET_IDS ?= $(shell rosa describe cluster -c $(ROSA_CLUSTER_NAME) -o json | jq -r '.aws.subnet_ids | join(" ")')
YELB_SECRET_NAME ?= yelb-connection-info
YELB_APP_NAME ?= yelb-app
YELB_UI_NAME ?= yelb-ui
YELB_DB_SERVER_ENDPOINT ?= $(shell cat infrastructure/deploy/terraform.tfstate | jq -r '.resources[] | select(.type == "aws_rds_cluster" and .name == "yelb") | .instances[0].attributes.endpoint')
YELB_DB_SERVER_PORT ?= $(shell cat infrastructure/deploy/terraform.tfstate | jq -r '.resources[] | select(.type == "aws_rds_cluster" and .name == "yelb") | .instances[0].attributes.port')
YELB_DB_NAME ?= $(shell cat infrastructure/deploy/terraform.tfstate | jq -r '.resources[] | select(.type == "aws_rds_cluster" and .name == "yelb") | .instances[0].attributes.database_name')
YELB_DB_USERNAME ?= $(shell cat infrastructure/deploy/terraform.tfstate | jq -r '.resources[] | select(.type == "aws_rds_cluster" and .name == "yelb") | .instances[0].attributes.master_username')
YELB_DB_PASSWORD ?= $(shell cat infrastructure/deploy/terraform.tfstate | jq -r '.resources[] | select(.type == "aws_rds_cluster" and .name == "yelb") | .instances[0].attributes.master_password')
REDIS_SERVER_ENDPOINT ?= $(shell cat infrastructure/deploy/terraform.tfstate | jq -r '.resources[] | select(.type == "aws_elasticache_replication_group" and .name == "yelb") | .instances[0].attributes.configuration_endpoint_address')
AWS_REGION ?= $(shell rosa describe cluster -c $(ROSA_CLUSTER_NAME) -o json | jq -r '.region.id')

#
# cloud administrator tasks
#

# deploy tasks
infra:
	ROSA_PRIVATE_SUBNET_IDS=$$(aws ec2 describe-subnets \
		--subnet-ids $(ROSA_SUBNET_IDS) \
		--query 'Subnets[?Tags[?Key==`Name` && contains(Value, `private`)]].SubnetId' | jq -r '.') && \
	cd infrastructure/deploy && \
	terraform init && \
	terraform apply -var="db_subnet_ids=$$ROSA_PRIVATE_SUBNET_IDS"

# cleanup tasks
infra-destroy:
	ROSA_PRIVATE_SUBNET_IDS=$$(aws ec2 describe-subnets \
		--subnet-ids $(ROSA_SUBNET_IDS) \
		--query 'Subnets[?Tags[?Key==`Name` && contains(Value, `private`)]].SubnetId' | jq -r '.') && \
	cd infrastructure/deploy && \
	terraform apply -destroy -var="db_subnet_ids=$$ROSA_PRIVATE_SUBNET_IDS"

#
# developer tasks
#

# development deploy tasks
infra-dev:
	cd developer/infrastructure && docker-compose up

app-dev:
	if [[ ! -d developer/yelb ]]; then git clone https://github.com/scottd018-demos/yelb.git developer/yelb; fi
	cd developer/yelb/yelb-appserver/go && \
		git pull && \
		kn func run -v -e YELB_DB_PASSWORD=postgres &
	sleep 30
	docker network connect infrastructure_yelb $$(docker ps | grep yelb | grep -v ui | awk '{print $$NF}')

ui-dev:
	if [[ ! -d developer/yelb ]]; then git clone https://github.com/scottd018-demos/yelb.git developer/yelb; fi
	cd developer/yelb/yelb-ui && git pull && \
		docker build --platform linux/amd64 . -t image-registry.openshift-image-registry.svc:5000/yelb/ui:latest && \
		docker run \
			--rm \
			-p 80:80 \
			--name yelb-ui \
			--network infrastructure_yelb \
			--env=YELB_APPSERVER_ENDPOINT=http://$$(docker inspect -f '{{.NetworkSettings.Networks.infrastructure_yelb.IPAddress}}' $$(docker ps | grep yelb | grep -v ui | awk '{print $$NF}')):8080 \
			--env=HACK_PATH=true \
			--platform linux/amd64 \
			-it image-registry.openshift-image-registry.svc:5000/yelb/ui:latest
			
# development cleanup tasks
infra-destroy-dev:
	cd developer/infrastructure && docker-compose down -v --rmi all --remove-orphans

app-destroy-dev:
	docker rm -f $$(docker ps | grep yelb | grep -v ui | awk '{print $$NF}')

ui-destroy-dev:
	docker rm -f $$(docker ps | grep yelb | grep ui | awk '{print $$NF}')

# deploy tasks
seed:
	oc apply -f developer/task-seed-db.yaml

secret:
	oc create secret generic $(YELB_SECRET_NAME) \
		--from-literal=RACK_ENV=custom \
		--from-literal=YELB_DB_SERVER_ENDPOINT=$(YELB_DB_SERVER_ENDPOINT) \
		--from-literal=YELB_DB_SERVER_PORT=$(YELB_DB_SERVER_PORT) \
		--from-literal=YELB_DB_NAME=$(YELB_DB_NAME) \
		--from-literal=YELB_DB_USERNAME=$(YELB_DB_USERNAME) \
		--from-literal=YELB_DB_PASSWORD=$(YELB_DB_PASSWORD) \
		--from-literal=REDIS_SERVER_ENDPOINT=$(REDIS_SERVER_ENDPOINT) \
		--from-literal=AWS_REGION=$(AWS_REGION)

app:
	if [[ ! -d developer/yelb ]]; then git clone https://github.com/scottd018-demos/yelb.git developer/yelb; fi  && \
	cd developer/yelb/yelb-appserver/go && \
	git pull && \
	kn func deploy \
	    --remote \
		--git-url=https://github.com/scottd018-demos/yelb.git \
		--git-dir=yelb-appserver/go \
		--git-branch main

# cleanup tasks
secret-destroy:
	oc delete secret $(YELB_SECRET_NAME)

app-destroy:
	oc delete all -l app=$(YELB_APP_NAME)

deploy-ui:
	oc new-app \
		--name $(YELB_UI_NAME) \
		--strategy=docker \
		https://github.com/scottd018-demos/yelb.git \
		--context-dir yelb-appserver && \
	oc set env --from=secret/$(YELB_SECRET_NAME) deployment/$(YELB_APP_NAME)